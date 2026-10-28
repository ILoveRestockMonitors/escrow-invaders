import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.join(path.dirname(fileURLToPath(import.meta.url)), 'build', 'web');
const port = Number(process.env.ESCROW_PORT || 9472);
const mime = { '.html': 'text/html; charset=utf-8', '.css': 'text/css; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.wasm': 'application/wasm', '.pck': 'application/octet-stream', '.png': 'image/png', '.svg': 'image/svg+xml', '.json': 'application/json', '.webmanifest': 'application/manifest+json', '.ogg': 'audio/ogg', '.ttf': 'font/ttf', '.txt': 'text/plain; charset=utf-8' };
// One shared save for every device on the private tailnet. Only enabled when systemd
// provides a writable StateDirectory (or ESCROW_STATE_DIR is set for tests).
const stateDir = process.env.ESCROW_STATE_DIR || process.env.STATE_DIRECTORY || '';
const SAVE_FILES = ['arcade-progress.json', 'response-journal.json', 'study-progress.json'];
const MAX_SAVE_BYTES = 32 * 1024 * 1024;
const HISTORY_KEEP = 40;
const json = (res, status, body) => { const text = JSON.stringify(body); res.writeHead(status, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', 'Content-Length': Buffer.byteLength(text), 'X-Content-Type-Options': 'nosniff', 'Cross-Origin-Resource-Policy': 'same-origin' }); res.end(text); };
// Progress is ordered by lifetime ship XP, then by recorded answers. Both only grow during play.
function saveScore(files) {
  let xp = 0, answers = 0;
  try { xp = Number(JSON.parse(files['arcade-progress.json'] || '{}').state?.total_xp) || 0; } catch {}
  try { answers = Object.keys(JSON.parse(files['response-journal.json'] || '{}').entries || {}).length; } catch {}
  return [xp, answers];
}
const better = (a, b) => a[0] !== b[0] ? a[0] > b[0] : a[1] > b[1];
function readSave() {
  try { return JSON.parse(fs.readFileSync(path.join(stateDir, 'save.json'), 'utf8')); }
  catch (error) { if (error.code === 'ENOENT') return { revision: 0, files: {} }; throw error; }
}
function writeSave(save) {
  const target = path.join(stateDir, 'save.json');
  fs.writeFileSync(target + '.tmp', JSON.stringify(save));
  fs.renameSync(target + '.tmp', target);
  const history = path.join(stateDir, 'history');
  fs.mkdirSync(history, { recursive: true });
  fs.copyFileSync(target, path.join(history, `save-${String(save.revision).padStart(8, '0')}.json`));
  const old = fs.readdirSync(history).filter(name => /^save-\d+\.json$/.test(name)).sort();
  for (const name of old.slice(0, Math.max(0, old.length - HISTORY_KEEP))) fs.rmSync(path.join(history, name));
}
function handleSave(req, res) {
  if (!stateDir) { json(res, 503, { error: 'Cloud save is not configured on this server.' }); return; }
  if (req.method === 'GET') {
    try { json(res, 200, readSave()); } catch { json(res, 500, { error: 'Stored save is unreadable.' }); }
    return;
  }
  if (req.method !== 'PUT') { res.writeHead(405); res.end(); return; }
  const chunks = []; let size = 0, aborted = false;
  req.on('data', chunk => { size += chunk.length; if (size > MAX_SAVE_BYTES && !aborted) { aborted = true; json(res, 413, { error: 'Save too large.' }); req.destroy(); } else if (!aborted) chunks.push(chunk); });
  req.on('end', () => {
    if (aborted) return;
    let body;
    try { body = JSON.parse(Buffer.concat(chunks).toString('utf8')); } catch { json(res, 400, { error: 'Invalid JSON.' }); return; }
    const files = body?.files;
    if (!Number.isInteger(body?.base_revision) || typeof files !== 'object' || files === null || Array.isArray(files)) { json(res, 400, { error: 'Missing base_revision or files.' }); return; }
    for (const [name, text] of Object.entries(files)) {
      if (!SAVE_FILES.includes(name) || typeof text !== 'string') { json(res, 400, { error: 'Unexpected save file.' }); return; }
      try { JSON.parse(text); } catch { json(res, 400, { error: `${name} is not valid JSON.` }); return; }
    }
    if (!files['arcade-progress.json']) { json(res, 400, { error: 'Ship progress is required.' }); return; }
    let current;
    try { current = readSave(); } catch { json(res, 500, { error: 'Stored save is unreadable.' }); return; }
    const score = saveScore(files);
    // A device that missed newer uploads may only replace them when it holds more progress.
    if (body.base_revision !== current.revision && !better(score, saveScore(current.files || {}))) { json(res, 409, current); return; }
    const next = { revision: current.revision + 1, updated_at: new Date().toISOString(), device_id: String(body.device_id || '').slice(0, 64), score, files };
    try { fs.mkdirSync(stateDir, { recursive: true }); writeSave(next); } catch { json(res, 500, { error: 'Could not store the save.' }); return; }
    json(res, 200, { revision: next.revision, updated_at: next.updated_at, score });
  });
}
const server = http.createServer((req, res) => {
  let pathname;
  try { pathname = decodeURIComponent(new URL(req.url, 'http://localhost').pathname); }
  catch { res.writeHead(400); res.end(); return; }
  if (pathname === '/api/save') { handleSave(req, res); return; }
  if (!['GET', 'HEAD'].includes(req.method)) { res.writeHead(405); res.end(); return; }
  if (pathname === '/health') { res.writeHead(200, { 'Content-Type': 'application/json' }); res.end(JSON.stringify({ app: 'escrow-invaders', version: '0.9.0', cloud_save: !!stateDir })); return; }
  if (pathname === '/pilot') { res.writeHead(302, { Location: '/pilot/' }); res.end(); return; }
  // Same-origin recovery entry bypasses an older root worker without clearing saves.
  const webPath = pathname.startsWith('/latest/') ? pathname.slice('/latest'.length) : pathname;
  const resolved = path.resolve(root, '.' + (webPath.endsWith('/') ? webPath + 'index.html' : webPath));
  if (!resolved.startsWith(root + path.sep)) { res.writeHead(403); res.end(); return; }
  if (!fs.existsSync(resolved) || !fs.statSync(resolved).isFile()) { res.writeHead(404); res.end('Not found'); return; }
  const encodings = String(req.headers['accept-encoding'] || '').split(',').map(part=>part.trim().split(';').map(value=>value.trim()));
  const gzip = encodings.find(parts=>parts[0]==='gzip') ?? encodings.find(parts=>parts[0]==='*');
  const quality = gzip?.find(value=>value.startsWith('q='));
  const compressed = !!gzip && (!quality || Number(quality.slice(2))>0) && fs.existsSync(resolved + '.gz');
  const selected = compressed ? resolved + '.gz' : resolved;
  const headers = { 'Content-Type': mime[path.extname(resolved)] || 'application/octet-stream', 'Content-Length': fs.statSync(selected).size, 'Cache-Control': 'no-cache', 'X-Content-Type-Options': 'nosniff', 'Cross-Origin-Opener-Policy': 'same-origin', 'Cross-Origin-Embedder-Policy': 'require-corp' };
  if (fs.existsSync(resolved + '.gz')) headers.Vary = 'Accept-Encoding';
  if (compressed) headers['Content-Encoding'] = 'gzip';
  res.writeHead(200, headers);
  if (req.method === 'HEAD') res.end(); else fs.createReadStream(selected).pipe(res);
});
server.on('error', error => { console.error(error.message); process.exitCode = 1; });
server.listen(port, '127.0.0.1', () => console.log(`Escrow Invaders: http://127.0.0.1:${server.address().port}/`));
