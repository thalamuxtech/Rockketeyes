// Group challenge end-to-end: one host screen + three player phones.
//
//   node e2e/group.mjs [outDir]      (same prerequisites as run.mjs)
//
// Players join through /join/CODE (the QR target), play the same board with
// simulated speech, and the host screen ranks them live and on the podium.
import { chromium } from 'playwright';
import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const BASE = process.env.BASE_URL || 'http://localhost:5173';
const OUT = process.argv[2] || 'e2e-group-out';
mkdirSync(OUT, { recursive: true });

const results = [];
const errors = [];
let shot = 0;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function check(name, ok, detail = '') {
  results.push({ name, ok: !!ok, detail });
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? ', ' + detail : ''}`);
}

const fakeSpeech = () => {
  class FakeSR {
    constructor() { this._results = []; }
    start() { window.__sr = this; this._running = true; setTimeout(() => this.onstart && this.onstart(), 30); }
    stop() { this.abort(); }
    abort() { if (!this._running) return; this._running = false; setTimeout(() => this.onend && this.onend(), 10); }
    _emit(i) {
      const results = this._results.map((r) => { const a = [{ transcript: r.text, confidence: 0.9 }]; a.isFinal = r.final; return a; });
      this.onresult && this.onresult({ resultIndex: i, results });
    }
  }
  window.SpeechRecognition = FakeSR;
  window.webkitSpeechRecognition = FakeSR;
  window.__speak = (word) => {
    const sr = window.__sr; if (!sr || !sr._running) return false;
    sr._results.push({ text: ' ' + word, final: true });
    sr._emit(sr._results.length - 1);
    return true;
  };
};

async function state(page) {
  const raw = await page.evaluate(() => (window.reE2E ? window.reE2E.state() : null));
  return raw ? JSON.parse(raw) : null;
}

async function waitFor(page, pred, label, timeout = 30000) {
  const t0 = Date.now();
  let s;
  while (Date.now() - t0 < timeout) {
    s = await state(page);
    if (s && pred(s)) return s;
    await sleep(120);
  }
  throw new Error(`timeout waiting for ${label}; last ${JSON.stringify(s)}`);
}

async function snap(page, name) {
  await page.screenshot({ path: join(OUT, `${String(++shot).padStart(2, '0')}-${name}.png`) });
}

// E2E builds keep Flutter's accessibility tree on, so nothing to toggle.
async function semantics() {}

async function click(page, name) {
  const b = page.getByRole('button', { name, exact: false }).first();
  await b.waitFor({ state: 'visible', timeout: 20000 });
  await b.click();
}

// Flutter exposes text as DOM text on desktop and as aria-labels on mobile.
async function textCount(page, text) {
  return page.evaluate((t) => {
    const norm = (x) => (x || '').replace(/[‘’]/g, "'");
    let n = 0;
    for (const el of document.querySelectorAll('flt-semantics, flt-semantics-host *')) {
      if (norm(el.getAttribute('aria-label')).includes(t) || (el.children.length === 0 && norm(el.textContent).includes(t))) n++;
    }
    return n;
  }, text);
}

const allPages = [];
async function boot(ctx) {
  const page = await ctx.newPage();
  allPages.push(page);
  page.on('console', (m) => { if (/listener error|failed|denied/i.test(m.text())) errors.push('console: ' + m.text().slice(0, 200)); });
  page.on('pageerror', (e) => errors.push(`${e.message} @ ${(e.stack || '').split(String.fromCharCode(10)).slice(0, 3).join(' | ')}`));
  return page;
}

// Plays until cleared, or makes a wrong answer at `mistakeAt`.
async function play(page, { gap, mistakeAt = -1 }) {
  await waitFor(page, (s) => s.round.phase === 'playing', 'player playing', 45000);
  for (let i = 0; i < 400; i++) {
    const s = await state(page);
    if (s.round.phase !== 'playing') break;
    let word = s.round.ink;
    if (i === mistakeAt) word = ['red', 'blue', 'green', 'yellow', 'orange', 'purple'].find((c) => c !== s.round.ink && c !== s.round.word);
    await page.evaluate((w) => window.__speak(w), word);
    await sleep(gap);
    if (i === mistakeAt) break;
  }
}

const browser = await chromium.launch({
  channel: 'chrome',
  headless: true,
  args: ['--use-fake-ui-for-media-stream', '--use-fake-device-for-media-stream', '--autoplay-policy=no-user-gesture-required'],
});

try {
  // ---- Host ----
  const hostCtx = await browser.newContext({ viewport: { width: 1366, height: 820 } });
  await hostCtx.addInitScript(fakeSpeech);
  const host = await boot(hostCtx);
  await host.goto(`${BASE}/group`);
  await host.waitForFunction(() => !!window.reE2E, null, { timeout: 60000 });
  await sleep(1500);
  await semantics(host);
  await snap(host, 'host-setup');
  await click(host, '4×4');
  await click(host, 'Open room');
  const code = await (async () => {
    for (let i = 0; i < 100; i++) {
      const c = await host.evaluate(() => window.reE2E.hostedRoom());
      if (c) return c;
      await sleep(150);
    }
    return null;
  })();
  check('host opens a room with a 6-character PIN', /^[A-HJ-NP-Z2-9]{6}$/.test(code || ''), code);
  await sleep(1500);
  check('host route is /group/host/PIN', (await state(host)).route === `/group/host/${code}`);
  await snap(host, 'host-lobby-empty');

  // ---- Players join via the QR link ----
  const names = ['Ada', 'Bola', 'Chen'];
  const players = [];
  for (const name of names) {
    const ctx = await browser.newContext({
      viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true, permissions: ['microphone'],
    });
    await ctx.addInitScript(fakeSpeech);
    const page = await boot(ctx);
    await page.goto(`${BASE}/join/${code}`);
    await page.waitForFunction(() => !!window.reE2E, null, { timeout: 60000 });
    await sleep(1800);
    await semantics(page);
    const box = page.getByRole('textbox').first();
    await box.waitFor({ timeout: 60000 });
    await box.click();
    await box.fill(name);
    if (name === 'Ada') await snap(page, 'player-join-form');
    await click(page, 'Join game');
    await sleep(1500);
    players.push({ name, ctx, page });
  }
  const inCount = await Promise.all(players.map((p) => textCount(p.page, "You're in")));
  check('all three players are in the lobby', inCount.every((n) => n > 0), inCount.join(','));
  await snap(players[0].page, 'player-waiting');
  await sleep(1000);
  const hostSees = await textCount(host, '3 joined');
  check('host lobby shows the players live', hostSees > 0);
  await snap(host, 'host-lobby-players');

  // ---- Round 1 ----
  await click(host, 'Start game');
  const pStates = await Promise.all(players.map((p) => waitFor(p.page, (s) => s.round.group === code && s.round.phase !== 'preparing', 'group round', 30000)));
  check('every player gets the group round', pStates.every((s) => s.round.group === code), pStates.map((s) => s.round.phase).join(','));
  const inks = await Promise.all(players.map(async (p) => {
    await waitFor(p.page, (s) => s.round.phase === 'playing', 'playing', 30000);
    return (await state(p.page)).round.ink;
  }));
  check('everyone plays the same board', new Set(inks).size === 1, inks.join(','));

  const race = Promise.all([
    play(players[0].page, { gap: 380 }), // Ada: fast, clears
    play(players[1].page, { gap: 650 }), // Bola: slower, clears
    play(players[2].page, { gap: 420, mistakeAt: 5 }), // Chen: mistake at word 6
  ]);
  await sleep(3500);
  await snap(host, 'host-live-race');
  await snap(players[1].page, 'player-midgame');
  await race;

  const finals = await Promise.all(players.map((p) => waitFor(p.page, (s) => s.round.phase === 'results', 'results', 20000)));
  check('Ada and Bola clear the board', finals[0].round.correct === 16 && finals[1].round.correct === 16);
  check('Chen is out after a mistake', finals[2].round.mistake === 'color' && finals[2].round.correct === 5, `${finals[2].round.correct} correct`);

  // Host finishes automatically once everyone is done.
  const t0 = Date.now();
  let podium = 0;
  while (Date.now() - t0 < 15000 && podium === 0) {
    podium = await textCount(host, 'cleared it first');
    await sleep(300);
  }
  check('host ends the round automatically and shows the podium', podium > 0);
  const adaWins = await textCount(host, 'Ada cleared it first');
  check('first to clear (Ada) wins', adaWins > 0);
  await sleep(1500);
  await snap(host, 'host-podium');

  const finalText = await textCount(players[0].page, 'Final results');
  check('players see the final standings', finalText > 0);
  await snap(players[0].page, 'player-final');
  await click(players[0].page, 'Back to the lobby');
  await sleep(1500);
  const won = await textCount(players[0].page, 'You won');
  check('winner sees "You won!" in the lobby', won > 0);
  await snap(players[0].page, 'player-won');
  const chenPlace = await (async () => {
    await click(players[2].page, 'Back to the lobby');
    await sleep(1200);
    return textCount(players[2].page, 'You placed #3');
  })();
  check('Chen placed #3', chenPlace > 0);

  // ---- Round 2 (play again) starts automatically on every phone ----
  await click(host, 'Play again');
  const r2 = await Promise.all(players.map((p) => waitFor(p.page, (s) => s.round.group === code && s.round.phase === 'playing', 'round 2', 45000)));
  check('"Play again" starts a new round on every phone', r2.length === 3);
  await click(host, 'End round now');
  let ended = 0;
  const t1 = Date.now();
  while (Date.now() - t1 < 10000 && ended === 0) {
    ended = await textCount(host, 'wins with the top score') + await textCount(host, 'cleared it first');
    await sleep(300);
  }
  check('host can end a round early', ended > 0);

  // ---- Late joiner and bad PIN ----
  const lateCtx = await browser.newContext({ viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true });
  const late = await boot(lateCtx);
  await late.goto(`${BASE}/join/ZZZZZZ`);
  await late.waitForFunction(() => !!window.reE2E, null, { timeout: 60000 });
  let badPin = 0;
  for (let i = 0; i < 60 && badPin === 0; i++) {
    await sleep(500);
    badPin = await textCount(late, 'No game with PIN');
  }
  check('unknown PIN shows a friendly message', badPin > 0);
  await snap(late, 'bad-pin');
} catch (e) {
  check('group suite crashed', false, e.message);
  for (const [i, pg] of allPages.entries()) {
    await pg.screenshot({ path: join(OUT, `crash-page-${i}.png`) }).catch(() => {});
    console.log('page', i, pg.url(), JSON.stringify(await state(pg).catch(() => null)));
  }
} finally {
  await browser.close();
}

const relevant = errors.filter((e) => !/dicebear|flagcdn|net::/i.test(e));
check('no uncaught page errors', relevant.length === 0, relevant.slice(0, 3).join(' | '));
const passed = results.filter((r) => r.ok).length;
writeFileSync(join(OUT, 'report.json'), JSON.stringify({ passed, total: results.length, results, errors }, null, 2));
console.log(`\n${passed}/${results.length} group checks passed. Screenshots in ${OUT}`);
process.exit(passed === results.length ? 0 : 1);
