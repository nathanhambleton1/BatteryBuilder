'use strict';
/* ---- Leaderboard ----------------------------------------------------------
   Every run is saved on this computer and waits in the score journal until the
   player presses Save (manual-save.js). Posting takes a short-lived lock file so
   players write one at a time, re-reads the board, merges by entry id, writes it,
   then reads it back to confirm the entry landed. Nothing here reads or writes the
   shared drive on a timer: the board on screen is the copy from the last Save or
   Refresh, kept in this browser. */
const BOARD_CAP=5000, sleep=ms=>new Promise(r=>setTimeout(r,ms));
function cleanEntry(e){if(!e||typeof e!=='object')return null;const s=Math.floor(Number(e.score));if(!Number.isFinite(s)||s<0||s>1e9)return null;return {id:String(e.id||Math.random()).slice(0,40),name:String(e.name||'Anonymous').replace(/[\u0000-\u001f]/g,'').slice(0,16)||'Anonymous',score:s,distance:Math.max(0,Math.floor(Number(e.distance)||0)),sub:SUB_BY_ID[e.sub]?e.sub:'virginia',diff:DIFFS[e.diff]?e.diff:'officer',ships:Math.max(0,Math.floor(Number(e.ships)||0)),date:String(e.date||'').slice(0,10),...entryAt(e)}}
// Runs since the time was added carry at: epoch ms. Older ones only have a UTC date, shown as is.
function entryAt(e){const at=Math.floor(Number(e.at));return Number.isFinite(at)&&at>1e12&&at<1e13?{at}:{}}
function whenText(e){if(!e.at)return e.date||'';const d=new Date(e.at),p=n=>String(n).padStart(2,'0');return d.getFullYear()+'-'+p(d.getMonth()+1)+'-'+p(d.getDate())+' '+p(d.getHours())+':'+p(d.getMinutes())}
function mergeEntries(a,b){const m=new Map();for(const e of [...a,...b])m.set(e.id,e);return [...m.values()].sort((x,y)=>y.score-x.score)}
// Achievements in the shared file: players[lower-case callsign] = {name, ach:{id:date}, xp}. Unions and maximums only, never removals.
function mergePlayer(a,b){if(!a)return b;if(!b)return a;const m={...b.ach};for(const [id,d] of Object.entries(a.ach))if(!m[id]||d<m[id])m[id]=d;return {name:b.name||a.name,ach:m,xp:Math.max(a.xp||0,b.xp||0)}}
function cleanPlayers(p){const out={};if(p&&typeof p==='object'&&!Array.isArray(p))for(const v of Object.values(p)){if(!v||typeof v!=='object')continue;const name=String(v.name||'').replace(/[\u0000-\u001f]/g,'').trim().slice(0,16);if(!name)continue;const a={};if(v.ach&&typeof v.ach==='object')for(const [id,d] of Object.entries(v.ach))if(ACH_BY_ID[id])a[id]=String(d||'').slice(0,10);const k=name.toLowerCase();out[k]=mergePlayer(out[k],{name,ach:a,xp:Math.max(0,Math.floor(+v.xp||0))})}return out}
function mergePlayers(a,b){const o={...a};for(const [k,v] of Object.entries(b))o[k]=mergePlayer(o[k],v);return o}
function myPlayer(){const name=callsign(),xp=profXp();if(name==='Anonymous'||!Object.keys(ach.un).length&&!xp)return null;return {name,ach:{...ach.un},xp}}
function playerCurrent(players){const me=myPlayer();if(!me)return true;if(lb.admin&&lb.admin.players[me.name.toLowerCase()])return true;const p=players[me.name.toLowerCase()];return !!p&&Object.keys(me.ach).every(id=>p.ach[id])&&(p.xp||0)>=me.xp}
const included=(list,e)=>list.some(x=>x.id===e.id);
// Where this page lives, e.g. \\SERVER\Share\Games\ or Z:\Games\, shown so players pick the right folder.
const PAGE_NAME=(()=>{try{return decodeURIComponent(location.pathname.split('/').pop()||'')}catch(_){return ''}})();
const GAME_DIR=(()=>{try{if(location.protocol!=='file:')return '';const p=decodeURIComponent(location.pathname);return (location.host?'\\\\'+location.host:'')+p.slice(0,p.lastIndexOf('/')+1).replace(/^\/([A-Za-z]:)/,'$1').replace(/\//g,'\\')}catch(_){return ''}})();
// The one folder the whole team shares. A page cannot open a folder by path, so each PC/browser
// points at it once; the handle is kept in IndexedDB and access is re-asked on load if needed.
const SHARED_DIR='G:\\Nathan Hambleton\\Submarine Photos\\Undertow', SHARED_NAME='shared folder';
const sameDir=(a,b)=>!!a&&!!b&&a.replace(/\\+$/,'').toLowerCase()===b.replace(/\\+$/,'').toLowerCase();
const lb={supported:typeof window.showDirectoryPicker==='function',dir:null,perm:'none',loaded:0,shared:[],players:{},admin:{entries:{},players:{},aliases:{}},achView:'path',achWho:'',local:(store.get('undertow.local.v1',[])||[]).map(cleanEntry).filter(Boolean),source:'shared',filter:'all',note:'',warn:'',gate:{ready:false,offline:false,msg:'',repick:false,busy:false},mine:new Set(store.get('undertow.mine.v1',[]))};
if(!lb.supported)lb.source='local';
$('lbPath').textContent=SHARED_DIR+'\\'+BOARD_FILE;
function idb(mode,fn){return new Promise((res,rej)=>{let open;try{open=indexedDB.open('undertow-offline',1)}catch(e){rej(e);return}open.onupgradeneeded=()=>open.result.createObjectStore('kv');open.onerror=()=>rej(open.error);open.onsuccess=()=>{const db=open.result;let tx,req;try{tx=db.transaction('kv',mode);req=fn(tx.objectStore('kv'))}catch(e){db.close();rej(e);return}tx.oncomplete=()=>{db.close();res(req.result)};tx.onerror=tx.onabort=()=>{db.close();rej(tx.error)}}})}
const idbGet=k=>idb('readonly',s=>s.get(k)), idbSet=(k,v)=>idb('readwrite',s=>s.put(v,k)), idbDel=k=>idb('readwrite',s=>s.delete(k));
const pending=()=>journalPending();
async function readText(name,dir=lb.dir){return (await (await dir.getFileHandle(name)).getFile()).text()}
async function writeText(name,text,dir=lb.dir){const w=await (await dir.getFileHandle(name,{create:true})).createWritable();try{await w.write(text);await w.close()}catch(e){try{await w.abort()}catch(_){}throw e}}
async function lbPermitted(ask){if(!lb.dir)return false;const o={mode:'readwrite'};try{if(await lb.dir.queryPermission(o)==='granted')return true;if(ask&&await lb.dir.requestPermission(o)==='granted')return true}catch(_){}return false}
async function lbRead(){
 for(let i=0;;i++){
  let text='';try{text=await readText(BOARD_FILE)}catch(e){if(e&&e.name==='NotFoundError')return lbFallback();if(i>=3)throw e;await sleep(120);continue}
  if(!text.trim())return lbFallback();
  const board=parseBoard(unseal(text));if(board)return board;
  // Unreadable or altered. It may be mid-replace, so look again, then use the backup.
  if(i>=3){const bak=await readBoard(BACKUP_FILE);if(bak)return bak;throw new Error(BOARD_FILE+' is not a readable Undertow leaderboard.')}await sleep(150);
 }
}
function parseBoard(text){if(text==null)return null;try{const data=JSON.parse(text),list=Array.isArray(data)?data:data&&Array.isArray(data.entries)?data.entries:null;if(list){const admin=cleanBoardAdmin(data.admin);return {entries:boardAdminEntries(list.map(cleanEntry).filter(Boolean),admin),players:boardAdminPlayers(cleanPlayers(data.players),admin),admin}}}catch(_){}return null}
async function readBoard(name){try{return parseBoard(unseal(await readText(name)))}catch(_){return null}}
// No board yet: use the backup, else import the old plain bin.json.
async function lbFallback(){let legacy=null;try{legacy=parseBoard(await readText(LEGACY_FILE))}catch(_){}return await readBoard(BACKUP_FILE)||legacy||{entries:[],players:{}}}
async function withLock(fn){
 const dir=lb.dir,me=crypto.randomUUID(),begun=performance.now();let got=false;
 while(!got&&performance.now()-begun<4500){
  let holder=null,modified=0;try{const file=await (await dir.getFileHandle(LOCK_FILE)).getFile();modified=file.lastModified||0;holder=JSON.parse(await file.text())}catch(_){}
  if(!holder||Date.now()-(holder.at||modified)>120000){await writeText(LOCK_FILE,JSON.stringify({id:me,at:Date.now()}),dir);await sleep(80+Math.random()*80);try{got=JSON.parse(await readText(LOCK_FILE,dir)).id===me}catch(_){}}
  if(!got)await sleep(100+Math.random()*100);
 }
 if(!got)throw Error('The shared drive is busy. Your local scores remain queued.');
 const owns=async()=>{const lock=JSON.parse(await readText(LOCK_FILE,dir));if(lock.id!==me)throw Error('Shared save ownership changed. Retrying safely.');};
 try{return await fn(true,owns)}finally{try{await owns();await dir.removeEntry(LOCK_FILE)}catch(_){}}
}
async function lbFlush(){
 const me=myPlayer();
 return withLock(async (locked,owns)=>{
  for(let attempt=0;attempt<6;attempt++){
   let {entries:list,players,admin}=await lbRead();admin=cleanBoardAdmin(admin);lb.admin=admin;journalReconcile({entries:list,admin});
   const missing=pending().filter(e=>!admin.entries[e.id]&&!included(list,e));
   if(missing.length||!playerCurrent(players)){
    const merged=me?mergePlayers(players,{[me.name.toLowerCase()]:me}):players;
    const text=seal(JSON.stringify({game:'UNDERTOW',version:4,updated:new Date().toISOString(),entries:boardAdminEntries(mergeEntries(list,missing),admin),players:boardAdminPlayers(merged,admin),admin}));
    try{await owns();await writeText(BOARD_FILE,text);await owns();await writeText(BACKUP_FILE,text)}catch(_){await sleep(100+Math.random()*250);continue}
    // Without the lock another write may land on top, so give it a moment first.
    if(!locked)await sleep(80+Math.random()*120);({entries:list,players,admin}=await lbRead());lb.admin=cleanBoardAdmin(admin);
   }
   if(pending().every(e=>lb.admin.entries[e.id]||included(list,e))&&playerCurrent(players)){await owns();journalAcknowledge(pending());lb.shared=list;lb.players=players;return}
   await sleep(100+Math.random()*250);
  }
  throw new Error('the file was busy.');
 });
}
let lbChain=Promise.resolve();
// The last board read from the shared drive, so the leaderboard shows without touching it.
const BOARD_CACHE='undertow.board-cache.v1';
// Only redraws. The drive is read by boardRefresh and written by saveAll, both from a click.
function lbSync(){renderBoard();return Promise.resolve(!!lb.loaded)}
function lbTake(r){lb.admin=cleanBoardAdmin(r.admin);lb.shared=boardAdminEntries(r.entries,lb.admin);lb.players=boardAdminPlayers(r.players,lb.admin);lb.loaded=Date.now();store.set(BOARD_CACHE,{entries:lb.shared,players:lb.players,admin:lb.admin,at:lb.loaded})}
function lbCached(){const c=store.get(BOARD_CACHE,null);if(!c||!Array.isArray(c.entries))return;const admin=cleanBoardAdmin(c.admin);lb.admin=admin;lb.shared=boardAdminEntries(c.entries.map(cleanEntry).filter(Boolean),admin);lb.players=boardAdminPlayers(cleanPlayers(c.players),admin);lb.loaded=Math.max(0,+c.at||0)}
// The shared-folder gate never opens in this edition: the folder is chosen from Save or the Leaderboard screen.
function sfShouldShow(){return false}
function sfRender(){$('sfGate').hidden=true}
async function sfCheck(){}
async function submitScore(entry){return persistScore(entry)}
function describeSave(res){
 if(!lastEntry)return;if(res!=='storage-error'&&lb.shared.some(e=>e.id===lastEntry.id)&&!pending().some(e=>e.id===lastEntry.id))res='shared';const list=res==='shared'?lb.shared:lb.local,rank=list.findIndex(e=>e.id===lastEntry.id)+1;
 const msg={'storage-error':'Browser storage is unavailable. Press Save now to keep this score.',shared:'Saved to the shared leaderboard'+(rank?`: rank ${rank} of ${list.length}.`:'.'),pending:'Kept on this computer. Press Save (top right) to post it to the shared leaderboard.',local:'Shared folders need Microsoft Edge or Google Chrome. Score kept on this computer.'}[res];
 $('saveNote').textContent=msg;
}
function renderEarned(){const box=$('achEarned');box.textContent='';
 if(run.gain>0){const sp=document.createElement('span');sp.className='xp-gain';sp.append(svgIcon('i-medal'),'+'+run.gain.toLocaleString()+' XP / '+(run.promoted?'PROMOTED TO LEVEL '+run.promoted:'LEVEL '+levelOf(profXp())));box.append(sp)}
 for(const id of run.earned){const a=ACH_BY_ID[id],sp=document.createElement('span'),i=document.createElementNS('http://www.w3.org/2000/svg','svg'),u=document.createElementNS('http://www.w3.org/2000/svg','use');i.setAttribute('class','ic');u.setAttribute('href','#i-medal');i.append(u);sp.append(i,a.name.toUpperCase());box.append(sp)}}
function cell(tr,text,cls){const td=document.createElement('td');td.textContent=text;if(cls)td.className=cls;tr.append(td)}
function renderBoard(){
 if(state==='over'&&lastEntry)describeSave(!lb.supported?'local':'pending');
 const useShared=lb.source==='shared',queued=pending(),unsaved=new Set(queued.map(e=>e.id));
 let msg=!lb.supported?'This browser cannot use shared folders. Use Microsoft Edge or Google Chrome for the shared leaderboard. Scores are kept on this computer.':lb.loaded?`Shared leaderboard as of ${whenText({at:lb.loaded})} · ${lb.shared.length} records. Refresh reads the latest copy.`:'The shared leaderboard has not been loaded on this computer yet. Press Refresh or Save.';
 if(lb.supported&&queued.length)msg+=` ${queued.length} unsaved score${queued.length>1?'s':''} — press Save (top right) to post ${queued.length>1?'them':'it'}.`;if(lb.warn)msg+=' '+lb.warn;if(lb.note)msg+=' '+lb.note;
 $('lbStatus').textContent=msg;
 $('lbConnect').hidden=true;$('lbRefresh').disabled=!lb.supported||saveJob.busy;
 $('lbConnect').querySelector('span').textContent=lb.dir?'Change shared folder':'Choose shared folder';
 document.querySelectorAll('#srcSeg button').forEach(b=>{b.setAttribute('aria-pressed',String(b.dataset.src===lb.source));if(b.dataset.src==='shared')b.disabled=!lb.supported});
 document.querySelectorAll('#filterSeg button').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.filter===lb.filter)));
 const body=$('lbBody');body.textContent='';
 // Your unsaved runs are placed among the shared ones so you can see where they would land.
 const rows=(useShared?boardAdminEntries(mergeEntries(lb.shared,queued),lb.admin):boardAdminEntries(lb.local,localBoardAdmin())).filter(e=>lb.filter==='all'||e.diff===lb.filter).slice(0,50);
 if(!rows.length){const tr=document.createElement('tr');cell(tr,useShared&&!lb.loaded?'Press Refresh to load everyone\u2019s scores.':'No scores yet. Be the first on the board.','empty');tr.firstChild.colSpan=7;body.append(tr)}
 rows.forEach((e,i)=>{const tr=document.createElement('tr');if(duelKey(e.name)===prof.key)tr.className='me';cell(tr,i+1);cell(tr,e.name,'name');cell(tr,e.score.toLocaleString(),'num');cell(tr,e.distance+' m','num hide-sm');cell(tr,SUB_BY_ID[e.sub].name,'hide-sm');cell(tr,DIFFS[e.diff].label);cell(tr,whenText(e)+(useShared&&unsaved.has(e.id)?' · UNSAVED':''),'hide-sm');if(useShared&&unsaved.has(e.id)){tr.classList.add('unsaved');tr.title='Not on the shared drive yet. Press Save.'}body.append(tr)});
 renderChip();if(panel==='ach')renderAch();
}
// The fleet is everyone in the shared file plus you, ranked by achievements held.
function fleet(){const me=myPlayer(),all=boardAdminPlayers(mergePlayers(lb.players,me?{[me.name.toLowerCase()]:me}:{}),lb.admin);return Object.values(all).map(p=>({...p,n:Object.keys(p.ach).length,last:Object.values(p.ach).sort().pop()||''})).filter(p=>p.n).sort((a,b)=>b.n-a.n||a.last.localeCompare(b.last))}
function svgIcon(id){const i=document.createElementNS('http://www.w3.org/2000/svg','svg'),u=document.createElementNS('http://www.w3.org/2000/svg','use');i.setAttribute('class','ic');u.setAttribute('href','#'+id);i.append(u);return i}
function renderAch(){
 const v=lb.achView,F=fleet(),meKey=callsign().toLowerCase(),other=lb.achWho&&lb.achWho!==meKey?F.find(p=>p.name.toLowerCase()===lb.achWho):null;
 document.querySelectorAll('#achSeg button').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.v===v)));
 $('achPathView').hidden=v!=='path';$('achFleetView').hidden=v!=='fleet';
 const held=other?other.ach:ach.un,n=ACHS.filter(a=>held[a.id]).length;
 const lvl=levelOf(other?other.xp||0:profXp());
 $('achNum').textContent=n+' / '+ACHS.length;$('achWho').textContent=(other?other.name.toUpperCase()+'\u2019S RECORD':'YOUR RECORD')+' / LEVEL '+lvl+' '+rankTitle(lvl);$('achBar').style.width=(n/ACHS.length*100)+'%';
 const path=$('achPath');path.textContent='';
 TIERS.forEach(([tn,sub],ti)=>{const list=ACHS.filter(a=>a.tier===ti),got=list.filter(a=>held[a.id]).length;
  const h=document.createElement('div');h.className='ach-tier';h.textContent=tn;const sm=document.createElement('small');sm.textContent=sub.toUpperCase()+' / '+got+' OF '+list.length;h.append(sm);path.append(h);
  const grid=document.createElement('div');grid.className='ach-grid';
  for(const a of list){const card=document.createElement('div'),has=held[a.id];card.className='ach'+(has?' got':'');
   const b=document.createElement('b');b.textContent=a.name.toUpperCase();const d=document.createElement('span');d.textContent=a.desc;const em=document.createElement('em');
   const holders=F.filter(p=>p.ach[a.id]).length;
   if(has)em.textContent='UNLOCKED '+has+(F.length>1?' / '+holders+' OF '+F.length+' SAILORS':'');
   else if(other)em.textContent='LOCKED'+(F.length>1?' / '+holders+' OF '+F.length+' SAILORS':'');
   else{const cur=Math.min(ach.best[a.id]||0,a.goal),u=document.createElement('u'),i=document.createElement('i');i.style.width=(cur/a.goal*100)+'%';u.append(i);em.append(u,a.goal>1?cur.toLocaleString()+' / '+a.goal.toLocaleString():'LOCKED')}
   card.append(svgIcon(has?'i-medal':'i-lock'),b,d,em);grid.append(card)}
  path.append(grid)});
 $('achFleetNote').textContent=(lb.loaded?'Sailors on the shared leaderboard as of your last Save or Refresh, ranked by achievements. ':'Press Refresh on the Leaderboard screen to see other sailors. ')+'Select a callsign to see their record.'+(callsign()==='Anonymous'?' Set a callsign on the home screen to post your own.':'');
 const body=$('achFleet');body.textContent='';
 if(!F.length){const tr=document.createElement('tr');cell(tr,'No achievements posted yet.','empty');tr.firstChild.colSpan=4;body.append(tr)}
 F.forEach((p,i)=>{const tr=document.createElement('tr'),k=p.name.toLowerCase();if(k===meKey)tr.className='me';if(k===lb.achWho)tr.classList.add('sel');cell(tr,i+1);cell(tr,p.name+(p.xp?' / LV '+levelOf(p.xp):''),'name');
  const td=document.createElement('td'),m=document.createElement('span'),mi=document.createElement('i');m.className='meter';mi.style.width=(p.n/ACHS.length*100)+'%';m.append(mi);td.append(m,p.n+' / '+ACHS.length);tr.append(td);
  const la=p.last?Object.keys(p.ach).find(id=>p.ach[id]===p.last):'';cell(tr,la?ACH_BY_ID[la].name:'','hide-sm');
  tr.onclick=()=>{lb.achWho=k;lb.achView='path';renderAch()};body.append(tr)});
}
function renderChip(){$('achCount').textContent=achCountText();const ch=$('lbChip'),n=lb.supported?pending().length:0;ch.classList.toggle('on',!!lb.loaded&&!n);ch.classList.toggle('warn',!!n);ch.querySelector('span').textContent=!lb.supported?'LEADERBOARD / THIS COMPUTER':n?n+' UNSAVED SCORE'+(n>1?'S':'')+' / PRESS SAVE':lb.loaded?'SHARED BOARD / '+whenText({at:lb.loaded}):'SHARED BOARD NOT LOADED YET'}
$('lbConnect').onclick=()=>lbPick(true);
$('lbRefresh').onclick=()=>boardRefresh();
$('sfGo').onclick=()=>lbPick();
$('sfRepick').onclick=()=>lbPick(true);
$('sfOffline').onclick=()=>{lb.gate.offline=true;lb.gate.msg='';sfRender();renderBoard()};
// While the gate is up, keep keys and clicks from reaching the game (Space would start a dive).
for(const ev of ['keydown','keyup'])addEventListener(ev,e=>{if(!$('sfGate').hidden)e.stopPropagation()},true);
for(const ev of ['pointerdown','pointerup','mousedown','mouseup','touchstart','touchend','contextmenu','wheel'])$('sfGate').addEventListener(ev,e=>e.stopPropagation());
addEventListener('focus',()=>sfCheck());document.addEventListener('visibilitychange',()=>{if(!document.hidden)sfCheck()});
document.querySelectorAll('#srcSeg button').forEach(b=>b.onclick=()=>{lb.source=b.dataset.src;renderBoard()});
document.querySelectorAll('#filterSeg button').forEach(b=>b.onclick=()=>{lb.filter=b.dataset.filter;renderBoard()});
// On load: only this browser's copies. A remembered folder handle is restored without asking for access.
async function initializeSharedScores(){
 await journalRestore();lbCached();
 lb.dir=null;lb.perm='none';lb.gate.ready=true;
 if(lb.supported)try{const dir=await idbGet('folder');if(dir&&dir.kind==='directory')lb.dir=dir}catch(_){}
 renderBoard();renderSaveStatus();
}
