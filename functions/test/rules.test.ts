// Firestore security rules tests. They need the Firestore emulator and only
// run when FIRESTORE_EMULATOR_HOST is set, e.g.
//   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 npx vitest run test/rules.test.ts
// A separate demo project id keeps these rules/data away from the smoke test.
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  type RulesTestEnvironment,
} from '@firebase/rules-unit-testing';
import { deleteDoc, doc, getDoc, serverTimestamp, setDoc, updateDoc, writeBatch } from 'firebase/firestore';
import { afterAll, beforeAll, beforeEach, describe, it } from 'vitest';

const HOST = process.env.FIRESTORE_EMULATOR_HOST;
const here = dirname(fileURLToPath(import.meta.url));
const RULES = resolve(here, '../../firebase/firestore.rules');

const CODE = 'ABC234';
const room = (over: Record<string, unknown> = {}) => ({
  hostUid: 'host',
  hostName: 'Host',
  status: 'lobby',
  config: { cols: 3, rows: 4, colorSet: 'normal', mode: 'voice' },
  seed: 42,
  round: 0,
  startAtMs: null,
  createdAt: new Date(),
  updatedAt: new Date(),
  ...over,
});
const player = (uid: string, over: Record<string, unknown> = {}) => ({
  uid,
  nickname: 'Nova',
  avatar: 'emoji:🦊:3',
  joinedAt: new Date(),
  joinedAtMs: 1_700_000_000_000,
  round: 0,
  state: 'waiting',
  correct: 0,
  cells: 0,
  score: 0,
  elapsedMs: 0,
  finishedAt: null,
  updatedAt: new Date(),
  ...over,
});

describe.skipIf(!HOST)('firestore.rules', () => {
  let env: RulesTestEnvironment;

  beforeAll(async () => {
    const [host, port] = HOST!.split(':');
    env = await initializeTestEnvironment({
      projectId: 'demo-rockketeyes-rules',
      firestore: { rules: readFileSync(RULES, 'utf8'), host, port: Number(port) },
    });
  });
  afterAll(async () => {
    await env?.cleanup();
  });
  beforeEach(async () => {
    await env.clearFirestore();
  });

  const as = (uid: string) => env.authenticatedContext(uid).firestore();
  const seed = (path: string, data: Record<string, unknown>) =>
    env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), path), data);
    });

  describe('rooms', () => {
    it('host creates a room', async () => {
      await assertSucceeds(setDoc(doc(as('host'), `rooms/${CODE}`), room()));
    });

    it('rejects a bad code, foreign hostUid, non-lobby status or bad config', async () => {
      const db = as('host');
      await assertFails(setDoc(doc(db, 'rooms/abc234'), room()));
      await assertFails(setDoc(doc(db, 'rooms/ABCI23'), room())); // I is excluded
      await assertFails(setDoc(doc(db, 'rooms/ABC23'), room()));
      await assertFails(setDoc(doc(db, `rooms/${CODE}`), room({ hostUid: 'someone' })));
      await assertFails(setDoc(doc(db, `rooms/${CODE}`), room({ status: 'playing' })));
      await assertFails(setDoc(doc(db, `rooms/${CODE}`), room({ config: { cols: 2, rows: 4, colorSet: 'normal', mode: 'voice' } })));
      await assertFails(setDoc(doc(db, `rooms/${CODE}`), room({ config: { cols: 3, rows: 4, colorSet: 'rainbow', mode: 'voice' } })));
    });

    it('host updates the room; hostUid cannot change', async () => {
      await seed(`rooms/${CODE}`, room());
      const db = as('host');
      await assertSucceeds(updateDoc(doc(db, `rooms/${CODE}`), { status: 'countdown', startAtMs: 1_700_000_000_000, round: 1 }));
      await assertFails(updateDoc(doc(db, `rooms/${CODE}`), { hostUid: 'other' }));
    });

    it('non-host cannot update or delete the room', async () => {
      await seed(`rooms/${CODE}`, room());
      await assertFails(updateDoc(doc(as('p1'), `rooms/${CODE}`), { status: 'playing' }));
      await assertFails(deleteDoc(doc(as('p1'), `rooms/${CODE}`)));
      await assertSucceeds(deleteDoc(doc(as('host'), `rooms/${CODE}`)));
    });

    it('anyone signed in can read; unauthenticated cannot', async () => {
      await seed(`rooms/${CODE}`, room());
      await seed(`rooms/${CODE}/players/p1`, player('p1'));
      await assertSucceeds(getDoc(doc(as('stranger'), `rooms/${CODE}`)));
      await assertSucceeds(getDoc(doc(as('stranger'), `rooms/${CODE}/players/p1`)));
      const anon = env.unauthenticatedContext().firestore();
      await assertFails(getDoc(doc(anon, `rooms/${CODE}`)));
      await assertFails(getDoc(doc(anon, `rooms/${CODE}/players/p1`)));
    });
  });

  describe('players', () => {
    it('player joins a lobby', async () => {
      await seed(`rooms/${CODE}`, room());
      await assertSucceeds(setDoc(doc(as('p1'), `rooms/${CODE}/players/p1`), player('p1')));
    });

    it('cannot join as someone else, a missing room, or with a bad nickname/avatar', async () => {
      await seed(`rooms/${CODE}`, room());
      const db = as('p1');
      await assertFails(setDoc(doc(db, `rooms/${CODE}/players/p2`), player('p2')));
      await assertFails(setDoc(doc(db, `rooms/${CODE}/players/p1`), player('p2')));
      await assertFails(setDoc(doc(db, 'rooms/ZZZ999/players/p1'), player('p1')));
      await assertFails(setDoc(doc(db, `rooms/${CODE}/players/p1`), player('p1', { nickname: '' })));
      await assertFails(setDoc(doc(db, `rooms/${CODE}/players/p1`), player('p1', { nickname: 'x'.repeat(17) })));
      await assertFails(setDoc(doc(db, `rooms/${CODE}/players/p1`), player('p1', { avatar: 'x'.repeat(65) })));
    });

    it('cannot join when the room is not in the lobby', async () => {
      for (const status of ['countdown', 'playing', 'finished']) {
        await seed(`rooms/${CODE}`, room({ status }));
        await assertFails(setDoc(doc(as('p1'), `rooms/${CODE}/players/p1`), player('p1')));
      }
    });

    it('player updates own progress', async () => {
      await seed(`rooms/${CODE}`, room({ status: 'playing' }));
      await seed(`rooms/${CODE}/players/p1`, player('p1'));
      await assertSucceeds(
        updateDoc(doc(as('p1'), `rooms/${CODE}/players/p1`), { state: 'cleared', correct: 12, cells: 12, score: 900, elapsedMs: 7200 }),
      );
      await assertFails(updateDoc(doc(as('p1'), `rooms/${CODE}/players/p1`), { uid: 'p2' }));
      await assertFails(updateDoc(doc(as('p1'), `rooms/${CODE}/players/p1`), { nickname: '' }));
    });

    it('player cannot edit or remove another player', async () => {
      await seed(`rooms/${CODE}`, room({ status: 'playing' }));
      await seed(`rooms/${CODE}/players/p2`, player('p2'));
      await assertFails(updateDoc(doc(as('p1'), `rooms/${CODE}/players/p2`), { score: 0, state: 'out' }));
      await assertFails(deleteDoc(doc(as('p1'), `rooms/${CODE}/players/p2`)));
    });

    it('host can reset or kick a player; player can leave', async () => {
      await seed(`rooms/${CODE}`, room({ status: 'finished' }));
      await seed(`rooms/${CODE}/players/p1`, player('p1', { state: 'cleared', score: 900 }));
      await seed(`rooms/${CODE}/players/p2`, player('p2'));
      await assertSucceeds(
        updateDoc(doc(as('host'), `rooms/${CODE}/players/p1`), { state: 'waiting', round: 1, correct: 0, cells: 0, score: 0, elapsedMs: 0 }),
      );
      await assertSucceeds(deleteDoc(doc(as('host'), `rooms/${CODE}/players/p2`)));
      await assertSucceeds(deleteDoc(doc(as('p1'), `rooms/${CODE}/players/p1`)));
    });

    it('client-shaped writes with server timestamps: join, host batch reset, close room', async () => {
      const host = as('host');
      await assertSucceeds(
        setDoc(doc(host, `rooms/${CODE}`), room({ createdAt: serverTimestamp(), updatedAt: serverTimestamp() })),
      );
      for (const uid of ['p1', 'p2']) {
        await assertSucceeds(
          setDoc(
            doc(as(uid), `rooms/${CODE}/players/${uid}`),
            player(uid, { joinedAt: serverTimestamp(), updatedAt: serverTimestamp(), finishedAt: null }),
          ),
        );
      }
      await assertSucceeds(updateDoc(doc(host, `rooms/${CODE}`), { status: 'playing', startAtMs: 1_700_000_003_000, updatedAt: serverTimestamp() }));
      await assertSucceeds(
        updateDoc(doc(as('p1'), `rooms/${CODE}/players/p1`), { state: 'cleared', finishedAt: serverTimestamp(), updatedAt: serverTimestamp() }),
      );
      const batch = writeBatch(host);
      for (const uid of ['p1', 'p2']) {
        batch.update(doc(host, `rooms/${CODE}/players/${uid}`), {
          round: 1, state: 'waiting', correct: 0, cells: 0, score: 0, elapsedMs: 0, finishedAt: null, updatedAt: serverTimestamp(),
        });
      }
      batch.update(doc(host, `rooms/${CODE}`), { status: 'lobby', round: 1, startAtMs: null, updatedAt: serverTimestamp() });
      await assertSucceeds(batch.commit());
      await assertSucceeds(deleteDoc(doc(host, `rooms/${CODE}/players/p2`)));
      await assertSucceeds(deleteDoc(doc(host, `rooms/${CODE}`)));
    });
  });

  describe('existing collections', () => {
    it('deny client writes but keep public reads', async () => {
      await seed('users/u1', { nickname: 'Nova' });
      await seed('bests/all_3x4.normal.voice_u1', { uid: 'u1', score: 1 });
      await seed('scores/s1', { uid: 'u1', score: 1 });
      const db = as('u1');
      await assertFails(setDoc(doc(db, 'users/u1'), { nickname: 'Hacker' }));
      await assertFails(setDoc(doc(db, 'bests/all_3x4.normal.voice_u1'), { uid: 'u1', score: 99999 }));
      await assertFails(setDoc(doc(db, 'scores/s2'), { uid: 'u1', score: 99999 }));
      await assertFails(setDoc(doc(db, 'rounds/r1'), { uid: 'u1' }));
      await assertFails(setDoc(doc(db, 'nicknames/nova'), { uid: 'u1' }));
      await assertFails(setDoc(doc(db, 'other/x'), { a: 1 }));
      await assertSucceeds(getDoc(doc(env.unauthenticatedContext().firestore(), 'users/u1')));
      await assertSucceeds(getDoc(doc(env.unauthenticatedContext().firestore(), 'bests/all_3x4.normal.voice_u1')));
      await assertSucceeds(getDoc(doc(db, 'scores/s1')));
      await assertFails(getDoc(doc(as('u2'), 'scores/s1')));
      await assertFails(getDoc(doc(db, 'rounds/r1')));
    });
  });
});
