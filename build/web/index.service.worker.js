const PREFIX='escrow-app-v3-';
const CACHE=PREFIX+"788180190d1040d7a7f9";
const FILES=["index.html","index.js","index.wasm","index.pck","index.audio.worklet.js","index.audio.position.worklet.js","index.manifest.json","index.144x144.png","index.180x180.png","index.512x512.png","cockpit-chakra.ttf","cockpit-plex.ttf"];
const DIGESTS={"index.html":"738d595124bcaba6706f1d7845750200b41690cfe0d051093583ef85369d8b04","index.js":"33c94cb3175f3333b82e2a3be5e8e86f77986f0aa2042b1631f6367a4e5bb6ba","index.wasm":"fc74679e3b97f76878947fcd4fbe1268cbfa6188182a2e33bbc3f5dc9bfa57d0","index.pck":"b1d2863a9b63097d555f00d4d7e568ab1e3b5e46a19c11bbc3abe08b4c52047b","index.audio.worklet.js":"5b476a9c9ce642c0ee4256436d1bc31d9c38f868aca0f9a8e2a57c18d2dec2a3","index.audio.position.worklet.js":"be33985bc7160d6bf9646f259cd86b259cd67b02ccb297ee5c44f8ac84327bc8","index.manifest.json":"40203335fd30c712fce438bfe5e74b73e90707f4321c2155ca18a34101b24c92","index.144x144.png":"c37581e4a94bded8e6c4332f0a586103ec3786d804862d3fd72018acd94e38d7","index.180x180.png":"742662efe44d0f47edc404a8b6a9a7f4612c14de3e75c76e1aec87bd7c4156fc","index.512x512.png":"0d4d70dbeef4b34caf95613ab87305df158f8453543e319946f8f17ae40dbc33","cockpit-chakra.ttf":"65fbf76d95651697275e19db4d717c0e95a789ddd3476478b05292104db278a0","cockpit-plex.ttf":"3b031aa4216174205bd8471f88a49b91f093169e9e87bd5262242bc5967fe2e3"};
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
