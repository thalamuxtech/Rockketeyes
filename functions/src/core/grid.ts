import { Mulberry32 } from './prng.js';

/**
 * Deterministic Stroop board generator.
 * Bit-exact port of `lib/features/game/domain/grid.dart` (same RNG call order).
 */
export const GENERATOR_VERSION = 1;

export interface Cell {
  index: number;
  /** Color key of the printed word. */
  word: string;
  /** Color key of the ink (the correct answer). */
  ink: string;
}

export const MIN_COLS = 3;
export const MAX_COLS = 16;
export const MIN_ROWS = 4;
export const MAX_ROWS = 16;

export interface GridSize {
  cols: number;
  rows: number;
}

/** Ranked presets. Anything else is playable but unranked. */
export const PRESETS: readonly GridSize[] = [
  { cols: 3, rows: 4 },
  { cols: 4, rows: 4 },
  { cols: 5, rows: 5 },
  { cols: 6, rows: 6 },
  { cols: 8, rows: 8 },
  { cols: 10, rows: 10 },
  { cols: 12, rows: 12 },
  { cols: 16, rows: 16 },
];

export function sizeId(s: GridSize): string {
  return `${s.cols}x${s.rows}`;
}

export function cellCount(s: GridSize): number {
  return s.cols * s.rows;
}

export function isValidSize(s: GridSize): boolean {
  return (
    Number.isInteger(s.cols) &&
    Number.isInteger(s.rows) &&
    s.cols >= MIN_COLS &&
    s.cols <= MAX_COLS &&
    s.rows >= MIN_ROWS &&
    s.rows <= MAX_ROWS
  );
}

export function isPreset(s: GridSize): boolean {
  return PRESETS.some((p) => p.cols === s.cols && p.rows === s.rows);
}

export function tryParseSize(id: string): GridSize | null {
  const m = /^(\d+)x(\d+)$/.exec(id);
  if (!m) return null;
  const g = { cols: parseInt(m[1]!, 10), rows: parseInt(m[2]!, 10) };
  return isValidSize(g) ? g : null;
}

function swap(a: string[], i: number, j: number): void {
  const t = a[i]!;
  a[i] = a[j]!;
  a[j] = t;
}

export function generateGrid(opts: {
  size: GridSize;
  colorKeys: readonly string[];
  seed: number;
  congruentRatio?: number;
}): Cell[] {
  const { size, colorKeys, seed } = opts;
  const congruentRatio = opts.congruentRatio ?? 0;
  const rng = new Mulberry32(seed);
  const n = size.cols * size.rows;
  const cols = size.cols;
  const k = colorKeys.length;

  // 1. Balanced ink bag, shuffled (Fisher-Yates, high to low).
  const ink: string[] = Array.from({ length: n }, (_, i) => colorKeys[i % k]!);
  for (let i = n - 1; i > 0; i--) {
    const j = rng.nextInt(i + 1);
    swap(ink, i, j);
  }

  // 2. Break consecutive repeats in reading order by swapping (no RNG use).
  for (let i = 1; i < n; i++) {
    if (ink[i] !== ink[i - 1]) continue;
    let swapped = false;
    for (let j = i + 1; j < n && !swapped; j++) {
      if (j === i + 1) {
        if (ink[j] !== ink[i - 1] && (j + 1 >= n || ink[i] !== ink[j + 1])) {
          swap(ink, i, j);
          swapped = true;
        }
      } else if (
        ink[j] !== ink[i - 1] &&
        (i + 1 >= n || ink[j] !== ink[i + 1]) &&
        ink[i] !== ink[j - 1] &&
        (j + 1 >= n || ink[i] !== ink[j + 1])
      ) {
        swap(ink, i, j);
        swapped = true;
      }
    }
    for (let j = 0; j < i - 1 && !swapped; j++) {
      if (
        ink[j] !== ink[i - 1] &&
        (i + 1 >= n || ink[j] !== ink[i + 1]) &&
        (j === 0 || ink[i] !== ink[j - 1]) &&
        ink[i] !== ink[j + 1]
      ) {
        swap(ink, i, j);
        swapped = true;
      }
    }
  }

  // 3. Words: never the ink (unless congruent roll), never equal to the
  //    left or above neighbour's word.
  const words: string[] = new Array<string>(n).fill('');
  for (let i = 0; i < n; i++) {
    const r = Math.floor(i / cols);
    const c = i % cols;
    if (congruentRatio > 0) {
      const roll = rng.nextDouble();
      if (roll < congruentRatio) {
        words[i] = ink[i]!;
        continue;
      }
    }
    const left = c > 0 ? words[i - 1] : null;
    const above = r > 0 ? words[i - cols] : null;
    let candidates = colorKeys.filter((key) => key !== ink[i] && key !== left && key !== above);
    if (candidates.length === 0) {
      candidates = colorKeys.filter((key) => key !== ink[i]);
    }
    words[i] = candidates[rng.nextInt(candidates.length)]!;
  }

  return Array.from({ length: n }, (_, i) => ({ index: i, word: words[i]!, ink: ink[i]! }));
}
