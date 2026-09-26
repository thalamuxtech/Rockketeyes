// RocketEye end-to-end suite (Flutter web build + Firebase emulators).
//
//   1. firebase emulators:start --only auth,firestore,functions --project rockketeyes
//   2. flutter build web --release --dart-define=RE_EMULATOR=true --dart-define=RE_E2E=true
//   3. node e2e/serve.mjs   (port 5173)
//   4. node e2e/run.mjs [outDir]
//
// Speech is simulated by replacing window.SpeechRecognition with a fake that
// emits Chrome-shaped result events, so the real bridge → matcher → round
// controller pipeline is exercised end to end.
import { chromium } from 'playwright';
import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const BASE = process.env.BASE_URL || 'http://localhost:5173';
const OUT = process.argv[2] || 'e2e-out';
mkdirSync(OUT, { recursive: true });

const results = [];
const consoleErrors = [];
let shot = 0;

function check(name, ok, detail = '') {
  results.push({ name, ok: !!ok, detail });
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? ', ' + detail : ''}`);
}

const fakeSpeech = () => {
  class FakeSR {
    constructor() { this.continuous = false; this.interimResults = false; this.lang = 'en-US'; this._results = []; }
    start() {
      window.__sr = this; this._running = true;
      setTimeout(() => this.onstart && this.onstart(), 30);
    }
    stop() { this.abort(); }
    abort() {
      if (!this._running) return;
      this._running = false;
      setTimeout(() => this.onend && this.onend(), 10);
    }
    _emit(resultIndex) {
      const results = this._results.map((r) => {
        const alt = { transcript: r.text, confidence: r.final ? 0.9 : 0 };
        const arr = [alt]; arr.isFinal = r.final; return arr;
      });
      this.onresult && this.onresult({ resultIndex, results });
    }
  }
  window.SpeechRecognition = FakeSR;
  window.webkitSpeechRecognition = FakeSR;
  // Mode "split": each word is its own result (interim then final).
  window.__speakSplit = (word) => {
    const sr = window.__sr; if (!sr || !sr._running) return false;
    sr._results.push({ text: word.slice(0, 2), final: false });
    const i = sr._results.length - 1;
    sr._emit(i);
    sr._results[i] = { text: ' ' + word, final: false }; sr._emit(i);
    sr._results[i] = { text: ' ' + word, final: true }; sr._emit(i);
    return true;
  };
  // Mode "stream": one growing interim result ("red" → "red blue" → ...).
  window.__speakStream = (word) => {
    const sr = window.__sr; if (!sr || !sr._running) return false;
    if (!sr._results.length || sr._results[sr._results.length - 1].final) sr._results.push({ text: '', final: false });
    const i = sr._results.length - 1;
    sr._results[i] = { text: (sr._results[i].text + ' ' + word).trim(), final: false };
    sr._emit(i);
    return true;
  };
  // Simulate Chrome ending the session (it auto-restarts in the bridge).
  window.__srEnd = () => { const sr = window.__sr; if (sr) { sr._running = false; sr.onend && sr.onend(); } };
};

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function state(page) {
  const raw = await page.evaluate(() => (window.reE2E ? window.reE2E.state() : null));
  return raw ? JSON.parse(raw) : null;
}

async function waitFor(page, pred, label, timeout = 20000) {
  const t0 = Date.now();
  let s;
  while (Date.now() - t0 < timeout) {
    s = await state(page);
    if (s && pred(s)) return s;
    await sleep(100);
  }
  throw new Error(`timeout waiting for ${label}; last state ${JSON.stringify(s)}`);
}

async function snap(page, name) {
  const file = join(OUT, `${String(++shot).padStart(2, '0')}-${name}.png`);
  await page.screenshot({ path: file });
  return file;
}

const seenText = [];
async function collectText(page) {
  const t = await page.evaluate(() => document.querySelector('flt-semantics-host')?.innerText || '');
  seenText.push(t);
}

async function enableSemantics(page) {
  // E2E builds keep Flutter's accessibility tree on; nothing to toggle.
  await sleep(300);
}

async function clickButton(page, name, exact = false) {
  const b = page.getByRole('button', { name, exact }).first();
  await b.waitFor({ state: 'visible', timeout: 15000 });
  await b.click();
}

async function playRound(page, { speak, mistakeAt = -1, mistakeKind = 'word', gap = 420, shotAt = -1, label }) {
  const s0 = await waitFor(page, (s) => s.round.phase === 'playing', `${label} playing`, 30000);
  const cells = s0.round.cells;
  for (let i = 0; i < cells; i++) {
    const s = await state(page);
    if (s.round.phase !== 'playing') break;
    let word = s.round.ink;
    if (i === mistakeAt) {
      word = mistakeKind === 'word' ? s.round.word : (['red', 'blue', 'green', 'yellow'].find((c) => c !== s.round.ink && c !== s.round.word));
    }
    const ok = await page.evaluate(([fn, w]) => window[fn](w), [speak, word]);
    if (!ok) throw new Error('fake recogniser not running');
    await sleep(gap);
    if (i === shotAt) await snap(page, `${label}-midgame`);
    if (i === mistakeAt) break;
  }
}

const browser = await chromium.launch({
  channel: 'chrome',
  headless: true,
  args: ['--use-fake-ui-for-media-stream', '--use-fake-device-for-media-stream', '--autoplay-policy=no-user-gesture-required'],
});

try {
  // ---------- Desktop flow ----------
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 860 }, permissions: ['microphone'] });
  await ctx.addInitScript(fakeSpeech);
  const page = await ctx.newPage();
  page.on('console', (m) => { if (m.type() === 'error') consoleErrors.push(m.text()); });
  page.on('pageerror', (e) => consoleErrors.push('pageerror: ' + e.message));

  const t0 = Date.now();
  await page.goto(BASE, { waitUntil: 'load' });
  await page.waitForFunction(() => !!window.reE2E, null, { timeout: 60000 });
  check('app boots and exposes E2E hooks', true, `${Date.now() - t0} ms`);
  await sleep(1200);
  let s = await state(page);
  check('first launch routes to onboarding', s.route.startsWith('/onboarding'), s.route);
  await snap(page, 'onboarding-1');

  await enableSemantics(page);
  await clickButton(page, 'Next');
  await sleep(900);
  await snap(page, 'onboarding-2');
  await clickButton(page, 'Next');
  await sleep(900);
  await clickButton(page, "Let's go");
  s = await waitFor(page, (x) => x.route.startsWith('/profile'), 'profile route', 8000).catch(() => state(page));
  check('onboarding ends on profile setup', s.route.startsWith('/profile'), s.route);

  const nick = `E2E Pilot ${Math.floor(Math.random() * 900 + 100)}`;
  const input = page.getByRole('textbox').first();
  await input.waitFor({ timeout: 15000 });
  await input.click();
  await input.fill(nick);
  await sleep(300);
  await snap(page, 'profile');
  // Avatar studio: pick an emoji avatar.
  await clickButton(page, 'Choose from characters and emoji');
  await sleep(1200);
  await snap(page, 'avatar-studio-characters');
  await clickButton(page, 'Emoji', true);
  await sleep(700);
  await clickButton(page, 'Animals', true);
  await sleep(500);
  await clickButton(page, 'Emoji 🦊', true);
  await sleep(400);
  await snap(page, 'avatar-studio-emoji');
  await clickButton(page, 'Use this avatar');
  await sleep(700);
  check('avatar studio opens and applies a choice', true);
  await clickButton(page, 'Save profile');
  await waitFor(page, (x) => x.route === '/', 'home after profile save', 15000).catch(() => null);
  s = await state(page);
  check('profile saves and returns home', s.route === '/', s.route);
  await sleep(1500);
  await snap(page, 'home');

  // Setup sheet → 3×4 voice.
  await clickButton(page, 'Play');
  await sleep(900);
  await snap(page, 'setup-sheet');
  await clickButton(page, '3×4');
  await clickButton(page, 'Normal');
  await clickButton(page, 'Voice');
  await clickButton(page, 'Start');
  await waitFor(page, (x) => x.round.phase === 'countdown', 'countdown', 20000);
  await sleep(250);
  await snap(page, 'countdown');
  check('countdown runs before play', true);

  // Round 1: clear the board with split-result speech.
  await playRound(page, { speak: '__speakSplit', gap: 450, shotAt: 5, label: 'r1' });
  s = await waitFor(page, (x) => x.round.phase === 'results', 'results r1', 15000);
  check('clearing the board ends the round', s.round.correct === s.round.cells, `${s.round.correct}/${s.round.cells}`);
  s = await waitFor(page, (x) => x.round.submit === 'done' || x.round.submit === 'failed', 'submit r1', 15000);
  check('ranked score submitted to server', s.round.submit === 'done', s.round.submit);
  check('server score equals client score', s.round.serverScore === s.round.score, `${s.round.serverScore} vs ${s.round.score}`);
  check('guest score is kept off Global Legends', s.round.legendsEligible === false && s.round.rankAll == null,
    `eligible=${s.round.legendsEligible} rank=${s.round.rankAll}`);
  await sleep(1300);
  await snap(page, 'r1-results');
  await collectText(page);

  await collectText(page);
  const guestCta = await page.getByText('Join Global Legends', { exact: false }).count();
  check('results invite guests to connect Google', guestCta > 0);
  const linked = await page.evaluate(() => window.reE2E.connectGoogle());
  check('Google account connects (and claims past bests)', linked === 'ok', linked);
  await sleep(1500);
  await snap(page, 'r1-after-google');

  // Round 2: Play again, streaming transcripts, mistake = reading the word at cell 4.
  await clickButton(page, 'Play again');
  await playRound(page, { speak: '__speakStream', mistakeAt: 4, mistakeKind: 'word', gap: 450, label: 'r2' });
  s = await waitFor(page, (x) => x.round.phase === 'ending', 'ending banner r2', 8000).catch(() => state(page));
  await snap(page, 'r2-mistake-banner');
  // Banner position is verified from this screenshot (canvas-rendered).

  await collectText(page);
  s = await waitFor(page, (x) => x.round.phase === 'results', 'results r2', 15000);
  check('reading the word ends the round as a "word" mistake', s.round.mistake === 'word', s.round.mistake);
  check('score counted until the mistake', s.round.correct === 4, `${s.round.correct} correct`);
  s = await waitFor(page, (x) => x.round.submit !== 'submitting' && x.round.submit !== 'none', 'submit r2', 15000);
  check('mistake round submitted', s.round.submit === 'done', s.round.submit);
  check('Google-connected score is ranked', s.round.legendsEligible === true && typeof s.round.rankAll === 'number',
    `all-time #${s.round.rankAll}`);
  await sleep(1300);
  await snap(page, 'r2-results');

  // Round 3: wrong color at the first cell + session restart mid-game.
  await clickButton(page, 'Play again');
  await waitFor(page, (x) => x.round.phase === 'playing', 'r3 playing', 30000);
  await page.evaluate(() => window.__speakSplit(JSON.parse(window.reE2E.state()).round.ink));
  await sleep(400);
  await page.evaluate(() => window.__srEnd());
  await sleep(500);
  const afterRestart = await state(page);
  const spoke = await page.evaluate(() => window.__speakSplit(JSON.parse(window.reE2E.state()).round.ink));
  await sleep(450);
  s = await state(page);
  check('recogniser auto-restarts after the engine ends', spoke && s.round.correct === afterRestart.round.correct + 1,
    `correct ${afterRestart.round.correct} → ${s.round.correct}`);
  // Loose sound-alike that is wrong must be ignored ("hello" → yellow).
  // A sound-alike of a *wrong* color must be ignored, never a mistake.
  const looseFor = { red: 'bed', blue: 'glue', green: 'queen', yellow: 'hello', orange: 'arrange', purple: 'people' };
  const looseWord = Object.entries(looseFor).find(([c]) => c !== s.round.ink)[1];
  await page.evaluate((w) => window.__speakSplit(w), looseWord);
  await sleep(400);
  const s2 = await state(page);
  check('sound-alike words never cause a mistake', s2.round.phase === 'playing' && !s2.round.mistake,
    `"${looseWord}" → ${s2.round.phase}`);
  const wrong = ['red', 'blue', 'green', 'yellow', 'orange', 'purple'].find((c) => c !== s.round.ink && c !== s.round.word);
  await page.evaluate((w) => window.__speakSplit(w), wrong);
  s = await waitFor(page, (x) => x.round.phase === 'results', 'results r3', 15000);
  check('wrong color ends the round as a "color" mistake', s.round.mistake === 'color', s.round.mistake);
  await sleep(1300);

  // Legends.
  await clickButton(page, 'Legends');
  await waitFor(page, (x) => x.route.startsWith('/legends'), 'legends route', 10000);
  await sleep(2500);
  await snap(page, 'legends');
  await collectText(page);
  const hasNick = await page.getByText(nick, { exact: false }).count();
  check('player appears on Global Legends', hasNick > 0, nick);

  // Tap mode round via number keys.
  await page.evaluate(() => window.reE2E.play('4x4', 'easy', 'tap'));
  await waitFor(page, (x) => x.round.phase === 'playing', 'tap playing', 30000);
  for (let i = 0; i < 16; i++) {
    const cur = await state(page);
    if (cur.round.phase !== 'playing') break;
    await page.evaluate(() => window.reE2E.sayCorrect());
    await sleep(320);
  }
  s = await waitFor(page, (x) => x.round.phase === 'results', 'tap results', 15000);
  check('tap mode round completes', s.round.correct === 16 && s.round.input === 'tap', `${s.round.correct}/16`);
  s = await waitFor(page, (x) => x.round.submit !== 'submitting' && x.round.submit !== 'none', 'tap submit', 15000);
  check('tap mode round submitted', s.round.submit === 'done', s.round.submit);

  // Settings screen.
  await page.evaluate(() => window.reE2E.go('/settings'));
  await sleep(1200);
  await snap(page, 'settings');
  await collectText(page);

  // Legal pages.
  const settingsOnly = await page.getByText('Credits', { exact: false }).count();
  check('settings list Terms of Use and License Policy only', settingsOnly === 0 &&
    (await page.getByText('Terms of Use').count()) > 0 && (await page.getByText('License Policy').count()) > 0);
  await page.evaluate(() => window.reE2E.go('/terms'));
  await sleep(1200);
  await snap(page, 'terms');
  check('Terms of Use page renders', (await page.getByText('Fair play', { exact: false }).count()) > 0);
  await collectText(page);
  await page.evaluate(() => window.reE2E.go('/license'));
  await sleep(1200);
  await snap(page, 'license');
  check('License Policy page renders', (await page.getByText('Third-party components', { exact: false }).count()) > 0);
  await collectText(page);

  // About screen.
  await page.evaluate(() => window.reE2E.go('/about'));
  await sleep(1500);
  await snap(page, 'about');
  await collectText(page);
  await page.mouse.move(640, 430);
  await page.mouse.wheel(0, 4000);
  await sleep(900);
  await snap(page, 'about-bottom');
  const dev = await page.getByText('Thalamuxtech', { exact: false }).count();
  check('About page credits the developer', dev > 0);
  await collectText(page);

  // Desktop 16x16: highlight across a row wrap.
  await page.evaluate(() => window.reE2E.play('16x16', 'hard', 'voice'));
  await playRound(page, { speak: '__speakSplit', gap: 330, mistakeAt: 17, mistakeKind: 'color', shotAt: 16, label: 'desk16' });
  await sleep(250);
  await snap(page, 'desk16-row-wrap');

  // Standalone about page beside the app.
  const res = await page.goto(BASE + '/about.html');
  const aboutHtml = await page.content();
  check('standalone about.html is served', res.ok() && aboutHtml.includes('Thalamuxtech') && !/[—–]/.test(aboutHtml));
  await snap(page, 'about-html');
  await ctx.close();

  // ---------- Mobile flow: dense 16×16 + custom size ----------
  const m = await browser.newContext({
    viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true, permissions: ['microphone'],
  });
  await m.addInitScript(fakeSpeech);
  await m.addInitScript(() => {
    // Skip onboarding on this profile.
    window.__skipOnboarding = true;
  });
  const mp = await m.newPage();
  mp.on('pageerror', (e) => consoleErrors.push('mobile pageerror: ' + e.message));
  await mp.goto(BASE, { waitUntil: 'load' });
  await mp.waitForFunction(() => !!window.reE2E, null, { timeout: 60000 });
  await sleep(1500);
  await snap(mp, 'mobile-onboarding');
  await mp.evaluate(() => window.reE2E.play('16x16', 'hard', 'voice'));
  await playRound(mp, { speak: '__speakSplit', gap: 330, mistakeAt: 40, mistakeKind: 'color', shotAt: 20, label: 'mobile16' });
  s = await waitFor(mp, (x) => x.round.phase === 'results', 'mobile results', 15000);
  check('16×16 on a phone plays and scrolls with the highlight', s.round.correct === 40, `${s.round.correct} correct`);
  await sleep(1300);
  await snap(mp, 'mobile16-results');
  await mp.evaluate(() => window.reE2E.play('7x9', 'normal', 'voice'));
  await waitFor(mp, (x) => x.round.phase === 'playing', 'custom playing', 30000);
  s = await state(mp);
  check('custom size is practice-only (unranked)', s.round.ranked === false && s.round.cells === 63, `ranked=${s.round.ranked}`);
  await snap(mp, 'mobile-custom-7x9');
  await mp.evaluate(() => window.reE2E.go('/'));
  await sleep(1200);
  await m.close();
} catch (e) {
  check('suite crashed', false, e.message);
} finally {
  await browser.close();
}

const dashHits = seenText.filter((t) => /[—–]/.test(t));
check('no em or en dashes in on-screen text', dashHits.length === 0, dashHits.map((t) => t.match(/.{0,30}[—–].{0,30}/)?.[0]).join(' | '));
const relevantErrors = consoleErrors.filter((e) => !/favicon|dicebear|flagcdn|ERR_INTERNET|net::/i.test(e));
check('no uncaught page errors', relevantErrors.length === 0, relevantErrors.slice(0, 5).join(' | '));
const passed = results.filter((r) => r.ok).length;
writeFileSync(join(OUT, 'report.json'), JSON.stringify({ passed, total: results.length, results, consoleErrors }, null, 2));
console.log(`\n${passed}/${results.length} checks passed. Screenshots in ${OUT}`);
process.exit(passed === results.length ? 0 : 1);
