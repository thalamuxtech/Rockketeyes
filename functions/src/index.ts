import { randomBytes, randomInt } from 'node:crypto';
import { initializeApp } from 'firebase-admin/app';
import { getAppCheck } from 'firebase-admin/app-check';
import { getAuth } from 'firebase-admin/auth';
import { FieldValue, getFirestore, Timestamp, type DocumentReference, type Firestore } from 'firebase-admin/firestore';
import * as logger from 'firebase-functions/logger';
import { onRequest, type Request } from 'firebase-functions/v2/https';
import type { Response } from 'express';

import { ApiError } from './core/errors.js';
import { GENERATOR_VERSION } from './core/grid.js';
import { bestPerBoard, hasGoogleProvider, type ScoreRow } from './core/legends.js';
import { parseProfile } from './core/profile.js';
import { SCORING_VERSION } from './core/scoring.js';
import { dayKey, isoWeekKey } from './core/time.js';
import {
  checkRoundUsable,
  parseRoundStart,
  parseSubmit,
  RATE_LIMIT_MAX_ROUNDS,
  RATE_LIMIT_WINDOW_MS,
  ROUND_TTL_MS,
  validateAndScore,
  type RoundDoc,
  type Verdict,
} from './core/validate.js';

initializeApp();

let _db: Firestore | undefined;
function db(): Firestore {
  if (!_db) {
    _db = getFirestore();
    _db.settings({ ignoreUndefinedProperties: true });
  }
  return _db;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function sendError(res: Response, err: ApiError): void {
  res.status(err.status).json({ error: { code: err.code, message: err.message } });
}

async function requireUser(req: Request): Promise<string> {
  const header = req.get('authorization') ?? '';
  const m = /^Bearer\s+(.+)$/i.exec(header);
  if (!m) throw new ApiError(401, 'unauthenticated', 'Missing Authorization: Bearer <ID token>.');
  try {
    const decoded = await getAuth().verifyIdToken(m[1]!.trim());
    return decoded.uid;
  } catch {
    throw new ApiError(401, 'unauthenticated', 'Invalid or expired ID token.');
  }
}

async function requireAppCheck(req: Request): Promise<void> {
  if (process.env.APPCHECK_ENFORCE !== 'true') return;
  const token = req.get('x-firebase-appcheck');
  if (!token) throw new ApiError(401, 'app_check_required', 'Missing X-Firebase-AppCheck header.');
  try {
    await getAppCheck().verifyToken(token);
  } catch {
    throw new ApiError(401, 'app_check_invalid', 'Invalid App Check token.');
  }
}

function readBody(req: Request): unknown {
  const b: unknown = req.body;
  if (b !== undefined && b !== null && !Buffer.isBuffer(b) && typeof b !== 'string') return b;
  const raw = typeof b === 'string' ? b : (req.rawBody ?? (Buffer.isBuffer(b) ? b : undefined))?.toString('utf8');
  if (!raw || raw.trim() === '') return {};
  try {
    return JSON.parse(raw) as unknown;
  } catch {
    throw new ApiError(400, 'invalid_json', 'Body must be valid JSON.');
  }
}

function defaultNickname(): string {
  return `Pilot-${String(randomInt(0, 10000)).padStart(4, '0')}`;
}

interface UserDoc {
  nickname?: string;
  nicknameLower?: string;
  avatarSeed?: string;
  country?: string;
  gamesPlayed?: number;
  /** Set once a google.com provider has been seen on the account. */
  google?: boolean;
  createdAt?: Timestamp;
  updatedAt?: Timestamp;
}

function profileOut(uid: string, u: UserDoc, google: boolean) {
  return {
    uid,
    nickname: u.nickname ?? '',
    avatarSeed: u.avatarSeed ?? uid,
    country: u.country ?? '',
    gamesPlayed: u.gamesPlayed ?? 0,
    google,
    createdAtMs: u.createdAt instanceof Timestamp ? u.createdAt.toMillis() : null,
    updatedAtMs: u.updatedAt instanceof Timestamp ? u.updatedAt.toMillis() : null,
  };
}

/** Global Legends eligibility: the Auth account has a linked google.com provider. */
async function isGoogleUser(uid: string): Promise<boolean> {
  const user = await getAuth().getUser(uid);
  return hasGoogleProvider(user.providerData);
}

// ---------------------------------------------------------------------------
// Handlers
// ---------------------------------------------------------------------------

async function handleRoundStart(uid: string, body: unknown) {
  const plan = parseRoundStart(body);
  const now = Date.now();

  const recent = await db()
    .collection('rounds')
    .where('uid', '==', uid)
    .where('issuedAt', '>', now - RATE_LIMIT_WINDOW_MS)
    .count()
    .get();
  if (recent.data().count >= RATE_LIMIT_MAX_ROUNDS) {
    throw new ApiError(429, 'rate_limited', `At most ${RATE_LIMIT_MAX_ROUNDS} rounds per minute.`);
  }

  const seed = randomBytes(4).readUInt32BE(0);
  const round: RoundDoc = {
    uid,
    seed,
    cols: plan.cols,
    rows: plan.rows,
    sizeId: plan.sizeId,
    colorSet: plan.colorSet,
    congruentRatio: plan.congruentRatio,
    mode: plan.mode,
    boardId: plan.boardId,
    ranked: plan.ranked,
    generatorVersion: plan.generatorVersion,
    scoringVersion: plan.scoringVersion,
    issuedAt: now,
    expiresAt: now + ROUND_TTL_MS,
    used: false,
  };
  const ref = db().collection('rounds').doc();
  await ref.set(round);
  return {
    roundId: ref.id,
    seed,
    issuedAt: round.issuedAt,
    expiresAt: round.expiresAt,
    ranked: round.ranked,
    boardId: round.boardId,
  };
}

type Period = 'all' | `d${string}` | `w${string}`;

async function handleScoreSubmit(uid: string, body: unknown) {
  const input = parseSubmit(body);
  const legendsEligible = await isGoogleUser(uid);
  const firestore = db();
  const roundRef = firestore.collection('rounds').doc(input.roundId);
  const scoreRef = firestore.collection('scores').doc();
  const userRef = firestore.collection('users').doc(uid);

  interface TxResult {
    verdict?: Verdict;
    error?: ApiError;
    round?: RoundDoc;
    personalBest: boolean;
    bestScores: Record<string, number>;
    periods: { key: 'day' | 'week' | 'all'; period: Period }[];
  }

  const result = await firestore.runTransaction<TxResult>(async (tx) => {
    const now = Date.now();
    const roundSnap = await tx.get(roundRef);
    if (!roundSnap.exists) throw new ApiError(404, 'round_not_found', 'Unknown roundId.');
    const round = roundSnap.data() as RoundDoc;
    checkRoundUsable(round, uid, now); // 403 / 410: nothing is written.

    const day = dayKey(now);
    const week = isoWeekKey(now);
    const periods: TxResult['periods'] = [
      { key: 'all', period: 'all' },
      { key: 'day', period: `d${day}` },
      { key: 'week', period: `w${week}` },
    ];
    const bestRefs = periods.map((p) => firestore.collection('bests').doc(`${p.period}_${round.boardId}_${uid}`));
    const userSnap = await tx.get(userRef);
    // Global Legends rows are only read/written for Google-linked accounts.
    const bestSnaps = legendsEligible ? await Promise.all(bestRefs.map((r) => tx.get(r))) : [];

    // From here on the round is consumed, even if validation fails, so a
    // rejected log cannot be tweaked and resubmitted.
    tx.update(roundRef, { used: true, usedAt: now });

    let verdict: Verdict;
    try {
      verdict = validateAndScore(round, input, now);
    } catch (e) {
      if (e instanceof ApiError) {
        tx.update(roundRef, { rejected: e.code });
        return { error: e, personalBest: false, bestScores: {}, periods };
      }
      throw e;
    }

    const user = (userSnap.exists ? userSnap.data() : undefined) as UserDoc | undefined;
    const nickname = user?.nickname ?? defaultNickname();
    const avatarSeed = user?.avatarSeed ?? uid;
    const country = user?.country ?? '';
    const createdAt = Timestamp.fromMillis(now);

    if (user) {
      tx.update(userRef, { gamesPlayed: FieldValue.increment(1), ...(legendsEligible ? { google: true } : {}) });
    } else {
      tx.set(userRef, {
        nickname,
        nicknameLower: nickname.toLowerCase(),
        avatarSeed,
        country,
        gamesPlayed: 1,
        ...(legendsEligible ? { google: true } : {}),
        createdAt,
        updatedAt: createdAt,
      });
    }

    const common = {
      score: verdict.score,
      cells: verdict.cells,
      correct: verdict.correct,
      end: verdict.end,
      completion: verdict.completion,
      elapsedMs: verdict.elapsedMs,
      correctElapsedMs: verdict.correctElapsedMs,
      mistakeKind: verdict.mistakeKind,
    };
    tx.set(scoreRef, {
      uid,
      nickname,
      avatarSeed,
      country,
      roundId: input.roundId,
      boardId: round.boardId,
      sizeId: round.sizeId,
      colorSet: round.colorSet,
      mode: round.mode,
      ranked: round.ranked,
      review: verdict.review,
      legendsEligible,
      ...common,
      scoringVersion: SCORING_VERSION,
      createdAt: FieldValue.serverTimestamp(),
      createdAtMs: now,
      day,
      week,
    });

    let personalBest = false;
    const bestScores: Record<string, number> = {};
    if (round.ranked && !verdict.review && legendsEligible) {
      periods.forEach((p, idx) => {
        const snap = bestSnaps[idx]!;
        const prev = snap.exists ? (snap.data()!.score as number) : undefined;
        if (prev === undefined || verdict.score > prev) {
          tx.set(bestRefs[idx]!, {
            uid,
            nickname,
            avatarSeed,
            country,
            boardId: round.boardId,
            period: p.period,
            ...common,
            createdAt,
            createdAtMs: now,
          });
          bestScores[p.key] = verdict.score;
          if (p.key === 'all') personalBest = true;
        } else {
          bestScores[p.key] = prev;
        }
      });
    }
    return { verdict, round, personalBest, bestScores, periods };
  });

  if (result.error) throw result.error;
  const verdict = result.verdict!;
  const round = result.round!;

  let personalBest = result.personalBest;
  if (round.ranked && !verdict.review && !legendsEligible) {
    // No `bests` rows for this player: compare against their own score
    // history for the board (ranked, non-review). The new score doc is
    // already committed, so it is the only one allowed at >= its score.
    const agg = await firestore
      .collection('scores')
      .where('uid', '==', uid)
      .where('boardId', '==', round.boardId)
      .where('ranked', '==', true)
      .where('review', '==', false)
      .where('score', '>=', verdict.score)
      .count()
      .get();
    personalBest = agg.data().count <= 1;
  }

  let rank: { day: number; week: number; all: number } | null = null;
  if (round.ranked && !verdict.review && legendsEligible) {
    const counts = await Promise.all(
      result.periods.map(async (p) => {
        const agg = await firestore
          .collection('bests')
          .where('period', '==', p.period)
          .where('boardId', '==', round.boardId)
          .where('score', '>', result.bestScores[p.key]!)
          .count()
          .get();
        return [p.key, agg.data().count + 1] as const;
      }),
    );
    const m = Object.fromEntries(counts) as Record<'day' | 'week' | 'all', number>;
    rank = { day: m.day, week: m.week, all: m.all };
  }

  return {
    score: verdict.score,
    correct: verdict.correct,
    cells: verdict.cells,
    end: verdict.end,
    mistakeKind: verdict.mistakeKind,
    completion: verdict.completion,
    elapsedMs: verdict.elapsedMs,
    ranked: round.ranked,
    review: verdict.review,
    personalBest,
    legendsEligible,
    rank,
  };
}

async function handleLegendsClaim(uid: string) {
  const authUser = await getAuth().getUser(uid);
  if (!hasGoogleProvider(authUser.providerData)) {
    throw new ApiError(403, 'google_required', 'Link a Google account to appear in Global Legends.');
  }
  const firestore = db();
  const userRef = firestore.collection('users').doc(uid);
  const now = Date.now();
  const day = dayKey(now);
  const week = isoWeekKey(now);

  const scoresSnap = await firestore.collection('scores').where('uid', '==', uid).get();
  const rows = scoresSnap.docs.map((d) => d.data() as ScoreRow);
  const wanted = bestPerBoard(rows, day, week);

  return firestore.runTransaction(async (tx) => {
    const userSnap = await tx.get(userRef);
    const user = (userSnap.exists ? userSnap.data() : undefined) as UserDoc | undefined;
    const nickname = user?.nickname ?? defaultNickname();
    const avatarSeed = user?.avatarSeed ?? uid;
    const country = user?.country ?? '';

    const refs = wanted.map((w) => firestore.collection('bests').doc(`${w.period}_${w.boardId}_${uid}`));
    const snaps = refs.length > 0 ? await tx.getAll(...refs) : [];

    const boards = new Set<string>();
    let claimed = 0;
    wanted.forEach((w, idx) => {
      const snap = snaps[idx]!;
      const prev = snap.exists ? (snap.data()!.score as number) : undefined;
      if (prev !== undefined && w.score.score <= prev) return;
      const s = w.score;
      const createdAtMs = typeof s.createdAtMs === 'number' ? s.createdAtMs : now;
      tx.set(refs[idx]!, {
        uid,
        nickname,
        avatarSeed,
        country,
        boardId: w.boardId,
        period: w.period,
        score: s.score,
        cells: s.cells,
        correct: s.correct,
        end: s.end,
        completion: s.completion,
        elapsedMs: s.elapsedMs,
        correctElapsedMs: s.correctElapsedMs,
        mistakeKind: s.mistakeKind ?? null,
        createdAt: Timestamp.fromMillis(createdAtMs),
        createdAtMs,
      });
      claimed++;
      boards.add(w.boardId);
    });

    if (user) {
      tx.update(userRef, { google: true });
    } else {
      const ts = Timestamp.fromMillis(now);
      tx.set(userRef, {
        nickname,
        nicknameLower: nickname.toLowerCase(),
        avatarSeed,
        country,
        gamesPlayed: 0,
        google: true,
        createdAt: ts,
        updatedAt: ts,
      });
    }
    return { claimed, boards: [...boards].sort() };
  });
}

async function handleProfilePost(uid: string, body: unknown) {
  const input = parseProfile(body);
  const google = await isGoogleUser(uid);
  const firestore = db();
  const userRef = firestore.collection('users').doc(uid);
  const nickRef = firestore.collection('nicknames').doc(input.nicknameLower);

  const profile = await firestore.runTransaction(async (tx) => {
    const now = Timestamp.now();
    const [userSnap, nickSnap] = await Promise.all([tx.get(userRef), tx.get(nickRef)]);
    const user = userSnap.exists ? (userSnap.data() as UserDoc) : undefined;
    if (nickSnap.exists && nickSnap.data()!.uid !== uid) {
      throw new ApiError(409, 'nickname_taken', 'That nickname is already taken.');
    }
    const prevLower = user?.nicknameLower;
    let prevRef: DocumentReference | undefined;
    if (prevLower && prevLower !== input.nicknameLower) {
      prevRef = firestore.collection('nicknames').doc(prevLower);
      const prevSnap = await tx.get(prevRef);
      if (!prevSnap.exists || prevSnap.data()!.uid !== uid) prevRef = undefined;
    }
    if (prevRef) tx.delete(prevRef);
    tx.set(nickRef, { uid, updatedAt: now });
    const update: UserDoc = {
      nickname: input.nickname,
      nicknameLower: input.nicknameLower,
      avatarSeed: input.avatarSeed,
      country: input.country,
      updatedAt: now,
    };
    if (google) update.google = true;
    if (!user) {
      update.createdAt = now;
      update.gamesPlayed = 0;
    }
    tx.set(userRef, update, { merge: true });
    return profileOut(uid, { ...user, ...update }, google);
  });

  // Denormalised leaderboard rows: best effort.
  try {
    const bests = await firestore.collection('bests').where('uid', '==', uid).get();
    for (let i = 0; i < bests.docs.length; i += 450) {
      const batch = firestore.batch();
      for (const d of bests.docs.slice(i, i + 450)) {
        batch.update(d.ref, { nickname: input.nickname, avatarSeed: input.avatarSeed, country: input.country });
      }
      await batch.commit();
    }
  } catch (e) {
    logger.warn('Failed to propagate profile to bests', { uid, error: String(e) });
  }

  return { profile };
}

async function handleProfileGet(uid: string) {
  const [snap, google] = await Promise.all([db().collection('users').doc(uid).get(), isGoogleUser(uid)]);
  if (!snap.exists) throw new ApiError(404, 'profile_not_found', 'No profile yet.');
  return { profile: profileOut(uid, snap.data() as UserDoc, google) };
}

/** Deletes everything stored for [uid]: profile, nickname, scores, leaderboard rows, rounds and the Auth account. */
async function handleAccountDelete(uid: string) {
  const firestore = db();
  const userRef = firestore.collection('users').doc(uid);
  const userSnap = await userRef.get();
  const nicknameLower = userSnap.exists ? (userSnap.data() as UserDoc).nicknameLower : undefined;

  const refs: DocumentReference[] = [userRef];
  if (nicknameLower) {
    const nickRef = firestore.collection('nicknames').doc(nicknameLower);
    const nickSnap = await nickRef.get();
    if (nickSnap.exists && nickSnap.data()!.uid === uid) refs.push(nickRef);
  }
  for (const name of ['scores', 'bests', 'rounds']) {
    const snap = await firestore.collection(name).where('uid', '==', uid).select().get();
    refs.push(...snap.docs.map((d) => d.ref));
  }
  for (let i = 0; i < refs.length; i += 450) {
    const batch = firestore.batch();
    for (const ref of refs.slice(i, i + 450)) batch.delete(ref);
    await batch.commit();
  }

  try {
    await getAuth().deleteUser(uid);
  } catch (e) {
    if ((e as { code?: string }).code !== 'auth/user-not-found') throw e;
  }
  logger.info('Account deleted', { uid, docs: refs.length });
  return { deleted: true, docs: refs.length };
}

// ---------------------------------------------------------------------------
// Router
// ---------------------------------------------------------------------------

export function routePath(path: string): string {
  let p = path.replace(/^\/api(?=\/|$)/, '');
  if (p.length > 1) p = p.replace(/\/+$/, '');
  return p === '' ? '/' : p;
}

export const api = onRequest(
  { region: 'us-central1', cors: true, maxInstances: 10 },
  async (req: Request, res: Response): Promise<void> => {
    const path = routePath(req.path);
    const route = `${req.method} ${path}`;
    try {
      if (route === 'GET /health') {
        res.json({ ok: true, generatorVersion: GENERATOR_VERSION, scoringVersion: SCORING_VERSION });
        return;
      }
      const known = ['POST /round/start', 'POST /score/submit', 'POST /profile', 'GET /profile', 'POST /legends/claim', 'POST /account/delete'];
      if (!known.includes(route)) {
        const pathKnown = known.some((k) => k.endsWith(` ${path}`));
        throw pathKnown
          ? new ApiError(405, 'method_not_allowed', `${req.method} not allowed on ${path}.`)
          : new ApiError(404, 'not_found', `No route ${path}.`);
      }
      await requireAppCheck(req);
      const uid = await requireUser(req);
      let out: unknown;
      switch (route) {
        case 'POST /round/start':
          out = await handleRoundStart(uid, readBody(req));
          break;
        case 'POST /score/submit':
          out = await handleScoreSubmit(uid, readBody(req));
          break;
        case 'POST /profile':
          out = await handleProfilePost(uid, readBody(req));
          break;
        case 'POST /legends/claim':
          out = await handleLegendsClaim(uid);
          break;
        case 'POST /account/delete':
          out = await handleAccountDelete(uid);
          break;
        default:
          out = await handleProfileGet(uid);
      }
      res.status(200).json(out);
    } catch (e) {
      if (e instanceof ApiError) {
        sendError(res, e);
      } else {
        logger.error('Unhandled error', { route, error: e instanceof Error ? e.stack : String(e) });
        sendError(res, new ApiError(500, 'internal', 'Internal error.'));
      }
    }
  },
);
