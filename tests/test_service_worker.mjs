// Exercise the generated worker with real WebCrypto and isolated in-memory caches.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import vm from 'node:vm';
import {webcrypto} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const temporary=fs.mkdtempSync(path.join(os.tmpdir(),'escrow-worker-'));
const origin='https://escrow.test';
const names=['index.html','index.js','index.wasm','index.pck','index.audio.worklet.js','index.audio.position.worklet.js','index.manifest.json','index.144x144.png','index.180x180.png','index.512x512.png','cockpit-chakra.ttf','cockpit-plex.ttf'];
const oldCache='escrow-app-v2-previous-release';
let checks=0;
function check(value,message) {assert.ok(value,message);checks++;}
function equal(actual,expected,message) {assert.deepEqual(actual,expected,message);checks++;}

try {
 for(const name of names) fs.writeFileSync(path.join(temporary,name),name==='index.manifest.json'?'{}':Buffer.from(`${name}\u0000release A\u00ff`));
 const finalizer=fileURLToPath(new URL('../web/finalize.mjs',import.meta.url));
 execFileSync(process.execPath,[finalizer,temporary],{stdio:'pipe'});
 const worker=fs.readFileSync(path.join(temporary,'index.service.worker.js'),'utf8');
 const assets=new Map(names.map(name=>[`${origin}/${name}`,fs.readFileSync(path.join(temporary,name))]));
 const manifest=JSON.parse(assets.get(`${origin}/index.manifest.json`).toString());
 equal([manifest.id,manifest.scope,manifest.start_url,manifest.display],['/','/','/','standalone'],'stable app identity survives export');

 function harness(fault={}) {
  const stores=new Map([[oldCache,new Map([[`${origin}/index.html`,new Response('previous release')]])],['unrelated-app',new Map()]]);
  const handlers={},requests=[],deleted=[];
  let claims=0,skips=0;
  const caches={
   has:async name=>stores.has(name),
   keys:async()=>[...stores.keys()],
   delete:async name=>{deleted.push(name);return stores.delete(name);},
   open:async name=>{
    if(!stores.has(name))stores.set(name,new Map());
    const entries=stores.get(name);
    return {
     put:async(request,response)=>entries.set(typeof request==='string'?request:request.url,response.clone()),
     match:async request=>entries.get(typeof request==='string'?request:request.url)?.clone()
    };
   }
  };
  const self={registration:{scope:`${origin}/`},location:{origin},addEventListener:(event,handler)=>{handlers[event]=handler;},skipWaiting:()=>{skips++;},clients:{claim:()=>{claims++;}}};
  vm.runInNewContext(worker,{self,caches,crypto:webcrypto,Request,Response,URL,Uint8Array,fetch:async request=>{
   requests.push({url:request.url,cache:request.cache});
   const name=new URL(request.url).pathname.slice(1);
   if(fault.network===name)throw new TypeError('Network disconnected');
   if(fault.http===name)return new Response('Unavailable',{status:503});
   const bytes=fault.corrupt===name?Buffer.from('another release'):assets.get(request.url);
   assert.ok(bytes,`unexpected URL: ${request.url}`);
   return new Response(bytes,{headers:{'Content-Type':'application/octet-stream','Content-Encoding':'gzip'}});
  }});
  async function event(name) {
   let work;
   handlers[name]({waitUntil:value=>{work=value;}});
   assert.ok(work,`${name} did not hold the worker alive`);
   await work;
  }
  async function cachedNavigation(pathname='/') {
   let response;
   handlers.fetch({request:{url:`${origin}${pathname}`,method:'GET',mode:'navigate'},respondWith:value=>{response=value;}});
   return await response;
  }
  return {stores,requests,deleted,event,cachedNavigation,counts:()=>({claims,skips})};
 }

 const success=harness();
 await success.event('install');
 const candidate=[...success.stores.keys()].find(name=>name.startsWith('escrow-app-v3-'));
 check(candidate,'installation creates a new content-derived cache');
 equal(success.stores.get(candidate).size,names.length+1,'complete release and completion marker are cached');
 equal(await success.stores.get(candidate).get(`${origin}/__escrow_release_verified__`).clone().text(),candidate,'completion marker identifies the fully verified release');
 for(const [url,bytes] of assets) {
  equal(Buffer.from(await success.stores.get(candidate).get(url).clone().arrayBuffer()),bytes,`cached bytes match ${url}`);
 }
 equal(success.requests.length,names.length,'every asset is fetched and verified');
 check(success.requests.every(request=>request.cache==='reload'),'HTTP cache cannot supply stale installation bytes');
 check(success.stores.has(oldCache),'previous release stays available while new worker waits');
 equal(success.counts(),{claims:0,skips:0},'installation never forces control or activation');
 equal(await (await success.cachedNavigation()).text(),assets.get(`${origin}/index.html`).toString(),'navigation serves one verified release');
 equal(await (await success.cachedNavigation('/index.html?online=1')).text(),assets.get(`${origin}/index.html`).toString(),'explicit game entry stays cached with query string');
 equal(await success.cachedNavigation('/pilot/'),undefined,'pilot navigation bypasses the Godot cache');
 equal(await success.cachedNavigation('/pilot/index.html'),undefined,'pilot explicit entry bypasses the Godot cache');
 equal(await success.cachedNavigation('/other-page'),undefined,'unrelated navigation bypasses the Godot cache');
 equal(await success.cachedNavigation('/latest/'),undefined,'same-origin current-game recovery bypasses the older root cache');
 await success.event('activate');
 check(!success.stores.has(oldCache),'activation retires old game release cache');
 check(success.stores.has('unrelated-app'),'activation preserves unrelated caches');
 check(success.stores.has(candidate),'activation retains current complete cache');
 equal(success.counts(),{claims:0,skips:0},'activation does not claim a running game window');

 for(const fault of [{corrupt:'index.pck'},{network:'index.wasm'},{http:'index.js'}]) {
  const broken=harness(fault);
  await assert.rejects(broken.event('install'),/checksum mismatch|Network disconnected|Release download failed/);checks++;
  check(![...broken.stores.keys()].some(name=>name.startsWith('escrow-app-v3-')),'failed install deletes incomplete candidate');
  equal(await broken.stores.get(oldCache).get(`${origin}/index.html`).clone().text(),'previous release','failed install leaves old release untouched');
  check(broken.stores.has('unrelated-app'),'failed install preserves unrelated cache');
  equal(broken.counts(),{claims:0,skips:0},'failed install cannot force replacement');
 }

 // Reinstalling the identical release must never delete a cache a current worker
 // may be using, even if the new worker's network download later fails.
 const existing=harness({corrupt:'index.pck'});
 existing.stores.set(candidate,new Map([...assets].map(([url,bytes])=>[url,new Response(bytes)])));
 existing.stores.get(candidate).set(`${origin}/__escrow_release_verified__`,new Response(candidate));
 await assert.rejects(existing.event('install'),/checksum mismatch/);checks++;
 check(existing.stores.has(candidate),'failed same-release install retains complete active cache');
 for(const [url,bytes] of assets) {
  equal(Buffer.from(await existing.stores.get(candidate).get(url).clone().arrayBuffer()),bytes,`existing cache remains valid at ${url}`);
 }
 const interrupted=harness({network:'index.wasm'});
 interrupted.stores.set(candidate,new Map([[`${origin}/index.html`,new Response(assets.get(`${origin}/index.html`))]]));
 await assert.rejects(interrupted.event('install'),/Network disconnected/);checks++;
 check(!interrupted.stores.has(candidate),'failed restart deletes an incomplete cache from an interrupted install');
 check(interrupted.stores.has(oldCache),'interrupted candidate never replaces previous release');
 console.log(`PASS: ${checks} service-worker release checks`);
} finally {
 const resolved=path.resolve(temporary);
 assert.ok(resolved.startsWith(path.resolve(os.tmpdir())+path.sep)&&path.basename(resolved).startsWith('escrow-worker-'),'cleanup target must be the exact test temporary directory');
 fs.rmSync(resolved,{recursive:true,force:true});
}
