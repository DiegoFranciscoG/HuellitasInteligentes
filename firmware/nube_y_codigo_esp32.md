# Firmware para la nube — parche único para las dos placas

Este archivo **reemplaza** al del token que te mencioné antes. No apliques aquel:
quedó obsoleto y este trae todo junto, para que toques cada `.ino` una sola vez.

Son dos cambios:

1. **La dirección del servidor** pasa a ser la de internet, porque el backend deja
   de correr en la PC de Diego.
2. **Un código de vivienda** que identifica tus placas, y —solo en la cámara— el
   envío de fotos al servidor.

---

## Antes de empezar: dos datos que te pasa Diego

| Dato | Para qué | Ejemplo |
|---|---|---|
| Dirección del servidor | Reemplaza la IP local | `http://huellitasinteligentes.duckdns.org:8087/api` |
| Código de la vivienda | Identifica tus placas | `a3f9c1e07b2d4856ff01a29c3e7b1d40` |

El código lo genera él desde la app, en **Cámaras → Agregar → Buscar en mi red →
Generar código**. Es de su casa, así que no lo publiques en ningún lado.

---

# PARCHE 1 — ESP32 de sensores

## 1. Cambia la dirección y añade el código

Donde tienes `SERVER_BASE`:

```cpp
// Antes: const char* SERVER_BASE = "http://192.168.1.186:8087/api";
const char* SERVER_BASE = "PEGAR_AQUI_LA_DIRECCION_DEL_SERVIDOR";
const char* DEVICE_CODE = "PEGAR_AQUI_EL_CODIGO";   // <— nuevo
```

## 2. Manda el código en `httpPOSTRequest()`

Por esa función salen casi todos los envíos, así que con tocarla una vez quedan
cubiertos los sensores y los actuadores:

```cpp
http.addHeader("Content-Type", "application/json");
http.addHeader("X-Device-Code", DEVICE_CODE);   // <— nuevo
```

## 3. Y en `sendLatido()`

El latido arma sus cabeceras aparte:

```cpp
http.addHeader("Content-Type", "application/json");
http.addHeader("X-Device-Mac", WiFi.macAddress());
http.addHeader("X-Device-Ip", WiFi.localIP().toString());
http.addHeader("X-Device-Code", DEVICE_CODE);   // <— nuevo
http.setTimeout(2000);
```

Eso es todo en esta placa.

---

# PARCHE 2 — ESP32-CAM

Aquí hay un cambio de fondo, no solo cabeceras.

## Por qué cambia

Hasta ahora el servidor le pedía la foto a la cámara, entrando a
`http://192.168.1.221/capture`. Eso funcionaba porque los dos estaban en la misma
red. Con el servidor en internet ya no puede: `192.168.1.221` solo existe dentro
de tu casa.

La solución es al revés: **que la cámara mande la foto**. Sale de tu red hacia
afuera, igual que el latido, así que funciona desde donde sea.

## 1. Cambia la dirección y añade el código

```cpp
const char* SERVER_BASE = "PEGAR_AQUI_LA_DIRECCION_DEL_SERVIDOR";
const char* ENDPOINT_LATIDO = "/huellitas/dispositivo/latido";
const char* ENDPOINT_MOMENTO = "/huellitas/camara/momento";   // <— nuevo
const char* DEVICE_CODE = "PEGAR_AQUI_EL_CODIGO";             // <— nuevo

unsigned long lastMomento = 0;
const unsigned long MOMENTO_INTERVAL = 60000;   // una foto por minuto
```

## 2. Añade el código al latido

```cpp
http.addHeader("Content-Type", "application/json");
http.addHeader("X-Device-Mac", WiFi.macAddress());
http.addHeader("X-Device-Ip", WiFi.localIP().toString());
http.addHeader("X-Device-Code", DEVICE_CODE);   // <— nuevo
```

## 3. Añade la función que sube la foto

Va junto a `sendLatidoCamara()`. Usa `esp_camera_fb_get()`, que ya está
disponible en el `CameraWebServer`:

```cpp
//=====================================================
// Sube una foto al servidor para que analice si hay
// una mascota. Reemplaza al antiguo /capture, que el
// servidor ya no puede alcanzar desde internet.
//=====================================================

void enviarMomento() {
    if (WiFi.status() != WL_CONNECTED) return;
    if (lastMomento != 0 && millis() - lastMomento < MOMENTO_INTERVAL) return;
    lastMomento = millis();

    camera_fb_t* fb = esp_camera_fb_get();
    if (!fb) {
        Serial.println("No se pudo capturar la foto");
        return;
    }

    HTTPClient http;
    http.begin(String(SERVER_BASE) + ENDPOINT_MOMENTO);
    http.addHeader("X-Device-Code", DEVICE_CODE);
    http.addHeader("X-Device-Mac", WiFi.macAddress());

    // El servidor espera la foto como un formulario, en el campo "fotos".
    String limite = "----HuellitasBoundary";
    http.addHeader("Content-Type", "multipart/form-data; boundary=" + limite);

    String cabecera = "--" + limite + "\r\n"
        "Content-Disposition: form-data; name=\"fotos\"; filename=\"foto.jpg\"\r\n"
        "Content-Type: image/jpeg\r\n\r\n";
    String cierre = "\r\n--" + limite + "--\r\n";

    int total = cabecera.length() + fb->len + cierre.length();
    uint8_t* cuerpo = (uint8_t*) malloc(total);
    if (!cuerpo) {
        Serial.println("Sin memoria para armar el envio");
        esp_camera_fb_return(fb);
        http.end();
        return;
    }

    memcpy(cuerpo, cabecera.c_str(), cabecera.length());
    memcpy(cuerpo + cabecera.length(), fb->buf, fb->len);
    memcpy(cuerpo + cabecera.length() + fb->len, cierre.c_str(), cierre.length());

    http.setTimeout(15000);   // subir una foto tarda mas que un latido
    int codigo = http.POST(cuerpo, total);

    if (codigo == 200) {
        Serial.println("Foto enviada · " + http.getString());
    } else {
        Serial.println("Error al enviar la foto: " + String(codigo));
    }

    free(cuerpo);
    esp_camera_fb_return(fb);
    http.end();
}
```

## 4. Llámala desde `loop()`

```cpp
void loop() {
  sendLatidoCamara();
  enviarMomento();     // <— nuevo
  delay(10000);
}
```

> El servidor de video de la placa (`/capture` y el stream) sigue igual. Eso lo
> sirve la cámara y no depende del backend.

---

## Cómo comprobar que quedó bien

**En el ESP32 de sensores**, monitor serie a 115200:

```
[INFO] 💓 Latido OK · MAC 3C:61:05:XX:XX:XX
[INFO]    Respuesta: {"ok":true,"registrado":true,...}
```

Si dice `registrado:true`, el código funcionó y la placa está reconocida.

**En la ESP32-CAM**, cada minuto:

```
Foto enviada · {"ok":true,"recibidas":1,"hayMascota":false,...}
```

`hayMascota:false` cuando no hay ningún perro delante es correcto. Cuando pase
uno, Diego debería recibir la notificación en su teléfono.

## Si algo falla

| Lo que ves | Qué pasa |
|---|---|
| `Error al enviar la foto: 401` | El código está mal copiado, o Diego lo regeneró. Pídele el nuevo. |
| `Error al enviar la foto: -1` | No alcanza el servidor. Revisa la dirección y que tengas internet. |
| `Sin memoria para armar el envio` | Baja la resolución de la cámara en `config.frame_size` (por ejemplo a `FRAMESIZE_VGA`). |
| El latido responde pero los sensores no | Falta la cabecera en `httpPOSTRequest()`. |

## Sobre el orden

Aplica esto **cuando Diego te avise de que el servidor ya está en internet**. Si
lo haces antes, las placas apuntarán a una dirección que todavía no existe y
dejarán de reportar hasta que él termine de subirlo.
