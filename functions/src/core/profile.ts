import { englishDataset, englishRecommendedTransformers, RegExpMatcher } from 'obscenity';
import { invalid } from './errors.js';

const matcher = new RegExpMatcher({
  ...englishDataset.build(),
  ...englishRecommendedTransformers,
});

export interface ProfileInput {
  nickname: string;
  nicknameLower: string;
  avatarSeed: string;
  country: string;
}

export function normalizeNickname(raw: string): string {
  return raw.trim().replace(/\s+/g, ' ');
}

export function isProfane(text: string): boolean {
  return matcher.hasMatch(text);
}

/**
 * Encoded avatar, e.g. `dicebear:adventurer:Nova42`, `emoji:🦊:3`, or a
 * legacy plain seed: 1..64 UTF-16 code units, no C0 control chars or DEL.
 */
export function isValidAvatarSeed(s: unknown): s is string {
  // eslint-disable-next-line no-control-regex
  return typeof s === 'string' && s.length >= 1 && s.length <= 64 && !/[\u0000-\u001F\u007F]/.test(s);
}

export function parseProfile(body: unknown): ProfileInput {
  if (typeof body !== 'object' || body === null || Array.isArray(body)) {
    throw invalid('invalid_argument', 'Body must be a JSON object.');
  }
  const b = body as Record<string, unknown>;
  if (typeof b.nickname !== 'string') throw invalid('invalid_nickname', 'nickname is required.');
  const nickname = normalizeNickname(b.nickname);
  if (nickname.length < 3 || nickname.length > 16 || !/^[A-Za-z0-9_ ]+$/.test(nickname)) {
    throw invalid('invalid_nickname', 'nickname must be 3-16 characters: letters, digits, underscore, space.');
  }
  if (isProfane(nickname)) throw invalid('profane', 'Please choose a different nickname.');

  const avatarSeed = b.avatarSeed ?? '';
  if (typeof avatarSeed !== 'string' || !(avatarSeed === '' || isValidAvatarSeed(avatarSeed))) {
    throw invalid(
      'invalid_avatar_seed',
      'avatarSeed must be a string of 1-64 characters without control characters.',
    );
  }
  const country = b.country ?? '';
  if (typeof country !== 'string' || !(country === '' || /^[A-Z]{2}$/.test(country))) {
    throw invalid('invalid_country', "country must be '' or a 2-letter uppercase ISO code.");
  }
  return { nickname, nicknameLower: nickname.toLowerCase(), avatarSeed, country };
}
