// Spike checker: talks to the running cefsimple over the DevTools protocol.
// Usage: node cdp_check.mjs <port> <outDir>
import { writeFileSync } from 'node:fs';

const port = process.argv[2] ?? '9333';
const outDir = process.argv[3] ?? '.';
const base = `http://127.0.0.1:${port}`;

function client(wsUrl) {
  const ws = new WebSocket(wsUrl);
  let id = 0;
  const pending = new Map();
  ws.onmessage = (ev) => {
    const msg = JSON.parse(ev.data);
    if (msg.id && pending.has(msg.id)) {
      pending.get(msg.id)(msg);
      pending.delete(msg.id);
    }
  };
  const ready = new Promise((r, j) => { ws.onopen = r; ws.onerror = j; });
  const send = (method, params = {}) =>
    new Promise((resolve) => {
      const i = ++id;
      pending.set(i, resolve);
      ws.send(JSON.stringify({ id: i, method, params }));
    });
  return { ready, send, close: () => ws.close() };
}

const evalIn = async (c, expression) => {
  const r = await c.send('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true });
  return r.result?.result?.value ?? r.result?.exceptionDetails?.text ?? r.error?.message;
};

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const targets = await (await fetch(`${base}/json/list`)).json();
const workers = targets.filter((t) => t.type === 'service_worker');
const ids = Object.fromEntries(workers.map((w) => {
  const id = new URL(w.url).host;
  return [w.url.includes('background/index.js') ? 'darkreader' : 'ubol', id];
}));
console.log('extension ids:', ids);

const page = targets.find((t) => t.type === 'page' && t.url.startsWith('http'));
const pc = client(page.webSocketDebuggerUrl);
await pc.ready;

// 1. Dark Reader content script effect on the page.
console.log('darkreader injected into page:', await evalIn(pc,
  `!!document.querySelector('style.darkreader') || document.documentElement.hasAttribute('data-darkreader-scheme') || document.documentElement.hasAttribute('data-darkreader-mode')`));

// 2. uBOL network blocking (declarativeNetRequest): ad script vs a normal resource.
const tryFetch = (u) => `fetch(${JSON.stringify(u)}, {mode:'no-cors'}).then(() => 'loaded').catch(e => 'blocked: ' + e.message)`;
console.log('ad request   :', await evalIn(pc, tryFetch('https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js')));
console.log('normal request:', await evalIn(pc, tryFetch('https://www.iana.org/favicon.ico')));

// Screenshot of the page (inside the browser, not the user's screen).
const shot = await pc.send('Page.captureScreenshot', { format: 'png' });
if (shot.result?.data) {
  writeFileSync(`${outDir}/page.png`, Buffer.from(shot.result.data, 'base64'));
  console.log('page screenshot saved');
}
pc.close();

// 3. Extension popups opened as tabs (there is no Chrome toolbar in this mode).
const version = await (await fetch(`${base}/json/version`)).json();
const bc = client(version.webSocketDebuggerUrl);
await bc.ready;
const popups = { darkreader: 'ui/popup/index.html', ubol: 'popup.html' };
for (const [name, path] of Object.entries(popups)) {
  if (!ids[name]) { console.log(`${name}: no id`); continue; }
  const url = `chrome-extension://${ids[name]}/${path}`;
  const created = await bc.send('Target.createTarget', { url });
  await sleep(3000);
  const list = await (await fetch(`${base}/json/list`)).json();
  const t = list.find((x) => x.id === created.result?.targetId);
  if (!t) { console.log(`${name} popup: target not created`, created.error ?? ''); continue; }
  const c = client(t.webSocketDebuggerUrl);
  await c.ready;
  const info = await evalIn(c, `JSON.stringify({title: document.title, bodyChars: document.body?.innerText.length ?? 0, hasChromeApi: typeof chrome?.runtime?.id})`);
  console.log(`${name} popup:`, info);
  const s = await c.send('Page.captureScreenshot', { format: 'png' });
  if (s.result?.data) writeFileSync(`${outDir}/${name}_popup.png`, Buffer.from(s.result.data, 'base64'));
  c.close();
}
bc.close();
process.exit(0);
