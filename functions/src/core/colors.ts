/**
 * Color-set ids. Port of `lib/features/game/domain/color_keys.dart`.
 * Key order is part of the grid-generation contract; never reorder.
 */
export type ColorSetId = 'easy' | 'normal' | 'hard' | 'colorblind';

export const COLOR_SETS: Readonly<Record<ColorSetId, readonly string[]>> = {
  easy: ['red', 'blue', 'green', 'yellow'],
  normal: ['red', 'blue', 'green', 'yellow', 'orange', 'purple'],
  hard: ['red', 'blue', 'green', 'yellow', 'orange', 'purple', 'pink', 'white'],
  colorblind: ['blue', 'orange', 'yellow', 'white', 'pink'],
};

export const COLOR_SET_IDS: readonly ColorSetId[] = ['easy', 'normal', 'hard', 'colorblind'];

export function isColorSetId(v: unknown): v is ColorSetId {
  return typeof v === 'string' && (COLOR_SET_IDS as readonly string[]).includes(v);
}

export function colorKeysFor(id: ColorSetId): readonly string[] {
  return COLOR_SETS[id];
}
