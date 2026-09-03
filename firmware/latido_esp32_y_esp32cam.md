# Latido del ESP32 y de la ESP32-CAM — los dos parches juntos

Son **dos placas físicas distintas**, con **dos archivos `.ino` distintos**, y
cada parche va en el suyo. No se mezclan ni se pegan en el mismo sketch.

| | Placa | Archivo que ya tienes abierto |
|---|---|---|
| **Parche 1** | ESP32 de sensores y actuadores (servos, stepper, bomba, LEDs, DHT, MQ135...) | tu `.ino` de siempre |
| **Parche 2** | ESP32-CAM (la que sirve el video) | el `CameraWebServer.ino` de fábrica |

Los dos hacen lo mismo — avisar cada 10 segundos "aquí estoy, esta es mi MAC" —
para que el botón **«Buscar en mi red»** encuentre a las dos placas. Ninguno de
los dos toca lo que ya funciona hoy: el ESP32 de sensores sigue respondiendo a
`/api/led`, `/api/servo`, etc. exactamente igual, y la ESP32-CAM sigue sirviendo
`/capture` y el stream exactamente igual.

---

# PARCHE 1 — ESP32 de sensores

Cuatro bloques que se pegan en tu `.ino` de siempre.

## 1. Añade el endpoint, junto a los otros

Busca el bloque de `ENDPOINT_*` y agrega la última línea:

```cpp
const char* ENDPOINT_SERVO3 = "/servo3";
const char* ENDPOINT_LATIDO = "/huellitas/dispositivo/latido";   // <— nuevo
```

> Ojo con la ruta: `SERVER_BASE` ya termina en `/api`, así que la URL completa
> queda `http://TU_IP:8087/api/huellitas/dispositivo/latido`. Es correcta así.

## 2. Añade el temporizador y el intervalo

Junto a los demás `unsigned long last...`:

```cpp
unsigned long lastLatido = 0;
const unsigned long LATIDO_INTERVAL = 10000;   // 10 s
```

## 3. Añade la función

Pégala junto a `sendServo3Data()`, que sigue el mismo patrón:

```cpp
//=====================================================
// LATIDO: avisa al backend que este aparato sigue vivo
//=====================================================

void sendLatido() {
    if (WiFi.status() != WL_CONNECTED) return;

    // El primer latido sale enseguida; después, uno cada LATIDO_INTERVAL.
    if (lastLatido != 0 && millis() - lastLatido < LATIDO_INTERVAL) return;
    lastLatido = millis();

    HTTPClient http;
    http.begin(buildServerURL(ENDPOINT_LATIDO));
    http.addHeader("Content-Type", "application/json");

    // La MAC es la identidad del aparato: es lo que hace que una vivienda
    // pueda adoptarlo y que ninguna otra pueda quedárselo.
    http.addHeader("X-Device-Mac", WiFi.macAddress());

    // La IP local la usa el backend para pedirle la foto a la ESP32-CAM
    // mientras los dos estén en la misma red.
    http.addHeader("X-Device-Ip", WiFi.localIP().toString());

    http.setTimeout(2000);   // corto a propósito: no bloquear la tarea HTTP

    int codigo = http.POST("{\"modelo\":\"ESP32 Huellitas\"}");

    if (codigo == HTTP_CODE_OK) {
        String cuerpo = http.getString();
        // "registrado":false significa que el aparato late pero todavía
        // ninguna vivienda lo ha adoptado. No es un error.
        static bool avisado = false;
        if (!avisado) {
            logMessage("💓 Latido OK · MAC " + WiFi.macAddress());
            logMessage("   Respuesta: " + cuerpo);
            avisado = true;
        }
    }

    http.end();
}
```

Y declara el prototipo arriba, con los demás:

```cpp
void sendLatido();
```

## 4. Llámala desde `httpTask()`

Al final de la lista de envíos:

```cpp
sendMotionData();
sendDHTData();
sendMQ135Data();
sendWaterLevelData();
sendUltrasonicData();
sendServo3Data();
sendLatido();          // <— nuevo
```

Va en el core 1 con prioridad baja, igual que los demás envíos, así que **no
interfiere con la tarea del stepper** ni con ningún movimiento en curso.

## Tres defectos que conviene arreglar de paso

Ya que se toca el archivo. Ninguno impide que funcione, pero los tres son reales.

**El segundo sensor de temperatura nunca se reporta.** En `sendDHTData()` la
condición de corte solo mira el sensor 1, y al guardar tampoco actualiza el 2.

```cpp
void sendDHTData() {
    if (WiFi.status() != WL_CONNECTED) return;

    bool cambio1 = abs(sensors.temperature1 - lastSensors.temperature1) >= TEMP_THRESHOLD
                || abs(sensors.humidity1    - lastSensors.humidity1)    >= HUM_THRESHOLD;
    bool cambio2 = abs(sensors.temperature2 - lastSensors.temperature2) >= TEMP_THRESHOLD
                || abs(sensors.humidity2    - lastSensors.humidity2)    >= HUM_THRESHOLD;
    if (!cambio1 && !cambio2) return;

    StaticJsonDocument<256> doc;
    doc["temperature1"] = sensors.temperature1;
    doc["humidity1"]    = sensors.humidity1;
    doc["temperature2"] = sensors.temperature2;
    doc["humidity2"]    = sensors.humidity2;

    String json;
    serializeJson(doc, json);

    if (httpPOSTRequest(ENDPOINT_DHT, json)) {
        lastSensors.temperature1 = sensors.temperature1;
        lastSensors.humidity1    = sensors.humidity1;
        lastSensors.temperature2 = sensors.temperature2;   // faltaban
        lastSensors.humidity2    = sensors.humidity2;      // estas dos
    }
}
```

**Los DHT11 se leen al doble de velocidad de la que aguantan.** `httpTask` gira
cada 500 ms y `readAllSensors()` alterna un sensor por vuelta, así que cada DHT
se lee cada segundo — la hoja de datos pide 2 segundos como mínimo.

```cpp
    // Reemplaza el bloque de lectura DHT en readAllSensors() por este,
    // con reloj propio:
    static unsigned long ultimaLecturaDht = 0;
    static int dhtCycle = 0;
    if (millis() - ultimaLecturaDht >= 2000) {
        ultimaLecturaDht = millis();
        if (dhtCycle == 0) {
            float t1 = dht1.readTemperature();
            float h1 = dht1.readHumidity();
            if (!isnan(t1)) sensors.temperature1 = t1;
            if (!isnan(h1)) sensors.humidity1 = h1;
            dhtCycle = 1;
        } else {
            float t2 = dht2.readTemperature();
            float h2 = dht2.readHumidity();
            if (!isnan(t2)) sensors.temperature2 = t2;
            if (!isnan(h2)) sensors.humidity2 = h2;
            dhtCycle = 0;
        }
    }
```

**El stepper está desincronizado con el backend.** El firmware permite hasta
`STEPPER_MAX_POSITION = 4096`, pero el backend recorta a `MAX_POSITION = 200`.
Hay que poner el mismo número en los dos lados — según cuál sea el recorrido
real del dispensador.

## Cómo comprobar que funciona

1. Sube el firmware y abre el monitor serie a 115200. Debe aparecer:
   ```
   [INFO] 💓 Latido OK · MAC 3C:61:05:XX:XX:XX
   [INFO]    Respuesta: {"ok":true,"registrado":false,"mac":"3C:61:05:XX:XX:XX"}
   ```
   `registrado:false` la primera vez es lo esperado: el aparato todavía no es de nadie.
2. Anota esa MAC.
3. En la web o en la app: **Cámaras → Agregar → Buscar en mi red.** Debe salir marcado como **Añadir**.
4. Púlsalo. A partir de ahí el latido responde `"registrado":true`.

## Para que pruebes en tu propia computadora

Cambia esta línea a **la IP de tu máquina** (la que ves con `ipconfig`):

```cpp
const char* SERVER_BASE = "http://192.168.1.186:8087/api";
```

Y agrega tu red WiFi al arreglo `WIFI_NETWORKS`, si no está.

> Su `application.properties` apunta a la base de Neon en la nube, que es la
> de producción. Si levantas el backend tal cual, escribes sobre datos reales.

---

# PARCHE 2 — ESP32-CAM

Va en el `CameraWebServer.ino` de fábrica. No toca el video.

## 1. Agrega el include

Al principio del `.ino`, con los demás `#include`:

```cpp
#include <HTTPClient.h>   // <— nuevo
```

`WiFi.h` ya está incluido en el ejemplo, no hace falta agregarlo.

## 2. Agrega la configuración del backend

Junto a `ssid`/`password`:

```cpp
const char* SERVER_BASE = "http://192.168.1.186:8087/api";  // misma IP que usa el otro ESP32
const char* ENDPOINT_LATIDO = "/huellitas/dispositivo/latido";

unsigned long lastLatido = 0;
const unsigned long LATIDO_INTERVAL = 10000;   // 10 s
```

> Usa la **misma IP** que ya tiene configurada el ESP32 de los sensores — los
> dos aparatos hablan con el mismo backend.

## 3. Agrega la función

```cpp
//=====================================================
// LATIDO: avisa al backend que la cámara sigue encendida
//=====================================================

void sendLatidoCamara() {
    if (WiFi.status() != WL_CONNECTED) return;

    if (lastLatido != 0 && millis() - lastLatido < LATIDO_INTERVAL) return;
    lastLatido = millis();

    HTTPClient http;
    http.begin(String(SERVER_BASE) + ENDPOINT_LATIDO);
    http.addHeader("Content-Type", "application/json");

    // La MAC identifica a la cámara: es lo que permite que una vivienda la
    // adopte y ninguna otra pueda quedársela.
    http.addHeader("X-Device-Mac", WiFi.macAddress());

    // La IP local es la que el backend usa después para pedirle una foto a
    // /capture, así que tiene que ser la real de la cámara en la red.
    http.addHeader("X-Device-Ip", WiFi.localIP().toString());

    http.setTimeout(2000);

    int codigo = http.POST("{\"modelo\":\"ESP32-CAM OV2640\"}");

    static bool avisado = false;
    if (codigo == HTTP_CODE_OK && !avisado) {
        Serial.println("💓 Latido de la cámara OK · MAC " + WiFi.macAddress() +
                        " · IP " + WiFi.localIP().toString());
        avisado = true;
    }

    http.end();
}
```

## 4. Llámala desde `loop()`

El `loop()` del ejemplo `CameraWebServer` normalmente está casi vacío —el
servidor de video corre en su propia tarea— y se ve así:

```cpp
void loop() {
  // Do nothing. Everything is done in another task by the web server
  delay(10000);
}
```

Solo agrega la llamada, sin tocar el `delay`:

```cpp
void loop() {
  sendLatidoCamara();   // <— nuevo
  delay(10000);
}
```

No interfiere con el streaming: la petición del latido tarda milisegundos y
corre en el core principal, mientras el video sigue sirviéndose desde la tarea
propia del servidor web.

## Cómo comprobar que funciona

1. Sube el firmware y abre el monitor serie a 115200. A los pocos segundos:
   ```
   💓 Latido de la cámara OK · MAC A0:B7:65:XX:XX:XX · IP 192.168.1.XX
   ```
2. En la web o en la app: **Cámaras → Agregar → Buscar en mi red.** La
   ESP32-CAM debe aparecer como **«ESP32-CAM OV2640»**, con el botón **Añadir**.
3. Púlsalo. Queda vinculada a esa vivienda — a partir de ahí nadie más la
   puede tomar, aunque esté en la misma red.

## Por qué la cámara no tenía esto hasta ahora

El `CameraWebServer` es el ejemplo de fábrica: sirve video y fotos, pero no
sabe que existe un backend ni que hace falta anunciarse. Por eso hasta hoy la
única forma de usarla era copiar la IP del puerto serie y abrirla a mano en el
navegador — funciona, pero hay que repetirlo cada vez que la IP cambia. Con
este parche, la cámara se anuncia sola, igual que el ESP32 de los sensores.

---

## Si prenden las dos placas a la vez

Cada una tiene su propia MAC de fábrica —nunca hay dos iguales— así que las
dos aparecen juntas en la misma lista de «Buscar en mi red», cada una con su
propio botón **Añadir**. Si hay más de una ESP32-CAM encendida al mismo tiempo,
todas aparecen también, distinguibles por su MAC y su IP (el parche manda
siempre el mismo nombre de modelo, así que conviene fijarse en la IP antes de
tocar Añadir, o ponerle un nombre propio a cada una al vincularla).
