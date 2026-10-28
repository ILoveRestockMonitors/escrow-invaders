(() => {
 'use strict';
 const root=document.createElement('div');root.id='orbital-ui';root.hidden=true;root.setAttribute('aria-hidden','true');document.body.append(root);
 root.innerHTML=`<div class="orbit-logo"><svg viewBox="0 0 44 44"><path d="M22 3 40 13v18L22 41 4 31V13Z"/><path d="m12 22 10-9 10 9M16 20v11h12V20M22 23v8"/></svg><div><strong>ESCROW <b>INVADERS</b></strong><small>ORBITAL CLOSING DESK</small></div><span class="division">OD / 01</span></div>
 <div class="cockpit-hud"><div class="hud-cell level"><small>SECTOR</small><strong data-value="level">01</strong></div><div class="hud-cell rank"><small>SHIP RANK</small><strong data-value="rank">01</strong></div><div class="hud-cell hull"><small>HULL INTEGRITY <span data-value="hull"></span></small><div class="hull-pips"><i></i><i></i><i></i></div></div><div class="hud-cell xp"><div><small>SHIP EXPERIENCE</small><span data-value="xp"></span></div><div class="xp-track"><i></i></div></div><div class="hud-cell credit coins"><i class="coin-icon"></i><div><small>COINS</small><strong data-value="coins">0</strong></div></div><div class="hud-cell credit gems"><i class="gem-icon"></i><div><small>GEMS</small><strong data-value="gems">0</strong></div></div></div>`;
 const logo=root.querySelector('.orbit-logo'),hud=root.querySelector('.cockpit-hud');
 const ratio=document.createElement('div');ratio.className='answer-ratio';ratio.innerHTML='<span></span><div class="ratio-track"><i></i></div>';root.append(ratio);
 const frame=document.createElement('div');frame.className='arena-bezel';frame.innerHTML='<div class="frame-tags"><span class="sector-tag"></span><span class="flight-tag"></span></div><i class="corner tl"></i><i class="corner tr"></i><i class="corner bl"></i><i class="corner br"></i>';root.append(frame);
 const screen=document.createElement('div');screen.className='arena-screen';root.append(screen);
 const repulsor=document.createElement('div');repulsor.className='repulsor';repulsor.innerHTML='<span class="space-key">SPACE</span><div class="repulsor-name"><strong>REPULSOR</strong><small>DEFENSIVE PULSE</small></div><div class="charge-segments">'+Array.from({length:12},()=>'<i></i>').join('')+'</div><span class="charge-state"></span>';root.append(repulsor);
 const segments=[...repulsor.querySelectorAll('.charge-segments i')],pulseLabel=repulsor.querySelector('.charge-state');
 const desk=document.createElement('div');desk.className='desk-panel';root.append(desk);
 const seal=document.createElement('div');seal.className='document-seal';root.append(seal);
 const footer=document.createElement('div');footer.className='footer-rule';root.append(footer);
 const papers=document.createElement('div');papers.className='answer-papers';root.append(papers);
 const banner=document.createElement('div');banner.className='celebration-banner';banner.hidden=true;banner.innerHTML='<strong></strong><span></span>';root.append(banner);
 banner.addEventListener('animationend',()=>{banner.hidden=true;});
 const compact=new Intl.NumberFormat('en',{notation:'compact',maximumFractionDigits:1});
 const amount=n=>n>=10000?compact.format(n):n.toLocaleString();
 const tweens=new Map();
 const fields=Object.fromEntries([...root.querySelectorAll('[data-value]')].map(node=>[node.dataset.value,node]));
 const pips=[...root.querySelectorAll('.hull-pips i')],xpFill=root.querySelector('.xp-track i');
 let last=null;
 function place(node,rect,offset){
  if(!rect||rect.length!==4){node.hidden=true;return;}node.hidden=false;
  const value=[rect[0]+offset.left,rect[1]+offset.top,rect[2],rect[3]].map(n=>Math.round(n*10)/10);
  const key=value.join(',');if(node.dataset.rect===key)return;node.dataset.rect=key;
  Object.assign(node.style,{left:value[0]+'px',top:value[1]+'px',width:value[2]+'px',height:value[3]+'px'});
 }
 function text(node,value){if(node.textContent!==String(value))node.textContent=String(value);}
 function count(node,value,format,reduced){
  const tween=tweens.get(node);
  if(tween&&tween.target===value&&!reduced)return;
  if(tween){cancelAnimationFrame(tween.frame);tweens.delete(node);}
  const from=Number(node.dataset.displayValue??value);
  if(reduced||Math.abs(value-from)<2){node.dataset.displayValue=value;text(node,format(value));return;}
  const start=performance.now(),task={target:value,frame:0};tweens.set(node,task);
  const tick=now=>{const t=Math.min(1,(now-start)/220),current=Math.round(from+(value-from)*(1-Math.pow(1-t,3)));node.dataset.displayValue=current;text(node,format(current));if(t<1)task.frame=requestAnimationFrame(tick);else tweens.delete(node);};
  task.frame=requestAnimationFrame(tick);
 }
 function pulse(node,name){node.classList.remove(name);requestAnimationFrame(()=>node.classList.add(name));}
 function showBanner(title,detail,state){
  text(banner.querySelector('strong'),title);text(banner.querySelector('span'),detail);
  banner.style.top=(state.mobile?state.hud[1]+state.hud[3]+8:12)+'px';banner.hidden=false;pulse(banner,'show');
 }
 function celebrate(payload){
  papers.replaceChildren();pulse(seal,'seal-impact');
  const area=payload.area,offset=document.getElementById('game-frame').getBoundingClientRect();
  const gentle=payload.reduced,count=gentle?18:72,fragment=document.createDocumentFragment();
  const colors=['var(--lime)','var(--teal)','var(--amber)','var(--pink)','#aa96ff','var(--text)'];
  for(let index=0;index<count;index++){
   const paper=document.createElement('i'),side=index%2?1:-1;paper.className='paper'+(gentle?' gentle':'');
   const x=gentle?16+(area[2]-32)*index/(count-1):area[2]*(side<0?.17:.83);
   Object.assign(paper.style,{left:(offset.left+area[0]+x)+'px',top:(offset.top+area[1]+(gentle?15+(index%3)*7:Math.min(90,area[3]*.18)))+'px',width:(4+Math.random()*3)+'px',height:(8+Math.random()*5)+'px',background:colors[index%colors.length]});
   paper.style.setProperty('--dx',(-side*(40+Math.random()*150))+'px');paper.style.setProperty('--peak',(-60-Math.random()*90)+'px');paper.style.setProperty('--fall',(180+Math.random()*190)+'px');paper.style.setProperty('--spin',(Math.random()*500-250)+'deg');
   paper.addEventListener('animationend',()=>paper.remove(),{once:true});fragment.append(paper);
  }
  papers.append(fragment);
 }
 function update(state){
  root.hidden=false;root.dataset.phase=state.phase;root.dataset.width=state.width;root.dataset.height=state.height;root.dataset.fps=state.fps;root.dataset.panelOverflow=state.panelOverflow;
  root.classList.toggle('mobile',state.mobile);root.classList.toggle('short',state.height<500);root.classList.toggle('reduced',state.reduced);root.classList.toggle('paused',state.paused);
  root.style.visibility=state.help?'hidden':'visible';
  const offset=document.getElementById('game-frame').getBoundingClientRect();
  place(logo,state.logo,offset);place(hud,state.hud,offset);
  place(ratio,state.ratioRect,offset);
  const answered=state.right+state.wrong,accuracy=answered?state.right/answered*100:0;
  text(ratio.querySelector('span'),'RIGHT '+state.right+' : '+state.wrong+' WRONG / '+(answered?Math.round(accuracy)+'%':'NO ANSWERS'));
  ratio.querySelector('i').style.width=accuracy+'%';ratio.classList.toggle('empty',!answered);
  place(frame,state.frame,offset);place(screen,state.arena,offset);place(repulsor,state.pulseRect,offset);
  place(desk,state.side,offset);place(seal,state.sealRect,offset);text(seal,state.seal||'');
  place(footer,state.footer,offset);
  const reading=['core','bonus','boost','revive','feedback','boost_intro'].includes(state.phase);
  desk.classList.toggle('document',reading);seal.classList.toggle('cleared',state.seal==='CLEARED');seal.classList.toggle('retry',state.seal==='WRONG');
  seal.classList.toggle('funded',state.seal==='FUNDED');
  const docked=['ready','shop','hangar','study'].includes(state.phase);
  text(frame.querySelector('.sector-tag'),docked?'ORBIT / HANGAR 01':'SECTOR '+String(state.level).padStart(2,'0'));
  text(frame.querySelector('.flight-tag'),state.paused?'FLIGHT PAUSED':docked?'ALL SYSTEMS ONLINE':state.phase==='combat'?(state.mobile?state.remaining+' HOSTILES':'FLIGHT ACTIVE'):'IN ESCROW / DANGER PAUSED');
  frame.classList.toggle('flying',state.phase==='combat'&&!state.paused);
  repulsor.classList.toggle('ready',state.pulse.ready&&!state.paused);
  repulsor.classList.toggle('offline',state.paused);
  segments.forEach((segment,index)=>segment.classList.toggle('filled',state.pulse.charge>index/12));
  text(pulseLabel,state.paused?'PAUSED':state.pulse.ready?'READY':state.pulse.cooldown>0?state.pulse.cooldown.toFixed(1)+'s':'ARMING');
  if(last&&state.pulse.cooldown>last.pulse.cooldown+1)pulse(repulsor,'used');
  count(fields.level,state.level,n=>n<10?'0'+n:amount(n),state.reduced);count(fields.rank,state.rank,n=>n<10?'0'+n:amount(n),state.reduced);
  text(fields.hull,state.hull+'/3');count(fields.xp,state.xp,n=>amount(n)+' / '+amount(state.xpMax)+' XP',state.reduced||!last||last.rank!==state.rank);
  count(fields.coins,state.coins,amount,state.reduced);count(fields.gems,state.gems,amount,state.reduced);
  if(last){
   if(state.hull<last.hull){pulse(root.querySelector('.hull'),'damaged');pulse(screen,'damaged');}
   if(state.coins>last.coins)pulse(root.querySelector('.coins'),'gained');
   if(state.gems>last.gems)pulse(root.querySelector('.gems'),'gained');
   if(state.phase==='clear'&&last.phase!=='clear')showBanner(state.unlockTitle?'UNLOCKED':'FUNDED',state.unlockTitle||'SECTOR '+(state.level-1)+' CLEARED',state);
   else if(state.funded&&!last.funded)showBanner('FUNDED','STUDY REWARD SECURED',state);
   else if(state.evolution>last.evolution)showBanner('SHIP EVOLVED','NEW HULL / DAMAGE +6% / FIRE RATE +4%',state);
   else if(state.rank>last.rank)showBanner('RANK UP','SHIP RANK '+state.rank+' / FREE UPGRADE EARNED',state);
  }
  pips.forEach((pip,index)=>pip.classList.toggle('lost',index>=state.hull));
  xpFill.style.width=Math.max(0,Math.min(100,state.xp/state.xpMax*100))+'%';
  last=state;
 }
 window.orbitalUI={update,celebrate};
})();
