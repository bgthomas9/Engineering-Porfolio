
#include <Servo.h>

Servo radarServo;

// Pins
const byte SERVO_PIN = 9;
const byte BUZZER_PIN = 4;
const byte TRIG_PIN = 2;
const byte ECHO_PIN = 3;
const byte SPEED_POT = A0;
const byte RANGE_POT = A1;

// Sweep limits
// Start safely at 5-175 degrees
const int MIN_ANGLE = 5;
const int MAX_ANGLE = 175;
const int ANGLE_STEP = 1;

// Radar range
const int MIN_RANGE = 100;
const int MAX_RANGE = 300;

// Timing
const unsigned long PING_INTERVAL = 65;
const unsigned long POT_INTERVAL = 30;

int angle = MIN_ANGLE;
int direction = 1;
int distance = 0;

int radarRange = 100;
int servoDelay = 35;

// Timing variables
unsigned long lastServoMove = 0;
unsigned long lastPing = 0;
unsigned long lastPotRead = 0;

// Buzzer
int buzzerZone = 0;
bool buzzerOn = false;
unsigned long lastBuzzerChange = 0;

// Read potentiometers
void updatePots() {
  int speedValue = analogRead(SPEED_POT);
  int rangeValue = analogRead(RANGE_POT);

  // Smooth 1-degree stepping
  // Fastest = 18ms
  // Slowest = 60ms
  servoDelay = map(
    speedValue, 0, 1023, 60, 18
  );

  // 100-300 cm radar range
  radarRange = map(
    rangeValue, 0, 1023, 100, 300
  );
}

// Calculate detection ring
int getBuzzerZone() {
  if (distance < 2 ||
      distance > radarRange) {
    return 0;
  }

  int zone = (long)(distance - 1) * 4
             / radarRange + 1;

  return constrain(zone, 1, 4);
}

// Smart ring-based buzzer
void updateBuzzer() {
  int newZone = getBuzzerZone();
  unsigned long now = millis();

  if (newZone == 0) {
    noTone(BUZZER_PIN);
    buzzerOn = false;
    buzzerZone = 0;
    return;
  }

  unsigned long onTime;
  unsigned long offTime;

  switch (newZone) {
    case 1:
      onTime = 90;
      offTime = 90;
      break;

    case 2:
      onTime = 80;
      offTime = 300;
      break;

    case 3:
      onTime = 70;
      offTime = 750;
      break;

    default:
      onTime = 55;
      offTime = 1700;
      break;
  }

  if (newZone != buzzerZone) {
    buzzerZone = newZone;
    noTone(BUZZER_PIN);
    buzzerOn = false;
    lastBuzzerChange = now - offTime;
  }

  if (buzzerOn) {
    if (now - lastBuzzerChange >= onTime) {
      noTone(BUZZER_PIN);
      buzzerOn = false;
      lastBuzzerChange = now;
    }
  } else {
    if (now - lastBuzzerChange >= offTime) {
      tone(BUZZER_PIN, 1800);
      buzzerOn = true;
      lastBuzzerChange = now;
    }
  }
}

// Read ultrasonic sensor
int readDistance() {
  digitalWrite(TRIG_PIN, LOW);
  delayMicroseconds(2);

  digitalWrite(TRIG_PIN, HIGH);
  delayMicroseconds(10);
  digitalWrite(TRIG_PIN, LOW);

  unsigned long duration =
    pulseIn(ECHO_PIN, HIGH, 19000UL);

  if (duration == 0) {
    return 0;
  }

  int cm = duration * 0.0343 / 2.0;

  if (cm < 2 || cm > MAX_RANGE) {
    return 0;
  }

  return cm;
}

// Send data to Processing
void sendData() {
  Serial.print(angle);
  Serial.print(",");
  Serial.print(distance);
  Serial.print(",");
  Serial.print(radarRange);
  Serial.print(",");
  Serial.println(servoDelay);
}

void setup() {
  Serial.begin(9600);

  pinMode(TRIG_PIN, OUTPUT);
  pinMode(ECHO_PIN, INPUT);
  pinMode(BUZZER_PIN, OUTPUT);

  digitalWrite(TRIG_PIN, LOW);

  updatePots();

  radarServo.attach(SERVO_PIN);
  radarServo.write(angle);

  delay(500);

  lastServoMove = millis();
  lastPing = millis();
  lastPotRead = millis();
}

void loop() {
  unsigned long now = millis();

  // Regular potentiometer updates
  if (now - lastPotRead >= POT_INTERVAL) {
    updatePots();
    lastPotRead = now;
  }

  // Smooth servo stepping
  if (now - lastServoMove >=
      (unsigned long)servoDelay) {

    // Reverse exactly at endpoints
    if (angle >= MAX_ANGLE) {
      direction = -1;
    } else if (angle <= MIN_ANGLE) {
      direction = 1;
    }

    angle += direction * ANGLE_STEP;

    radarServo.write(angle);
    lastServoMove = now;
  }

  // Separate ultrasonic sampling
  if (now - lastPing >= PING_INTERVAL) {
    distance = readDistance();

    sendData();

    lastPing = millis();
  }

  // Buzzer updates independently
  updateBuzzer();
}