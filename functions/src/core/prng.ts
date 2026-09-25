/**
 * Portable 32-bit PRNG (mulberry32).
 *
 * Bit-exact port of `lib/features/game/domain/prng.dart`. Verified by the
 * golden test (`test/golden.test.ts`). Do not change without bumping
 * GENERATOR_VERSION on both sides.
 */
export class Mulberry32 {
  private state: number;

  constructor(seed: number) {
    this.state = seed >>> 0;
  }

  /** Next unsigned 32-bit value. */
  nextUint32(): number {
    this.state = (this.state + 0x6d2b79f5) >>> 0;
    let t = this.state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t = (t ^ (t + Math.imul(t ^ (t >>> 7), t | 61))) >>> 0;
    return (t ^ (t >>> 14)) >>> 0;
  }

  /** Uniform double in [0, 1). */
  nextDouble(): number {
    return this.nextUint32() / 4294967296.0;
  }

  /** Uniform int in [0, max). */
  nextInt(max: number): number {
    return Math.floor(this.nextDouble() * max);
  }
}
