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
  log('POST /profile', r.body);

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

  // Issue three 3x4 normal voice rounds.
  const startBody = { cols: 3, rows: 4, colorSet: 'normal', congruentRatio: 0, mode: 'voice' };
  const starts = [];
  for (let k = 0; k < 3; k++) {
    r = await call('POST', '/round/start', { token: me.idToken, body: startBody });
    assert.equal(r.status, 200, JSON.stringify(r.body));
    assert.equal(r.body.ranked, true);
    assert.equal(r.body.boardId, '3x4.normal.voice');
    assert.equal(r.body.expiresAt - r.body.issuedAt, 30 * 60 * 1000);
    starts.push(r.body);
  }
  log('3 rounds started', starts.map((s) => ({ roundId: s.roundId, seed: s.seed })));

  // Wait so that elapsedMs (7200) is within wall-clock time since issue.
  await sleep(6800);

  // 1. Cleared round: all 12 correct, t spaced 600 ms.
  const [cleared, mistake, fast] = starts;
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
  assert.equal(r.body.personalBest, true);
  assert.deepEqual(r.body.rank, { day: 1, week: 1, all: 1 });
  const clearedScore = r.body.score;
  log('cleared round submitted', r.body);

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
  assert.equal(r.body.rank.all, 1);
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

  // Read the all-time best via the Firestore REST API (public read per rules).
  const bestId = `all_3x4.normal.voice_${me.uid}`;
  const fsRes = await fetch(`http://${FS_HOST}/v1/projects/${PROJECT}/databases/(default)/documents/bests/${encodeURIComponent(bestId)}`);
  const fsDoc = await fsRes.json();
  assert.equal(fsRes.status, 200, JSON.stringify(fsDoc));
  assert.equal(Number(fsDoc.fields.score.integerValue), clearedScore);
  assert.equal(fsDoc.fields.nickname.stringValue, nickname);
  assert.equal(fsDoc.fields.end.stringValue, 'cleared');
  log('bests doc via REST', { id: bestId, score: fsDoc.fields.score.integerValue, period: fsDoc.fields.period.stringValue });

  // List the 3x4 board bests (public) and confirm scores are not publicly readable.
  const listRes = await fetch(`http://${FS_HOST}/v1/projects/${PROJECT}/databases/(default)/documents/bests?pageSize=20`);
  const list = await listRes.json();
  assert.equal(listRes.status, 200);
  assert.equal((list.documents || []).length, 3); // all + day + week
  const scoresRes = await fetch(`http://${FS_HOST}/v1/projects/${PROJECT}/databases/(default)/documents/scores?pageSize=5`);
  assert.equal(scoresRes.status, 403);
  log('bests list (3 periods) readable; scores list denied', { bests: list.documents.map((d) => d.name.split('/').pop()) });

  r = await call('GET', '/profile', { token: me.idToken });
  assert.equal(r.status, 200);
  assert.equal(r.body.profile.gamesPlayed, 2);
  log('GET /profile', r.body);

  console.log('\nSMOKE OK');
}

main().catch((e) => {
  console.error('\nSMOKE FAILED:', e);
  process.exit(1);
});
