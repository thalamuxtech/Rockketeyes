/// Portable 32-bit PRNG (mulberry32).
///
/// Produces bit-identical sequences on the Dart VM, dart2js/dart2wasm and the
/// TypeScript port in `functions/src/core/prng.ts`, so the server can rebuild
/// any board from its seed. Do not replace with `dart:math` [Random].
class Mulberry32 {
  Mulberry32(int seed) : _state = seed & _mask;

  static const int _mask = 0xFFFFFFFF;
  int _state;

  /// 32-bit integer multiply with wraparound (same as JavaScript `Math.imul`),
  /// split into 16-bit halves so no intermediate exceeds 2^53 on the web.
  static int imul(int a, int b) {
    a &= _mask;
    b &= _mask;
    final ah = (a >> 16) & 0xFFFF;
    final al = a & 0xFFFF;
    final bh = (b >> 16) & 0xFFFF;
    final bl = b & 0xFFFF;
    final high = ((ah * bl + al * bh) & 0xFFFF) * 0x10000;
    return (al * bl + high) & _mask;
  }

  /// Next unsigned 32-bit value.
  int nextUint32() {
    _state = (_state + 0x6D2B79F5) & _mask;
    var t = _state;
    t = imul(t ^ (t >>> 15), t | 1);
    t = (t ^ ((t + imul(t ^ (t >>> 7), t | 61)) & _mask)) & _mask;
    return (t ^ (t >>> 14)) & _mask;
  }

  /// Uniform double in [0, 1).
  double nextDouble() => nextUint32() / 4294967296.0;

  /// Uniform int in [0, max).
  int nextInt(int max) => (nextDouble() * max).floor();
}
