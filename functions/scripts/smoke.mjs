// End-to-end smoke test against the local emulators (never production).
//
//   cd app && firebase emulators:exec --only auth,firestore,functions \
//     --project rockketeyes "node functions/scripts/smoke.mjs"
//
// (or `npm run smoke` inside functions/). Requires `npm run build` first,
// because it reuses the compiled core module to regenerate boards.
import { createRequire } from 'node:module';
import assert from 'node:assert/strict';

const require = createRequire(import.meta.url);
const { generateGrid } = require('../lib/core/grid.js');
const { COLOR_SETS } = require('../lib/core/colors.js');

const PROJECT = process.env.GCLOUD_PROJECT || process.env.FIREBASE_PROJECT || 'rockketeyes';
if (PROJECT !== 'rockketeyes') throw new Error(`Refusing to run against project ${PROJECT}`);
const AUTH_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST || '127.0.0.1:9099';
const FS_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
const FN_HOST = process.env.FUNCTIONS_EMULATOR_HOST || '127.0.0.1:5001';
const API = `http://${FN_HOST.replace(/^https?:\/\//, '')}/${PROJECT}/us-central1/api`;

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let step = 0;
const log = (msg, extra) => console.log(`[smoke ${++step}] ${msg}`, extra !== undefined ? JSON.stringify(extra) : '');

async function signUpAnon() {
  const res = await fetch(`http://${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ returnSecureToken: true }),
  });
  const body = await res.json();
  assert.equal(res.status, 200, JSON.stringify(body));
  return { idToken: body.idToken, uid: body.localId };
}

async function call(method, path, { token, body } = {}) {
  const headers = { 'Content-Type': 'application/json' };
  if (token) headers.Authorization = `Bearer ${token}`;
  const res = await fetch(`${API}${path}`, { method, headers, body: body ? JSON.stringify(body) : undefined });
  const text = await res.text();
  let json;
  try {
    json = JSON.parse(text);
  } catch {
    json = { raw: text };
  }
  return { status: res.status, body: json };
}

function gridFor(start, cols, rows, colorSet) {
  return generateGrid({ size: { cols, rows }, colorKeys: COLOR_SETS[colorSet], seed: start.seed, congruentRatio: 0 });
}

// Link a google.com identity to the (anonymous) account behind idToken via
// the Auth emulator; returns a fresh idToken for the same uid.
async function linkGoogle(idToken) {
  const rand = Math.random().toString(36).slice(2, 10);
  const claims = { sub: `g-${rand}`, email: `x${rand}@example.com`, email_verified: true };
  const res = await fetch(`http://${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signInWithIdp?key=fake`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      idToken,
      postBody: `id_token=${encodeURIComponent(JSON.stringify(claims))}&providerId=google.com`,
      requestUri: 'http://localhost',
      returnIdpCredential: true,
      returnSecureToken: true,
    }),
  });
  const body = await res.json();
  assert.equal(res.status, 200, JSON.stringify(body));
  assert.equal(body.providerId, 'google.com', JSON.stringify(body));
  return { idToken: body.idToken, uid: body.localId };
}

const FS_DOCS = `http://${FS_HOST}/v1/projects/${PROJECT}/databases/(default)/documents`;
const fsVal = (v) => (typeof v === 'number' ? { integerValue: String(v) } : { stringValue: v });

// Public (rules-evaluated) query over `bests` via the Firestore REST API.
async function queryBests(filters) {
  const res = await fetch(`${FS_DOCS}:runQuery`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      structuredQuery: {
        from: [{ collectionId: 'bests' }],
        where: {
          compositeFilter: {
            op: 'AND',
            filters: filters.map(([field, op, value]) => ({ fieldFilter: { field: { fieldPath: field }, op, value: fsVal(value) } })),
          },
        },
      },
    }),
  });
  const rows = await res.json();
  assert.equal(res.status, 200, JSON.stringify(rows));
  return rows.filter((r) => r.document).map((r) => r.document);
}

// Leaderboard position = 1 + number of rows strictly above score. Computed
// from live data so the smoke test also works against long-running emulators.
async function expectedRank(period, boardId, score) {
  const above = await queryBests([
    ['period', 'EQUAL', period],
    ['boardId', 'EQUAL', boardId],
    ['score', 'GREATER_THAN', score],
  ]);
  return above.length + 1;
}

async function main() {
  // Health (no auth), also via the /api prefix that the hosting rewrite uses.
  let r = await call('GET', '/health');
  assert.equal(r.status, 200);
  assert.deepEqual(r.body, { ok: true, generatorVersion: 1, scoringVersion: 1 });
  r = await call('GET', '/api/health');
  assert.equal(r.status, 200);
  log('health ok', r.body);

  const me = await signUpAnon();
  log('anonymous user', { uid: me.uid });

  r = await call('POST', '/round/start', { body: { cols: 3, rows: 4, colorSet: 'normal', congruentRatio: 0, mode: 'voice' } });
  assert.equal(r.status, 401);
  assert.equal(r.body.error.code, 'unauthenticated');
  log('unauthenticated -> 401', r.body);

  r = await call('GET', '/profile', { token: me.idToken });
  assert.equal(r.status, 404);
  log('GET /profile before creation -> 404', r.body.error);

  const nickname = `Smoke ${me.uid.slice(0, 6)}`.replace(/[^A-Za-z0-9_ ]/g, '_');
  r = await call('POST', '/profile', { token: me.idToken, body: { nickname: `  ${nickname}  `, avatarSeed: 'seed-1', country: 'GB' } });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  assert.equal(r.body.profile.nickname, nickname);
  assert.equal(r.body.profile.google, false);
  log('POST /profile', r.body);

  for (const avatarSeed of ['dicebear:adventurer:Nova42', 'emoji:\u{1F98A}:3']) {
    r = await call('POST', '/profile', { token: me.idToken, body: { nickname, avatarSeed, country: 'GB' } });
    assert.equal(r.status, 200, JSON.stringify(r.body));
    assert.equal(r.body.profile.avatarSeed, avatarSeed);
  }
  r = await call('POST', '/profile', { token: me.idToken, body: { nickname, avatarSeed: 'bad\u0007seed', country: 'GB' } });
  assert.equal(r.status, 400);
  assert.equal(r.body.error.code, 'invalid_avatar_seed');
  log('encoded avatars accepted; control char -> 400', r.body.error);

  r = await call('POST', '/profile', { token: me.idToken, body: { nickname: 'fuckface', avatarSeed: '', country: '' } });
  assert.equal(r.status, 400);
  assert.equal(r.body.error.code, 'profane');
  log('profane nickname -> 400', r.body.error);

  const other = await signUpAnon();
  r = await call('POST', '/profile', { token: other.idToken, body: { nickname: nickname.toUpperCase(), avatarSeed: '', country: '' } });
  assert.equal(r.status, 409);
  assert.equal(r.body.error.code, 'nickname_taken');
  log('duplicate nickname (other user, different case) -> 409', r.body.error);

  r = await call('POST', '/round/start', { token: me.idToken, body: { cols: 2, rows: 4, colorSet: 'normal', congruentRatio: 0, mode: 'voice' } });
  assert.equal(r.status, 400);
  log('invalid size -> 400', r.body.error);

  // Issue four 3x4 normal voice rounds (the 4th is played after linking Google).
  const startBody = { cols: 3, rows: 4, colorSet: 'normal', congruentRatio: 0, mode: 'voice' };
  const starts = [];
  for (let k = 0; k < 4; k++) {
    r = await call('POST', '/round/start', { token: me.idToken, body: startBody });
    assert.equal(r.status, 200, JSON.stringify(r.body));
    assert.equal(r.body.ranked, true);
    assert.equal(r.body.boardId, '3x4.normal.voice');
    assert.equal(r.body.expiresAt - r.body.issuedAt, 30 * 60 * 1000);
    starts.push(r.body);
  }
  log('4 rounds started', starts.map((s) => ({ roundId: s.roundId, seed: s.seed })));

  // Wait so that elapsedMs (7200) is within wall-clock time since issue.
  await sleep(6800);

  // 1. Cleared round: all 12 correct, t spaced 600 ms.
  const [cleared, mistake, fast, afterLink] = starts;
  const g1 = gridFor(cleared, 3, 4, 'normal');
  const clearedEvents = g1.map((c, i) => ({ i, c: c.ink, t: (i + 1) * 600 }));
  r = await call('POST', '/score/submit', { token: me.idToken, body: { roundId: cleared.roundId, elapsedMs: 7200, events: clearedEvents } });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  assert.equal(r.body.end, 'cleared');
  assert.equal(r.body.correct, 12);
  assert.equal(r.body.cells, 12);
  assert.equal(r.body.mistakeKind, null);
  assert.ok(r.body.score > 0);
  assert.equal(r.body.ranked, true);
  assert.equal(r.body.review, false);
  assert.equal(r.body.personalBest, true); // from own score history
  assert.equal(r.body.legendsEligible, false); // anonymous: not on Global Legends
  assert.equal(r.body.rank, null);
  const clearedScore = r.body.score;
  log('cleared round submitted (anonymous, not legends-eligible)', r.body);

  r = await call('POST', '/score/submit', { token: me.idToken, body: { roundId: cleared.roundId, elapsedMs: 7200, events: clearedEvents } });
  assert.equal(r.status, 410);
  assert.equal(r.body.error.code, 'round_used');
  log('resubmit -> 410', r.body.error);

  // 2. Sudden death: 4 correct, wrong color at cell 5 (index 4).
  const g2 = gridFor(mistake, 3, 4, 'normal');
  const mistakeEvents = g2.slice(0, 5).map((c, i) => ({ i, c: c.ink, t: (i + 1) * 600 }));
  const cell5 = g2[4];
  mistakeEvents[4].c = COLOR_SETS.normal.find((k) => k !== cell5.ink && k !== cell5.word);
  r = await call('POST', '/score/submit', { token: me.idToken, body: { roundId: mistake.roundId, elapsedMs: 3000, events: mistakeEvents } });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  assert.equal(r.body.end, 'mistake');
  assert.equal(r.body.correct, 4);
  assert.equal(r.body.mistakeKind, 'color');
  assert.ok(r.body.score < clearedScore);
  assert.equal(r.body.personalBest, false);
  assert.equal(r.body.legendsEligible, false);
  assert.equal(r.body.rank, null);
  log('mistake round submitted', r.body);

  // 3. Too fast: 12 correct at 100 ms each.
  const g3 = gridFor(fast, 3, 4, 'normal');
  const fastEvents = g3.map((c, i) => ({ i, c: c.ink, t: (i + 1) * 100 }));
  r = await call('POST', '/score/submit', { token: me.idToken, body: { roundId: fast.roundId, elapsedMs: 1200, events: fastEvents } });
  assert.equal(r.status, 400);
  assert.equal(r.body.error.code, 'too_fast');
  log('too-fast round -> 400', r.body.error);

  // Other user's round cannot be submitted by me.
  r = await call('POST', '/round/start', { token: other.idToken, body: startBody });
  assert.equal(r.status, 200);
  r = await call('POST', '/score/submit', { token: me.idToken, body: { roundId: r.body.roundId, elapsedMs: 600, events: [{ i: 0, c: 'red', t: 600 }] } });
  assert.equal(r.status, 403);
  log("other user's round -> 403", r.body.error);

  // Anonymous players never get Global Legends rows.
  const BOARD = '3x4.normal.voice';
  const bestId = `all_${BOARD}_${me.uid}`;
  const bestUrl = `${FS_DOCS}/bests/${encodeURIComponent(bestId)}`;
  let fsRes = await fetch(bestUrl);
  assert.equal(fsRes.status, 404, await fsRes.text());
  assert.equal((await queryBests([['uid', 'EQUAL', me.uid]])).length, 0);
  log('anonymous: no bests docs', { id: bestId });

  // Claiming without Google is refused.
  r = await call('POST', '/legends/claim', { token: me.idToken });
  assert.equal(r.status, 403);
  assert.equal(r.body.error.code, 'google_required');
  log('claim before linking Google -> 403', r.body.error);

  // Link a Google identity to the anonymous account (same uid, new token).
  const linked = await linkGoogle(me.idToken);
  assert.equal(linked.uid, me.uid);
  me.idToken = linked.idToken;
  r = await call('GET', '/profile', { token: me.idToken });
  assert.equal(r.status, 200);
  assert.equal(r.body.profile.google, true);
  log('Google linked; GET /profile google=true', { uid: linked.uid, google: r.body.profile.google });

  r = await call('POST', '/legends/claim', { token: me.idToken });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  assert.ok(r.body.claimed >= 1);
  assert.equal(r.body.claimed, 3); // all + day + week for the one board
  assert.deepEqual(r.body.boards, [BOARD]);
  log('POST /legends/claim', r.body);

  r = await call('POST', '/legends/claim', { token: me.idToken });
  assert.equal(r.status, 200);
  assert.deepEqual(r.body, { claimed: 0, boards: [] });
  log('second claim is a no-op', r.body);

  // Read the claimed all-time best via the Firestore REST API (public read per rules).
  fsRes = await fetch(bestUrl);
  const fsDoc = await fsRes.json();
  assert.equal(fsRes.status, 200, JSON.stringify(fsDoc));
  assert.equal(Number(fsDoc.fields.score.integerValue), clearedScore);
  assert.equal(fsDoc.fields.nickname.stringValue, nickname);
  assert.equal(fsDoc.fields.end.stringValue, 'cleared');
  assert.equal(fsDoc.fields.avatarSeed.stringValue, 'emoji:\u{1F98A}:3');
  log('claimed bests doc via REST', { id: bestId, score: fsDoc.fields.score.integerValue, period: fsDoc.fields.period.stringValue });

  // My bests rows (public) and confirm scores are not publicly readable.
  const mine = await queryBests([['uid', 'EQUAL', me.uid]]);
  assert.equal(mine.length, 3); // all + day + week
  const scoresRes = await fetch(`${FS_DOCS}/scores?pageSize=5`);
  assert.equal(scoresRes.status, 403);
  log('bests (3 periods) readable; scores list denied', { bests: mine.map((d) => d.name.split('/').pop()) });

  // 4. Next submission (now Google-linked) is legends-eligible and ranked.
  const g4 = gridFor(afterLink, 3, 4, 'normal');
  const linkedEvents = g4.map((c, i) => ({ i, c: c.ink, t: (i + 1) * 550 }));
  r = await call('POST', '/score/submit', { token: me.idToken, body: { roundId: afterLink.roundId, elapsedMs: 6600, events: linkedEvents } });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  assert.equal(r.body.end, 'cleared');
  assert.equal(r.body.legendsEligible, true);
  assert.equal(r.body.personalBest, r.body.score > clearedScore);
  const myBest = Math.max(clearedScore, r.body.score);
  const periods = (await queryBests([['uid', 'EQUAL', me.uid]])).map((d) => d.fields.period.stringValue);
  const dayP = periods.find((p) => p.startsWith('d'));
  const weekP = periods.find((p) => p.startsWith('w'));
  assert.deepEqual(r.body.rank, {
    day: await expectedRank(dayP, BOARD, myBest),
    week: await expectedRank(weekP, BOARD, myBest),
    all: await expectedRank('all', BOARD, myBest),
  });
  log('post-link round submitted (legends-eligible)', r.body);

  r = await call('GET', '/profile', { token: me.idToken });
  assert.equal(r.status, 200);
  assert.equal(r.body.profile.gamesPlayed, 3);
  assert.equal(r.body.profile.google, true);
  log('GET /profile', r.body);

  console.log('\nSMOKE OK');
}

main().catch((e) => {
  console.error('\nSMOKE FAILED:', e);
  process.exit(1);
});
