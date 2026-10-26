'use strict';
/* ---- Campaign screens -----------------------------------------------------------
   The campaign panel (missions, dry dock, workshop, logbook), the mission debrief,
   the cutscene player, the in-dive campaign HUD, and the campaign's controls. */
const el=(tag,cls,text)=>{const e=document.createElement(tag);if(cls)e.className=cls;if(text!==undefined)e.textContent=text;return e};
const icon=id=>{const s=document.createElementNS('http://www.w3.org/2000/svg','svg'),u=document.createElementNS('http://www.w3.org/2000/svg','use');s.setAttribute('class','ic');u.setAttribute('href','#'+id);s.append(u);return s};
const pad2=n=>String(n).padStart(2,'0');
const missionTags=m=>[m.boss&&'BOSS',m.race&&'RACE',m.chase&&'CHASE',m.wrecks&&m.obj&&(m.obj.salv||m.obj.sub)&&'SALVAGE',m.recon&&'RECON',m.ships&&'WARSHIPS',m.night!==undefined&&'NIGHT'].filter(Boolean);
function objectiveText(m){const o=m.obj||{},L=[];
 if(m.boss)L.push('Defeat '+BOSS[m.boss.k].name.split(' / ').pop().replace(/^THE /,'the ').toLowerCase().replace(/(^|\s)\S/g,s=>s.toUpperCase()));
 else L.push(m.race?'Beat Volkov to the finish':m.chase?'Outrun the Kraken to the far side':'Reach the rendezvous');
 if(o.salv)L.push('Recover '+o.salv+' salvage loads with the drone');if(o.sub)L.push('Recover '+o.sub+' loads from sunken submarines');
 if(o.clues)L.push('Find '+o.clues+' beacons with the spotter drone');if(o.need==='core')L.push('Raise the Thermal Core');return L}
function partsText(p){return PARTS.map(([,n],i)=>p[i]?'+'+p[i]+' '+n:'').filter(Boolean).join('  ')}
function firstOpenMission(){for(let i=0;i<MISSIONS.length;i++)if(campOpen(i)&&!camp.data.done[MISSIONS[i].id])return i;return MISSIONS.length-1}
function campTile(){const n=Object.keys(camp.data.done).length,cp=camp.data.cp;$('campTileSub').textContent=n?(n>=MISSIONS.length?'Complete / ':'Mission '+(firstOpenMission()+1)+' of '+MISSIONS.length+' / ')+campStars()+' of '+MISSIONS.length*3+' stars'+(cp?' / resume ready':''):'Operation Deep Meridian / 24 missions'}

function renderCamp(){
 if(camp.sel<0||!campOpen(camp.sel))camp.sel=firstOpenMission();
 const d=camp.data,tot=$('campTot');tot.textContent='';
 for(const [label,val] of [['MISSIONS',Object.keys(d.done).length+' / '+MISSIONS.length],['STARS',campStars()+' / '+MISSIONS.length*3],...PARTS.map(([k,n])=>[n,campParts(k)])]){const b=el('div','cp-stat');b.append(el('small',null,label),el('b',null,String(val)));tot.append(b)}
 document.querySelectorAll('#campTabs button').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.tab===camp.tab)));
 const body=$('campBody');body.textContent='';
 ({missions:renderMissions,dock:renderDock,shop:renderShop,log:renderLog})[camp.tab](body);
 campTile();
}
function renderMissions(body){
 const grid=el('div','cp-grid'),list=el('div','cp-list'),det=el('div','cp-detail');grid.append(list,det);body.append(grid);
 CHAPTERS.forEach((ch,ci)=>{const box=el('div','cp-ch'),h=el('div','cp-ch-h');h.append(el('b',null,'CHAPTER '+ch.n),el('span',null,ch.name));box.append(h);
  MISSIONS.filter(m=>m.ch===ci).forEach(m=>{const open=campOpen(m.i),s=camp.data.done[m.id]||0,b=el('button','cp-m');b.setAttribute('aria-pressed',String(m.i===camp.sel));if(!open)b.classList.add('locked');if(s)b.classList.add('won');
   const nm=el('span','cp-t',m.name);nm.append(el('small',null,open?missionTags(m).slice(0,3).join(' / ')||'PATROL':'LOCKED'));
   const st=el('span','cp-s');for(let k=0;k<3;k++){const i=icon('i-star');if(s>>k&1)i.classList.add('got');st.append(i)}
   b.append(el('span','cp-n',pad2(m.i+1)),nm,open?st:icon('i-lock'));if(camp.data.cp&&camp.data.cp.m===m.id)b.append(el('i','cp-dot'));
   b.onclick=()=>{camp.sel=m.i;renderCamp()};box.append(b)});list.append(box)});
 const m=MISSIONS[camp.sel],ch=CHAPTERS[m.ch],s=camp.data.done[m.id]||0,cp=camp.data.cp&&camp.data.cp.m===m.id?camp.data.cp:null;
 det.append(el('div','eyebrow','CHAPTER '+ch.n+' / '+ch.name+' / MISSION '+pad2(m.i+1)),el('h3',null,m.name));
 const tags=el('div','cp-tags');missionTags(m).forEach(x=>tags.append(el('span',x==='BOSS'?'boss':x==='RACE'?'race':'',x)));det.append(tags,el('p','cp-brief',m.brief));
 const ob=el('div','cp-block');ob.append(el('div','cp-bh','OBJECTIVES'));objectiveText(m).forEach(x=>{const r=el('div','cp-row');r.append(icon('i-next'),el('span',null,x));ob.append(r)});
 ob.append(el('div','cp-sub','CHECKPOINTS / '+m.cps.length+(m.boss?' / BOSS ARENA AFTER THE LAST':'')));det.append(ob);
 const sb=el('div','cp-block');sb.append(el('div','cp-bh','STARS'));
 [['Complete the mission',1],['Complete it in one run, from the start, without losing the boat',2],['Find Dr. Vance’s journal page hidden on the course',4]].forEach(([x,bit])=>{const r=el('div','cp-row'+(s&bit?' got':''));const i=icon('i-star');r.append(i,el('span',null,x));sb.append(r)});det.append(sb);
 const rw=el('div','cp-block');rw.append(el('div','cp-bh','FIRST-TIME REWARD'));rw.append(el('div','cp-row',(s?'Claimed: ':'')+partsText(m.reward||[])+(m.unlock?'  +  NEW BOAT: '+SUB_BY_ID[m.unlock].name.toUpperCase()+' CLASS':'')));det.append(rw);
 if(!campOpen(m.i)){det.append(el('p','cp-lock','Complete mission '+pad2(m.i)+', '+MISSIONS[m.i-1].name+', to unlock.'));return}
 // Boat for the campaign: any boat the campaign has released.
 const vr=el('div','vessel-row cp-vessel'),cv=el('canvas','mini'),info=el('div'),boat=SUB_BY_ID[campSubs().includes(camp.data.sub)?camp.data.sub:'gato'];
 cv.width=Math.round(112*dpr);cv.height=Math.round(38*dpr);info.append(el('b',null,boat.name.toUpperCase()+' CLASS'),el('small',null,'HULL '+campSubFor(boat.id).hull+' / E: '+boat.ability.name));
 const ch2=el('button',null);ch2.append(icon('i-sub'),'Dry dock');ch2.onclick=()=>{camp.tab='dock';renderCamp()};vr.append(cv,info,ch2);det.append(vr);drawPreview(cv,boat,112,38);
 const acts=el('div','cp-acts'),go=el('button','launch');
 if(!callsignSet()){const n=el('p','cp-lock','Enter a callsign on the home screen first: campaign progress is saved under it.');det.append(n)}
 go.append(el('span',null,cp?'RESUME / CHECKPOINT '+cp.i+' OF '+m.cps.length:s?'REPLAY MISSION':'LAUNCH MISSION'),icon('i-go'));go.onclick=()=>campLaunch(m.i,!!cp);acts.append(go);
 if(cp){const r=el('button','text-button');r.append(icon('i-refresh'),'Start from the beginning');r.onclick=()=>campLaunch(m.i,false);acts.append(r)}
 if(m.pre&&camp.data.seen[m.pre]){const r=el('button','text-button');r.append(icon('i-book'),'Replay briefing');r.onclick=()=>playCine(m.pre,()=>openPanel('camp'));acts.append(r)}
 det.append(acts);
}
function campSubFor(id){const save=subId;subId=id;try{return campSub()}finally{subId=save}}
function renderDock(body){
 body.append(el('p','cp-note','Boats are released to you as the campaign goes on. Workshop upgrades apply to every one of them.'));
 const list=el('div','subs'),open=campSubs();
 for(const base of SUBS){const m=campSubFor(base.id),ok=open.includes(base.id),b=el('button','sub-card');b.setAttribute('aria-pressed',String(ok&&camp.data.sub===base.id));if(!ok){b.classList.add('locked');b.disabled=true}
  const cv=el('canvas','mini');cv.width=Math.round(240*dpr);cv.height=Math.round(64*dpr);const nm=el('b',null,base.name.toUpperCase()+' CLASS');nm.append(icon('i-check'));
  b.append(cv,nm,el('small',null,base.origin.toUpperCase()+' / '+base.mark));
  if(ok){b.append(el('p',null,base.desc));const ab=el('div','ab'),an=el('b',null,'E / '+base.ability.name);ab.append(an,base.ability.desc);b.append(ab);
   for(const [label,v] of statRows(m)){const row=el('div','stat'),bar=el('span'),fill=el('i');fill.style.width=Math.round(clamp(v,.08,1)*100)+'%';bar.append(fill);row.append(el('label',null,label),bar);b.append(row)}}
  else{const u=campUnlockedBy(base.id);b.append(el('p','cp-lockline','Released after mission '+pad2(u.i+1)+': '+u.name+'.'))}
  b.onclick=()=>{if(!ok)return;camp.data.sub=base.id;camp.data.at=Date.now();profDirty(false);renderCamp()};list.append(b);drawPreview(cv,base,240,64)}
 body.append(list);
}
function renderShop(body){
 const inv=el('div','cp-inv');for(const [k,n] of PARTS){const b=el('div','cp-part');b.append(el('b',null,String(campParts(k))),el('small',null,n));inv.append(b)}
 body.append(el('p','cp-note','Salvage drones bring parts back from wrecks; missions pay out the first time you finish them. Upgrades apply to every campaign boat.'),inv);
 const list=el('div','cp-shop');
 for(const u of UPGRADES){const lv=camp.data.up[u.id]||0,row=el('div','cp-up'),txt=el('div','cp-up-t');txt.append(el('b',null,u.name.toUpperCase()),el('span',null,u.desc+' '+u.per+' per level.'));
  const pips=el('div','cp-pips');for(let i=0;i<u.max;i++){const p=el('i');if(i<lv)p.className='on';pips.append(p)}
  const cost=lv<u.max?u.cost[lv]:null,can=cost&&PART_KEYS.every((k,i)=>campParts(k)>=cost[i]);
  const btn=el('button','cp-build',lv>=u.max?'MAXED':'BUILD');btn.disabled=!can;
  const price=el('small','cp-price',cost?PARTS.map(([,n],i)=>cost[i]?cost[i]+' '+n:'').filter(Boolean).join(' / '):'All levels built');
  btn.onclick=()=>{if(!can)return;PART_KEYS.forEach((k,i)=>camp.data.spent[k]+=cost[i]);camp.data.up[u.id]=lv+1;profDirty(false);achCheck();tone(520,.15,.04,780);renderCamp()};
  const right=el('div','cp-up-r');right.append(price,btn);row.append(txt,pips,right);list.append(row)}
 body.append(list);
}
function renderLog(body){
 const d=camp.data,stats=el('div','cp-inv');
 for(const [v,n] of [[Object.keys(d.relic).length+' / '+JOURNAL.length,'JOURNAL PAGES'],[d.clues,'BEACONS FOUND'],[d.salv,'SALVAGE LOADS'],[Object.keys(d.boss).length,'BOSSES BEATEN'],[d.races,'RACES WON']]){const b=el('div','cp-part');b.append(el('b',null,String(v)),el('small',null,n));stats.append(b)}
 body.append(stats);
 const cs=el('div','cp-block');cs.append(el('div','cp-bh','CUTSCENES'));const row=el('div','cp-cines');
 for(const [id,label] of [['prologue','Prologue'],...MISSIONS.flatMap(m=>[m.pre&&m.pre!=='prologue'?[m.pre,pad2(m.i+1)+' '+m.name+' / briefing']:null,m.post?[m.post,pad2(m.i+1)+' '+m.name+' / debrief']:null]).filter(Boolean)]){if(!d.seen[id])continue;const b=el('button','text-button',label);b.onclick=()=>playCine(id,()=>openPanel('camp'));row.append(b)}
 if(!row.children.length)row.append(el('span','cp-note','Cutscenes you have watched can be replayed here.'));cs.append(row);body.append(cs);
 const jb=el('div','cp-block');jb.append(el('div','cp-bh','THE JOURNAL OF DR. ELIAS VANCE'));
 JOURNAL.forEach((txt,i)=>{const m=MISSIONS[i],got=d.relic[m.id],r=el('div','cp-page'+(got?' got':''));r.append(el('b',null,'PAGE '+pad2(i+1)),el('span',null,got?txt:'Hidden in mission '+pad2(i+1)+', '+m.name+'.'));jb.append(r)});
 body.append(jb);
}

/* ---- Debrief ---- */
function showDebrief(){
 const m=cm,R=camp.run,res=R.result;
 $('cdKick').textContent='MISSION COMPLETE / CHAPTER '+CHAPTERS[m.ch].n;$('cdName').textContent=m.name;
 const st=$('cdStars');st.textContent='';
 [['MISSION COMPLETE',1],['NO LOSSES',2],['JOURNAL PAGE',4]].forEach(([x,bit])=>{const r=el('div','cd-star'+(res.stars&bit?' got':''));r.append(icon('i-star'),el('span',null,x));if(res.stars&bit&&!(res.prev&bit))r.append(el('em',null,'NEW'));st.append(r)});
 const g=$('cdStats');g.textContent='';
 const mm=Math.floor(res.secs/60),ss=res.secs%60;
 for(const [k,v] of [['SCORE',res.score.toLocaleString()],['TIME',mm+':'+pad2(ss)],['SALVAGE',partsText(R.loot)||'NONE'],['XP',(run.gain>0?'+'+run.gain.toLocaleString():'0')+' / LV '+levelOf(profXp())]]){const b=el('div');b.append(el('label',null,k),el('strong',null,v));g.append(b)}
 const e=$('cdEarned');e.textContent='';
 if(res.first&&m.reward)e.append(el('span','xp-gain','FIRST-TIME REWARD / '+partsText(m.reward)));
 if(res.newSub){const sp=el('span','unlock');sp.append(icon('i-sub'),'NEW BOAT IN THE DRY DOCK / '+SUB_BY_ID[res.newSub].name.toUpperCase()+' CLASS');e.append(sp)}
 for(const id of run.earned){const sp=el('span');sp.append(icon('i-medal'),ACH_BY_ID[id].name.toUpperCase());e.append(sp)}
 $('cdNext').firstChild.textContent=m.i>=MISSIONS.length-1?'FINISH':'CONTINUE';
 openPanel('campDone');
}
function campContinue(){
 const m=cm,res=camp.run&&camp.run.result;if(!m)return;show('campDone',false);panel=null;
 const next=()=>{camp.sel=Math.min(MISSIONS.length-1,m.i+1);home()};
 if(m.post&&(res&&res.first||!camp.data.seen[m.post]))playCine(m.post,next);else next();
}
function campReplay(){const i=cm.i;show('campDone',false);panel=null;campExit();campLaunch(i,false)}

/* ---- Cutscene player ---- */
const cine={on:false,lines:null,i:0,done:null,scene:'title',t0:0,raf:0};
function playCine(id,done){
 const L=CINES[id];if(!L){if(done)done();return}
 if(!camp.data.seen[id]){camp.data.seen[id]=1;profDirty(false)}
 if(panel)show(panel,false);panel='cine';cine.on=true;cine.lines=L;cine.i=0;cine.done=done;cine.scene='';
 show('cine',true);clearInput();cineShow();cancelAnimationFrame(cine.raf);cine.raf=requestAnimationFrame(cineFrame);
}
function cineShow(){
 const L=cine.lines[cine.i],box=$('cineBox'),ti=$('cineTitle');
 const scene=Array.isArray(L)?L[2]:L.scene;if(scene&&scene!==cine.scene){cine.scene=scene;cine.t0=performance.now()}
 if(!Array.isArray(L)){box.hidden=true;ti.hidden=false;ti.classList.remove('in');void ti.offsetWidth;ti.classList.add('in');ti.querySelector('b').textContent=L.title;ti.querySelector('small').textContent=L.sub||'';typer.el=null;return}
 const [w,text]=L,C=CAST[w];ti.hidden=true;box.hidden=false;box.classList.toggle('narr',w==='NARR');
 cine.who=w;$('cinePort').style.borderColor=C.c+'88';
 $('cineName').textContent=w==='NARR'?'':speakerName(w);$('cineName').style.color=C.c;$('cineRole').textContent=C.role;typeText($('cineText'),text);
 $('cineHint').textContent=cine.i<cine.lines.length-1?'SPACE / CLICK TO CONTINUE':'SPACE / CLICK TO FINISH';
}
function cineNext(){if(!cine.on)return;if(!typeDone())return;cine.i++;if(cine.i>=cine.lines.length)return cineEnd();cineShow()}
function cineEnd(){if(!cine.on)return;cine.on=false;cancelAnimationFrame(cine.raf);clearInterval(typer.timer);show('cine',false);if(panel==='cine')panel=null;const d=cine.done;cine.done=null;if(d)d()}
function cineFrame(now){
 if(!cine.on)return;const cv=$('cineArt'),w=innerWidth,h=innerHeight,k=Math.min(devicePixelRatio||1,1.5);
 if(cv.width!==Math.round(w*k)||cv.height!==Math.round(h*k)){cv.width=Math.round(w*k);cv.height=Math.round(h*k)}
 const g=cv.getContext('2d');g.setTransform(k,0,0,k,0,0);g.globalAlpha=1;g.globalCompositeOperation='source-over';
 // A frame's timestamp can predate the scene change by a few milliseconds.
 const tm=Math.max(0,now-cine.t0);paintScene(g,cine.scene||'title',w,h,tm/1000);
 const pc=$('cinePort');if(cine.who&&cine.who!=='NARR'&&!$('cineBox').hidden)paintPortrait(pc.getContext('2d'),cine.who,pc.width,pc.height,now/1000,typer.el===$('cineText')&&typer.i<typer.text.length);
 const fade=clamp(tm/600,0,1);if(fade<1){g.fillStyle=`rgba(0,0,0,${1-fade})`;g.fillRect(0,0,w,h)}
 cine.raf=requestAnimationFrame(cineFrame);
}

/* ---- In-dive HUD ---- */
let campHudKey='';
function campHudInit(){
 show('campHud',true);show('bossBar',false);show('droneBlock',!!(cm.wrecks||cm.recon));
 $('chName').textContent='MISSION '+pad2(cm.i+1)+' / '+cm.name.toUpperCase();
 const goal=cm.boss?cm.boss.at:cm.L,ticks=$('chTicks');ticks.textContent='';
 for(const x of cm.cps)if(x<goal){const i=el('i');i.style.left=(x/goal*100)+'%';ticks.append(i)}
 show('chRival',!!cm.race);$('restartPause').lastChild.textContent='Restart from checkpoint';campHudKey='';
}
function campHUD(){
 if(!cr)return;const m=cm,o=m.obj||{},L=[];
 $('sector').textContent='CH '+CHAPTERS[m.ch].n+' / M'+pad2(m.i+1)+' / '+m.name.toUpperCase()+(m.night!==undefined&&night>.9?' / NIGHT':'');
 const goal=m.boss?m.boss.at:m.L,left=Math.max(0,Math.ceil((goal-sub.x)*.1));
 if(m.boss)L.push(cr.boss?['DEFEAT '+BOSS[m.boss.k].name.split(' / ').pop(),0]:['ARENA IN '+left.toLocaleString()+' M',0]);
 else if(cr.boss&&cr.boss.k==='kchase'&&!cr.boss.leaving)L.push(['OUTRUN THE KRAKEN / '+left.toLocaleString()+' M',0,1]);
 else L.push([(m.race?'FINISH IN ':'RENDEZVOUS IN ')+left.toLocaleString()+' M',0]);
 if(o.salv)L.push(['SALVAGE '+cr.salv.size+' / '+o.salv,cr.salv.size>=o.salv]);
 if(o.sub)L.push(['SUB PARTS '+cr.subLoads+' / '+o.sub+(cr.tubes?' / TUBES ONLINE':' / TUBES OFFLINE'),cr.tubes,!cr.tubes]);
 if(o.clues)L.push(['BEACONS '+cr.clues.size+' / '+o.clues+(cr.air&&cr.air.held.size?' (+'+cr.air.held.size+' ON DRONE)':''),cr.clues.size>=o.clues]);
 if(o.need==='core')L.push([cr.core?'THERMAL CORE ABOARD':'RAISE THE THERMAL CORE',cr.core]);
 if(cr.rival){const gap=Math.round((cr.rival.x-sub.x)*.1);L.push([gap>0?'VOLKOV '+gap+' M AHEAD':'VOLKOV '+(-gap)+' M BEHIND',gap<=0,gap>0]);if(t<cr.boostUntil)L.push(['VENT BOOST',1]);else if(cr.inStream)L.push(['SLIPSTREAM +30%',1])}
 if(cr.cpNext<m.cps.length&&m.cps[cr.cpNext]<goal)L.push(['CHECKPOINT '+(cr.cpNext+1)+' IN '+Math.max(0,Math.ceil((m.cps[cr.cpNext]-sub.x)*.1)).toLocaleString()+' M',0]);else if(cr.cpNext)L.push(['CHECKPOINT '+cr.cpNext+' SAVED',1]);
 const foes=cr.foes.filter(f=>!f.dead&&f.k!=='ambush').length;if(foes)L.push([foes+(foes>1?' HOSTILES':' HOSTILE')+' IN CONTACT',0,1]);
 L.push([cr.relicGot?'JOURNAL PAGE FOUND':'JOURNAL PAGE: HIDDEN',cr.relicGot,0,1]);
 const key=JSON.stringify(L);if(key!==campHudKey){campHudKey=key;const box=$('chObj');box.textContent='';for(const [txt,ok,warn,dim] of L){const r=el('div',(ok?'ok ':'')+(warn?'warn ':'')+(dim?'dim':''));r.append(el('i'),el('span',null,txt));box.append(r)}}
 $('chFill').style.width=clamp(sub.x/goal,0,1)*100+'%';
 if(cr.rival)$('chRival').style.left=clamp(cr.rival.x/goal,0,1)*100+'%';
 const b=cr.boss;if(b&&b.max&&!b.dead){$('bossFill').style.width=(b.hp/b.max*100)+'%';const pts=BOSS[b.k].pts(b);$('bossBar').classList.toggle('armored',pts.every(p=>p.armor));$('bossBar').classList.toggle('hit',t-b.hitAt<.25)}
 if(!$('droneBlock').hidden){const z=inRecon(sub.x),w=!cr.drone&&!cr.air&&wreckInRange();let s,h,ready=false;
  if(cr.air){ready=true;s=cr.air.dir>0?'Q: TURN BACK':'Q: TURN OUT';h=(cr.air.dir>0?'OUTBOUND':'LAND ON DECK')+' / '+Math.ceil(cr.air.bat)+' S'}else if(cr.drone){s='DRONE OUT';h=cr.drone.st==='dig'?'DIGGING':cr.drone.st==='out'?'DIVING':'RETURNING'}
  else if(z){ready=surfaced&&t>=cr.airCool;s=surfaced?'LAUNCH SPOTTER':'SURFACE TO LAUNCH';h='Q / TAP'}else if(w){ready=t>=cr.droneCool;s='SALVAGE READY';h='Q / TAP'}else{s='NO TARGET';h='WRECKS / RECON POINTS'}
  $('droneState').textContent=s;$('droneHint').textContent=h;setRing($('droneBtn'),ready?1:cr.drone||cr.air?.5:0,false);$('droneBtn').classList.toggle('ready',ready)}
 commsTick();
}

/* ---- Wiring ---- */
$('campOpen').onclick=()=>openPanel('camp');$('campClose').onclick=closePanel;
document.querySelectorAll('#campTabs button').forEach(b=>b.onclick=()=>{camp.tab=b.dataset.tab;renderCamp()});
$('cdNext').onclick=campContinue;$('cdReplay').onclick=campReplay;$('cdHome').onclick=()=>{show('campDone',false);panel=null;home()};
$('cine').addEventListener('pointerdown',e=>{if(e.target.closest('#cineSkip'))return;e.preventDefault();cineNext()});
$('cineSkip').onclick=e=>{e.stopPropagation();cineEnd()};
$('letterbox').addEventListener('pointerdown',e=>{e.preventDefault();cutNext()});
$('droneBtn').addEventListener('pointerdown',e=>{e.preventDefault();e.stopPropagation();initAudio();campDrone()});
// Runs before the game's own key handler: cutscenes, cut-ins and the debrief own the keyboard.
addEventListener('keydown',e=>{
 const adv=['Space','Enter','ArrowRight','NumpadEnter'].includes(e.code);
 if(cine.on){e.stopImmediatePropagation();if(adv||e.code==='Escape')e.preventDefault();if(e.repeat)return;if(adv)cineNext();else if(e.code==='Escape')cineEnd();return}
 if(state==='cut'){e.stopImmediatePropagation();if(adv||e.code==='Escape'){e.preventDefault();if(!e.repeat)cutNext()}return}
 if(panel==='campDone'&&e.code==='Escape'){e.stopImmediatePropagation();e.preventDefault();return}
 if(state==='playing'&&cm&&e.code==='KeyQ'&&!e.repeat&&!(e.target instanceof HTMLInputElement)){e.preventDefault();campDrone()}
},true);
