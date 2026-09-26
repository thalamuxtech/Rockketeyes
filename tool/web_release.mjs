// Production web release with cache busting.
//
//   node tool/web_release.mjs            build + fingerprint
//   node tool/web_release.mjs --deploy   ...and deploy to Firebase Hosting
//
// Flutter's web output uses fixed file names (main.dart.js, assets/...), so a
// browser that cached them keeps running an old build. This script moves the
// code and assets under build-specific paths (long-cacheable), keeps the entry
// files (index.html, flutter_bootstrap.js) revalidated on every load, and
// replaces the deprecated service worker with one that clears old caches.
import { execSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, renameSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const web = join(root, 'build', 'web');
const flutter = process.platform === 'win32' ? 'C:/src/flutter/bin/flutter.bat' : 'flutter';
const run = (cmd) => execSync(cmd, { cwd: root, stdio: 'inherit' });

run(`"${existsSync(flutter) ? flutter : 'flutter'}" build web --release --no-wasm-dry-run --pwa-strategy=none`);

const main = readFileSync(join(web, 'main.dart.js'));
const hash = createHash('sha256').update(main).digest('hex').slice(0, 10);
const version = `v/${hash}/`;

// 1. Code: main.dart.js -> main.<hash>.dart.js
renameSync(join(web, 'main.dart.js'), join(web, `main.${hash}.dart.js`));
for (const ext of ['main.dart.js.map']) {
  if (existsSync(join(web, ext))) rmSync(join(web, ext));
}

// 2. Assets: assets/ -> v/<hash>/assets/
mkdirSync(join(web, 'v', hash), { recursive: true });
renameSync(join(web, 'assets'), join(web, 'v', hash, 'assets'));

// 3. Bootstrap: point at the fingerprinted code and asset base.
const bootPath = join(web, 'flutter_bootstrap.js');
let boot = readFileSync(bootPath, 'utf8');
if (!boot.includes('"mainJsPath":"main.dart.js"')) throw new Error('unexpected flutter_bootstrap.js format');
boot = boot.replace('"mainJsPath":"main.dart.js"', `"mainJsPath":"main.${hash}.dart.js"`);
boot = boot.replace(/_flutter\.loader\.load\(\s*\{?[\s\S]*?\}?\s*\);\s*$/, `_flutter.loader.load({ config: { assetBase: "${version}" } });\n`);
writeFileSync(bootPath, boot);

// 4. index.html references the splash font from assets.
const indexPath = join(web, 'index.html');
let index = readFileSync(indexPath, 'utf8');
index = index.replaceAll('assets/assets/fonts/', `${version}assets/assets/fonts/`);
index = index.replace('<script src="flutter_bootstrap.js" async></script>', `<script src="flutter_bootstrap.js?v=${hash}" async></script>`);
writeFileSync(indexPath, index);

// 5. Retire the old offline service worker for returning visitors.
writeFileSync(join(web, 'flutter_service_worker.js'), `// Clears caches from earlier builds, then gets out of the way.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    for (const key of await caches.keys()) await caches.delete(key);
    await self.registration.unregister();
    for (const client of await self.clients.matchAll({ type: 'window' })) client.navigate(client.url);
  })());
});
`);

writeFileSync(join(web, 'version.txt'), `${hash}\n`);
console.log(`Fingerprinted web build ${hash}`);

if (process.argv.includes('--deploy')) {
  const account = process.env.FIREBASE_ACCOUNT ? ` --account ${process.env.FIREBASE_ACCOUNT}` : '';
  run(`firebase deploy --only hosting --project rockketeyes${account}`);
}
