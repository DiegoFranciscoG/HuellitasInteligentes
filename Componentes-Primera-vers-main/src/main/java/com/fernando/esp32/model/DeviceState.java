package com.fernando.esp32.model;

/**
 * Instantánea agregada del estado de todos los dispositivos y sensores
 * gestionados por el ESP32, junto con el estado del modo automático.
 */
public class DeviceState {

    private ServoState servo;
    private Servo2State servo2;
    private Servo3State servo3;
    private StepperState stepper;
    private PumpState pump;
    private MotionState motion;
    private LedState led;
    private FanState fan;
    private DhtState dht;
    private Mq135State mq135;
    private WaterLevelState water;
    private UltrasonicState ultrasonic;
    private boolean automaticMode;


    public DeviceState() {
    }

    public DeviceState(ServoState servo,
                       Servo2State servo2,
                       Servo3State servo3,
                       StepperState stepper,
                       PumpState pump,
                       MotionState motion,
                       LedState led,
                       FanState fan,
                       DhtState dht,
                       Mq135State mq135,
                       WaterLevelState water,
                       UltrasonicState ultrasonic) {

        this.servo = servo;
        this.servo2 = servo2;
        this.servo3 = servo3;
        this.stepper = stepper;
        this.pump = pump;
        this.motion = motion;
        this.led = led;
        this.fan = fan;
        this.dht = dht;
        this.mq135 = mq135;
        this.water = water;
        this.ultrasonic = ultrasonic;
        this.automaticMode = true;
    }

    public ServoState getServo() {
        return servo;
    }

    public void setServo(ServoState servo) {
        this.servo = servo;
    }


    public StepperState getStepper() {
        return stepper;
    }

    public void setStepper(StepperState stepper) {
        this.stepper = stepper;
    }

    public PumpState getPump() {
        return pump;
    }

    public void setPump(PumpState pump) {
        this.pump = pump;
    }

    public MotionState getMotion() {
        return motion;
    }

    public void setMotion(MotionState motion) {
        this.motion = motion;
    }

    public LedState getLed() {
        return led;
    }

    public void setLed(LedState led) {
        this.led = led;
    }

    public Servo2State getServo2() {
        return servo2;
    }

    public void setServo2(Servo2State servo2) {
        this.servo2 = servo2;
    }

    public Servo3State getServo3() {
        return servo3;
    }

    public void setServo3(Servo3State servo3) {
        this.servo3 = servo3;
    }

    public FanState getFan() {
        return fan;
    }

    public void setFan(FanState fan) {
        this.fan = fan;
    }

    public DhtState getDht() {
        return dht;
    }

    public void setDht(DhtState dht) {
        this.dht = dht;
    }

    public Mq135State getMq135() {
        return mq135;
    }

    public void setMq135(Mq135State mq135) {
        this.mq135 = mq135;
    }

    public WaterLevelState getWater() {
        return water;
    }

    public void setWater(WaterLevelState water) {
        this.water = water;
    }

    public UltrasonicState getUltrasonic() {
        return ultrasonic;
    }

    public void setUltrasonic(UltrasonicState ultrasonic) {
        this.ultrasonic = ultrasonic;
    }

    public boolean isAutomaticMode() {
        return automaticMode;
    }

    public void setAutomaticMode(boolean automaticMode) {
        this.automaticMode = automaticMode;
    }
}