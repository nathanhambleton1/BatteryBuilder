'use strict';
/* ---- Leaderboard ----------------------------------------------------------
   Every run is saved on this computer, then queued for bin.dat. Posting takes a
   short-lived lock file so players write one at a time, re-reads the board,
   merges by entry id, writes it, then reads it back to confirm the entry landed.
   If another player's write replaced it, it merges and writes again, so several
   people can finish at once without losing scores. Failures retry on their own. */
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
const SHARED_DIR='your chosen shared folder', SHARED_NAME='shared folder';
const sameDir=(a,b)=>!!a&&!!b&&a.replace(/\\+$/,'').toLowerCase()===b.replace(/\\+$/,'').toLowerCase();
const lb={supported:false,dir:null,perm:'none',shared:[],players:{},admin:{entries:{},players:{}},achView:'path',achWho:'',local:(store.get('undertow.local.v1',[])||[]).map(cleanEntry).filter(Boolean),source:'shared',filter:'all',note:'',warn:'',gate:{ready:false,offline:false,msg:'',repick:false,busy:false},mine:new Set(store.get('undertow.mine.v1',[]))};
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
 const queue=pending(),me=myPlayer();
 return withLock(async (locked,owns)=>{
  for(let attempt=0;attempt<6;attempt++){
   let {entries:list,players,admin}=await lbRead();admin=cleanBoardAdmin(admin);lb.admin=admin;
   const missing=queue.filter(e=>!admin.entries[e.id]&&!included(list,e));
   if(missing.length||!playerCurrent(players)){
    const merged=me?mergePlayers(players,{[me.name.toLowerCase()]:me}):players;
    const text=seal(JSON.stringify({game:'UNDERTOW',version:4,updated:new Date().toISOString(),entries:boardAdminEntries(mergeEntries(list,missing),admin),players:boardAdminPlayers(merged,admin),admin}));
    try{await owns();await writeText(BOARD_FILE,text);await owns();await writeText(BACKUP_FILE,text)}catch(_){await sleep(100+Math.random()*250);continue}
    // Without the lock another write may land on top, so give it a moment first.
    if(!locked)await sleep(80+Math.random()*120);({entries:list,players,admin}=await lbRead());lb.admin=cleanBoardAdmin(admin);
   }
   if(queue.every(e=>lb.admin.entries[e.id]||included(list,e))&&playerCurrent(players)){await owns();journalAcknowledge(queue);lb.shared=list;lb.players=players;return}
   await sleep(100+Math.random()*250);
  }
  throw new Error('the file was busy.');
 });
}
// One sync at a time per page; a failed post retries itself a few times.
let lbChain=Promise.resolve(),retryTimer=0,retries=0;
function lbSync(ask){return queueBoardSync(ask)}
async function syncNow(ask){
 if(!lb.dir){lb.perm='none';if(pending().length)saveStatus('scores','queued','Shared drive not connected · Backup safe');renderBoard();return false}
 if(!await lbPermitted(ask)){lb.perm='prompt';saveStatus('scores','queued','Shared drive needs access · Backup safe');renderBoard();return false}
 lb.perm='granted';saveStatus('scores','busy','Checking the shared drive…');
 try{const r=await lbRead();journalReconcile(r);lb.shared=r.entries;lb.players=r.players;lb.admin=cleanBoardAdmin(r.admin);if(pending().length||!playerCurrent(r.players))await lbFlush();lb.note='';retries=0;if(!prof.pulled)profSync();saveStatus('scores',pending().length?'queued':'done',pending().length?'Shared-drive uploads pending · Retrying automatically':'Scores saved to the shared drive')}
 catch(e){retries++;lb.note='Could not update '+BOARD_FILE+': '+(e&&e.message||e)+'. Local scores will retry automatically.';clearTimeout(retryTimer);retryTimer=setTimeout(()=>lbSync(false),Math.min(30000,1500*Math.pow(2,Math.min(retries,5))));saveStatus('scores','queued','Shared drive unavailable · Retrying automatically · Backup safe');renderBoard();return false}
 renderBoard();return true;
}
/* Shared-folder gate. Called from a click (needs a user gesture): with a stored handle it asks for
   access again (Chrome/Edge then offer "Allow on every visit"); without one, or if the stored handle
   is unusable, it opens the folder picker and checks the pick really is the shared game folder. */
async function lbPick(repick){
 const g=lb.gate;if(!lb.supported||g.busy)return false;if(repick===true)g.repick=true;g.busy=true;g.msg='';sfRender();
 try{
  if(lb.dir&&!g.repick){
   let st='denied';
   try{st=await lb.dir.requestPermission({mode:'readwrite'})}
   catch(e){g.msg='Your folder is remembered. Click Allow access to reopen the browser permission prompt. You do not need to choose the folder again.';return false}
   if(st!=='granted'){g.msg='Access was not allowed. Select Allow access again and choose Allow (or Allow on every visit) in the browser prompt. If the browser no longer asks, use Pick the folder again below.';return false}
  }else if(!await sfPick())return false;
  g.repick=false;g.msg='';lb.source='shared';lb.note='';
  return await lbSync(false);
 }catch(e){g.msg='Could not open the folder: '+(e&&e.message||e);return false}
 finally{g.busy=false;renderBoard();sfRender()}
}
async function sfPick(){return false}
function sfShouldShow(){const g=lb.gate;return lb.supported&&g.ready&&!g.offline&&lb.perm!=='granted'&&state!=='playing'&&!(duel&&(duel.run||duel.watch))}
function sfRender(){
 const g=lb.gate,box=$('sfGate'),was=!box.hidden,on=sfShouldShow();box.hidden=!on;if(!on)return;
 const first=!lb.dir||g.repick,here=sameDir(GAME_DIR,SHARED_DIR);
 $('sfTitle').textContent=first?'Connect the shared folder':'Allow the shared folder';
 $('sfBody').textContent='UNDERTOW saves the leaderboard, duels and your profile to the team’s shared folder:';
 $('sfPath').textContent=SHARED_DIR;
 $('sfHint').textContent='Choose the folder your team uses for shared game data. It may be anywhere and does not need to contain the game. Everyone must choose the same folder. You can change it with Connect shared folder.';
 $('sfGo').querySelector('span').textContent=first?'CHOOSE '+SHARED_NAME.toUpperCase():'ALLOW ACCESS';$('sfGo').disabled=g.busy;
 $('sfMsg').textContent=g.msg;$('sfMsg').hidden=!g.msg;
 $('sfRepick').hidden=!(lb.dir&&!g.repick&&g.msg);
 if(!was)$('sfGo').focus({preventScroll:true});
}
// Re-check when the page comes back; only bring the gate back if access was actually lost.
async function sfCheck(){
 if(!lb.supported||!lb.gate.ready||lb.gate.busy||document.hidden)return;
 const ok=await lbPermitted(false);
 if(ok&&lb.perm!=='granted')await lbSync(false);
 else if(!ok&&lb.perm==='granted'){lb.gate.offline=false;lb.perm=lb.dir?'prompt':'none';renderBoard()}
 sfRender();
}
async function submitScore(entry){return persistScore(entry)}
function describeSave(res){
 if(!lastEntry)return;if(res!=='storage-error'&&lb.shared.some(e=>e.id===lastEntry.id)&&!pending().some(e=>e.id===lastEntry.id))res='shared';const list=res==='shared'?lb.shared:lb.local,rank=list.findIndex(e=>e.id===lastEntry.id)+1;
 const msg={'storage-error':'Shared-drive save not confirmed; backup unavailable. Keep the game open.',shared:'Saved to the shared leaderboard'+(rank?`: rank ${rank} of ${list.length}.`:'.'),retrying:'Shared drive unavailable — retrying automatically. Backup safe.',pending:lb.perm==='granted'?'Uploading to the shared drive automatically. Backup safe.':'Not on the shared drive yet — allow folder access for automatic uploads. Backup safe.',nohandle:'Not on the shared drive yet — connect the folder to enable automatic uploads. Backup safe.',local:'Shared drive unsupported in this browser. Backup saved on this computer.'}[res];
 $('saveNote').textContent=msg;renderPlace(list,res==='shared');
}
function renderEarned(){const box=$('achEarned');box.textContent='';
 if(run.gain>0){const sp=document.createElement('span');sp.className='xp-gain';sp.append(svgIcon('i-medal'),'+'+run.gain.toLocaleString()+' XP / '+(run.promoted?'PROMOTED TO LEVEL '+run.promoted:'LEVEL '+levelOf(profXp())));box.append(sp)}
 for(const id of run.earned){const a=ACH_BY_ID[id],sp=document.createElement('span'),i=document.createElementNS('http://www.w3.org/2000/svg','svg'),u=document.createElementNS('http://www.w3.org/2000/svg','use');i.setAttribute('class','ic');u.setAttribute('href','#i-medal');i.append(u);sp.append(i,a.name.toUpperCase());box.append(sp)}}
// Game over: your row on the board with up to two runs above and two below.
function renderPlace(list,shared){
 const box=$('placeRows'),i=lastEntry?list.findIndex(e=>e.id===lastEntry.id):-1;box.textContent='';$('place').hidden=i<0;if(i<0)return;
 $('placeLabel').textContent=(shared?'SHARED LEADERBOARD':'THIS COMPUTER')+' / RANK '+(i+1)+' OF '+list.length;
 for(let k=Math.max(0,i-2);k<=Math.min(list.length-1,i+2);k++){const e=list[k],row=document.createElement('div');row.className=k===i?'pr me':'pr';row.title=whenText(e);
  for(const [txt,cls] of [['#'+(k+1)],[e.name,'nm'],[e.score.toLocaleString()],[e.distance+' m']]){const sp=document.createElement('span');sp.textContent=txt;if(cls)sp.className=cls;row.append(sp)}box.append(row)}
}
function cell(tr,text,cls){const td=document.createElement('td');td.textContent=text;if(cls)td.className=cls;tr.append(td)}
function renderBoard(){
 if(state==='over'&&lastEntry)describeSave(!lb.supported?'local':!lb.dir?'nohandle':lb.perm!=='granted'?'pending':lb.note?'retrying':'pending');
 const connected=lb.dir&&lb.perm==='granted',useShared=lb.source==='shared';
 let msg=!lb.supported?'This browser cannot use shared folders. Use Microsoft Edge or Google Chrome for the shared leaderboard. Scores are kept on this computer.':lb.perm!=='granted'?`Not connected to ${SHARED_NAME} (${SHARED_DIR}). Select Allow access to post and see everyone’s scores; until then they are kept on this computer.`:`Connected to ${lb.dir.name} / ${BOARD_FILE} / ${lb.shared.length} records.`;
 const queued=lb.supported?pending().length:0;if(queued)msg+=` ${queued} score${queued>1?'s':''} waiting to post.`;if(lb.warn)msg+=' '+lb.warn;if(lb.note)msg+=' '+lb.note;
 $('lbStatus').textContent=msg;
 $('lbConnect').hidden=!lb.supported||connected;$('lbRefresh').disabled=!connected;
 $('lbConnect').querySelector('span').textContent='Allow access';
 document.querySelectorAll('#srcSeg button').forEach(b=>{b.setAttribute('aria-pressed',String(b.dataset.src===lb.source));if(b.dataset.src==='shared')b.disabled=!lb.supported});
 document.querySelectorAll('#filterSeg button').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.filter===lb.filter)));
 const body=$('lbBody');body.textContent='';
 const rows=(useShared?(connected?boardAdminEntries(lb.shared,lb.admin):[]):boardAdminEntries(lb.local,localBoardAdmin())).filter(e=>lb.filter==='all'||e.diff===lb.filter).slice(0,50);
 if(!rows.length){const tr=document.createElement('tr');cell(tr,useShared&&!connected?'Connect the shared folder to see everyone\u2019s scores.':'No scores yet. Be the first on the board.','empty');tr.firstChild.colSpan=7;body.append(tr)}
 rows.forEach((e,i)=>{const tr=document.createElement('tr');if(duelKey(e.name)===prof.key)tr.className='me';cell(tr,i+1);cell(tr,e.name,'name');cell(tr,e.score.toLocaleString(),'num');cell(tr,e.distance+' m','num hide-sm');cell(tr,SUB_BY_ID[e.sub].name,'hide-sm');cell(tr,DIFFS[e.diff].label);cell(tr,whenText(e),'hide-sm');body.append(tr)});
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
 $('achFleetNote').textContent=(lb.dir&&lb.perm==='granted'?'Sailors on the shared leaderboard, ranked by achievements. ':'Connect the shared folder from the Leaderboard screen to see other sailors. ')+'Select a callsign to see their record.'+(callsign()==='Anonymous'?' Set a callsign on the home screen to post your own.':'');
 const body=$('achFleet');body.textContent='';
 if(!F.length){const tr=document.createElement('tr');cell(tr,'No achievements posted yet.','empty');tr.firstChild.colSpan=4;body.append(tr)}
 F.forEach((p,i)=>{const tr=document.createElement('tr'),k=p.name.toLowerCase();if(k===meKey)tr.className='me';if(k===lb.achWho)tr.classList.add('sel');cell(tr,i+1);cell(tr,p.name+(p.xp?' / LV '+levelOf(p.xp):''),'name');
  const td=document.createElement('td'),m=document.createElement('span'),mi=document.createElement('i');m.className='meter';mi.style.width=(p.n/ACHS.length*100)+'%';m.append(mi);td.append(m,p.n+' / '+ACHS.length);tr.append(td);
  const la=p.last?Object.keys(p.ach).find(id=>p.ach[id]===p.last):'';cell(tr,la?ACH_BY_ID[la].name:'','hide-sm');
  tr.onclick=()=>{lb.achWho=k;lb.achView='path';renderAch()};body.append(tr)});
}
function renderChip(){$('achCount').textContent=achCountText();const ch=$('lbChip');ch.classList.toggle('on',lb.perm==='granted');ch.classList.toggle('warn',lb.supported&&lb.perm!=='granted');ch.querySelector('span').textContent=!lb.supported?'LEADERBOARD / THIS COMPUTER':lb.perm==='granted'?'CONNECTED TO '+(lb.dir?lb.dir.name:SHARED_NAME).toUpperCase():SHARED_NAME.toUpperCase()+' NOT CONNECTED / ALLOW ACCESS'}
$('lbConnect').onclick=()=>lbPick(true);
$('lbRefresh').onclick=()=>lbSync(true);
$('sfGo').onclick=()=>lbPick();
$('sfRepick').onclick=()=>lbPick(true);
$('sfOffline').onclick=()=>{lb.gate.offline=true;lb.gate.msg='';sfRender();renderBoard()};
// While the gate is up, keep keys and clicks from reaching the game (Space would start a dive).
for(const ev of ['keydown','keyup'])addEventListener(ev,e=>{if(!$('sfGate').hidden)e.stopPropagation()},true);
for(const ev of ['pointerdown','pointerup','mousedown','mouseup','touchstart','touchend','contextmenu','wheel'])$('sfGate').addEventListener(ev,e=>e.stopPropagation());
addEventListener('focus',()=>sfCheck());document.addEventListener('visibilitychange',()=>{if(!document.hidden)sfCheck()});
document.querySelectorAll('#srcSeg button').forEach(b=>b.onclick=()=>{lb.source=b.dataset.src;renderBoard()});
document.querySelectorAll('#filterSeg button').forEach(b=>b.onclick=()=>{lb.filter=b.dataset.filter;renderBoard()});
// Background synchronization runs throughout gameplay, not only on the board screen.
// On load: connect silently if the stored folder is still allowed, otherwise put the gate up right away.
// A folder linked before there was one fixed folder may be the wrong one: ask for the right one instead.
async function initializeSharedScores(){
 await journalRestore();
 lb.dir=null;lb.perm='none';lb.gate.ready=true;
 renderBoard();sfRender();
}
