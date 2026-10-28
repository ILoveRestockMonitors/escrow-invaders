// Finalize Godot's web export as one versioned, installable app release.
import fs from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
const root = process.argv[2];
const source=path.dirname(fileURLToPath(import.meta.url));
const htmlPath=path.join(root,'index.html');
let html=fs.readFileSync(htmlPath,'utf8');
html=html.replace('<!--ORBITAL_CSS-->','<style>'+fs.readFileSync(path.join(source,'cockpit.css'),'utf8')+'</style>');
html=html.replace('<!--ORBITAL_JS-->','<script>'+fs.readFileSync(path.join(source,'cockpit.js'),'utf8')+'</script>');
fs.writeFileSync(htmlPath,html);
for(const [from,to] of [['ChakraPetch-Bold.ttf','cockpit-chakra.ttf'],['IBMPlexSans.ttf','cockpit-plex.ttf'],['ChakraPetch-OFL.txt','ChakraPetch-OFL.txt'],['IBMPlexSans-OFL.txt','IBMPlexSans-OFL.txt']])fs.copyFileSync(path.join(source,'../assets/fonts',from),path.join(root,to));
const manifestPath = path.join(root,'index.manifest.json');
const manifest = JSON.parse(fs.readFileSync(manifestPath,'utf8'));
Object.assign(manifest,{id:'/',start_url:'/',scope:'/',short_name:'Escrow',theme_color:'#080e1d',display:'standalone'});
fs.writeFileSync(manifestPath,JSON.stringify(manifest));
const files = ['index.html','index.js','index.wasm','index.pck','index.audio.worklet.js','index.audio.position.worklet.js','index.manifest.json','index.144x144.png','index.180x180.png','index.512x512.png','cockpit-chakra.ttf','cockpit-plex.ttf'];
const release = createHash('sha256');
const digests = {};
for(const file of files) {
 const bytes=fs.readFileSync(path.join(root,file));
 digests[file]=createHash('sha256').update(bytes).digest('hex');
 release.update(bytes);
}
// A worker activates only after its complete release is cached and all old app
// windows close. No forced reload during questions, and learner IndexedDB is untouched.
const worker = `const PREFIX='escrow-app-v3-';
const CACHE=PREFIX+${JSON.stringify(release.digest('hex').slice(0,20))};
const FILES=${JSON.stringify(files)};
const DIGESTS=${JSON.stringify(digests)};
const URLS=FILES.map(f=>new URL(f,self.registration.scope).href);
const READY=new URL('__escrow_release_verified__',self.registration.scope).href;
self.addEventListener('install',event=>event.waitUntil((async()=>{
 const cache=await caches.open(CACHE);
 const marker=await cache.match(READY);
 const complete=marker&&(await marker.text())===CACHE;
 try {
  // Check decoded bytes, not transport gzip. A release switch during installation
  // must fail rather than mixing a new pack with an older engine or shell.
  for(let i=0;i<FILES.length;i++) {
   const request=new Request(URLS[i],{cache:'reload'});
   const response=await fetch(request);
   if(!response.ok) throw new Error('Release download failed: '+FILES[i]);
   const digest=await crypto.subtle.digest('SHA-256',await response.clone().arrayBuffer());
   const hex=Array.from(new Uint8Array(digest),b=>b.toString(16).padStart(2,'0')).join('');
   if(hex!==DIGESTS[FILES[i]]) throw new Error('Release checksum mismatch: '+FILES[i]);
   await cache.put(request,response);
  }
  await cache.put(READY,new Response(CACHE));
 } catch(error) {
  // An already complete cache can be in use by an older worker with identical
  // assets. Every write above was verified, so retain that existing release.
  if(!complete) await caches.delete(CACHE);
  throw error;
 }
})()));
self.addEventListener('activate',event=>event.waitUntil((async()=>{
 for(const name of await caches.keys()) {
  if((name.startsWith('escrow-app-v')||name.startsWith('Escrow Invaders-sw-cache-'))&&name!==CACHE) await caches.delete(name);
 }
})()));
self.addEventListener('fetch',event=>{
 const url=new URL(event.request.url);
 if(event.request.method!=='GET'||url.origin!==self.location.origin)return;
 const navigation=event.request.mode==='navigate';
 const scopePath=new URL(self.registration.scope).pathname;
 // The root game worker must not turn a separate pilot or sibling page into Godot.
 if(navigation&&url.pathname!==scopePath&&url.pathname!==scopePath+'index.html')return;
 if(!navigation&&!URLS.includes(url.href))return;
 event.respondWith((async()=>{
  const cache=await caches.open(CACHE);
  const response=await cache.match(navigation?URLS[0]:url.href);
  // Never substitute an asset from a different release into a cached engine.
  return response||new Response('Please close the app and reopen with Tailscale connected.',{status:503,headers:{'Content-Type':'text/plain'}});
 })());
});
`;
fs.writeFileSync(path.join(root,'index.service.worker.js'),worker);
console.log('Installable release finalized:',files.length,'cached files');
