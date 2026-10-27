'use strict';
/* ---- Campaign engine ------------------------------------------------------------
   A campaign mission runs on the endless engine with a scripted, seeded course (the
   same for every sailor), plus what this file adds on top: checkpoints, a finish line
   or boss arena, salvage and spotter drones, a rival boat to race, bosses and their
   hazards. cm is the mission being flown (null outside the campaign) and cr its live
   state for the current attempt. A lost boat restarts at the last checkpoint passed;
   what was collected up to that checkpoint is restored from a snapshot.

   Progress lives in the sailor's profile (camp.data) so it follows the callsign:
   missions and stars, the resume checkpoint, parts earned and spent, upgrades,
   journal pages, beacons, bosses beaten and cutscenes seen. Every field only grows
   (spending is a separate running total), so two copies merge by taking the larger. */
const PART_KEYS=['scrap','alloy','circ'];
const blankCamp=()=>({done:{},cp:null,cpx:0,earn:{scrap:0,alloy:0,circ:0},spent:{scrap:0,alloy:0,circ:0},up:{},relic:{},clue:{},seen:{},boss:{},races:0,salv:0,clues:0,sub:'gato',at:0});
// Maps are kept in key order so two merges of the same copies serialise identically.
const sortKeys=o=>{for(const k of ['done','up','relic','clue','seen','boss'])o[k]=Object.fromEntries(Object.entries(o[k]).sort((a,b)=>a[0]<b[0]?-1:1));return o};
const cint=v=>Math.max(0,Math.floor(+v||0)),cflags=(o,ok)=>{const r={};if(o&&typeof o==='object')for(const k of Object.keys(o))if(o[k]&&(!ok||ok(k)))r[String(k).slice(0,24)]=1;return r};
function cleanCamp(c){
 const b=blankCamp();if(!c||typeof c!=='object')return b;
 if(c.done&&typeof c.done==='object')for(const [id,s] of Object.entries(c.done))if(MISSION_BY_ID[id])b.done[id]=cint(s)&7;
 for(const k of PART_KEYS){b.earn[k]=cint(c.earn&&c.earn[k]);b.spent[k]=Math.min(b.earn[k],cint(c.spent&&c.spent[k]))}
 for(const u of UPGRADES)if(c.up&&c.up[u.id])b.up[u.id]=Math.min(u.max,cint(c.up[u.id]));
 b.relic=cflags(c.relic,k=>MISSION_BY_ID[k]);b.clue=cflags(c.clue);b.seen=cflags(c.seen,k=>CINES[k]);b.boss=cflags(c.boss);
 b.cpx=Math.max(0,+c.cpx||0);b.races=cint(c.races);b.salv=cint(c.salv);b.clues=cint(c.clues);b.sub=SUB_BY_ID[c.sub]?c.sub:'gato';b.at=Math.max(0,+c.at||0);
 const p=c.cp;if(p&&typeof p==='object'&&MISSION_BY_ID[p.m]){const m=MISSION_BY_ID[p.m],s=p.snap&&typeof p.snap==='object'?p.snap:{};
  b.cp={m:p.m,i:Math.min(m.cps.length,cint(p.i)),at:Math.max(0,+p.at||0),snap:{salv:(Array.isArray(s.salv)?s.salv:[]).map(cint).slice(0,40),clues:(Array.isArray(s.clues)?s.clues:[]).map(String).slice(0,20),subs:cint(s.subs),tubes:s.tubes!==false,core:!!s.core,rival:Number.isFinite(+s.rival)?clamp(+s.rival,-3000,3000):320}};if(!b.cp.i)b.cp=null}
 return sortKeys(b);
}
function mergeCamp(a,b){
 const o=blankCamp();
 for(const id of new Set([...Object.keys(a.done),...Object.keys(b.done)]))o.done[id]=(a.done[id]||0)|(b.done[id]||0);
 for(const k of PART_KEYS){o.earn[k]=Math.max(a.earn[k],b.earn[k]);o.spent[k]=Math.min(o.earn[k],Math.max(a.spent[k],b.spent[k]))}
 for(const u of UPGRADES){const v=Math.max(a.up[u.id]||0,b.up[u.id]||0);if(v)o.up[u.id]=v}
 for(const k of ['relic','clue','seen','boss'])o[k]={...a[k],...b[k]};
 for(const k of ['races','salv','clues'])o[k]=Math.max(a[k],b[k]);
 const n=b.at>a.at?b:a;o.sub=n.sub;o.at=Math.max(a.at,b.at);
 // The resume point is the newest checkpoint, unless a later mission end cleared it (cpx).
 o.cpx=Math.max(a.cpx,b.cpx);o.cp=!a.cp?b.cp:!b.cp?a.cp:(b.cp.at>a.cp.at?b.cp:a.cp);if(o.cp&&o.cp.at<=o.cpx)o.cp=null;
 return sortKeys(o);
}
const camp={data:blankCamp(),saved:null,run:null,after:false,sel:-1,tab:'missions'};
const campParts=k=>camp.data.earn[k]-camp.data.spent[k];
const starCount=s=>(s&1)+(s>>1&1)+(s>>2&1);
const campStars=()=>Object.values(camp.data.done).reduce((n,s)=>n+starCount(s),0);
const campOpen=i=>secretAdmin.active||i===0||!!camp.data.done[MISSIONS[i-1].id];
const campBuilt=()=>Object.values(camp.data.up).reduce((n,v)=>n+v,0);
// Boats the campaign has released: the Gato from the start, then one per milestone.
function campSubs(){if(secretAdmin.active)return SUBS.map(s=>s.id);const s=['gato'];for(const m of MISSIONS)if(m.unlock&&camp.data.done[m.id])s.push(m.unlock);return s}
const campUnlockedBy=id=>MISSIONS.find(m=>m.unlock===id);
// Lifetime numbers the achievements and XP read.
function campLife(){const d=camp.data;return {cmis:Object.keys(d.done).length,cstars:campStars(),csalv:d.salv,cclues:d.clues,cbuilt:campBuilt(),cboss:d.boss,craces:d.races,crelic:Object.keys(d.relic).length,cfin:d.done.m24?1:0}}
function campXp(){const L=campLife();return L.cmis*250+L.cstars*120+Object.keys(L.cboss).length*600+L.csalv*15+L.cclues*50+L.crelic*80+L.craces*200}
function campSeed(m){let h=0x5EED1986;for(const ch of 'meridian:'+m.id)h=Math.imul(h^ch.charCodeAt(0),2654435761);return (h^h>>>15)>>>0}

/* ---- Course setup (called from reset and newWorld) ---- */
function campDiff(){const m=cm,b=DIFFS[m.diff],len=m.boss?m.boss.at+9000:m.L;
 return {...b,label:'Campaign',ramp:len*.55,ships:m.ships||Infinity,shipHp:m.shipHp||b.shipHp,space:b.space.map(v=>v/(m.mines||1)),gap:b.gap.map(v=>v*(m.gapK||1)),air:m.air===undefined?b.air:m.air,drift:m.drift===undefined?b.drift:m.drift}}
function campSub(){const b=SUB_BY_ID[subId]||SUBS[0],u=camp.data.up,l=k=>u[k]||0;
 return {...b,hull:b.hull+l('hull'),o2:Math.round(b.o2*(1+.15*l('air'))),reload:b.reload*(1-.1*l('reload')),sonar:b.sonar/(1+.12*l('sonar')),agility:b.agility*(1+.06*l('ballast'))}}
function campWorld(){
 let x=0;SEG=cm.biomes.map(([k,len],i)=>{const s={x0:x,len:cm.boss&&i===cm.biomes.length-1?1e9:len,r:i?wrnd(1400,1650):1,kind:k,v:i||k!=='open'?BIOMES[k].v():{cave:0,basin:0,lift:0,tight:0,rough:1}};x+=len;return s});
 TP.night=cm.night===undefined?1e9:cm.night>0?cm.night:-3600;
}
// Mines stay clear of checkpoints, the finish, recon points and boss arenas.
function campCalm(x){const m=cm,calm=()=>{lastCenter=null;return true};
 if(m.wrecks){const recovered=cr?cr.salv:new Set(camp.run&&camp.run.snap&&camp.run.snap.salv||[]);if(m.wrecks.some(([wx,k],i)=>k==='mineRig'&&recovered.has(i)&&x>=wx&&x<=wx+5000))return calm()}
 if(m.mineZones&&!m.mineZones.some(([a,b])=>x>=a&&x<=b))return calm();
 if(m.wrecks&&m.wrecks.some(([wx])=>Math.abs(x-wx)<1000))return calm();
 if(m.chase&&x>=m.chase.from-400&&x<=m.chase.to)return calm();
 for(const p of m.cps)if(x>p-480&&x<p+760)return calm();
 if(!m.boss&&x>m.L-650&&x<m.L+900)return calm();
 if(m.boss&&x>m.boss.at-350)return calm();
 if(m.recon)for(const z of m.recon)if(x>z.x0-520&&x<z.x1+380)return calm();
 // The Thermal Core must be raisable: no mines over its wreck.
 if(m.wrecks)for(const [wx,k] of m.wrecks)if(k==='core'&&x>wx-900&&x<wx+500)return calm();
 return false}
const campReach=()=>cr&&cr.air?Math.max(sub.x,cr.air.x):sub.x;
const inRecon=x=>cm&&cm.recon?cm.recon.find(z=>x>=z.x0&&x<=z.x1)||null:null;
const ceilAt=x=>{const z=terrain(x);return z.cave>.002?z.top:SURFACE};
function safeY(x,y,pad=40){const z=terrain(x);return clamp(y,ceilAt(x)+S.hy+pad,z.bottom-S.hy-pad)}
const relicSpot=()=>{const r=cm.relic,z=terrain(r.x),top=ceilAt(r.x);return [r.x,clamp(mix(top,z.bottom,r.d),top+45,z.bottom-45)]};
const clueY=(x,h)=>(terrain(x).cave>.002?Math.min(SURFACE,islandTop(x)):SURFACE)-h;
// The slipstream current a racer rides, and the thermal vents along a race course.
function streamY(x){const z=terrain(x),top=ceilAt(x)+95,bot=Math.max(top,z.bottom-95);return clamp(route(x)+85*Math.sin(x/1150+cm.i*1.7),top,bot)}
function buildVents(){const v=[];for(let x=2200,k=0;x<cm.L-600;k++){x+=1300+hash(cm.i*17.3+k*3.1)*700;if(cm.cps.some(p=>Math.abs(p-x)<500))continue;const z=terrain(x);v.push({x,y:safeY(x,mix(streamY(x),route(x),.5)+(hash(cm.i+k*7.7)-.5)*220,55),taken:false})}return v}

/* ---- Mission flow ---- */
function campLaunch(i,resume){
 const m=MISSIONS[i];if(!m||!campOpen(i))return;
 if(!callsignSet()){closePanel();launchDive();return}
 store.set('undertow.callsign',$('callsign').value.trim().slice(0,16));profSwitch();
 if(!camp.saved)camp.saved={diffId,subId,practice};
 subId=campSubs().includes(camp.data.sub)?camp.data.sub:'gato';diffId=m.diff;practice=false;
 let cp=resume&&camp.data.cp&&camp.data.cp.m===m.id?camp.data.cp:null;
 if(cp&&m.recon){const held=new Set(cp.snap.clues||[]),miss=m.recon.find((z,zi)=>z.x1<m.cps[cp.i-1]&&z.clues.some((_,j)=>!held.has(zi+':'+j)));if(miss){const i=m.cps.filter(x=>x<miss.x0).length;cp={...cp,i}}}
 camp.run={m,cp:cp?cp.i:0,snap:cp?cp.snap:null,clean:!cp,deaths:0,loot:[0,0,0],time:0,cuts:{}};
 cm=m;courseSeed=campSeed(m);camp.sel=i;camp.after=false;
 if(panel)show(panel,false);panel=null;
 const go=()=>campBegin();
 if(m.pre&&!cp&&!camp.data.seen[m.pre])playCine(m.pre,go);else go();
}
function campBegin(){
 ['camp','campDone','menu','footer'].forEach(id=>show(id,false));
 start();courseSeed=campSeed(cm);
 const m=cm,R=camp.run;
 toast((R.cp?'CHECKPOINT '+R.cp+' / ':'MISSION '+(m.i+1)+' / ')+m.name.toUpperCase(),m.brief,4.5);
}
function campRetry(){
 if(!cm)return;const R=camp.run;if(R.cp)R.clean=false;if(state!=='over')R.time+=t;
 camp.after=false;show('over',false);show('paused',false);if(panel)closePanel();campBegin();
}
function campAgain(){if(cm&&camp.after){campRetry();return true}return false}
// Leaving the campaign: restore the sailor's own level, boat and mission setting.
function campExit(){
 if(!cm)return false;if(cr&&cr.expedition)expeditionPanel(false);cm=null;cr=null;courseSeed=null;runX0=0;camp.after=false;camp.run=null;
 if(camp.saved){diffId=camp.saved.diffId;subId=camp.saved.subId;setMission(camp.saved.practice);camp.saved=null}
 ['campHud','bossBar','droneBlock','letterbox'].forEach(id=>show(id,false));$('comms').classList.remove('show');commsQ.length=0;
 $('endBest').previousElementSibling.textContent='BEST SCORE';$('again').lastChild.textContent='DIVE AGAIN';$('restartPause').lastChild.textContent='Restart dive';
 return true;
}
function campReset(){
 if(cr&&cr.expedition)expeditionPanel(false);
 const m=cm,R=camp.run,cpI=R.cp,x0=cpI?m.cps[cpI-1]:0,snap=R.snap||{};
 cr={salv:new Set(snap.salv||[]),clues:new Set(snap.clues||[]),subLoads:snap.subs||0,core:!!snap.core,
  tubes:snap.tubes===undefined?!(m.start&&m.start.tubes===false):snap.tubes,cpNext:cpI,msgI:0,
  drone:null,droneCool:0,air:null,airCool:0,boss:null,hz:[],rival:null,boostUntil:0,slowUntil:0,inStream:false,
  done:false,fx:0,fy:0,fa:ambient,ret:false,cut:null,nextAirX:0,relicGot:!!camp.data.relic[m.id],cpFlash:-9,inked:0,chased:false,foes:[],foeI:0,camK:camLead};
 runX0=x0;
 if(x0>0){sub.x=x0;sub.y=safeY(x0,route(x0),50);if(terrain(x0).cave<.002)sub.y=Math.max(sub.y,SURFACE+S.hy+40);populate();const z=terrain(x0);camY=Math.max(-130,mix(z.centre,sub.y,.35)-vh*.53)}
 cr.fx=sub.x;cr.fy=sub.y;
 firstShip=m.ships?Math.max(m.ships,x0+1600):Infinity;
 const msgs=m.msgs||[];while(cr.msgI<msgs.length&&msgs[cr.msgI][0]<x0+60)cr.msgI++;
 const fl=m.foes||[];while(cr.foeI<fl.length&&fl[cr.foeI][0]<x0+60)cr.foeI++;
 cr.wrecks=(m.wrecks||[]).map(([x,k],i)=>({x,k,i,y:terrain(x).bottom-4,done:cr.salv.has(i),busy:false}));
 const required=campRequiredWrecks(m);let moved=0;for(const w of cr.wrecks){w.required=required.includes(w.i);if(w.required&&!w.done&&w.x<x0+500){w.x=x0+900+(moved++)*1400;w.y=terrain(w.x).bottom-4}}
 if(m.start&&m.start.hull&&!cr.tubes)hull=Math.max(1,S.hull+m.start.hull);
 if(m.race){cr.rival={x:x0+(snap.rival===undefined?320:snap.rival),y:sub.y+50,k:m.race.rival};cr.vents=buildVents()}
 if(m.relic&&m.relic.t==='float'&&!cr.relicGot)cr.relicAt=relicSpot();
 commsQ.length=0;commsUntil=0;$('comms').classList.remove('show');
 fieldBuild();
 campHudInit();
}
function campSnap(){return {salv:[...cr.salv],clues:[...cr.clues],subs:cr.subLoads,tubes:cr.tubes,core:cr.core,rival:cr.rival?Math.round(clamp(cr.rival.x-sub.x,-2500,2500)):undefined}}
function reachCheckpoint(i){
 const R=camp.run;R.cp=i+1;R.snap=campSnap();camp.data.cp={m:cm.id,i:i+1,snap:R.snap,at:Date.now()};profDirty(false);
 cr.cpFlash=t;toast('CHECKPOINT '+(i+1)+' / '+cm.cps.length,'Progress saved. A lost boat restarts here.',2.6);csfx.checkpoint();
 const cut=cm.cuts&&cm.cuts[i+1];if(cut&&!R.cuts[i+1]){R.cuts[i+1]=1;campaignRadioCut(cut)}
}
function campStep(dt){
 campStationTick();campSupplyTick();fieldStep(dt);
 const m=cm,msgs=m.msgs||[];
 while(cr.msgI<msgs.length&&sub.x>=msgs[cr.msgI][0]){const [,w,txt]=msgs[cr.msgI++];comms(w,txt)}
 while(cr.cpNext<m.cps.length&&sub.x>=m.cps[cr.cpNext]){reachCheckpoint(cr.cpNext);cr.cpNext++;if(state!=='playing')return}
 if(cr.relicAt){const [rx,ry]=cr.relicAt,dx=(rx-sub.x)/(S.hx+20),dy=(ry-sub.y)/(S.hy+20);if(dx*dx+dy*dy<1){cr.relicAt=null;relicGet()}}
 const fl=m.foes||[];while(cr.foeI<fl.length&&sub.x>=fl[cr.foeI][0]&&!cr.air)spawnFoe(fl[cr.foeI++][1]);
 updateSalvage(dt);updateAir(dt);updateRace(dt);updateBoss(dt);updateFoes(dt);updateHazards(dt);if(state!=='playing')return;
 // Bosses and the Kraken chase run long; air pockets keep coming in their arenas.
 if(cr.boss&&!cr.boss.dead&&sub.x>cr.nextAirX){cr.nextAirX=sub.x+rnd(1100,1500);const px=sub.x+Math.max(vw,900)+200,py=safeY(px,mix(route(px),sub.y,.5)+rnd(-90,90),60);pickups.push({x:px,y:py,cy:py,phase:rnd(0,TAU),taken:false})}
 if(!m.boss&&sub.x>=m.L)campArrive();
 if(cr&&cr.air)camY=mix(camY,cr.air.y-vh*.46,1-Math.exp(-dt*3));
 // The Grozny fights on the surface: keep the waterline in view.
 else if(cr&&cr.boss&&cr.boss.k==='warden')camY=mix(camY,Math.max(-280,Math.min(camY,SURFACE-vh*.32)),1-Math.exp(-dt*2));
}
// Called from physics(): the boat's speed multiplier (currents, vents, recon, flight).
function campSpeed(){if(!cr)return 1;if(cr.air||campStation())return 0;let k=1;
 if(cm.race){cr.inStream=Math.abs(sub.y-streamY(sub.x))<64;if(cr.inStream)k*=1.3;if(t<cr.boostUntil)k*=1.55;if(t<cr.slowUntil)k*=.65}
 if(inRecon(sub.x))k*=.6;return k}
const campHold=()=>!!(cr&&cr.air);
const airBattery=()=>40+5*(camp.data.up.drone||0);
function campHit(){if(cr&&cm.race)cr.slowUntil=t+1.5}
function campCanFire(){if(!cr||cr.tubes)return true;toast('TUBES OFFLINE','Salvage parts from sunken submarines to repair the torpedo room.',1.8,true);tone(150,.12,.03,110);return false}
const campQuiet=()=>!!(cr&&(cr.air||cr.boss||inRecon(sub.x)||cr.foes.some(f=>f.k==='destroyer'&&!f.dead)));
function campArrive(){
 const o=cm.obj||{};let why='';
 if(o.salv&&cr.salv.size<o.salv)why='Only '+cr.salv.size+' of '+o.salv+' salvage loads recovered. The tender will not take an empty boat.';
 else if(o.sub&&cr.subLoads<o.sub)why='The torpedo room is still flooded: '+cr.subLoads+' of '+o.sub+' submarine parts recovered.';
 else if(o.clues&&cr.clues.size<o.clues)why='Only '+cr.clues.size+' of '+o.clues+' beacons found. Fly the spotter drone at every recon point.';
 else if(o.need==='core'&&!cr.core)why='The Thermal Core is still on the bottom. Raise it from the glowing wreck.';
 if(why){deathCause=why;campFinish();return}
 campWin();
}
// Mission complete: stars, rewards and unlocks, then the debrief panel.
function campWin(){
 if(state!=='playing'||!cr||cr.done)return;cr.done=true;
 const m=cm,R=camp.run,d=camp.data,first=!d.done[m.id],prev=d.done[m.id]||0,subsBefore=campSubs();
 const stars=1|(R.clean?2:0)|(d.relic[m.id]?4:0);d.done[m.id]=prev|stars;
 if(first&&m.reward)addParts(m.reward,true);
 if(m.boss)d.boss[m.boss.k]=1;if(m.race)d.races++;if(d.cp&&d.cp.m===m.id){d.cp=null;d.cpx=Date.now()}
 state='debrief';clearInput();show('pause',false);$('hint').style.opacity='0';
 achCommit();const x=profXp(),l0=levelOf(run.xp0),l1=levelOf(x);run.gain=x-run.xp0;run.promoted=l1>l0?l1:0;if(run.promoted)achPop({kind:'PROMOTED',name:'LEVEL '+l1+' / '+rankTitle(l1)});
 achCheck();profDirty(false);
 R.result={stars,prev,first,newSub:campSubs().find(s=>!subsBefore.includes(s)),score:score(),secs:Math.round((R.time||0)+t)};
 toast('MISSION COMPLETE',m.name.toUpperCase(),3);csfx.win();
 setTimeout(()=>{if(state==='debrief'&&cm===m)showDebrief()},650);
}
// Mission failed (a lost boat, or an objective missed at the finish).
function campFinish(){
 if(state==='over')return;state='over';const m=cm,R=camp.run;R.clean=false;R.deaths++;R.time=(R.time||0)+t;
 if(cr){cr.drone=null;cr.air=null;cr.foes=[]}
 achCommit();const x=profXp(),l0=levelOf(run.xp0),l1=levelOf(x);run.gain=x-run.xp0;run.promoted=l1>l0?l1:0;if(run.promoted)achPop({kind:'PROMOTED',name:'LEVEL '+l1+' / '+rankTitle(l1)});
 $('overLabel').textContent='MISSION FAILED / '+m.name.toUpperCase();$('cause').textContent=deathCause;
 $('endScore').textContent=score().toLocaleString();$('endMeta').textContent=S.name.toUpperCase()+' CLASS / CAMPAIGN MISSION '+(m.i+1);
 $('endDistance').textContent=Math.floor(distance)+' m';$('endShips').textContent=shipsSunk;$('endGates').textContent=cleared;$('endDepth').textContent=Math.floor(maxDepth)+' m';$('endAir').textContent=airCollected;
 $('endBest').previousElementSibling.textContent='CHECKPOINT';$('endBest').textContent=R.cp+' / '+m.cps.length;
 renderEarned();$('place').hidden=true;$('saveShared').hidden=true;
 $('saveNote').textContent=R.cp?'Progress saved at checkpoint '+R.cp+'. Retry from there, or surface and come back later.':'Retry from the start of the mission.';
 $('again').lastChild.textContent=R.cp?'RETRY FROM CHECKPOINT '+R.cp:'RETRY MISSION';
 show('over',true);overAt=performance.now();$('hud').classList.add('ended');$('again').focus({preventScroll:true});show('pause',false);
 camp.after=true;profDirty(false);
}
function addParts(p,quiet){const d=camp.data;PART_KEYS.forEach((k,i)=>{d.earn[k]+=p[i]||0;if(camp.run)camp.run.loot[i]+=p[i]||0});if(!quiet)profDirty(false)}
function relicGet(){
 const d=camp.data;if(d.relic[cm.id])return;d.relic[cm.id]=1;cr.relicGot=true;profDirty(false);
 achPop({kind:'JOURNAL PAGE FOUND',name:'VANCE’S LOG / PAGE '+(cm.i+1)});csfx.relic();comms('VANCE',JOURNAL[cm.i]);achCheck();
}

/* ---- Salvage drone: dives to a wreck, digs, and chases the boat home ---- */
function wreckInRange(){let best=null,bd=Infinity;for(const w of cr.wrecks){if(w.done||w.busy)continue;const dx=w.x-sub.x;if(dx<-420||dx>1100)continue;const d=Math.abs(dx-300)-(w.required?2000:0);if(d<bd){bd=d;best=w}}return best}
function campDrone(){
 if(state!=='playing'||!cr)return;
 if(cr.expedition){expeditionScan();return}
 if(cr.air){const a=cr.air;if(t-a.turnAt>.3){a.dir=-a.dir;a.turnAt=t;tone(a.dir>0?520:390,.1,.03,a.dir>0?700:300);toast(a.dir>0?'DRONE OUTBOUND':'DRONE RETURNING','',1.2)}return}
 const z=inRecon(sub.x);
 if(z&&surfaced){if(t>=cr.airCool)launchAir(z);return}
 if(cr.drone){toast('DRONE DEPLOYED','Wait for it to come back aboard.',1.4);return}
 if(t<cr.droneCool){tone(150,.07,.02,120);return}
 const w=wreckInRange();
 if(!w){toast(z?'SURFACE TO LAUNCH':'NO SALVAGE IN RANGE',z?'Ride the surface at the recon point, then launch the spotter drone.':'Wait for a SALVAGE marker on a wreck below.',1.8);tone(150,.12,.03,110);return}
 expeditionStart(w);
}
function moveTo(o,tx,ty,v,dt){const dx=tx-o.x,dy=ty-o.y,d=Math.hypot(dx,dy);if(d<1e-3)return 0;const s=Math.min(d,v*dt);o.x+=dx/d*s;o.y+=dy/d*s;return d-s}
function updateSalvage(dt){
 const d=cr.drone;if(!d)return;const k=1+.35*(camp.data.up.drone||0);
 if(d.st==='out'){if(moveTo(d,d.w.x,d.w.y-12,820*k,dt)<4){d.st='dig';d.dig=.85/k}}
 else if(d.st==='dig'){d.dig-=dt;if(Math.random()<.5)debris.push({x:d.w.x+rnd(-14,14),y:d.w.y-6,vx:rnd(-30,30),vy:rnd(-40,-10),life:.6+Math.random()*.5,r:.8+Math.random()*1.6});if(d.dig<=0)d.st='back'}
 else if(moveTo(d,sub.x-S.hx*.25,sub.y+S.hy*.7,speed+760*k,dt)<10){deliver(d.w);cr.drone=null;return}
 if(Math.random()<.4)bubbles.push({x:d.x,y:d.y,r:.8+Math.random()*1.5,life:.8+Math.random()*.5,vx:rnd(-10,10),vy:-14});
 // A drone that blunders into a mine sets it off: the mine is gone, and so is the drone.
 for(const g of gates){if(Math.abs(g.x-d.x)>R+8)continue;for(let j=0;j<2;j++)if(!g.dead[j]&&Math.hypot(g.x-d.x,mineY(g,j)-d.y)<R+5){detonateMine(g,j,false);d.w.busy=false;cr.drone=null;cr.droneCool=t+2.5;toast('DRONE LOST','It struck a mine. A spare will be ready in a moment.',2.2,true);return}}
}
function lootFor(w){const L=LOOT[w.k]||LOOT.ship,h=n=>hash(cm.i*31.7+w.i*7.3+n*1.91);return [L[0]+Math.floor(h(1)*(L[1]+1)),h(2)<L[2]?1:0,h(3)<L[3]?1:0]}
function deliver(w){
 w.done=true;w.busy=false;cr.salv.add(w.i);const p=lootFor(w);addParts(p);camp.data.salv++;
 if(w.k==='mineRig'){for(const g of gates)if(g.x>=w.x&&g.x<=w.x+5000){g.dead=[true,true];boom(g.x,g.centre,20)}comms('JUNO','Controller disabled. Its downstream minefield is cold. Route is clear.')}
 if(w.k==='sub'||w.k==='akula')cr.subLoads++;if(w.k==='core')cr.core=true;
 csfx.salvage();const got=PARTS.map(([,n],i)=>p[i]?'+'+p[i]+' '+n:'').filter(Boolean).join('  ');
 const o=cm.obj||{},n=o.salv?' / LOAD '+cr.salv.size+' OF '+o.salv:o.sub&&(w.k==='sub'||w.k==='akula')?' / SUB PARTS '+cr.subLoads+' OF '+o.sub:'';
 toast(w.k==='core'?'THERMAL CORE RECOVERED':'SALVAGE RECOVERED'+n,got,2.4);
 if(w.k==='core')comms('JUNO','It is aboard. Oh, it is warm. Everyone, hold on to something.');
 if(cm.relic&&cm.relic.t==='wreck'&&cm.relic.i===w.i&&!cr.relicGot)relicGet();
 if(o.sub&&!cr.tubes&&cr.subLoads>=o.sub){cr.tubes=true;hull=Math.min(S.hull,hull+1);lastFire=-99;lastHud=-1;toast('TUBES ONLINE','The torpedo room is pumped dry and the hull is patched.',3);comms('JUNO','Tubes are back! F or right-click, Captain. Give them hell.')}
 if(camp.data.salv===1)comms('JUNO','Parts go straight to the Workshop. Spend them on upgrades between missions.');
 achCheck();
}

/* ---- Spotter drone ------------------------------------------------------------
   A flight over the islands while the boat holds at the surface. The drone flies out
   on its own heading; Q turns it around. Beacons (and a hidden journal page) are only
   logged on the drone: they count once it lands back on the deck. Gusts knock it about,
   gulls and flak bring it down, and a flat battery drops it in the sea. */
function launchAir(z){
 enemyMissiles=[];cr.hz=[];
 const zi=cm.recon.indexOf(z),flock=[];for(let k=0;k<(z.flak?6:4);k++){let bx=z.x1+900+k*1000+hash(zi*9+k)*300;if(z.clues.some(([cx])=>Math.abs(cx-bx-200)<260))bx+=460;for(let j=0;j<3;j++)flock.push({x:bx+j*26,y:SURFACE-150-hash(zi*5+k*3)*260+j*12,ph:hash(k*7+j)*TAU})}
 cr.air={x:sub.x+S.hx*.3,y:SURFACE-22,v:-170,dir:1,turnAt:-9,bat:airBattery(),z,zi,t0:t,flak:[],nextFlak:t+1.1,gustAt:t+rnd(1.5,3),gust:-9,birds:flock,held:new Set(),relic:false,warned:false,
  hp:3,hitAt:-9,end:Math.max(...z.clues.map(c=>c[0]),z.relic?z.relic[0]:0)+700};
 cr.ret=false;csfx.drone();toast('SPOTTER DRONE AIRBORNE','Find the beacons, then press Q to turn back and land on the deck.',3);
}
const deckAt=()=>[sub.x+S.hx*.1,sub.y-S.hy*1.4];
function updateAir(dt){
 const a=cr.air;if(!a)return;sub.y=SURFACE+S.hy*.2;sub.v=0;
 const up=pointerLift||inputKeys.has('Space')||inputKeys.has('ArrowUp')||inputKeys.has('KeyW'),dn=inputKeys.has('ArrowDown')||inputKeys.has('KeyS');
 if(t>a.gustAt){a.v+=(Math.random()<.5?-1:1)*rnd(140,a.z.flak?300:220);a.gust=t;a.gustAt=t+rnd(1.4,3)}
 a.v=clamp(a.v+((up?-560:dn?440:200)-1.6*a.v)*dt,-280,300);a.y+=a.v*dt;a.x+=360*a.dir*dt;a.bat-=dt;
 const ceil=SURFACE-620;if(a.y<ceil){a.y=ceil;a.v=Math.max(0,a.v)}
 const [dx,dy]=deckAt();if(a.dir<0&&Math.abs(a.x-dx)<230){a.y=mix(a.y,dy,1-Math.exp(-dt*4));a.v*=Math.exp(-dt*5)}if(t-a.t0>1.5&&Math.hypot(a.x-dx,(a.y-dy)*1.4)<65)return airLand();
 const isle=terrain(a.x).cave>.002,g=isle?islandTop(a.x):SURFACE;
 if(a.y>g-9)return airEnd(isle?'The drone clipped the cliffs.':'The drone ditched in the sea.');
 // Gulls wheel over their patch of sky rather than drifting down onto the boat.
 for(const b of a.birds){b.x+=Math.cos(ambient*.9+b.ph)*60*dt;b.y+=Math.sin(ambient*1.3+b.ph)*40*dt;if(Math.hypot(b.x-a.x,b.y-a.y)<24){airHit('Bird strike. Keep clear of the flock.');if(!cr.air)return}}
 if(a.z.flak&&t>a.nextFlak){a.flak.push({x:a.x+a.dir*rnd(220,500),y:clamp(a.y+rnd(-100,100),ceil+30,g-45),born:t});a.nextFlak=t+rnd(.45,.85)}
 for(const f of a.flak){const age=t-f.born;if(!f.pop&&age>=.75){f.pop=true;sfx.boom(12);if(Math.hypot(f.x-a.x,f.y-a.y)<54){airHit('Flak hit. Move away from the red rings.');if(!cr.air)return}}}
 a.flak=a.flak.filter(f=>t-f.born<1.7);
 a.z.clues.forEach(([cx,h],j)=>{const id=a.zi+':'+j;if(cr.clues.has(id)||a.held.has(id))return;if(Math.hypot(cx-a.x,clueY(cx,h)-a.y)<64){a.held.add(id);csfx.relic();
  toast('BEACON LOGGED ON THE DRONE',CLUE_TEXT[(cm.i*3+cr.clues.size+a.held.size)%CLUE_TEXT.length]+' Bring the drone home to keep it.',3)}});
 if(a.z.relic&&!cr.relicGot&&!a.relic){const [rx,rh]=a.z.relic;if(Math.hypot(rx-a.x,clueY(rx,rh)-a.y)<64){a.relic=true;csfx.relic();toast('JOURNAL PAGE ON THE DRONE','Land it on the deck to keep it.',2.4)}}
 // Range warnings: a drone needs the battery to fly home.
 const need=Math.abs(a.x-dx)/360+2;if(a.dir>0&&!a.warned&&a.bat<need+3){a.warned=true;toast('TURN BACK NOW','Press Q. The battery will only just get it home.',2.4,true);sfx.alarm()}
 if(a.dir>0&&a.x>a.end){a.dir=-1;a.turnAt=t;toast('SURVEY RUN COMPLETE','Bring the drone home and land it on the deck.',2.6)}
 if(a.dir<0&&a.x<dx-700){a.dir=1;a.turnAt=t}
 if(a.bat<=0)return airEnd('The battery died and the drone fell into the sea.');
}
function airHit(message){const a=cr.air;if(!a||t-a.hitAt<1.2)return;a.hitAt=t;a.hp--;boom(a.x,a.y,12);if(a.hp<=0)return airEnd(message);toast('DRONE HIT / '+a.hp+' HULL',message,1.6,true)}
function airLand(){
 const a=cr.air,n=a.held.size;cr.air=null;cr.ret=true;cr.airCool=t+.8;clearInput();
 for(const id of a.held){cr.clues.add(id);camp.data.clue[cm.id+':'+id]=1;camp.data.clues++}
 if(n)profDirty(false);csfx.salvage();
 const need=(cm.obj||{}).clues;toast('DRONE RECOVERED',n?n+(n>1?' beacons':' beacon')+' logged'+(need?' / '+cr.clues.size+' OF '+need:'')+'.':'Nothing new on this flight.',2.6);
 if(a.relic)relicGet();if(n)achCheck();
}
function airEnd(msg){
 const a=cr.air;cr.air=null;cr.ret=true;cr.airCool=t+1.2;boom(a.x,a.y,22);clearInput();
 const lost=a.held.size+(a.relic?1:0);toast('DRONE DOWN',msg+(lost?' What it had logged went down with it.':'')+(inRecon(sub.x)?' A spare is ready.':''),3,true);
}

/* ---- Race: the rival rides the current; vents and the slipstream speed you up ---- */
function updateRace(dt){
 const r=cr.rival;if(!r)return;
 // Volkov eases off when far ahead and pushes when far behind, so a race stays a race.
 const gap=r.x-sub.x,base=mix(D.speed[0],D.speed[1],clamp(r.x/D.ramp,0,1))*cm.race.rv,k=gap<0?1+clamp(-gap-600,0,1200)/1200*.65:1-clamp(gap-1200,0,2000)/2000*.15;
 const combat=cr.foes.some(f=>!f.dead)||cr.boss;
 const pace=combat?Math.min(base*S.speed,campCombatSpeed()*(cr.inStream?.92:1.04)):base*S.speed;
 const fieldPace=fieldActive()?Math.min(pace,fieldSpeed(pace)*(cr.inStream?.92:1.04)):pace;
 r.x+=campTerrainSpeed(fieldPace,r.x)*k*dt;const ty=streamY(r.x+220);r.y+=clamp((ty-r.y)*1.4,-110,110)*dt;
 if(t-(r.lb||0)>.05){r.lb=t;bubbles.push({x:r.x-60,y:r.y+(Math.random()-.5)*10,r:1+Math.random()*2,life:1.5,vx:-40,vy:-12})}
 for(const v of cr.vents){if(v.taken||Math.abs(v.x-sub.x)>S.hx+26)continue;if(Math.abs(v.y-sub.y)<S.hy+28){v.taken=true;cr.boostUntil=t+2.2;csfx.boost();for(let i=0;i<20;i++)bubbles.push({x:v.x,y:v.y,r:1+Math.random()*3,life:1,vx:rnd(-80,80),vy:rnd(-80,20)})}}
 if(cr.inStream&&Math.random()<.5)bubbles.push({x:sub.x-S.hx,y:sub.y+rnd(-12,12),r:1,life:.8,vx:-120,vy:0});
 if(r.x>=cm.L&&sub.x<cm.L){deathCause=(r.k==='typhoon'?'The Typhoon':'The Vepr')+' reached the marker first. Volkov wins this leg.';campFinish()}
}

/* ---- Bosses ------------------------------------------------------------------
   A boss keeps pace with the boat (x = sub.x + offset) so the fight never scrolls
   away. pts() lists its weak points for missiles: {x,y,r[,ry][,armor]}; an armoured
   point deflects. Hazards (cr.hz) are arms, sweeps, ink, depth charges and drifting
   mines; seekers and torpedoes reuse the enemy missile code. */
function spawnArms(b,ph,who){
 // One readable formation at a time. This also prevents an ambush and a boss
 // from combining individually fair patterns into an impossible wall.
 if(cr.hz.some(h=>h.k==='tent'||h.k==='sweep'))return;
 const ag=S.agility*(t<ballastUntil?.55:1),v=Math.max(90,Math.min(speed,campCombatSpeed())),eta=3.1;
 const x=sub.x+v*eta+S.hx+38,z=terrain(x),top=ceilAt(x),bot=z.bottom;
 const half=S.hy+Math.max(64,86-ph*8),margin=half+32;
 // Leave a reaction interval, then bound the target by both steering envelopes.
 const lo=Math.max(top+margin,campVerticalReach(sub.y,sub.v,eta-.7,true)+half*.25);
 const hi=Math.min(bot-margin,campVerticalReach(sub.y,sub.v,eta-.7,false)-half*.25);
 if(lo>hi)return; // A terrain transition takes priority over an arm formation.
 const desired=clamp(sub.y+(Math.random()<.5?-1:1)*(65+ph*18)*ag,lo,hi);
 const target=[desired,clamp(sub.y,lo,hi),(lo+hi)/2].find(y=>campArmRouteClear(y,v));
 if(target===undefined)return;
 for(const fromTop of [true,false])cr.hz.push({k:'tent',x,top:fromTop,base:fromTop?top-12:bot+12,tip:target+(fromTop?-half:half),born:t,warn:eta-.75,ext:.3,hold:1.3,ret:.45,w:who==='mother'?17:23,who,safe:target});
 cr.escape={x,y:target,until:t+eta+1.3};
}

function torp(x,y,seek){enemyMissiles.push({x,y,vx:speed-180,vy:0,air:false,life:9,turn:0,seek:0,err:0,sp:Math.abs(speed-180),torp:true})}
function seeker(x,y,ph){enemyMissiles.push({x,y,vx:speed-260,vy:rnd(-80,-30),air:false,life:6,turn:D.turn*(.45+.15*ph),seek:1.5,err:rnd(-50,50),sp:speed+D.mvel*.5})}
const BOSS={
 warden:{name:'GROZNY / THE IRON WARDEN',hp:15,
  init(b){b.off=500;b.y=SURFACE;b.nextC=t+2.2;b.nextM=t+4.5},
  update(b,dt){const ph=b.hp<=b.max/2?1:0;b.x=sub.x+b.off+200*Math.sin((t-b.t0)*.3);
   if(t>b.nextC){const n=2+ph;for(let i=0;i<n;i++){const x=b.x-110+i*80+rnd(-15,15),fl=terrain(x).bottom-50;cr.hz.push({k:'charge',x,y:SURFACE+4,vy:30,ty:clamp(sub.y+rnd(-50,50)+(i-(n-1)/2)*45,SURFACE+70,fl),r:88,spin:rnd(0,TAU)})}b.nextC=t+(ph?1.4:1.95)*rnd(.85,1.15);sfx.splash()}
   if(t>b.nextM){enemyMissiles.push({x:b.x-30,y:SURFACE-30,vx:(sub.x-b.x)*.12+speed*.4,vy:-200-Math.random()*50,air:true,life:7,turn:D.turn*(ph?.55:.4),seek:ph?1.4:1.1,err:(Math.random()-.5)*110,sp:speed+D.mvel*.45});b.nextM=t+(ph?3.4:4.8);sfx.enemyLaunch()}
   if(sub.y-S.hy<SURFACE+16&&Math.abs(b.x-sub.x)<175+S.hx)damage(2,'The boat rammed the cruiser Grozny.','breach')},
  pts(b){return [-130,-65,0,65,130].map(dx=>({x:b.x+dx,y:SURFACE-2,r:36}))}},
 mother:{name:'OLD MOTHER',hp:20,
  init(b){b.off=700;b.y=terrain(sub.x+700).centre;b.nextA=t+1.6;b.nextI=t+7},
  update(b,dt){const ph=b.hp<=b.max/2?1:0,z=terrain(b.x);b.x=sub.x+b.off+50*Math.sin((t-b.t0)*.45);b.y=mix(b.y,z.centre+35*Math.sin((t-b.t0)*.6),1-Math.exp(-dt*2));
   if(t>b.nextA){spawnArms(b,ph,'mother');b.nextA=t+(ph?1.5:2.05)}
   if(t>b.nextI){const x=sub.x+rnd(340,520);cr.hz.push({k:'ink',x,y:safeY(x,sub.y+rnd(-60,60),20),r:20,R:ph?240:200,born:t,life:8});b.nextI=t+(ph?6.5:9.5);sfx.splash()}},
  pts(b){return [{x:b.x-95,y:b.y-8,r:44}]}},
 vepr:{name:'VEPR / CAPT. VOLKOV',hp:9,sub:'akula',scale:1.4,
  init(b){b.off=620;b.y=sub.y;b.nextT=t+2;b.nextM=t+6},
  update(b,dt){const ph=b.hp<=b.max/2?1:0,top=ceilAt(b.x)+70,bot=terrain(b.x).bottom-70;
   b.x=sub.x+b.off+140*Math.sin((t-b.t0)*.38);const ty=clamp(sub.y+130*Math.sin((t-b.t0)*.55),top,Math.max(top,bot));b.y+=clamp((ty-b.y)*1.2,-95,95)*dt;
   if(t>b.nextT){const n=ph?3:1;if(n>1)campVolley(b.x-85,b.y,n,55);else torp(b.x-85,b.y,.3);b.nextT=t+(ph?1.8:2.3);sfx.launch()}
   if(t>b.nextM){for(let i=0;i<2+ph;i++)cr.hz.push({k:'fmine',x:b.x-70-i*45,y:clamp(b.y+(i-.5)*70,top,Math.max(top,bot)),ph:rnd(0,TAU)});b.nextM=t+(ph?5:6.5)}},
  pts(b){return [{x:b.x,y:b.y,r:66,ry:34}]}},
 kchase:{name:'THE KRAKEN',hp:0,
  init(b){b.off=900;b.y=sub.y+80;b.nextA=t+2.4},
  update(b,dt){const p=clamp((sub.x-cm.chase.from)/(cm.chase.to-cm.chase.from),0,1),ph=p<.35?0:p<.7?1:2;
   if(b.leaving){b.off+=420*dt;b.x=sub.x+b.off;if(t-b.leaving>3.5)cr.boss=null;return}
   b.x=sub.x+b.off+40*Math.sin((t-b.t0)*.3);b.y=mix(b.y,terrain(b.x).bottom-60,1-Math.exp(-dt));
   if(t>b.nextA){spawnArms(b,ph,'kraken');b.nextA=t+[2.3,1.9,1.55][ph]}}},
 kraken:{name:'THE KRAKEN',hp:16,
  init(b){b.off=820;b.y=sub.y;b.nextA=t+2;b.nextS=t+9;b.openUntil=0;b.nextOpen=t+5.5;b.nextI=t+14},
  update(b,dt){const p=b.hp/b.max,ph=p>.66?0:p>.33?1:2,z=terrain(b.x);
   b.x=sub.x+b.off+40*Math.sin((t-b.t0)*.3);b.y=mix(b.y,mix(z.centre,sub.y,.5)+30*Math.sin((t-b.t0)*.5),1-Math.exp(-dt*1.2));
   const was=b.open;b.open=t<b.openUntil;if(was&&!b.open)csfx.lid();
   if(t>b.nextA&&!b.open){spawnArms(b,ph,'kraken');b.nextA=t+[1.9,1.6,1.3][ph]}
   if(ph&&t>b.nextS&&!b.open&&!cr.hz.some(h=>h.k==='tent'||h.k==='sweep')){const top=ceilAt(sub.x)+60,bot=terrain(sub.x).bottom-60;cr.hz.push({k:'sweep',y:clamp(sub.y,top,bot),h:44,born:t,warn:2.5,ext:.45,hold:.55,ret:.5});b.nextS=t+(ph>1?6.5:8);b.nextOpen=Math.min(b.nextOpen,t+2.8)}
   if(ph>1&&t>b.nextI){const x=sub.x+rnd(340,520);cr.hz.push({k:'ink',x,y:safeY(x,sub.y,20),r:20,R:230,born:t,life:8});b.nextI=t+9}
   if(!b.open&&t>b.nextOpen){b.openUntil=t+4.5;b.nextOpen=t+4.5+[6,5.5,5][ph];toast('THE EYE IS OPEN','Fire now!',1.6);csfx.lid()}},
  pts(b){return [{x:b.x-150,y:b.y-30,r:54,armor:!b.open}]}},
 leviathan:{name:'LEVIATHAN / TYPHOON TK-208',hp:22,sub:'typhoon',scale:1.8,
  init(b){b.off=680;b.y=sub.y;b.next=t+2.6;b.vulnUntil=0;b.lunge=null;b.n=0},
  update(b,dt){const p=b.hp/b.max,ph=p>.6?0:p>.3?1:2,top=ceilAt(b.x)+90,bot=Math.max(top,terrain(b.x).bottom-90);
   let off=b.off+120*Math.sin((t-b.t0)*.33);const L=b.lunge;
   if(L){const e=t-L.t0;if(e>2.6&&e<3.4)off=mix(off,70,smooth(2.6,3.4,e));else if(e>=3.4&&e<4.7)off=mix(70,off,smooth(3.4,4.7,e));else if(e>=4.7){b.lunge=null;b.vulnUntil=t+4}
    if(e>2.75&&e<3.9&&Math.abs(b.x-sub.x)<S.hx+140&&Math.abs(b.y-sub.y)<S.hy+42)damage(2,'The Typhoon rammed the hull.','breach')}
   b.x=sub.x+off;const ty=b.lunge?b.lunge.y:clamp(sub.y+110*Math.sin((t-b.t0)*.5),top,bot);b.y+=clamp((ty-b.y)*1.3,-100,100)*dt;
   if(!b.lunge&&t>b.next){const pick=ph>1&&b.n%3===2?3:b.n%3===0?0:b.n%3===1?1:2;b.n++;
    if(pick===0){const n=3+ph;campVolley(b.x-120,b.y,n,60);sfx.launch()}
    else if(pick===1){for(let i=0;i<2+ph;i++)seeker(b.x-40+i*30,b.y-30,ph);sfx.enemyLaunch()}
    else if(pick===2){const gx=b.x-90,gy=clamp(sub.y,top,bot);for(let y=top-40;y<=bot+40;y+=68)if(Math.abs(y-gy)>S.hy+58)cr.hz.push({k:'fmine',x:gx,y,ph:rnd(0,TAU)})}
    if(pick===3){b.lunge={t0:t,y:clamp(sub.y,top,bot)};toast('RAMMING SPEED','Her depth is locked. Climb or dive clear!',2.6,true);csfx.alarm()}else b.vulnUntil=t+4;
    b.next=t+[4.2,3.6,3.1][ph]}},
  pts(b){return [{x:b.x,y:b.y,r:115,ry:40,armor:t>=b.vulnUntil}]}},
};
function startBoss(k){
 const B=BOSS[k],b={k,hp:B.hp,max:B.hp,t0:t,x:sub.x+900,y:sub.y,hitAt:-9,dead:0};B.init(b);cr.foes=[];cr.hz=[];enemyMissiles=[];gates=gates.filter(g=>g.x<sub.x-200);cr.boss=b;cr.nextAirX=sub.x+900;
 if(k==='kchase'){toast('THE KRAKEN','Do not fight it. Outrun the arms!',3,true);csfx.roar()}
 else{toast(B.name,'Weak points flash when hit. Good hunting, Captain.',3,true);csfx.roar()}
 $('bossName').textContent=B.name;show('bossBar',!!B.hp);
}
function updateBoss(dt){
 if(cm.boss&&!cr.boss&&!cr.bossDone&&sub.x>=cm.boss.at)startBoss(cm.boss.k);
 const c=cm.chase;if(c&&!cr.chased&&sub.x>=c.from&&sub.x<c.to){cr.chased=true;startBoss('kchase')}
 const b=cr.boss;if(!b)return;
 if(b.k==='kchase'&&c&&sub.x>=c.to&&!b.leaving){b.leaving=t;cr.hz=cr.hz.filter(h=>h.k!=='tent');comms('RIGGS','It is falling back! We are clear of it!')}
 if(b.dead){const e=t-b.dead;if(Math.random()<dt*6&&e<2.6)boom(b.x+rnd(-120,120),b.y+rnd(-50,50),rnd(30,60));if(e>3.4){cr.boss=null;cr.bossDone=true;campWin()}return}
 BOSS[b.k].update(b,dt);
}
function bossHit(b,x,y){
 b.hp--;b.hitAt=t;boom(x,y,32);bonus+=60;lastHud=-1;
 if(b.hp<=0){b.dead=t;cr.hz=[];enemyMissiles=[];bonus+=1500;boom(b.x,b.y,90);toast(BOSS[b.k].name.split(' / ')[0]+' DESTROYED','+1,500',3);sfx.sunk();show('bossBar',false)}
 else if(b.hp===Math.floor(b.max/2))toast('IT IS ENRAGED','The attacks are coming faster.',2,true);
}
// Missile targeting hooks (game.js): drifting mines close ahead first, then the boss.
function campAcquire(skip){
 if(!cr)return null;let best=null,bd=Infinity;
 for(const h of cr.hz){if(h.k!=='fmine'||skip.includes(h))continue;const dx=h.x-sub.x;if(dx<S.hx||dx>650||Math.abs(h.y-sub.y)>110)continue;const d=dx+Math.abs(h.y-sub.y)*2;if(d<bd){bd=d;best={camp:h}}}
 if(best)return best;
 for(const f of cr.foes){if(f.dead||!FOES[f.k].pts||skip.includes(f)||f.rel>vw*.85)continue;const d=Math.abs(f.rel);if(d<bd){bd=d;best={camp:f,foe:true}}}
 if(best)return best;
 const b=cr.boss;if(b&&!b.dead&&BOSS[b.k].pts&&!skip.includes(b))return {camp:b,boss:true};
 return null;
}
function campTargetPos(tg){const o=tg.camp;if(!cr)return null;
 if(tg.boss){if(cr.boss!==o||o.dead)return null;const p=BOSS[o.k].pts(o),q=p.find(p=>!p.armor)||p[0];return [q.x,q.y]}
 if(tg.foe){if(!cr.foes.includes(o)||o.dead)return null;const q=FOES[o.k].pts(o)[0];return [q.x,q.y]}
 return cr.hz.includes(o)?[o.x,o.y]:null}
function campMissile(m){
 if(!cr)return false;
 for(const h of cr.hz)if(h.k==='fmine'&&Math.hypot(h.x-m.x,h.y-m.y)<R+6){killHz(h);bonus+=25;minesDestroyed++;return true}
 for(const f of cr.foes){if(f.dead||!FOES[f.k].pts)continue;for(const p of FOES[f.k].pts(f)){const ky=p.ry?p.r/p.ry:1;if(Math.hypot(p.x-m.x,(p.y-m.y)*ky)<p.r){foeHit(f,m.x,m.y);return true}}}
 const b=cr.boss;if(b&&!b.dead&&BOSS[b.k].pts)for(const p of BOSS[b.k].pts(b)){const ky=p.ry?p.r/p.ry:1;if(Math.hypot(p.x-m.x,(p.y-m.y)*ky)<p.r){if(p.armor){boom(m.x,m.y,14);sfx.shield();cr.deflect=t}else bossHit(b,m.x,m.y);return true}}
 return false;
}
function campStrike(){if(!cr)return 0;let n=0;for(const f of cr.foes)if(!f.dead&&FOES[f.k].pts&&f.rel<vw*.85){launch({camp:f,foe:true},-300,5.5);n++}
 const b=cr.boss;if(b&&!b.dead&&BOSS[b.k].pts)for(let i=0;i<3;i++){launch({camp:b,boss:true},-300-i*80,5.5);n++}return n}
function killHz(h){cr.hz.splice(cr.hz.indexOf(h),1);boom(h.x,h.y,34)}

/* ---- Encounters -----------------------------------------------------------------
   Enemies met between checkpoints (m.foes: [x,kind]). Like a boss, each keeps pace
   ahead of the boat (rel = x - sub.x) while it attacks, then breaks off after `dur`
   seconds. Hunter subs fire torpedoes and sow mines, destroyers roll depth charges
   from the surface, octopods grab from cave walls; an ambush is Kraken arms out of the
   rock with nothing to shoot. Sinking one pays a bonus and a little scrap. */
const FOES={
 hunter:{name:'HUNTER SUB',hp:3,dur:16,
  init(f){f.target=rnd(520,680);f.y=safeY(sub.x+f.rel,sub.y+rnd(-90,90),40);f.nextT=t+1.5;f.nextM=t+4.5},
  update(f,dt){const leave=t>f.until;f.rel+=clamp(((leave?vw+800:f.target+80*Math.sin((t-f.t0)*.6))-f.rel)*1.4,-450,450)*dt;f.x=sub.x+f.rel;
   const top=ceilAt(f.x)+55,bot=Math.max(top,terrain(f.x).bottom-55);f.y+=clamp((clamp(sub.y+110*Math.sin((t-f.t0)*.7+f.ph),top,bot)-f.y)*1.3,-110,110)*dt;
   if(!leave&&f.rel<vw*.75){if(t>f.nextT){torp(f.x-50,f.y,.7);f.nextT=t+rnd(1.8,2.5);sfx.launch()}if(t>f.nextM){cr.hz.push({k:'fmine',x:f.x-40,y:f.y,ph:rnd(0,TAU)});f.nextM=t+rnd(4.5,6)}}
   return !(leave&&f.rel>vw+700)},
  pts(f){return [{x:f.x,y:f.y,r:46,ry:22}]}},
 destroyer:{name:'DESTROYER',hp:4,dur:16,
  init(f){f.target=rnd(420,600);f.y=SURFACE;f.nextC=t+1.6;f.nextM=t+3.2},
  update(f,dt){if(terrain(f.x).cave>.03)f.until=Math.min(f.until,t);const leave=t>f.until;f.rel+=clamp(((leave?vw+900:f.target+150*Math.sin((t-f.t0)*.4))-f.rel)*1.2,-450,450)*dt;f.x=sub.x+f.rel;
   if(!leave&&f.rel<vw*.8){if(t>f.nextC){for(let i=0;i<2;i++){const x=f.x-60+i*80;cr.hz.push({k:'charge',x,y:SURFACE+4,vy:30,ty:clamp(sub.y+rnd(-40,40)+(i-.5)*55,SURFACE+70,terrain(x).bottom-50),r:80,spin:rnd(0,TAU)})}f.nextC=t+rnd(1.7,2.4);sfx.splash()}
    if(t>f.nextM){enemyMissiles.push({x:f.x-20,y:SURFACE-26,vx:(sub.x-f.x)*.12+speed*.4,vy:-200-Math.random()*50,air:true,life:7,turn:D.turn*.5,seek:1.3,err:(Math.random()-.5)*100,sp:speed+D.mvel*.45});f.nextM=t+rnd(3.4,4.8);sfx.enemyLaunch()}}
   if(sub.y-S.hy<SURFACE+16&&Math.abs(f.x-sub.x)<125+S.hx)damage(2,'The boat rammed a destroyer.','breach');
   return !(leave&&f.rel>vw+800)},
  pts(f){return [-80,0,80].map(dx=>({x:f.x+dx,y:SURFACE-2,r:32}))}},
 octopod:{name:'OCTOPOD',hp:3,dur:15,
  init(f){f.target=rnd(560,680);f.y=terrain(sub.x+f.rel).centre;f.nextA=t+1.4;f.nextI=t+4.5},
  update(f,dt){const leave=t>f.until;f.rel+=clamp(((leave?vw+800:f.target+40*Math.sin((t-f.t0)*.5))-f.rel)*1.3,-450,450)*dt;f.x=sub.x+f.rel;f.y=mix(f.y,terrain(f.x).centre+30*Math.sin((t-f.t0)*.8),1-Math.exp(-dt*2));
   if(!leave&&f.rel<vw*.75){if(t>f.nextA){spawnArms(f,0,'mother');f.nextA=t+rnd(2.2,2.8)}if(t>f.nextI){const x=sub.x+rnd(320,480);cr.hz.push({k:'ink',x,y:safeY(x,sub.y,20),r:20,R:170,born:t,life:7});f.nextI=t+rnd(7,9)}}
   return !(leave&&f.rel>vw+700)},
  pts(f){return [{x:f.x-52,y:f.y-4,r:26}]}},
 ambush:{name:'THE ROCK IS MOVING',hp:0,dur:10,
  init(f){f.nextA=t+.8},
  update(f){f.x=sub.x+900;if(t<f.until&&t>f.nextA){spawnArms(f,1,'kraken');f.nextA=t+rnd(1.15,1.6)}return t<f.until+2.5}},
};
function spawnFoe(k){
 if(k==='destroyer'&&[0,600,1200].some(dx=>terrain(sub.x+900+dx).cave>.01))k='hunter';
 if(k==='octopod'&&terrain(sub.x+800).cave<.3)k='hunter';
 const F=FOES[k],f={k,hp:F.hp,max:F.hp,t0:t,until:t+F.dur,ph:rnd(0,TAU),hitAt:-9,dead:0,rel:Math.max(vw*.8,700)+260,x:0,y:sub.y};f.x=sub.x+f.rel;F.init(f);cr.foes.push(f);
 if(k==='ambush'){toast(F.name,'Kraken arms out of the walls. Watch for the glow.',2.6,true);csfx.roar()}
 else{toast(F.name+' CONTACT',k==='destroyer'?'Surface ship rolling depth charges. Sink it or slip past.':k==='octopod'?'Something with arms is waiting in the rock.':'Attack sub ahead. Torpedoes in the water!',2.4,true);sfx.enemyLaunch()}
}
function updateFoes(dt){
 for(let i=cr.foes.length-1;i>=0;i--){const f=cr.foes[i];
  if(f.dead){f.rel+=40*dt;f.x=sub.x+f.rel;if(t-f.dead>2.6)cr.foes.splice(i,1);continue}
  // Nobody presses an attack on a boat holding at a recon point.
  if(cr.air||inRecon(sub.x))f.until=Math.min(f.until,t);
  if(!FOES[f.k].update(f,dt))cr.foes.splice(i,1);if(state!=='playing')return}
}
function foeHit(f,x,y){
 f.hp--;f.hitAt=t;boom(x,y,30);lastHud=-1;
 if(f.hp<=0){f.dead=t;bonus+=400;boom(f.x,f.y,60);sfx.sunk();if(f.k==='destroyer')shipsSunk++;addParts([2,0,0]);toast(FOES[f.k].name+' DESTROYED','+400 / +2 SCRAP',2)}
}

/* ---- Hazards ---- */
// A tentacle's spine: from its root to its current reach, curling as it goes.
function tentPts(h,e,n=10){const pts=[],tipY=h.base+(h.tip-h.base)*e;for(let i=0;i<=n;i++){const u=i/n,y=mix(h.base,tipY,u),x=h.x+Math.sin(u*3.2+ambient*2.6+h.x*.01)*16*u+(h.top?-1:1)*u*u*10;pts.push([x,y,h.w*(1-.68*u)])}return pts}
function tentReach(h){const a=t-h.born;if(a<h.warn)return 0;let e=a-h.warn;if(e<h.ext)return smooth(0,1,e/h.ext);e-=h.ext;if(e<h.hold)return 1;e-=h.hold;return e<h.ret?1-smooth(0,1,e/h.ret):-1}
function sweepReach(h){const a=t-h.born;if(a<h.warn)return 0;let e=a-h.warn;if(e<h.ext)return smooth(0,1,e/h.ext);e-=h.ext;if(e<h.hold)return 1;e-=h.hold;return e<h.ret?1-smooth(0,1,e/h.ret):-1}
const hitsSub=(x,y,r)=>{const dx=(x-sub.x)/(S.hx+r),dy=(y-sub.y)/(S.hy+r);return dx*dx+dy*dy<1};
function updateHazards(dt){
 for(let i=cr.hz.length-1;i>=0;i--){
  const h=cr.hz[i];if(!h)continue;
  if(h.k==='tent'){const e=tentReach(h);if(e<0){cr.hz.splice(i,1);continue}
   if(e>.2&&t>=invulnUntil){for(const [x,y,w] of tentPts(h,e,8))if(hitsSub(x,y,w*.85)){damage(1,h.who==='mother'?'Old Mother’s arm crushed the hull.':'The Kraken’s arm crushed the hull.','ballast');break}}}
  else if(h.k==='sweep'){const e=sweepReach(h);if(e<0){cr.hz.splice(i,1);continue}const b=cr.boss;if(!b){cr.hz.splice(i,1);continue}
   h.tipX=b.x-120-(b.x-120-(sub.x-500))*e;if(e>.55&&sub.x>h.tipX-S.hx&&Math.abs(sub.y-h.y)<h.h+S.hy*.6)damage(1,'The Kraken swept the boat into the trench wall.','random')}
  else if(h.k==='charge'){h.vy=Math.min(h.vy+300*dt,145);h.y+=h.vy*dt;h.spin+=dt*3;
   if(h.y>=h.ty||h.y>terrain(h.x).bottom-10){cr.hz.splice(i,1);boom(h.x,h.y,48);shake=Math.max(shake,reduced?0:4);if(Math.hypot((h.x-sub.x)*.8,h.y-sub.y)<h.r+S.hy)damage(1,'A depth charge burst beside the hull.','random')}}
  else if(h.k==='ink'){if(t-h.born>h.life){cr.hz.splice(i,1);continue}h.r=mix(h.r,h.R,1-Math.exp(-dt*2.2));if(Math.hypot(h.x-sub.x,h.y-sub.y)<h.r*.85){cr.inked=t+.4;sonarDownUntil=Math.max(sonarDownUntil,t+1.2)}}
  else if(h.k==='fmine'){const y=h.y+Math.sin(ambient*1.2+h.ph)*6;if(hitsSub(h.x,y,R*.9)){killHz(h);damage(2,'A drifting mine detonated against the hull.','breach')}}
  if(state!=='playing')return;
  const j=cr.hz.indexOf(h);if(j>=0&&h.x<sub.x-900)cr.hz.splice(j,1);
 }
}

/* ---- Radio, cut-ins and sound ---- */
const commsQ=[];let commsUntil=0;
const speakerName=w=>w==='YOU'?'CAPTAIN '+callsign().toUpperCase():CAST[w].name;
function comms(w,text){commsQ.push([w,text]);if(commsQ.length>4)commsQ.splice(1,1)}
function commsTick(){
 const box=$('comms');if(performance.now()<commsUntil)return;
 if(!commsQ.length){box.classList.remove('show');return}
 const [w,text]=commsQ.shift(),C=CAST[w],pc=$('commsPort');pc.hidden=w==='NARR';if(w!=='NARR')paintPortrait(pc.getContext('2d'),w,pc.width,pc.height,1.2,false);
 $('commsWho').textContent=speakerName(w)+(C.role?' / '+C.role:'');$('commsWho').style.color=C.c;$('commsText').textContent=text;
 box.classList.add('show');commsUntil=performance.now()+clamp(text.length*32,2200,5500);csfx.radio();
}
const typer={el:null,text:'',i:0,timer:0};
function typeText(el,text){clearInterval(typer.timer);typer.el=el;typer.text=text;typer.i=text.length;el.textContent=text}
function typeDone(){if(typer.el&&typer.i<typer.text.length){clearInterval(typer.timer);typer.i=typer.text.length;typer.el.textContent=typer.text;return false}return true}
function campCut(lines){cr.cut={lines,i:0};state='cut';clearInput();$('letterbox').classList.remove('on');show('letterbox',true);requestAnimationFrame(()=>{if(cr&&cr.cut)$('letterbox').classList.add('on')});cutShow()}
function cutShow(){const [w,text]=cr.cut.lines[cr.cut.i],C=CAST[w],pc=$('cutPort');$('cutWho').textContent=speakerName(w);$('cutWho').style.color=C.c;paintPortrait(pc.getContext('2d'),w,pc.width,pc.height,.5,false);typeText($('cutText'),text)}
function cutNext(){
 if(!cr||!cr.cut)return;if(!typeDone())return;cr.cut.i++;
 if(cr.cut.i<cr.cut.lines.length)return cutShow();
 cr.cut=null;$('letterbox').classList.remove('on');setTimeout(()=>{if(!cr||!cr.cut)show('letterbox',false)},450);
 state='playing';last=performance.now();acc=0;clearInput();
}
const csfx={
 checkpoint(){if(!audible())return;const at=audio.currentTime;[523,784,1047].forEach((f,i)=>osc('sine',f,f,at+i*.09,.5,.045,sfxBus,{verb:.5}))},
 relic(){if(!audible())return;const at=audio.currentTime;[659,880,1175,1568].forEach((f,i)=>osc('triangle',f,f*1.01,at+i*.07,.6,.035,sfxBus,{verb:.7}))},
 salvage(){if(!audible())return;const at=audio.currentTime;osc('square',220,330,at,.12,.03,sfxBus,{cut:1400});osc('square',330,440,at+.12,.14,.03,sfxBus,{cut:1400});noise(at,.3,.05,sfxBus,{type:'bandpass',f:800,end:2000,q:3})},
 drone(){if(!audible())return;const at=audio.currentTime;osc('sawtooth',180,520,at,.5,.025,sfxBus,{cut:900,cutEnd:2400,verb:.3})},
 boost(){if(!audible())return;const at=audio.currentTime;noise(at,.7,.09,sfxBus,{type:'bandpass',f:300,end:3000,q:1.2,verb:.3});osc('sawtooth',90,240,at,.6,.05,sfxBus,{cut:600,cutEnd:2400})},
 radio(){if(!audible())return;const at=audio.currentTime;noise(at,.12,.03,sfxBus,{type:'bandpass',f:2400,q:4});osc('sine',1400,1400,at+.1,.06,.015)},
 roar(){if(!audible())return;const at=audio.currentTime;osc('sawtooth',55,32,at,2.6,.12,sfxBus,{cut:300,a:.5,verb:.8});noise(at,2.4,.1,sfxBus,{f:400,end:90,a:.6,verb:.6})},
 lid(){if(!audible())return;const at=audio.currentTime;osc('sine',90,60,at,.6,.12,sfxBus,{verb:.5})},
 alarm(){if(!audible())return;const at=audio.currentTime;for(let i=0;i<3;i++)osc('square',740,560,at+i*.22,.18,.025,sfxBus,{cut:2000})},
 win(){if(!audible())return;const at=audio.currentTime;[392,494,587,784].forEach((f,i)=>osc('triangle',f,f,at+i*.12,1.2-i*.1,.05,sfxBus,{verb:.7}))},
};
