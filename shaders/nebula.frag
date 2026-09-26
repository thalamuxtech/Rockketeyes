#version 460 core
#include <flutter/runtime_effect.glsl>

// Rockketeyes space journey. The camera flies forward through space and
// visits a new place every SEG seconds, jumping between them at warp speed:
//   0 spiral galaxy · 1 emission nebula · 2 planet flyby · 3 black hole
// Shooting stars and comets appear along the way. uCalm (0..1) fades the
// journey down to a quiet starfield (used while playing).
uniform vec2 uSize;
uniform float uTime;
uniform float uIntensity;
uniform float uCalm;

out vec4 fragColor;

const float PI = 3.14159265;
const float SEG = 34.0;

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

vec2 segment(vec2 p, vec2 a, vec2 b) {
  vec2 pa = p - a, ba = b - a;
  float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-6), 0.0, 1.0);
  return vec2(length(pa - ba * h), h);
}

vec3 starColor(float h) {
  return h < 0.2 ? vec3(1.0, 0.82, 0.62) : (h > 0.75 ? vec3(0.7, 0.82, 1.0) : vec3(1.0, 0.97, 0.94));
}

// A layer of stars at a given zoom; `stretch` elongates them radially (warp).
vec3 starLayer(vec2 p, float scale, float density, float t, float seed, float stretch) {
  vec2 q = p * scale;
  vec2 cell = floor(q);
  vec2 f = fract(q) - 0.5;
  float h = hash21(cell + seed);
  if (h > density) return vec3(0.0);
  vec2 off = (hash22(cell + seed * 1.7) - 0.5) * 0.7;
  vec2 d = f - off;
  vec2 radial = normalize(p + vec2(1e-5));
  float along = dot(d, radial);
  float across = dot(d, vec2(-radial.y, radial.x));
  d = vec2(along / (1.0 + stretch), across);
  float size = mix(0.02, 0.085, pow(hash11(h * 91.7), 3.0));
  float core = smoothstep(size, 0.0, length(d));
  float glow = exp(-dot(d, d) / (size * size * 9.0)) * 0.35;
  float tw = 0.65 + 0.35 * sin(t * (1.2 + h * 4.0) + h * 60.0);
  float spikes = 0.0;
  if (size > 0.06 && stretch < 0.5) {
    spikes = (exp(-abs(d.x) * 90.0) * exp(-abs(d.y) * 9.0) + exp(-abs(d.y) * 90.0) * exp(-abs(d.x) * 9.0)) * 0.45;
  }
  // Fade out before the cell edge so no glow is ever clipped into a square.
  float edge = smoothstep(0.5, 0.36, max(abs(f.x), abs(f.y)));
  return starColor(hash11(h * 13.1)) * (core + glow + spikes) * tw * edge;
}

vec3 galaxy(vec2 p, vec2 c, float scale, float t) {
  vec2 g = rot(0.55) * (p - c) / scale;
  g.y /= 0.42;
  float r = length(g);
  float a = atan(g.y, g.x) + t * 0.015;
  float arms = 0.5 + 0.5 * cos(2.0 * a - log(r + 0.02) * 4.2);
  float disc = exp(-r * 4.2);
  float dust = smoothstep(0.35, 0.75, fbm(g * 9.0 + vec2(a * 0.6, 0.0)));
  float armLight = pow(arms, 3.0) * disc * (0.55 + 0.45 * fbm(g * 14.0));
  vec3 armCol = mix(vec3(0.62, 0.72, 1.0), vec3(1.0, 0.86, 0.95), fbm(g * 6.0));
  vec3 col = armCol * armLight * 0.95 * (1.0 - 0.55 * dust * disc);
  float hii = smoothstep(0.78, 0.95, fbm(g * 22.0 + 7.0)) * pow(arms, 2.0) * disc;
  col += vec3(1.0, 0.35, 0.55) * hii * 0.8;
  col += vec3(1.0, 0.86, 0.60) * (exp(-r * r * 90.0) * 0.75 + exp(-r * 11.0) * 0.28);
  return col;
}

vec3 emissionNebula(vec2 p, vec2 c, float scale, float t) {
  vec2 q = (p - c) / scale;
  vec2 w = q * 1.4 + vec2(t * 0.01, 0.0);
  float warp1 = fbm(w + fbm(w * 1.3 + 2.0) * 1.6);
  float warp2 = fbm(w * 1.8 - 5.0 + warp1);
  float body = exp(-dot(q, q) * 1.6);
  vec3 col = vec3(0.0);
  col += vec3(0.95, 0.25, 0.55) * smoothstep(0.42, 0.9, warp1) * body * 1.1;
  col += vec3(0.10, 0.75, 0.80) * smoothstep(0.5, 0.95, warp2) * body * 0.8;
  col += vec3(1.0, 0.62, 0.25) * smoothstep(0.62, 1.0, warp1 * warp2 * 1.6) * body * 0.9;
  float pillars = smoothstep(0.45, 0.7, fbm(vec2(q.x * 3.0, q.y * 1.2) + 12.0)) * smoothstep(0.2, -0.6, q.y);
  col *= 1.0 - 0.75 * pillars;
  vec2 sc = floor(q * 28.0);
  float sh = hash21(sc + 3.0);
  if (sh < 0.04) {
    vec2 sd = fract(q * 28.0) - 0.5 - (hash22(sc) - 0.5) * 0.6;
    float tw = 0.6 + 0.4 * sin(t * 3.0 + sh * 90.0);
    col += vec3(0.85, 0.95, 1.0) * exp(-dot(sd, sd) * 180.0) * tw * body * 2.0;
  }
  return col;
}

// Returns disk/ring light; .a = 1 inside the event horizon.
vec4 blackHole(vec2 p, vec2 c, float scale, float t) {
  vec2 d = (p - c) / scale;
  float r = length(d);
  float rh = 0.11;
  vec2 dd = rot(-0.28) * d;
  vec2 e = vec2(dd.x, dd.y / 0.22);
  float er = length(e);
  float ang = atan(e.y, e.x) + t * 0.6;
  float swirl = 0.6 + 0.4 * sin(ang * 3.0 + er * 30.0 - t * 2.0) * fbm(vec2(ang * 2.0, er * 12.0));
  float disk = smoothstep(rh * 1.35, rh * 1.6, er) * smoothstep(rh * 4.2, rh * 2.0, er);
  float doppler = 0.55 + 0.45 * cos(atan(e.y, e.x) - 0.3);
  vec3 hot = mix(vec3(1.0, 0.45, 0.12), vec3(1.0, 0.92, 0.75), smoothstep(rh * 3.5, rh * 1.6, er));
  vec3 col = vec3(0.0);
  float ring = exp(-pow((r - rh * 1.5) / (rh * 0.08), 2.0)) * 1.4;
  float arch = exp(-pow((r - rh * 1.9) / (rh * 0.35), 2.0)) * smoothstep(0.1, -0.6, d.y / max(r, 1e-3)) * 0.8;
  col += vec3(1.0, 0.85, 0.6) * ring + hot * arch * swirl;
  if (dd.y > 0.0 || r > rh) col += hot * disk * swirl * doppler * 1.6;
  float horizon = smoothstep(rh * 1.02, rh * 0.96, r);
  return vec4(col * (1.0 - horizon), horizon);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 uv = frag / uSize;
  vec2 p = (frag - 0.5 * uSize) / uSize.y;
  float aspect = uSize.x / uSize.y;
  float t = uTime;
  float k = uIntensity;
  float live = 1.0 - clamp(uCalm, 0.0, 1.0);

  // Journey timeline.
  float seg = floor(t / SEG);
  float lt = mod(t, SEG);
  float place = mod(seg, 4.0);
  float warpOut = smoothstep(SEG - 2.6, SEG - 0.3, lt);
  float warpIn = 1.0 - smoothstep(0.0, 1.8, lt);
  float warp = max(warpOut, warpIn) * live;
  float visible = smoothstep(1.2, 4.0, lt) * (1.0 - smoothstep(SEG - 4.0, SEG - 1.6, lt)) * live;
  float prog = lt / SEG;

  vec3 col = mix(vec3(0.018, 0.016, 0.040), vec3(0.055, 0.044, 0.105), smoothstep(-0.6, 0.8, -p.y + 0.2));

  vec2 np = p * 1.6 + vec2(t * 0.004, -t * 0.002);
  float n1 = fbm(np + fbm(np * 0.8 + 3.1));
  col += vec3(0.28, 0.17, 0.58) * smoothstep(0.55, 0.95, n1) * 0.30 * k;

  // Where the place sits; we approach it while it drifts past.
  float side = hash11(seg * 3.1 + 0.2) > 0.5 ? 1.0 : -1.0;
  // Portrait phones: smaller and further off-centre so titles stay readable.
  float pf = clamp((aspect - 0.45) / 0.9, 0.0, 1.0);
  vec2 placePos = vec2(side * mix(0.35, -0.15, prog) * max(aspect, 0.95) * 0.6, mix(-0.12, 0.06, prog) + (hash11(seg * 7.7) - 0.5) * 0.15);
  float approach = mix(0.8, 1.35, prog) * mix(0.7, 1.0, pf);

  // Black hole lensing bends the stars behind it.
  vec2 sp = p;
  vec4 hole = vec4(0.0);
  bool isHole = place > 2.5 && visible > 0.001;
  if (isHole) {
    hole = blackHole(p, placePos, approach, t);
    vec2 d = p - placePos;
    float r = max(length(d), 0.015);
    float rs = 0.11 * approach;
    sp = p - normalize(d) * (rs * rs * 1.6) / r * visible;
  }

  // Starfield: forward flight, stars stream out from the centre; faster and
  // stretched into streaks during warp.
  float speed = 0.035 + warp * 1.4;
  vec3 stars = starLayer(sp, 150.0, 0.30, t, 1.0, 0.0) * 0.5;
  for (int i = 0; i < 3; i++) {
    float fi = float(i);
    float depth = fract(t * speed * (0.6 + fi * 0.2) + fi / 3.0);
    float sc = mix(70.0, 6.0, depth);
    float fade = smoothstep(0.0, 0.25, depth) * smoothstep(1.0, 0.85, depth);
    // Short stretch only: long streaks come from the hyperspace lanes below
    // (a star can't extend past its grid cell without looking blocky).
    stars += starLayer(sp, sc, 0.16, t, 5.0 + fi * 11.0, warp * 2.2 * depth) * fade * (0.8 + warp * 0.6);
  }
  col += stars;

  // Hyperspace streaks and arrival flash.
  if (warp > 0.001) {
    float ang = atan(p.y, p.x);
    float r = length(p);
    float lane = floor(ang * 140.0 / PI);
    float lh = hash11(lane * 1.37);
    float streak = step(0.62, lh) * smoothstep(0.02, 0.2, r) * (0.5 + 0.5 * hash11(lane * 7.1));
    float flow = fract(r * 1.5 - t * (2.5 + lh * 3.0) + lh * 10.0);
    float line = smoothstep(0.0, 0.3, flow) * smoothstep(0.6, 0.3, flow);
    col += mix(vec3(0.6, 0.75, 1.0), vec3(1.0, 0.9, 0.8), lh) * streak * line * warp * 1.2;
    col += vec3(0.75, 0.85, 1.0) * pow(warp, 3.0) * 0.35 * exp(-r * 2.5);
  }

  // The place itself.
  if (visible > 0.001) {
    if (place < 0.5) {
      col += galaxy(p, placePos, approach, t) * visible * k;
    } else if (place < 1.5) {
      col += emissionNebula(p, placePos, approach * 0.9, t) * visible * k;
    } else if (isHole) {
      col = mix(col, vec3(0.0), hole.a * visible);
      col += hole.rgb * visible;
    }
  }

  // Planet system: the rocket passes a world.
  if (place > 1.5 && place < 2.5 && visible > 0.001) {
    float scene = mod(floor(seg / 4.0), 4.0);
    float s = clamp((lt - 1.5) / (SEG - 3.5), 0.0, 1.0);
    float ease = s * s * (3.0 - 2.0 * s);
    vec2 center = vec2(side * mix(0.75, -0.75, ease) * aspect * 0.62, mix(-0.12, 0.10, ease) + sin(s * PI) * -0.05);
    float R = mix(0.05, 0.19, sin(s * PI * 0.92 + 0.1)) * mix(0.62, 1.0, clamp((aspect - 0.45) / 0.9, 0.0, 1.0));
    float fade = visible;
    vec3 L = normalize(vec3(0.75, -0.45, 0.55));
    vec2 q = (p - center) / R;
    float rq = length(q);

    float ringFront = 0.0;
    vec3 ringCol = vec3(0.0);
    if (scene > 1.5 && scene < 2.5) {
      vec2 rqv = rot(-0.35) * q;
      float rr = length(vec2(rqv.x, rqv.y / 0.26));
      if (rr > 1.3 && rr < 2.35) {
        float band = 0.55 + 0.45 * sin(rr * 38.0) * sin(rr * 11.0 + 1.0);
        float gap = smoothstep(0.02, 0.05, abs(rr - 1.95));
        float ra = smoothstep(1.3, 1.4, rr) * smoothstep(2.35, 2.2, rr) * gap;
        ringCol = mix(vec3(0.78, 0.68, 0.52), vec3(0.95, 0.88, 0.72), band) * ra * 0.9;
        ringFront = rqv.y > 0.0 ? 1.0 : 0.0;
        if (rqv.y <= 0.0 && rq > 1.0) col += ringCol * fade;
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
        float turb = fbm(tc * vec2(3.0, 9.0) + vec2(t * 0.02, 0.0)) * 0.9;
        float bands = sin(lat * 14.0 + turb * 2.4);
        surf = mix(vec3(0.62, 0.45, 0.32), vec3(0.93, 0.86, 0.74), 0.5 + 0.5 * bands);
        surf = mix(surf, vec3(0.78, 0.55, 0.40), smoothstep(0.6, 0.9, fbm(tc * 6.0)) * 0.5);
        vec2 gs = vec2(mod(lon - 1.2, 2.0 * PI) - PI, lat + 0.36);
        float spot = exp(-dot(gs / vec2(0.34, 0.16), gs / vec2(0.34, 0.16)));
        surf = mix(surf, vec3(0.78, 0.32, 0.20), spot * 0.9);
      } else if (scene < 2.5) {
        float bands = sin(lat * 11.0 + fbm(tc * vec2(2.0, 8.0)) * 1.2);
        surf = mix(vec3(0.80, 0.68, 0.48), vec3(0.95, 0.88, 0.70), 0.5 + 0.5 * bands);
      } else {
        float m = fbm(tc * vec2(2.0, 2.6) + 4.0);
        surf = mix(vec3(0.72, 0.30, 0.14), vec3(0.45, 0.18, 0.10), smoothstep(0.45, 0.7, m));
        surf = mix(surf, vec3(0.95, 0.92, 0.88), smoothstep(1.2, 1.35, lat));
      }
      vec3 planet = surf * light;
      float rim = pow(1.0 - z, 3.0) * smoothstep(-0.2, 0.4, dot(n, L));
      vec3 atm = scene < 0.5 ? vec3(0.35, 0.6, 1.0) : (scene > 2.5 ? vec3(0.9, 0.5, 0.35) : vec3(0.9, 0.8, 0.6));
      planet += atm * rim * (scene < 0.5 ? 0.9 : 0.35);
      col = mix(col, planet, smoothstep(1.0, 0.985, rq) * fade);
      if (ringFront > 0.5) col += ringCol * fade;
    } else {
      float halo = exp(-(rq - 1.0) * 14.0) * (scene < 0.5 ? 0.35 : 0.12);
      col += (scene < 0.5 ? vec3(0.35, 0.6, 1.0) : vec3(0.9, 0.75, 0.55)) * halo * fade;
      if (ringFront > 0.5) col += ringCol * fade;
    }

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
        vec3 moonSurf = mix(vec3(0.45), vec3(0.78), fbm(mq * 3.5 + 20.0));
        float ml = smoothstep(-0.05, 0.4, dot(mn, L)) * (0.2 + 0.8 * clamp(dot(mn, L), 0.0, 1.0));
        col = mix(col, moonSurf * ml, smoothstep(1.0, 0.95, mrq) * fade);
      }
    }
  }

  // Shooting stars (paused during warp).
  float meteorGate = live * (1.0 - warp);
  for (int i = 0; i < 4; i++) {
    float fi = float(i);
    float period = 5.5 + fi * 1.9;
    float cycle = floor((t + fi * 2.3) / period);
    float mt = mod(t + fi * 2.3, period);
    float seed = hash11(cycle * 7.13 + fi * 3.7);
    float dur = 0.7 + seed * 0.6;
    if (mt < dur && hash11(seed * 51.0) > 0.25 && meteorGate > 0.01) {
      vec2 start = vec2((hash11(seed * 17.0) - 0.2) * aspect, -0.55 + hash11(seed * 29.0) * 0.6);
      vec2 dir = normalize(vec2(-0.55 - hash11(seed * 3.0) * 0.5, 0.35 + hash11(seed * 5.0) * 0.4));
      vec2 head = start + dir * (1.3 + seed * 0.9) * mt;
      float len = 0.22 + seed * 0.18;
      vec2 sd = segment(p, head - dir * len, head);
      float life = sin(PI * clamp(mt / dur, 0.0, 1.0));
      float w = mix(0.0007, 0.0035, sd.y);
      float line = exp(-sd.x * sd.x / (w * w)) * pow(sd.y, 2.2) * life;
      float headGlow = exp(-dot(p - head, p - head) / 0.00008) * life;
      col += (vec3(0.85, 0.92, 1.0) * line * 1.3 + vec3(1.0, 0.92, 0.78) * headGlow) * meteorGate;
    }
  }

  // Comet: a slow crossing now and then.
  {
    float period = 41.0;
    float cycle = floor((t + 9.0) / period);
    float ct = mod(t + 9.0, period);
    float seed = hash11(cycle * 3.77 + 0.5);
    float dur = 16.0;
    if (ct < dur && meteorGate > 0.01) {
      float s = ct / dur;
      vec2 from = vec2((0.62 + seed * 0.2) * aspect * 0.5 + 0.1, -0.52 + seed * 0.25);
      vec2 to = vec2(-0.7 * aspect * 0.5 - 0.1, 0.05 + seed * 0.3);
      vec2 head = mix(from, to, s) + vec2(0.0, sin(s * PI) * 0.06);
      float fade = smoothstep(0.0, 0.12, s) * smoothstep(1.0, 0.85, s) * meteorGate;
      vec2 away = normalize(head - vec2(0.3, -0.25) + vec2(1e-4));
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

  float vig = smoothstep(1.35, 0.3, length((uv - 0.5) * vec2(1.2, 1.0)) * 1.6);
  col *= mix(0.6, 1.0, vig);
  col = col / (1.0 + col * 0.35);
  fragColor = vec4(col, 1.0);
}
