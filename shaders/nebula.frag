#version 460 core
#include <flutter/runtime_effect.glsl>

// Rockketeyes galaxy backdrop: spiral galaxy, layered twinkling starfield,
// shooting stars, an occasional comet and soft nebula gas.
uniform vec2 uSize;
uniform float uTime;
uniform float uIntensity;

out vec4 fragColor;

const float PI = 3.14159265;

float hash11(float p) {
  p = fract(p * 0.1031);
  p *= p + 33.33;
  p *= p + p;
  return fract(p);
}

float hash21(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.xx + p3.yz) * p3.zy);
}

float noise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
             mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
  float v = 0.0;
  float a = 0.5;
  for (int i = 0; i < 5; i++) {
    v += a * noise(p);
    p = p * 2.03 + vec2(1.7, 9.2);
    a *= 0.5;
  }
  return v;
}

mat2 rot(float a) {
  float c = cos(a), s = sin(a);
  return mat2(c, -s, s, c);
}

// Distance from p to segment ab, plus position along it (0 at a, 1 at b).
vec2 segment(vec2 p, vec2 a, vec2 b) {
  vec2 pa = p - a, ba = b - a;
  float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-6), 0.0, 1.0);
  return vec2(length(pa - ba * h), h);
}

// One twinkling star layer. Returns additive color.
vec3 starLayer(vec2 p, float scale, float density, float drift, float t, float seed) {
  vec2 q = p * scale + vec2(t * drift, t * drift * 0.35);
  vec2 cell = floor(q);
  vec2 f = fract(q) - 0.5;
  float h = hash21(cell + seed);
  if (h > density) return vec3(0.0);
  vec2 off = (hash22(cell + seed * 1.7) - 0.5) * 0.7;
  vec2 d = f - off;
  float size = mix(0.02, 0.085, pow(hash11(h * 91.7), 3.0));
  float core = smoothstep(size, 0.0, length(d));
  float glow = exp(-dot(d, d) / (size * size * 9.0)) * 0.35;
  float tw = 0.65 + 0.35 * sin(t * (1.2 + h * 4.0) + h * 60.0);
  // Diffraction spikes for the brightest stars.
  float spikes = 0.0;
  if (size > 0.06) {
    spikes = (exp(-abs(d.x) * 90.0) * exp(-abs(d.y) * 9.0) + exp(-abs(d.y) * 90.0) * exp(-abs(d.x) * 9.0)) * 0.45;
  }
  float temp = hash11(h * 13.1);
  vec3 col = temp < 0.2 ? vec3(1.0, 0.82, 0.62) : (temp > 0.75 ? vec3(0.7, 0.82, 1.0) : vec3(1.0, 0.97, 0.94));
  return col * (core + glow + spikes) * tw;
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 uv = frag / uSize;
  vec2 p = (frag - 0.5 * uSize) / uSize.y;   // aspect-correct, centred
  float t = uTime;
  float k = uIntensity;

  // Deep space.
  vec3 col = mix(vec3(0.020, 0.018, 0.045), vec3(0.060, 0.048, 0.115), smoothstep(-0.6, 0.8, -p.y + 0.2));

  // Nebula gas.
  vec2 np = p * 1.6 + vec2(t * 0.004, -t * 0.002);
  float n1 = fbm(np + fbm(np * 0.8 + 3.1));
  float n2 = fbm(np * 1.7 - vec2(4.3, 1.2));
  col += vec3(0.30, 0.18, 0.62) * smoothstep(0.52, 0.95, n1) * 0.45 * k;
  col += vec3(0.05, 0.32, 0.42) * smoothstep(0.58, 1.0, n2) * 0.30 * k;

  // Spiral galaxy (tilted disc, slowly rotating).
  vec2 gc = vec2(0.34 * (uSize.x / uSize.y) * 0.55, -0.22);
  vec2 g = rot(0.55) * (p - gc);
  g.y /= 0.42;                                  // inclination
  float r = length(g);
  float a = atan(g.y, g.x) + t * 0.012;
  float arms = 0.5 + 0.5 * cos(2.0 * a - log(r + 0.02) * 4.2);
  float disc = exp(-r * 4.2);
  float dust = smoothstep(0.35, 0.75, fbm(g * 9.0 + vec2(a * 0.6, 0.0)));
  float armLight = pow(arms, 3.0) * disc * (0.55 + 0.45 * fbm(g * 14.0));
  vec3 armCol = mix(vec3(0.62, 0.72, 1.0), vec3(1.0, 0.86, 0.95), fbm(g * 6.0));
  col += armCol * armLight * 0.9 * k * (1.0 - 0.55 * dust * disc);
  float hii = smoothstep(0.78, 0.95, fbm(g * 22.0 + 7.0)) * pow(arms, 2.0) * disc;
  col += vec3(1.0, 0.35, 0.55) * hii * 0.8 * k;
  col += vec3(1.0, 0.86, 0.60) * (exp(-r * r * 90.0) * 1.1 + exp(-r * 11.0) * 0.35) * k;

  // Starfield: far, mid, near (parallax drift).
  col += starLayer(p, 150.0, 0.30, 0.10, t, 1.0) * 0.55;
  col += starLayer(p, 70.0, 0.20, 0.22, t, 7.0) * 0.8;
  col += starLayer(p, 32.0, 0.12, 0.45, t, 13.0);

  // Shooting stars: four independent slots.
  float aspect = uSize.x / uSize.y;
  for (int i = 0; i < 4; i++) {
    float fi = float(i);
    float period = 5.5 + fi * 1.9;
    float cycle = floor((t + fi * 2.3) / period);
    float lt = mod(t + fi * 2.3, period);
    float seed = hash11(cycle * 7.13 + fi * 3.7);
    float dur = 0.7 + seed * 0.6;
    if (lt < dur && hash11(seed * 51.0) > 0.25) {
      vec2 start = vec2((hash11(seed * 17.0) - 0.2) * aspect, -0.55 + hash11(seed * 29.0) * 0.6);
      vec2 dir = normalize(vec2(-0.55 - hash11(seed * 3.0) * 0.5, 0.35 + hash11(seed * 5.0) * 0.4));
      float speed = 1.3 + seed * 0.9;
      vec2 head = start + dir * speed * lt;
      float len = 0.22 + seed * 0.18;
      vec2 sd = segment(p, head - dir * len, head);
      float life = sin(PI * clamp(lt / dur, 0.0, 1.0));
      float w = mix(0.0007, 0.0035, sd.y);
      float line = exp(-sd.x * sd.x / (w * w)) * pow(sd.y, 2.2) * life;
      float headGlow = exp(-dot(p - head, p - head) / 0.00008) * life;
      col += vec3(0.85, 0.92, 1.0) * line * 1.3 + vec3(1.0, 0.92, 0.78) * headGlow;
    }
  }

  // Comet: one slow crossing every ~32 s.
  {
    float period = 32.0;
    float cycle = floor((t + 9.0) / period);
    float lt = mod(t + 9.0, period);
    float seed = hash11(cycle * 3.77 + 0.5);
    float dur = 18.0;
    if (lt < dur) {
      float s = lt / dur;
      vec2 from = vec2((0.62 + seed * 0.2) * aspect * 0.5 + 0.1, -0.52 + seed * 0.25);
      vec2 to = vec2(-0.7 * aspect * 0.5 - 0.1, 0.05 + seed * 0.3);
      vec2 head = mix(from, to, s) + vec2(0.0, sin(s * PI) * 0.06);
      float fade = smoothstep(0.0, 0.12, s) * smoothstep(1.0, 0.85, s);
      // Tails point away from the galaxy core, like a comet away from the sun.
      vec2 away = normalize(head - gc + vec2(1e-4));
      vec2 perp = vec2(-away.y, away.x);
      vec2 d = p - head;
      float u = dot(d, away);
      float v = dot(d, perp);
      float ion = 0.0;
      float dustTail = 0.0;
      if (u > 0.0) {
        float wi = 0.003 + u * 0.026;
        ion = exp(-v * v / (wi * wi)) * exp(-u * 4.6);
        float vd = v - u * u * 0.9;
        float wd = 0.008 + u * 0.10;
        dustTail = exp(-vd * vd / (wd * wd)) * exp(-u * 6.0);
      }
      float coma = exp(-dot(d, d) / 0.00045);
      float nucleus = exp(-dot(d, d) / 0.000015);
      col += (vec3(0.45, 0.75, 1.0) * ion * 0.9 + vec3(1.0, 0.85, 0.55) * dustTail * 0.7
              + vec3(0.75, 0.95, 1.0) * coma * 0.8 + vec3(1.0) * nucleus) * fade;
    }
  }

  // Planet flybys: every 46 s the "rocket" passes a world (Earth + Moon,
  // Jupiter, Saturn, Mars). It drifts in small, grows as we approach, exits.
  {
    float period = 46.0;
    float lt = mod(t - 5.0, period);
    float scene = mod(floor((t - 5.0) / period), 4.0);
    float dur = 26.0;
    if (t > 5.0 && lt < dur) {
      float s = lt / dur;
      float ease = s * s * (3.0 - 2.0 * s);
      vec2 center = vec2(mix(0.75, -0.75, ease) * aspect * 0.62, mix(-0.12, 0.10, ease) + sin(s * PI) * -0.05);
      // Smaller on tall portrait screens so titles stay readable.
      float R = mix(0.05, 0.19, sin(s * PI * 0.92 + 0.1)) * mix(0.62, 1.0, clamp((aspect - 0.45) / 0.9, 0.0, 1.0));
      float fade = smoothstep(0.0, 0.08, s) * smoothstep(1.0, 0.9, s);
      vec3 L = normalize(vec3(0.75, -0.45, 0.55));
      vec2 q = (p - center) / R;
      float rq = length(q);

      // Saturn's ring (drawn around the sphere; front half over it).
      float ringFront = 0.0;
      vec3 ringCol = vec3(0.0);
      if (scene > 1.5 && scene < 2.5) {
        vec2 rqv = rot(-0.35) * q;
        float rr = length(vec2(rqv.x, rqv.y / 0.26));
        if (rr > 1.3 && rr < 2.35) {
          float band = 0.55 + 0.45 * sin(rr * 38.0) * sin(rr * 11.0 + 1.0);
          float gap = smoothstep(0.02, 0.05, abs(rr - 1.95));
          float a = smoothstep(1.3, 1.4, rr) * smoothstep(2.35, 2.2, rr) * gap;
          ringCol = mix(vec3(0.78, 0.68, 0.52), vec3(0.95, 0.88, 0.72), band) * a * 0.9;
          ringFront = rqv.y > 0.0 ? 1.0 : 0.0;
          if (rqv.y <= 0.0 || rq > 1.0) col += ringCol * fade * (rq < 1.0 ? 0.0 : 1.0) * (rqv.y > 0.0 ? 0.0 : 1.0);
        }
      }

      if (rq < 1.0) {
        float z = sqrt(1.0 - rq * rq);
        vec3 n = vec3(q.x, -q.y, z);
        float lon = atan(n.x, n.z) + t * 0.05;
        float lat = asin(clamp(n.y, -1.0, 1.0));
        vec2 tc = vec2(lon, lat);
        float diff = clamp(dot(n, L), 0.0, 1.0);
        float light = smoothstep(-0.05, 0.35, dot(n, L)) * (0.25 + 0.75 * diff);
        vec3 surf;
        if (scene < 0.5) {
          // Earth: oceans, continents, polar ice, clouds.
          float land = fbm(tc * vec2(1.6, 2.2) + 11.0);
          float cont = smoothstep(0.52, 0.56, land);
          vec3 ocean = mix(vec3(0.02, 0.10, 0.32), vec3(0.05, 0.28, 0.55), fbm(tc * 3.0));
          vec3 ground = mix(vec3(0.16, 0.38, 0.14), vec3(0.55, 0.45, 0.25), smoothstep(0.56, 0.72, land));
          surf = mix(ocean, ground, cont);
          surf = mix(surf, vec3(0.95), smoothstep(1.15, 1.35, abs(lat)));
          float clouds = smoothstep(0.52, 0.75, fbm(tc * vec2(2.4, 3.2) + vec2(t * 0.03, 0.0)));
          surf = mix(surf, vec3(1.0), clouds * 0.85);
          float spec = pow(clamp(dot(reflect(-L, n), vec3(0.0, 0.0, 1.0)), 0.0, 1.0), 24.0) * (1.0 - cont) * (1.0 - clouds);
          surf += vec3(0.6, 0.7, 0.9) * spec * 0.6;
        } else if (scene < 1.5) {
          // Jupiter: turbulent bands and the Great Red Spot.
          float turb = fbm(tc * vec2(3.0, 9.0) + vec2(t * 0.02, 0.0)) * 0.9;
          float bands = sin(lat * 14.0 + turb * 2.4);
          surf = mix(vec3(0.62, 0.45, 0.32), vec3(0.93, 0.86, 0.74), 0.5 + 0.5 * bands);
          surf = mix(surf, vec3(0.78, 0.55, 0.40), smoothstep(0.6, 0.9, fbm(tc * 6.0)) * 0.5);
          vec2 gs = vec2(mod(lon - 1.2, 2.0 * PI) - PI, lat + 0.36);
          float spot = exp(-dot(gs / vec2(0.34, 0.16), gs / vec2(0.34, 0.16)));
          surf = mix(surf, vec3(0.78, 0.32, 0.20), spot * 0.9);
        } else if (scene < 2.5) {
          // Saturn: soft golden bands.
          float bands = sin(lat * 11.0 + fbm(tc * vec2(2.0, 8.0)) * 1.2);
          surf = mix(vec3(0.80, 0.68, 0.48), vec3(0.95, 0.88, 0.70), 0.5 + 0.5 * bands);
        } else {
          // Mars: rust plains, dark maria, polar cap.
          float m = fbm(tc * vec2(2.0, 2.6) + 4.0);
          surf = mix(vec3(0.72, 0.30, 0.14), vec3(0.45, 0.18, 0.10), smoothstep(0.45, 0.7, m));
          surf = mix(surf, vec3(0.95, 0.92, 0.88), smoothstep(1.2, 1.35, lat));
        }
        vec3 planet = surf * light;
        // Atmospheric rim (Earth strongest).
        float rim = pow(1.0 - z, 3.0) * smoothstep(-0.2, 0.4, dot(n, L));
        vec3 atm = scene < 0.5 ? vec3(0.35, 0.6, 1.0) : (scene > 2.5 ? vec3(0.9, 0.5, 0.35) : vec3(0.9, 0.8, 0.6));
        planet += atm * rim * (scene < 0.5 ? 0.9 : 0.35);
        float edge = smoothstep(1.0, 0.985, rq);
        col = mix(col, planet, edge * fade);
        // Ring shadow on the planet, then the front ring.
        if (ringFront > 0.5) col += ringCol * fade;
      } else {
        // Outer atmosphere glow.
        float halo = exp(-(rq - 1.0) * 14.0) * (scene < 0.5 ? 0.35 : 0.12);
        vec3 atm = scene < 0.5 ? vec3(0.35, 0.6, 1.0) : vec3(0.9, 0.75, 0.55);
        col += atm * halo * fade;
        if (ringFront > 0.5) col += ringCol * fade;
      }

      // Earth's Moon orbiting nearby.
      if (scene < 0.5) {
        float ma = t * 0.18;
        vec2 mc = center + vec2(cos(ma) * R * 2.2, sin(ma) * R * 0.6);
        float mr = R * 0.27;
        vec2 mq = (p - mc) / mr;
        float mrq = length(mq);
        bool behind = sin(ma) < 0.0 && length(p - center) < R;
        if (mrq < 1.0 && !behind) {
          float mz = sqrt(1.0 - mrq * mrq);
          vec3 mn = vec3(mq.x, -mq.y, mz);
          float craters = fbm(mq * 3.5 + 20.0);
          vec3 moonSurf = mix(vec3(0.45), vec3(0.78), craters);
          float ml = smoothstep(-0.05, 0.4, dot(mn, L)) * (0.2 + 0.8 * clamp(dot(mn, L), 0.0, 1.0));
          col = mix(col, moonSurf * ml, smoothstep(1.0, 0.95, mrq) * fade);
        }
      }
    }
  }

  // Vignette and gentle tone mapping.
  float vig = smoothstep(1.35, 0.3, length((uv - 0.5) * vec2(1.2, 1.0)) * 1.6);
  col *= mix(0.6, 1.0, vig);
  col = col / (1.0 + col * 0.35);

  fragColor = vec4(col, 1.0);
}
