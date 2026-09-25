#version 460 core
#include <flutter/runtime_effect.glsl>

// Slow cosmic nebula for the RocketEye background.
uniform vec2 uSize;
uniform float uTime;
uniform float uIntensity;

out vec4 fragColor;

float hash(vec2 p) {
  p = fract(p * vec2(123.34, 456.21));
  p += dot(p, p + 45.32);
  return fract(p.x * p.y);
}

float noise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  float a = hash(i);
  float b = hash(i + vec2(1.0, 0.0));
  float c = hash(i + vec2(0.0, 1.0));
  float d = hash(i + vec2(1.0, 1.0));
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
  float v = 0.0;
  float amp = 0.5;
  for (int i = 0; i < 5; i++) {
    v += amp * noise(p);
    p = p * 2.03 + vec2(1.7, 9.2);
    amp *= 0.5;
  }
  return v;
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 uv = frag / uSize;
  float aspect = uSize.x / max(uSize.y, 1.0);
  vec2 p = vec2(uv.x * aspect, uv.y) * 2.2;
  float t = uTime * 0.025;

  vec2 q = vec2(fbm(p + vec2(0.0, t)), fbm(p + vec2(5.2, -t)));
  float n = fbm(p + 2.4 * q + vec2(t * 0.6, t * 0.3));

  vec3 deep = vec3(0.027, 0.024, 0.059);    // #07060F
  vec3 indigo = vec3(0.078, 0.063, 0.149);  // #141026
  vec3 violet = vec3(0.486, 0.361, 1.0);    // #7C5CFF
  vec3 gold = vec3(0.961, 0.722, 0.239);    // #F5B83D
  vec3 teal = vec3(0.10, 0.55, 0.75);

  vec3 col = mix(deep, indigo, smoothstep(0.0, 1.0, uv.y + 0.2));
  col = mix(col, violet * 0.55, smoothstep(0.45, 0.95, n) * 0.55 * uIntensity);
  col = mix(col, teal * 0.35, smoothstep(0.55, 1.0, q.y) * 0.35 * uIntensity);
  col += gold * 0.18 * smoothstep(0.72, 0.98, n * q.x) * uIntensity;

  // Sparse twinkling stars.
  vec2 grid = frag / 3.0;
  float s = hash(floor(grid));
  float star = step(0.9975, s) * (0.55 + 0.45 * sin(uTime * (1.0 + s * 3.0) + s * 40.0));
  col += vec3(star) * 0.8;

  // Vignette.
  float vig = smoothstep(1.25, 0.35, length(uv - 0.5) * 1.6);
  col *= mix(0.55, 1.0, vig);

  fragColor = vec4(col, 1.0);
}
