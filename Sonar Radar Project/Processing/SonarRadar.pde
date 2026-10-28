import processing.serial.*;

Serial arduino;

// Arduino connection
String portName = "/dev/cu.usbmodem2101";

// Radar settings
final int MIN_ANGLE = 5;
final int MAX_ANGLE = 175;

int radarRange = 100;
int angle = 5;
int distance = 0;
int servoDelay = 35;

// Detection history
float[] readings = new float[181];
int[] lastSeen = new int[181];

// Green sweep trail
int[] sweepAngles = new int[80];
int[] sweepTimes = new int[80];
int sweepIndex = 0;

// Radar dimensions
float cx, cy, radius;

final int TARGET_LIFETIME = 12000;
final int SWEEP_LIFETIME = 1100;

void setup() {
  size(1100, 720);
  smooth(4);
  frameRate(60);

  cx = width / 2.0;
  cy = height - 100;
  radius = 465;

  for (int i = 0; i < readings.length; i++) {
    readings[i] = -1;
    lastSeen[i] = -100000;
  }

  for (int i = 0; i < sweepAngles.length; i++) {
    sweepAngles[i] = -1;
    sweepTimes[i] = -100000;
  }

  textFont(createFont("Monospaced", 16));

  // Connect to Arduino
  try {
    arduino = new Serial(this, portName, 9600);
    arduino.clear();
    arduino.bufferUntil('\n');

    println("Connected to " + portName);
  }
  catch (Exception e) {
    println("Serial connection error:");
    println(e.getMessage());
  }
}

void draw() {
  background(2, 10, 7);

  drawGrid();
  drawSweepTrail();
  drawTargets();
  drawSweep();
  drawStatus();
}

// Convert radar position to screen
float radarX(float a, float r) {
  return cx - r * cos(radians(a));
}

float radarY(float a, float r) {
  return cy - r * sin(radians(a));
}

// Radar grid
void drawGrid() {
  noFill();
  strokeWeight(1.5);

  // Four radar rings
  for (int i = 1; i <= 4; i++) {
    float r = radius * i / 4.0;

    stroke(0, 160, 70, 180);
    arc(cx, cy, r * 2, r * 2,
        PI, TWO_PI);
  }

  // Baseline
  stroke(0, 200, 80);
  line(cx - radius, cy,
       cx + radius, cy);

  // Angle guides
  for (int a = 0; a <= 180; a += 30) {
    stroke(0, 100, 45, 125);
    strokeWeight(1);

    line(cx, cy,
         radarX(a, radius),
         radarY(a, radius));

    fill(75, 255, 125);
    textAlign(CENTER);
    textSize(13);

    text(a + "°",
         radarX(a, radius + 24),
         radarY(a, radius + 24));
  }

  // Distance labels
  fill(75, 255, 125);
  textAlign(CENTER);
  textSize(13);

  for (int i = 1; i <= 4; i++) {
    int cm = round(radarRange * i / 4.0);
    float x = cx + radius * i / 4.0;

    text(cm + "cm", x, cy - 12);
  }
}

// Fading green trail
void drawSweepTrail() {
  int now = millis();

  for (int i = 0; i < sweepAngles.length; i++) {
    int a = sweepAngles[i];

    if (a < 0) continue;

    int age = now - sweepTimes[i];

    if (age < 0 || age > SWEEP_LIFETIME) {
      continue;
    }

    float alpha = map(
      age, 0, SWEEP_LIFETIME, 115, 0
    );

    stroke(0, 255, 90, alpha);
    strokeWeight(2);

    line(cx, cy,
         radarX(a, radius),
         radarY(a, radius));
  }
}

// Main scanning line
void drawSweep() {
  float x = radarX(angle, radius);
  float y = radarY(angle, radius);

  stroke(0, 255, 90, 35);
  strokeWeight(12);
  line(cx, cy, x, y);

  stroke(85, 255, 140);
  strokeWeight(3);
  line(cx, cy, x, y);

  noStroke();

  fill(110, 255, 150);
  ellipse(x, y, 8, 8);

  fill(50, 255, 120);
  ellipse(cx, cy, 9, 9);
}

// Check valid detection
boolean validTarget(int a) {
  return readings[a] >= 2 &&
         readings[a] <= radarRange &&
         millis() - lastSeen[a] <
         TARGET_LIFETIME;
}

// Draw red object detections
void drawTargets() {
  noStroke();

  for (int a = 0; a <= 180; a++) {

    if (!validTarget(a)) continue;

    int age = millis() - lastSeen[a];

    float alpha = map(
      age, 0, TARGET_LIFETIME, 255, 0
    );

    float r = map(
      readings[a], 0, radarRange,
      0, radius
    );

    float x = radarX(a, r);
    float y = radarY(a, r);

    // Outer red glow
    fill(255, 40, 40, alpha * 0.12);
    ellipse(x, y, 27, 27);

    // Middle glow
    fill(255, 55, 55, alpha * 0.35);
    ellipse(x, y, 16, 16);

    // Bright red point
    fill(255, 80, 80, alpha);
    ellipse(x, y, 7, 7);
  }
}

// Top-left radar information
void drawStatus() {
  textAlign(LEFT);
  textSize(15);
  fill(60, 255, 125);

  text("ANGLE: " + angle + "°",
       20, 25);

  if (distance >= 2 &&
      distance <= radarRange) {

    text("DISTANCE: " + distance + " cm",
         20, 50);

  } else {

    text("DISTANCE: --",
         20, 50);
  }

  text("RADAR RANGE: " +
       radarRange + " cm",
       20, 75);
}

// Read Arduino serial information
void serialEvent(Serial port) {
  String line = port.readStringUntil('\n');

  if (line == null) {
    return;
  }

  line = trim(line);
  String[] parts = split(line, ',');

  // Supports both:
  // angle,distance,range,delay
  // angle,distance,range,delay,measurementFlag
  if (parts.length != 4 && parts.length != 5) {
    println("Unexpected data: " + line);
    return;
  }

  try {
    int newAngle = Integer.parseInt(parts[0]);
    int newDistance = Integer.parseInt(parts[1]);
    int newRange = Integer.parseInt(parts[2]);
    int newDelay = Integer.parseInt(parts[3]);

    int measured = 1;

    if (parts.length == 5) {
      measured = Integer.parseInt(parts[4]);
    }

    // Validate incoming readings
    if (newAngle < 0 || newAngle > 180) {
      return;
    }

    if (newRange < 100 || newRange > 300) {
      return;
    }

    // Update radar
    angle = newAngle;
    radarRange = newRange;
    servoDelay = newDelay;

    // Record green sweep history
    sweepAngles[sweepIndex] = angle;
    sweepTimes[sweepIndex] = millis();

    sweepIndex =
      (sweepIndex + 1) % sweepAngles.length;

    // Update targets only on
    // fresh ultrasonic measurements
    if (measured == 1) {
      distance = newDistance;

      if (distance >= 2 &&
          distance <= 300) {

        if (readings[angle] > 0 &&
            millis() - lastSeen[angle] <
            TARGET_LIFETIME &&
            abs(readings[angle] - distance) < 35) {

          readings[angle] =
            readings[angle] * 0.35 +
            distance * 0.65;

        } else {
          readings[angle] = distance;
        }

      } else {
        readings[angle] = -1;
      }

      lastSeen[angle] = millis();
    }
  }
  catch (NumberFormatException e) {
    println("Invalid serial data: " + line);
  }
}
