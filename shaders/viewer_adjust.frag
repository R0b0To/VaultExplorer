#version 460 core

// Live picture adjustments for the media viewer, used through
// ImageFilter.shader. Uniform order matters: the engine fills float 0 and 1
// (uSize) and sampler 0 (uTex); Dart sets the rest starting at float index 2.
//
// Pipeline order: gamma, brightness, contrast, saturation, hue.
// Works on un-premultiplied, gamma-encoded sRGB.

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uBrightness;
uniform float uContrast;
uniform float uSaturation;
uniform float uHue;   // radians
uniform float uGamma;
uniform sampler2D uTex;

out vec4 fragColor;

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec4 c = texture(uTex, uv);
  vec3 rgb = c.a > 0.0 ? c.rgb / c.a : c.rgb;

  rgb = pow(max(rgb, vec3(0.0)), vec3(1.0 / uGamma));
  rgb += uBrightness;
  rgb = (rgb - 0.5) * uContrast + 0.5;

  float l = dot(rgb, vec3(0.2126, 0.7152, 0.0722));
  rgb = mix(vec3(l), rgb, uSaturation);

  // Hue: rotate around the gray axis (Rodrigues, k = 1/sqrt(3)).
  float s = sin(uHue);
  float co = cos(uHue);
  vec3 k = vec3(0.57735027);
  rgb = rgb * co + cross(k, rgb) * s + k * dot(k, rgb) * (1.0 - co);

  fragColor = vec4(clamp(rgb, 0.0, 1.0) * c.a, c.a);
}
