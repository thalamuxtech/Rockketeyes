// Rockketeyes brand generator: one logo definition, every asset.
//
//   node tool/brand/logo.mjs
//
// Writes brand/*.svg masters, renders PNG icons for web and Android with the
// e2e Playwright install, and injects the animated splash logo into
// web/index.html. The Flutter painter (lib/core/widgets/logo.dart) mirrors
// the same geometry, so every place the mark appears looks identical.
import { createRequire } from 'node:module';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const require = createRequire(join(root, 'e2e', 'package.json'));

// ---------- Geometry (512 × 512 design grid) ----------
export const G = {
  c: 256,
  orbitR: 214, orbitW: 3,
  irisR: 152, irisW: 46, gapDeg: 6,
  lensR: 126,
  pupilR: 66,
  cometDeg: -38, cometTailDeg: 78, cometR: 11,
};
export const INKS = ['#FF4D5E', '#FF9F1C', '#FFD93D', '#2EE59D', '#4D8DFF', '#B57BFF', '#FF6FCF', '#F5F5F7'];
const GOLD = { soft: '#FFE3A3', mid: '#F5B83D', deep: '#D9951E' };

const rad = (d) => (d * Math.PI) / 180;
const pt = (r, deg) => [G.c + r * Math.cos(rad(deg)), G.c + r * Math.sin(rad(deg))];
const f = (n) => n.toFixed(2);

function arcPath(r, a0, a1) {
  const [x0, y0] = pt(r, a0);
  const [x1, y1] = pt(r, a1);
  const large = a1 - a0 > 180 ? 1 : 0;
  return `M${f(x0)} ${f(y0)} A${r} ${r} 0 ${large} 1 ${f(x1)} ${f(y1)}`;
}

/**
 * The mark as SVG. Options:
 *  background: 'none' | 'squircle' | 'full'  (app icons need a backdrop)
 *  scale: size of the mark inside the canvas (1 = fills the 512 grid)
 *  animated: adds CSS classes/keyframes used by the web splash
 */
export function logoSvg({ background = 'none', scale = 1, animated = false, id = 're', mark = true } = {}) {
  const seg = 360 / INKS.length;
  const iris = INKS.map((color, i) => {
    const a0 = -90 + i * seg + G.gapDeg / 2;
    const a1 = -90 + (i + 1) * seg - G.gapDeg / 2;
    return `<path d="${arcPath(G.irisR, a0, a1)}" stroke="${color}" stroke-width="${G.irisW}" fill="none"/>`;
  }).join('');

  const head = pt(G.orbitR, G.cometDeg);
  const tail = pt(G.orbitR, G.cometDeg - G.cometTailDeg);
  const bg = background === 'none' ? '' : `
    <defs>
      <radialGradient id="${id}-bg" cx="50%" cy="30%" r="80%">
        <stop offset="0" stop-color="#2A2056"/><stop offset=".55" stop-color="#120E26"/><stop offset="1" stop-color="#07060F"/>
      </radialGradient>
    </defs>
    ${background === 'squircle'
      ? `<rect x="16" y="16" width="480" height="480" rx="112" fill="url(#${id}-bg)"/>
         <rect x="16.75" y="16.75" width="478.5" height="478.5" rx="111.25" fill="none" stroke="#ffffff" stroke-opacity=".08" stroke-width="1.5"/>`
      : `<rect width="512" height="512" fill="url(#${id}-bg)"/>`}`;

  const t = `translate(256 256) scale(${scale}) translate(-256 -256)`;
  const css = animated ? `
    <style>
      .${id}-spin { transform-origin: 256px 256px; animation: ${id}-spin 24s linear infinite; }
      .${id}-orbit { transform-origin: 256px 256px; animation: ${id}-spin 2.4s cubic-bezier(.45,.05,.55,.95) infinite; }
      .${id}-pupil { transform-origin: 256px 256px; animation: ${id}-breathe 2.4s ease-in-out infinite; }
      .${id}-glow { animation: ${id}-glow 2.4s ease-in-out infinite; }
      @keyframes ${id}-spin { to { transform: rotate(360deg); } }
      @keyframes ${id}-breathe { 0%,100% { transform: scale(1); } 50% { transform: scale(1.06); } }
      @keyframes ${id}-glow { 0%,100% { opacity: .55; } 50% { opacity: 1; } }
    </style>` : '';

  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512">
  ${css}${bg}
  <defs>
    <radialGradient id="${id}-halo" cx="50%" cy="50%" r="50%">
      <stop offset=".55" stop-color="#7C5CFF" stop-opacity=".38"/><stop offset="1" stop-color="#7C5CFF" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="${id}-shade" gradientUnits="userSpaceOnUse" cx="256" cy="256" r="${G.irisR + G.irisW / 2}">
      <stop offset="${f((G.irisR - G.irisW / 2) / (G.irisR + G.irisW / 2))}" stop-color="#000" stop-opacity=".42"/>
      <stop offset="${f((G.irisR - 6) / (G.irisR + G.irisW / 2))}" stop-color="#000" stop-opacity="0"/>
      <stop offset=".9" stop-color="#fff" stop-opacity=".10"/>
      <stop offset="1" stop-color="#000" stop-opacity=".30"/>
    </radialGradient>
    <radialGradient id="${id}-lens" cx="42%" cy="36%" r="70%">
      <stop offset="0" stop-color="#241D45"/><stop offset=".7" stop-color="#0C0A1A"/><stop offset="1" stop-color="#07060F"/>
    </radialGradient>
    <radialGradient id="${id}-pupil" cx="38%" cy="34%" r="72%">
      <stop offset="0" stop-color="${GOLD.soft}"/><stop offset=".5" stop-color="${GOLD.mid}"/><stop offset="1" stop-color="${GOLD.deep}"/>
    </radialGradient>
    <linearGradient id="${id}-tail" gradientUnits="userSpaceOnUse" x1="${f(tail[0])}" y1="${f(tail[1])}" x2="${f(head[0])}" y2="${f(head[1])}">
      <stop offset="0" stop-color="${GOLD.mid}" stop-opacity="0"/><stop offset=".75" stop-color="${GOLD.mid}" stop-opacity=".85"/><stop offset="1" stop-color="#FFF6DD"/>
    </linearGradient>
    <radialGradient id="${id}-head" cx="50%" cy="50%" r="50%">
      <stop offset="0" stop-color="#FFFFFF"/><stop offset=".45" stop-color="#FFF1C9"/><stop offset="1" stop-color="${GOLD.mid}" stop-opacity="0"/>
    </radialGradient>
  </defs>
  ${mark ? '' : '<!--'}<g transform="${t}">
    <circle class="${animated ? id + '-glow' : ''}" cx="256" cy="256" r="236" fill="url(#${id}-halo)"/>
    <circle cx="256" cy="256" r="${G.orbitR}" fill="none" stroke="#FFFFFF" stroke-opacity=".10" stroke-width="${G.orbitW}"/>
    <circle cx="256" cy="256" r="${G.irisR}" fill="none" stroke="#0C0A1A" stroke-width="${G.irisW + 4}"/>
    <g class="${animated ? id + '-spin' : ''}">${iris}
      <circle cx="256" cy="256" r="${G.irisR}" fill="none" stroke="url(#${id}-shade)" stroke-width="${G.irisW}"/>
    </g>
    <circle cx="256" cy="256" r="${G.lensR}" fill="url(#${id}-lens)"/>
    <circle cx="256" cy="256" r="${G.lensR - 0.75}" fill="none" stroke="#FFFFFF" stroke-opacity=".14" stroke-width="1.5"/>
    <g class="${animated ? id + '-pupil' : ''}">
      <circle cx="256" cy="256" r="${G.pupilR + 14}" fill="${GOLD.mid}" fill-opacity=".16"/>
      <circle cx="256" cy="256" r="${G.pupilR}" fill="url(#${id}-pupil)"/>
      <ellipse cx="${256 - 22}" cy="${256 - 25}" rx="17" ry="13" fill="#FFFFFF" fill-opacity=".92" transform="rotate(-30 ${256 - 22} ${256 - 25})"/>
      <circle cx="${256 + 20}" cy="${256 + 22}" r="5" fill="#FFFFFF" fill-opacity=".45"/>
    </g>
    <g class="${animated ? id + '-orbit' : ''}">
      <path d="${arcPath(G.orbitR, G.cometDeg - G.cometTailDeg, G.cometDeg)}" stroke="url(#${id}-tail)" stroke-width="7" stroke-linecap="round" fill="none"/>
      <circle cx="${f(head[0])}" cy="${f(head[1])}" r="${G.cometR * 2.2}" fill="url(#${id}-head)"/>
      <circle cx="${f(head[0])}" cy="${f(head[1])}" r="${G.cometR * 0.62}" fill="#FFFFFF"/>
    </g>
  </g>${mark ? '' : '-->'}
</svg>`;
}

// ---------- Render ----------
async function render() {
  const { chromium } = require('playwright');
  const browser = await chromium.launch({ channel: 'chrome', headless: true });
  const page = await browser.newPage();

  async function png(svg, size, out) {
    await page.setViewportSize({ width: size, height: size });
    await page.setContent(`<html><body style="margin:0;background:transparent">
      <div id="c" style="width:${size}px;height:${size}px">${svg.replace('width="512" height="512"', `width="${size}" height="${size}"`)}</div>
      </body></html>`);
    mkdirSync(dirname(out), { recursive: true });
    await page.locator('#c').screenshot({ path: out, omitBackground: true });
  }

  const p = (...x) => join(root, ...x);

  // Masters.
  mkdirSync(p('brand'), { recursive: true });
  writeFileSync(p('brand', 'logo.svg'), logoSvg());
  writeFileSync(p('brand', 'icon.svg'), logoSvg({ background: 'squircle', scale: 0.8, id: 'ic' }));
  writeFileSync(p('brand', 'logo-animated.svg'), logoSvg({ animated: true }));

  // Web.
  const webIcon = logoSvg({ background: 'squircle', scale: 0.8, id: 'w' });
  const maskable = logoSvg({ background: 'full', scale: 0.72, id: 'm' });
  // Favicon: the bare mark (no tile) so it stays legible at tab size.
  const favicon = logoSvg({ scale: 1.08, id: 'fav' });
  writeFileSync(p('web', 'favicon.svg'), favicon);
  await png(favicon, 64, p('web', 'favicon.png'));
  await png(webIcon, 192, p('web', 'icons', 'Icon-192.png'));
  await png(webIcon, 512, p('web', 'icons', 'Icon-512.png'));
  await png(maskable, 192, p('web', 'icons', 'Icon-maskable-192.png'));
  await png(maskable, 512, p('web', 'icons', 'Icon-maskable-512.png'));

  // Google Play listing icon (512, full square; Play applies its own mask).
  await png(logoSvg({ background: 'full', scale: 0.78, id: 'ps' }), 512, p('brand', 'play-store-icon-512.png'));

  // Android launcher: legacy square icon + adaptive (foreground/background).
  const dens = { mdpi: 1, hdpi: 1.5, xhdpi: 2, xxhdpi: 3, xxxhdpi: 4 };
  const res = (...x) => p('android', 'app', 'src', 'main', 'res', ...x);
  for (const [d, k] of Object.entries(dens)) {
    await png(logoSvg({ background: 'squircle', scale: 0.86, id: 'l' }), 48 * k, res(`mipmap-${d}`, 'ic_launcher.png'));
    // Adaptive foreground: 108dp canvas, mark kept inside the 66dp safe zone.
    await png(logoSvg({ scale: 0.7, id: 'fg' }), 108 * k, res(`mipmap-${d}`, 'ic_launcher_foreground.png'));
    await png(logoSvg({ background: 'full', mark: false, id: 'bgl' }), 108 * k, res(`mipmap-${d}`, 'ic_launcher_background.png'));
    // Launch splash logo (Android < 12 layer-list and Android 12+ splash icon).
    await png(logoSvg({ scale: 0.62, id: 'sp' }), 160 * k, res(`drawable-${d}`, 'splash_logo.png'));
  }
  await browser.close();

  // Inject the animated mark into the web loading splash.
  const indexPath = p('web', 'index.html');
  const html = readFileSync(indexPath, 'utf8');
  const start = '<!--LOGO-START-->';
  const end = '<!--LOGO-END-->';
  if (html.includes(start)) {
    const svg = logoSvg({ animated: true, id: 'sl' }).replace('width="512" height="512"', 'width="148" height="148" class="re-logo" aria-hidden="true"');
    const next = html.slice(0, html.indexOf(start) + start.length) + '\n    ' + svg + '\n    ' + html.slice(html.indexOf(end));
    writeFileSync(indexPath, next);
  }
  console.log('Brand assets written.');
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  await render();
}
