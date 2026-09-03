/// Instantánea completa del estado del dispositivo IoT (ESP32): agrupa el
/// estado de todos los sensores y actuadores de una casa (servos, bomba,
/// LEDs, ventiladores, sensores ambientales) más el modo automático.
class DeviceState {
  final ServoState servo;
  final Servo2State servo2;
  final Servo3State servo3;
  final StepperState stepper;
  final PumpState pump;
  final MotionState motion;
  final LedState led;
  final FanState fan;
  final DhtState dht;
  final Mq135State mq135;
  final WaterLevelState water;
  final UltrasonicState ultrasonic;
  final bool automaticMode;

  DeviceState({
    required this.servo,
    required this.servo2,
    required this.servo3,
    required this.stepper,
    required this.pump,
    required this.motion,
    required this.led,
    required this.fan,
    required this.dht,
    required this.mq135,
    required this.water,
    required this.ultrasonic,
    required this.automaticMode,
  });

  /// Construye un [DeviceState] a partir del JSON devuelto por el endpoint
  /// `/devices` del backend/ESP32, aplicando valores por defecto seguros a
  /// los campos que falten.
  factory DeviceState.fromJson(Map<String, dynamic> json) {
    return DeviceState(
      servo: ServoState.fromJson(json['servo']),
      servo2: Servo2State.fromJson(json['servo2']),
      // Tolera un backend anterior a Servo3: si el bloque no viene, se asume reposo.
      servo3: Servo3State.fromJson(json['servo3'] ?? const {}),
      stepper: StepperState.fromJson(json['stepper']),
      pump: PumpState.fromJson(json['pump']),
      motion: MotionState.fromJson(json['motion']),
      led: LedState.fromJson(json['led']),
      fan: FanState.fromJson(json['fan']),
      dht: DhtState.fromJson(json['dht']),
      mq135: Mq135State.fromJson(json['mq135']),
      water: WaterLevelState.fromJson(json['water']),
      ultrasonic: UltrasonicState.fromJson(json['ultrasonic']),
      automaticMode: json['automaticMode'] ?? true,
    );
  }
}

/// Estado del servomotor principal (cuarto 1): ángulo actual y estado de
/// operación reportado por el dispositivo.
class ServoState {
  final int angle;
  final String status;

  ServoState({required this.angle, required this.status});

  /// Crea el estado a partir del JSON del dispositivo (ángulo 90° y
  /// estado `OK` por defecto si faltan datos).
  factory ServoState.fromJson(Map<String, dynamic> json) {
    return ServoState(
      angle: json['angle'] ?? 90,
      status: json['status'] ?? 'OK',
    );
  }
}

/// Estado del segundo servomotor (cuarto 2): solo guarda el ángulo actual.
class Servo2State {
  final int angle;

  Servo2State({required this.angle});

  /// Crea el estado a partir del JSON del dispositivo (ángulo 90° por defecto).
  factory Servo2State.fromJson(Map<String, dynamic> json) {
    return Servo2State(angle: json['angle'] ?? 90);
  }
}

/// Estado del tercer servomotor, el que orienta la cámara de la vivienda.
class Servo3State {
  final int angle;
  final String status;

  Servo3State({required this.angle, required this.status});

  /// Crea el estado a partir del JSON del dispositivo. El ángulo por defecto
  /// es 0, que es la posición de reposo con la que se montó el hardware.
  factory Servo3State.fromJson(Map<String, dynamic> json) {
    return Servo3State(
      angle: json['angle'] ?? 0,
      status: json['status'] ?? 'OK',
    );
  }
}

/// Estado del motor paso a paso que controla el dispensador de comida.
class StepperState {
  final int position;

  /// Recorrido máximo del dispensador, tal como lo declara el backend.
  ///
  /// Se lee de la respuesta en vez de llevarlo escrito en la app para que el
  /// número no se desincronice del que aplica el servidor: si el mecanismo
  /// cambia de recorrido, cambia en un solo sitio.
  final int maxPosition;

  StepperState({required this.position, this.maxPosition = 200});

  /// Crea el estado a partir del JSON del dispositivo (posición 0 por defecto).
  factory StepperState.fromJson(Map<String, dynamic> json) {
    return StepperState(
      position: json['position'] ?? 0,
      maxPosition: json['maxPosition'] ?? 200,
    );
  }
}

/// Estado de la bomba de agua/comida (encendida o apagada).
class PumpState {
  final bool enabled;

  PumpState({required this.enabled});

  /// Crea el estado a partir del JSON del dispositivo (`false` por defecto).
  factory PumpState.fromJson(Map<String, dynamic> json) {
    return PumpState(enabled: json['enabled'] ?? false);
  }
}

/// Estado de los sensores de movimiento en las entradas/salidas de ambos
/// cuartos, usados para detectar el paso de la mascota.
class MotionState {
  final bool room1Entry;
  final bool room1Exit;
  final bool room2Entry;
  final bool room2Exit;

  MotionState({
    required this.room1Entry,
    required this.room1Exit,
    required this.room2Entry,
    required this.room2Exit,
  });

  /// Crea el estado a partir del JSON del dispositivo (todo `false` por defecto).
  factory MotionState.fromJson(Map<String, dynamic> json) {
    return MotionState(
      room1Entry: json['room1Entry'] ?? false,
      room1Exit: json['room1Exit'] ?? false,
      room2Entry: json['room2Entry'] ?? false,
      room2Exit: json['room2Exit'] ?? false,
    );
  }
}

/// Estado de los LEDs de ambos cuartos y si se controlan en modo automático.
class LedState {
  final bool room1Led;
  final bool room2Led;
  final bool automatic;

  LedState({
    required this.room1Led,
    required this.room2Led,
    required this.automatic,
  });

  /// Crea el estado a partir del JSON del dispositivo (LEDs apagados y modo
  /// automático activo por defecto).
  factory LedState.fromJson(Map<String, dynamic> json) {
    return LedState(
      room1Led: json['room1Led'] ?? false,
      room2Led: json['room2Led'] ?? false,
      automatic: json['automatic'] ?? true,
    );
  }
}

/// Estado de los ventiladores de ambos cuartos y si se controlan en modo
/// automático.
class FanState {
  final bool fan1;
  final bool fan2;
  final bool automatic;

  FanState({
    required this.fan1,
    required this.fan2,
    required this.automatic,
  });

  /// Crea el estado a partir del JSON del dispositivo (todo `false` por defecto).
  factory FanState.fromJson(Map<String, dynamic> json) {
    return FanState(
      fan1: json['fan1'] ?? false,
      fan2: json['fan2'] ?? false,
      automatic: json['automatic'] ?? false,
    );
  }
}

/// Lecturas de temperatura y humedad de los sensores DHT de ambos cuartos.
class DhtState {
  final double temperature1;
  final double humidity1;
  final double temperature2;
  final double humidity2;

  DhtState({
    required this.temperature1,
    required this.humidity1,
    required this.temperature2,
    required this.humidity2,
  });

  /// Crea el estado a partir del JSON del dispositivo (0 por defecto en
  /// cualquier lectura ausente).
  factory DhtState.fromJson(Map<String, dynamic> json) {
    return DhtState(
      temperature1: (json['temperature1'] ?? 0).toDouble(),
      humidity1: (json['humidity1'] ?? 0).toDouble(),
      temperature2: (json['temperature2'] ?? 0).toDouble(),
      humidity2: (json['humidity2'] ?? 0).toDouble(),
    );
  }
}

/// Lecturas de calidad del aire (sensor MQ135) de ambos cuartos.
class Mq135State {
  final int airQuality1;
  final int airQuality2;

  Mq135State({
    required this.airQuality1,
    required this.airQuality2,
  });

  /// Crea el estado a partir del JSON del dispositivo (0 por defecto).
  factory Mq135State.fromJson(Map<String, dynamic> json) {
    return Mq135State(
      airQuality1: json['airQuality1'] ?? 0,
      airQuality2: json['airQuality2'] ?? 0,
    );
  }
}

/// Nivel de agua reportado por el sensor del bebedero.
class WaterLevelState {
  final int level;

  WaterLevelState({required this.level});

  /// Crea el estado a partir del JSON del dispositivo (0 por defecto).
  factory WaterLevelState.fromJson(Map<String, dynamic> json) {
    return WaterLevelState(level: json['level'] ?? 0);
  }
}

/// Distancia medida por el sensor ultrasónico (por ejemplo, nivel de comida
/// en el dispensador).
class UltrasonicState {
  final double distance;

  UltrasonicState({required this.distance});

  /// Crea el estado a partir del JSON del dispositivo (0 por defecto).
  factory UltrasonicState.fromJson(Map<String, dynamic> json) {
    return UltrasonicState(distance: (json['distance'] ?? 0).toDouble());
  }
}