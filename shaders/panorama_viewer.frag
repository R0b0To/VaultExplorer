#version 460 core

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uYaw;
uniform float uPitch;
uniform float uFov;
uniform float uFullWidth;
uniform float uFullHeight;
uniform float uCropLeft;
uniform float uCropTop;
uniform float uCropWidth;
uniform float uCropHeight;
uniform float uSensor;
uniform vec3 uDevR0;
uniform vec3 uDevR1;
uniform vec3 uDevR2;
uniform sampler2D uImage;

out vec4 fragColor;

const float PI = 3.14159265358979323846;

void main() {
  vec2 screen = FlutterFragCoord().xy / uSize;
  float aspect = uSize.x / max(uSize.y, 1.0);
  float tanHalfFov = tan(uFov * 0.5);
  float screenX = (screen.x * 2.0 - 1.0) * tanHalfFov * aspect;
  float screenY = (1.0 - screen.y * 2.0) * tanHalfFov;

  vec3 direction;
  if (uSensor > 0.5) {
    // Gyro mode: the ray starts in screen space (x right, y up, -z into the
    // screen), is tilted by the local pitch offset, rotated into the world by
    // the device attitude, then turned by the heading offset.
    vec3 rd = normalize(vec3(screenX, screenY, -1.0));
    float cp = cos(uPitch);
    float sp = sin(uPitch);
    rd = vec3(rd.x, rd.y * cp - rd.z * sp, rd.y * sp + rd.z * cp);
    vec3 w = vec3(dot(uDevR0, rd), dot(uDevR1, rd), dot(uDevR2, rd));
    float cy = cos(uYaw);
    float sy = sin(uYaw);
    direction = normalize(vec3(cy * w.x - sy * w.z, w.y, sy * w.x + cy * w.z));
  } else {
    vec3 forward = vec3(
      sin(uYaw) * cos(uPitch),
      sin(uPitch),
      -cos(uYaw) * cos(uPitch)
    );
    vec3 right = vec3(cos(uYaw), 0.0, sin(uYaw));
    vec3 up = vec3(
      -sin(uYaw) * sin(uPitch),
      cos(uPitch),
      cos(uYaw) * sin(uPitch)
    );
    direction = normalize(forward + right * screenX + up * screenY);
  }

  float longitude = atan(direction.x, -direction.z);
  float u = fract(longitude / (2.0 * PI) + 0.5);
  float v = 0.5 - asin(clamp(direction.y, -1.0, 1.0)) / PI;
  vec2 imageUv = vec2(
    (u * uFullWidth - uCropLeft) / uCropWidth,
    (v * uFullHeight - uCropTop) / uCropHeight
  );

  if (imageUv.x < 0.0 || imageUv.x > 1.0 ||
      imageUv.y < 0.0 || imageUv.y > 1.0) {
    fragColor = vec4(0.0, 0.0, 0.0, 1.0);
  } else {
    fragColor = texture(uImage, imageUv);
  }
}
