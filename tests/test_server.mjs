import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { spawn } from 'node:child_process';
import { gzipSync } from 'node:zlib';
const root=fs.mkdtempSync(path.join(os.tmpdir(),'escrow-server-audit-'));
let server,checks=0;
const eq=(a,b,label)=>{assert.deepEqual(a,b,label);checks++;};
try{
  fs.copyFileSync(new URL('../server.mjs',import.meta.url),path.join(root,'server.mjs'));
  const web=path.join(root,'build/web');fs.mkdirSync(path.join(web,'pilot/assets'),{recursive:true});
  for(const [file,data] of [['index.html','GODOT'],['pilot/index.html','PILOT'],['pilot/assets/main.css','body{color:red}'],['pilot/assets/main.js','export const game=true;']]){
    const target=path.join(web,file);fs.writeFileSync(target,data);fs.writeFileSync(target+'.gz',gzipSync(data));
  }
  const stateDir=path.join(root,'state');
  server=spawn(process.execPath,[path.join(root,'server.mjs')],{env:{...process.env,ESCROW_PORT:'0',ESCROW_STATE_DIR:stateDir},windowsHide:true,stdio:['ignore','pipe','pipe']});
  const base=await new Promise((resolve,reject)=>{
    const timeout=setTimeout(()=>reject(new Error('Server start timed out')),5000);
    server.once('error',reject);server.stdout.on('data',chunk=>{const match=chunk.toString().match(/http:\/\/127\.0\.0\.1:\d+\//);if(match){clearTimeout(timeout);resolve(match[0]);}});
  });
  let response=await fetch(base);eq(await response.text(),'GODOT','root serves production entry');
  response=await fetch(base+'latest/');eq(await response.text(),'GODOT','same-origin recovery serves the current game');
  response=await fetch(base+'pilot/');eq(await response.text(),'PILOT','directory serves pilot entry');
  response=await fetch(base+'pilot',{redirect:'manual'});eq(response.status,302,'canonical pilot directory redirect');eq(response.headers.get('location'),'/pilot/','relative private-origin redirect');
  response=await fetch(base+'pilot/assets/main.css');eq(response.headers.get('content-type'),'text/css; charset=utf-8','CSS served with nosniff-compatible type');eq(await response.text(),'body{color:red}','nested stylesheet intact');
  response=await fetch(base+'pilot/assets/main.js',{headers:{'accept-encoding':'gzip;q=0, *;q=1'}});eq(response.headers.get('content-encoding'),null,'explicit gzip refusal beats wildcard');eq(response.headers.get('vary'),'Accept-Encoding','identity representation varies too');
  response=await fetch(base+'pilot/assets/main.js',{headers:{'accept-encoding':'gzip;q=0.5'}});eq(response.headers.get('content-encoding'),'gzip','accepted gzip used');eq(await response.text(),'export const game=true;','compressed script decodes exactly');
  response=await fetch(base+'pilot/assets/main.css',{method:'HEAD'});eq(response.status,200,'HEAD status');eq(await response.text(),'','HEAD has no body');
  response=await fetch(base+'health');eq((await response.json()).version,'0.9.0','health matches release');
  eq((await fetch(base+'missing')).status,404,'missing route');
  eq((await fetch(base+'%',{redirect:'manual'})).status,400,'bad URL encoding rejected');
  eq((await fetch(base+'%2e%2e%5cserver.mjs')).status,403,'encoded Windows parent traversal rejected');
  eq((await fetch(base,{method:'POST'})).status,405,'read-only server rejects writes');
  // Shared cloud save.
  const save=(xp,answers,extra={})=>({'arcade-progress.json':JSON.stringify({version:1,state:{total_xp:xp}}),'response-journal.json':JSON.stringify({version:1,entries:Object.fromEntries(Array.from({length:answers},(_,i)=>['a'+i,{}]))}),...extra});
  const put=body=>fetch(base+'api/save',{method:'PUT',headers:{'content-type':'application/json'},body:JSON.stringify(body)});
  response=await fetch(base+'api/save');eq(response.status,200,'empty save readable');eq((await response.json()).revision,0,'empty save starts at revision 0');
  response=await put({base_revision:0,device_id:'phone',files:save(10,1)});eq(response.status,200,'first upload accepted');eq((await response.json()).revision,1,'first upload is revision 1');
  response=await put({base_revision:0,device_id:'pc',files:save(9000,400)});eq(response.status,200,'never-synced device with more progress replaces a smaller save');eq((await response.json()).revision,2,'revision advances');
  response=await put({base_revision:0,device_id:'mac',files:save(20,2)});eq(response.status,409,'stale device with less progress is refused');let body=await response.json();eq(body.revision,2,'conflict returns the current save');eq(body.device_id,'pc','conflict carries the better save');
  response=await put({base_revision:2,device_id:'mac',files:save(9000,400)});eq(response.status,200,'up-to-date device may save even without gaining progress');
  response=await put({base_revision:2,device_id:'pc',files:save(9000,400)});eq(response.status,409,'equal progress from an outdated revision is refused');
  response=await put({base_revision:3,device_id:'pc',files:{'arcade-progress.json':'{oops'}});eq(response.status,400,'invalid JSON file rejected');
  response=await put({base_revision:3,device_id:'pc',files:{'../evil.json':'{}','arcade-progress.json':'{}'}});eq(response.status,400,'unexpected file name rejected');
  response=await put({base_revision:3,device_id:'pc',files:{'study-progress.json':'{}'}});eq(response.status,400,'ship progress required');
  response=await fetch(base+'api/save');body=await response.json();eq(body.revision,3,'stored revision persists');eq(JSON.parse(body.files['arcade-progress.json']).state.total_xp,9000,'stored files round-trip');
  eq(fs.readdirSync(path.join(stateDir,'history')).length,3,'every accepted revision is kept in history');
  eq((await fetch(base+'api/save',{method:'DELETE'})).status,405,'save cannot be deleted over HTTP');
  console.log(`PASS: ${checks} HTTP delivery checks`);
}finally{
  if(server){server.kill();await new Promise(resolve=>server.once('exit',resolve));}
  const resolved=path.resolve(root);
  assert.equal(path.dirname(resolved),path.resolve(os.tmpdir()));assert.ok(path.basename(resolved).startsWith('escrow-server-audit-'));
  fs.rmSync(resolved,{recursive:true,force:true});
}
