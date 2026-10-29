'use strict';
/* ---- 1v1 duels ---------------------------------------------------------------
   Duels live in a data folder next to bin.dat, one file per writer so no two
   computers ever write the same file:
     p-<callsign>-<id>-<beat>.dat  presence: a heartbeat every few seconds while the game is open
     m-<id>-a.dat           the challenge and the challenger's round scores
     m-<id>-b.dat           the reply and the opponent's round scores
     l-<id>-a|b.dat         the diver's live track, twice a second, for anyone watching
   Each round both players dive the same seeded course, taking turns (challenger
   first). The higher total over 1, 3 or 5 rounds wins. A player counts as online
   while their heartbeat keeps changing, so clocks on different PCs never matter.
   Nothing stays on the drive once a duel is over: each player keeps the result in
   their own history on their computer, and the files are deleted. */
const DUEL_DIR='data',BEAT_MS=4000,POLL_MS=2500,ONLINE_MS=25000,DAY=864e5;
const duel={root:null,dir:null,beat:0,lastBeat:0,beatFile:'',files:new Map(),seen:new Map(),online:[],matches:[],rounds:3,diff:'officer',run:null,after:null,watch:null,saved:null,busy:false,pollJob:null,action:'',actionButton:'',presenceAt:0,presenceName:'',beatError:'',scanAt:0,version:0,roundBackupSafe:true,lastRoundRetry:0,pendingRound:store.get('undertow.duel-round.v1',null),note:'',fails:0,dupe:false,orphans:new Map(),own:new Map(),gone:new Map(),flash:'',flashUntil:0,
 history:(store.get('undertow.duels.v1',[])||[]).filter(h=>h&&h.id).slice(0,20),pc:crypto.randomUUID().replaceAll('-','')};
if(duel.pendingRound&&(!/^[a-z0-9]+$/.test(duel.pendingRound.id)||!['a','b'].includes(duel.pendingRound.side)||!Number.isInteger(duel.pendingRound.round)||duel.pendingRound.round<0||duel.pendingRound.round>4||!Number.isFinite(duel.pendingRound.score)||typeof duel.pendingRound.name!=='string'))duel.pendingRound=null;
// Each open game has its own presence file; it is removed when the page closes, or a day later.
addEventListener('pagehide',()=>{if(duel.dir&&duel.beatFile)duelRemove(duel.beatFile,1)});
const duelKey=n=>String(n||'').toLowerCase().replace(/[^a-z0-9]+/g,'_').replace(/^_+|_+$/g,'').slice(0,24)||'x';
const duelIdentity=n=>String(n||'').trim().toLowerCase();
const duelSeed=(m,round)=>(m.a.seed+Math.imul(round+1,7919))>>>0;
const total=a=>a.reduce((n,v)=>n+v,0), fmt=n=>Math.round(n).toLocaleString();
/* On a network share Windows refuses to replace or delete a file while another PC
   has it open (the rival's game reads duel files every few seconds), so saves and
   deletes try again for a few seconds. Windows also caches a folder's listing and
   file details briefly, so this game remembers its own saves and deletes and trusts
   those over what the drive shows. */
async function duelWrite(name,obj,tries=7){
 obj={...obj,v:Date.now()};const text=seal(JSON.stringify(obj));
 for(let i=0;;i++){try{if(duel.swap&&name.startsWith('l-'))await duel.dir.removeEntry(name).catch(e=>{if(!e||e.name!=='NotFoundError')throw e});await writeText(name,text,duel.dir);if(/^[mp]-/.test(name)&&await readFresh(await duel.dir.getFileHandle(name))!==text)throw Error('Shared-drive save verification failed');break}catch(e){if(i>=tries-1)throw e;await sleep(150*(i+1)+Math.random()*200)}}
 if(name.startsWith('m-')){duel.own.set(name,obj);duel.gone.delete(name)}return obj;
}
async function duelRemove(name,tries=4){
 for(let i=0;;i++){try{await duel.dir.removeEntry(name);break}catch(e){if(e&&e.name==='NotFoundError')break;if(i>=tries-1)return false;await sleep(150*(i+1)+Math.random()*200)}}
 duel.own.delete(name);duel.gone.set(name,Date.now());return true;
}
/* Match files are never replaced. The rival's game has them open every few seconds and
   Windows will not replace a file on a share while another PC is reading it (Chrome
   reports "state cached in an interface object ... changed since it was read from disk"),
   so each save is a new m-<id>-<side>-<version>.dat and older copies are deleted once free. */
const MATCH_RE=/^m-([a-z0-9]+)-([ab])(?:-([a-z0-9]+))?\.dat$/;
const matchVer=name=>{const x=MATCH_RE.exec(name);return x&&x[3]?parseInt(x[3],36):0};
const sideFiles=(id,side)=>[...new Set([...duel.files.keys(),...duel.own.keys()])].filter(n=>{const x=MATCH_RE.exec(n);return x&&x[1]===id&&x[2]===side});
// Never act on an older match revision when the newest save is temporarily unreadable.
function duelSide(id,side){
 let best=null;
 for(const name of sideFiles(id,side)){const f=duel.files.get(name),data=f?f.data:duel.own.get(name),ver=matchVer(name);if(!best||ver>best.ver)best={name,ver,data}}
 return best;
}
async function duelSave(id,side,obj){
 duel.version=Math.max(Date.now(),duel.version+1,...sideFiles(id,side).map(n=>matchVer(n)+1));
 const saved=await duelWrite('m-'+id+'-'+side+'-'+duel.version.toString(36)+'.dat',{...obj,owner:callsign()});
 return saved;
}
async function duelRemoveSide(id,side,tries){let ok=true;for(const n of sideFiles(id,side))if(!await duelRemove(n,tries))ok=false;return ok}
// A network drive can replace a file between opening it and reading it (the browser
// then refuses the read), and a folder listing can fail while files change. Look again.
async function readFresh(h){for(let i=0;;i++){try{return await (await h.getFile()).text()}catch(e){if(i>=3)throw e;await sleep(60+Math.random()*140)}}}
async function duelEntries(){for(let i=0;;i++){try{const out=[];for await (const e of duel.dir.entries())out.push(e);return out}catch(e){if(i>=3)throw e;await sleep(100+Math.random()*200)}}}
async function duelReadLive(name){try{return JSON.parse(unseal(await readFresh(await duel.dir.getFileHandle(name)))||'null')}catch(_){return null}}
const duelReady=()=>!!(lb.dir&&lb.perm==='granted'&&callsign()!=='Anonymous');
async function duelFolder(){
 if(lb.dir!==duel.root){duel.root=lb.dir;duel.dir=null;duel.files=new Map();duel.seen.clear();duel.own.clear();duel.gone.clear();duel.online=[];duel.matches=[];duel.beatFile='';duel.presenceAt=0;duel.scanAt=0;duel.lastBeat=0;duel.check=null}
 if(!duelReady())return null;
 if(!duel.dir){try{duel.dir=await lb.dir.getDirectoryHandle(DUEL_DIR,{create:true})}catch(e){throw Error('Cannot open the duel folder: '+(e.message||e))}await duelCheck()}
 return duel.dir;
}
/* Once per connection, try each thing duels need on this drive with a scratch file,
   and report anything that fails on the Duel screen. If the drive will not let a
   file be replaced but does allow deleting, saves delete the old file first. */
async function duelCheck(){
 const n='t-'+duel.pc+'.dat',r={};
 const step=async(k,fn)=>{try{await fn();r[k]='ok'}catch(e){r[k]=(e&&e.name||'Error')+': '+(e&&e.message||e)}};
 await step('create',()=>writeText(n,'one',duel.dir));
 await step('replace',()=>writeText(n,'two',duel.dir));
 await step('read back',async()=>{const t=await readFresh(await duel.dir.getFileHandle(n));if(t!=='two')throw new Error('got "'+t.slice(0,8)+'" instead of the new text')});
 await step('delete',()=>duel.dir.removeEntry(n));
 duel.check=r;duel.swap=r.replace!=='ok'&&r.delete==='ok';
}
// Immutable revisions can be cached; legacy overwritten files are always reread.
// Bounded parallel reads keep a slow peer file from delaying every player.
async function duelScan(){
 const out=new Map(),entries=(await duelEntries()).filter(([name,h])=>h.kind==='file'&&/^[pm]-[a-z0-9_-]+\.dat$/.test(name));
 const read=async([name,h])=>{
  const old=duel.files.get(name),immutable=/^p-.*-[a-f0-9]{32}-[a-z0-9]+\.dat$/.test(name)||!!matchVer(name);
  if(immutable&&old&&old.data){out.set(name,{...old,missingSince:0});return}
  try{const data=JSON.parse(unseal(await readFresh(h))||'null');out.set(name,data?{data}:old||{data:null})}
  catch(_){out.set(name,old||{data:null})}
 };
 for(let i=0;i<entries.length;i+=6)await Promise.all(entries.slice(i,i+6).map(read));
 for(const [name,f] of duel.files)if(name.startsWith('p-')&&!out.has(name)&&Date.now()-(f.missingSince||Date.now())<ONLINE_MS)out.set(name,{...f,missingSince:f.missingSince||Date.now()});
 for(const [name,o] of duel.own){const f=out.get(name);if(!f||!f.data||(+f.data.v||0)<o.v)out.set(name,{mod:f?f.mod:0,size:f?f.size:0,data:o})}
 for(const [name,at] of duel.gone){if(Date.now()-at>60000)duel.gone.delete(name);else out.delete(name)}
 duel.files=out;
}
const duelStatusWord=()=>state==='watching'?'watching a duel':state==='playing'||state==='paused'?(duel.run?'in a duel':'diving'):'in port';
async function duelBeat(){
 if(duel.presenceName===callsign()&&Date.now()-duel.lastBeat<BEAT_MS)return;
 const beat=++duel.beat,file='p-'+duelKey(callsign())+'-'+duel.pc+'-'+beat.toString(36)+'.dat';
 await duelWrite(file,{name:callsign(),pc:duel.pc,beat,at:Date.now(),status:duelStatusWord()},1);
 duel.beatFile=file;duel.lastBeat=Date.now();duel.presenceAt=Date.now();duel.presenceName=callsign();duel.beatError='';
 // Only remove this session's older heartbeats after the new one is verified.
 // Failed deletes are harmless: readers choose the greatest beat per session.
 for(const [name,f] of duel.files)if(name!==file&&name.startsWith('p-')&&f.data&&f.data.pc===duel.pc)await duelRemove(name,1);
}
function duelPeople(){
 const me=duelIdentity(callsign()),now=Date.now(),sessions=new Map(),by=new Map();duel.dupe=false;
 for(const [name,f] of duel.files){
  if(!name.startsWith('p-')||!f.data)continue;const p=f.data;
  if(!p.name||typeof p.pc!=='string'||!Number.isFinite(p.beat))continue;
  const key=JSON.stringify([duelIdentity(p.name),p.pc]),prev=sessions.get(key);
  if(!prev||p.beat>prev.p.beat)sessions.set(key,{name,p});
 }
 for(const [session,{name,p}] of sessions){
  const k=duelIdentity(p.name);if(k===me&&p.pc===duel.pc)continue;
  let seen=duel.seen.get(session);
  // Never trust the remote wall clock or unchanged metadata. A changing counter
  // proves this session is alive, even if the PCs' clocks are hours apart.
  if(!seen){seen={beat:p.beat,since:now,confirmed:false};duel.seen.set(session,seen)}
  else if(p.beat>seen.beat){seen.beat=p.beat;seen.since=now;seen.confirmed=true}
  const online=seen.confirmed&&now-seen.since<ONLINE_MS,checking=!seen.confirmed&&now-seen.since<ONLINE_MS;
  if(k===me){if(online)duel.dupe=true;continue}
  const person={name:String(p.name).slice(0,16),key:k,status:String(p.status||'').slice(0,20),online,checking,file:name,seenAt:seen.since};
  const prev=by.get(k);if(!prev||online&&!prev.online||online===prev.online&&seen.since>prev.seenAt)by.set(k,person);
 }
 return [...by.values()].sort((a,b)=>b.online-a.online||a.name.localeCompare(b.name));
}

function duelMatchList(){
 const me=duelIdentity(callsign()),by=new Map(),list=[],now=Date.now();duel.orphanNames=[];
 for(const name of duel.files.keys()){const m=MATCH_RE.exec(name);if(m)by.set(m[1],1)}
 for(const id of by.keys()){
  const fa=duelSide(id,'a'),fb=duelSide(id,'b'),a=fa&&(fa.data||{unread:true}),b=fb&&(fb.data||{unread:true});
  if(!a){if(b&&!b.unread)duel.orphanNames.push(id);continue}
  if(a.unread||!a.a||!a.b||b&&b.unread)continue;const side=duelIdentity(a.a)===me?'a':duelIdentity(a.b)===me?'b':null;if(!side)continue;
  const R=[1,3,5].includes(a.rounds)?a.rounds:3,num=v=>Array.isArray(v)?v.slice(0,R).map(x=>Math.max(0,Math.floor(+x)||0)):[];
  const sa=num(a.scores),sb=num(b&&b.scores),updated=Math.max(+a.created||0,+a.at||0,+(b&&b.at)||0);
  const status=a.cancelled?'closed':!b?(a.closed?'closed':now-updated>DAY?'expired':'pending'):b.declined?'declined':a.forfeit||b.forfeit?'forfeit':sa.length>=R&&sb.length>=R?'done':'active';
  const turn=status==='active'?(sa.length===sb.length?'a':'b'):null,mine=side==='a'?sa:sb,theirs=side==='a'?sb:sa;
  const result=status==='done'?(total(mine)>total(theirs)?'won':total(mine)<total(theirs)?'lost':'drew'):status==='forfeit'?((side==='a'?a:b).forfeit?'lost':'won'):null;
  const round=turn==='a'?sa.length:sb.length,own=side==='a'?a:b,abandoned=turn===side&&!!own&&own.began===round&&!(duel.run&&duel.run.id===id);
  list.push({id,side,a,b,R,sa,sb,mine,theirs,turn,round,abandoned,status,result,opp:String(side==='a'?a.b:a.a).slice(0,16),diff:DIFFS[a.diff]?a.diff:'officer',updated});
 }
 return list.sort((x,y)=>y.updated-x.updated);
}
// Results are kept on this computer only; the duel's files are removed from the drive.
function duelRemember(m,result){
 if(duel.history.some(h=>h.id===m.id))return;
 duel.history.unshift({id:m.id,opp:m.opp,result,side:m.side,R:m.R,diff:m.diff,mine:total(m.mine),theirs:total(m.theirs),rounds:m.mine.length||m.theirs.length?duelRounds(m):'',at:Date.now()});
 duel.history=duel.history.slice(0,20);
 if(result==='won'||result==='lost'||result==='drew'){ach.st.duels++;if(result==='won')ach.st.wins++;if(!practice)achCheck()}
 profDirty(false);
}
async function duelCleanup(){
 for(const m of duel.matches){
  const own=m.side==='a'?m.a:m.b,other=m.side==='a'?m.b:m.a,live='l-'+m.id+'-'+m.side+'.dat';
  // Older copies of my side that were still open on the rival's PC when replaced.
  const cur=duelSide(m.id,m.side);if(cur)for(const n of sideFiles(m.id,m.side))if(matchVer(n)<cur.ver)await duelRemove(n,1);
  if(m.status==='closed'){
   if(m.a.cancelled){
    // Keep the cancellation visible until the recipient acknowledges it. A cached
    // directory listing must not turn an old challenge into an active match.
    if(m.side==='b'&&!(m.b&&m.b.closed))await duelSave(m.id,'b',{id:m.id,closed:true,at:Date.now(),scores:[]});
    else if(m.side==='a'&&(m.b&&m.b.closed||Date.now()-(+m.a.at||0)>DAY)){await duelRemoveSide(m.id,'a');await duelRemove(live)}
   }else{await duelRemoveSide(m.id,m.side);await duelRemove(live)}
  }
  else if(m.side==='a'&&(m.status==='expired'||m.status==='declined')){duelRemember(m,m.status);await duelRemoveSide(m.id,'a')}
  else if(m.status==='done'||m.status==='forfeit'){
   duelRemember(m,m.result);
   // Each side marks the duel closed; once both have, the files go.
   if(!own.closed)await duelSave(m.id,m.side,{...own,closed:true,at:Date.now()}).catch(()=>{});
   else if(other&&other.closed){await duelRemoveSide(m.id,m.side);await duelRemove(live)}
  }
 }
 // My replies whose challenge has gone (cancelled, or closed by the other side).
 const seenNow=new Set(duel.orphanNames);
 for(const id of seenNow){const n=(duel.orphans.get(id)||0)+1;duel.orphans.set(id,n);
  const f=duelSide(id,'b');if(f&&f.data&&(duelIdentity(f.data.owner)===duelIdentity(callsign())||duel.own.has(f.name))&&(f.data.closed||f.data.declined||n>=2)){await duelRemoveSide(id,'b');await duelRemove('l-'+id+'-b.dat');duel.orphans.delete(id)}}
 for(const id of [...duel.orphans.keys()])if(!seenNow.has(id))duel.orphans.delete(id);
 // Presence files from games closed without saying goodbye.
 for(const [name,f] of duel.files)if(name.startsWith('p-')&&f.data&&duel.seen.has(JSON.stringify([duelIdentity(f.data.name),f.data.pc]))&&Date.now()-duel.seen.get(JSON.stringify([duelIdentity(f.data.name),f.data.pc])).since>DAY&&name!==duel.beatFile)await duelRemove(name);
}
function duelTick(force=false){
 if(duel.busy)return duel.pollJob;
 if(duel.action&&!force)return Promise.resolve(false);
 duel.busy=true;
 duel.pollJob=(async()=>{
  try{
   if(!await duelFolder()){duel.online=[];duel.matches=[];duel.presenceAt=0;return false}
   try{await duelBeat()}catch(e){duel.lastBeat=0;duel.beatError='Could not publish your online status. Retrying automatically.'}
   await duelScan();duel.online=duelPeople();duel.matches=duelMatchList();duel.scanAt=Date.now();
   await duelCleanup();duel.fails=0;duel.note='';return true;
  }catch(e){
   duel.fails++;duel.note='Cannot refresh duels: '+(e&&e.message||e)+'. Retrying automatically.';
   duel.online=duel.online.map(p=>({...p,online:p.online&&Date.now()-p.seenAt<ONLINE_MS,checking:false}));
   return false;
  }finally{duel.busy=false;renderDuel()}
 })();return duel.pollJob;
}
function duelFlash(text){duel.flash=text;duel.flashUntil=Date.now()+8000;renderDuel()}
async function duelAct(fn,label='Saving…'){
 if(duel.action)return false;
 duel.action=label;renderDuel();saveStatus('duel','busy',label);
 let ok=false;
 try{
  if(duel.pollJob)await duel.pollJob;
  if(!await duelFolder())throw Error('Connect the shared folder and set a callsign first.');
  // Work from current drive contents, not the snapshot captured by a button.
  await duelScan();duel.online=duelPeople();duel.matches=duelMatchList();
  if(duel.dupe)throw Error('Another game is using your callsign. Close the other game or choose a unique callsign');
  await fn();ok=true;
  saveStatus('duel','done','Duel change saved and verified.');
  duel.lastBeat=0;await duelTick(true);
 }catch(e){saveStatus('duel','error','Duel save failed. Retry the action.');duelFlash('Not saved: '+(e&&e.message||e)+'. Please retry.')}
 finally{duel.action='';renderDuel()}
 return ok;
}

const mySide=m=>m.side==='a'?m.a:m.b;
function duelChallenge(name){const id=Date.now().toString(36)+Math.random().toString(36).slice(2,6);return duelAct(()=>{if(!duel.online.some(p=>p.online&&p.key===duelIdentity(name)))throw Error('That player is not confirmed online yet');if(duel.dupe)throw Error('Choose a unique callsign before challenging');if(duel.matches.some(m=>['active','pending'].includes(m.status)&&duelIdentity(m.opp)===duelIdentity(name)))throw Error('You already have a duel with that player');return duelSave(id,'a',{id,a:callsign(),b:name,rounds:duel.rounds,diff:duel.diff,seed:Math.floor(Math.random()*2**31),created:Date.now(),at:Date.now(),scores:[]})},'Sending challenge…')}
const duelReply=(m,yes)=>duelAct(async()=>{
 const cur=duel.matches.find(x=>x.id===m.id);if(!cur||cur.status!=='pending'||cur.side!=='b')throw Error('This challenge is no longer waiting for a reply');
 await duelSave(cur.id,'b',{id:cur.id,accepted:yes,declined:!yes,at:Date.now(),scores:[]});
 if(!yes)duelRemember(cur,'declined');
},yes?'Accepting challenge…':'Declining challenge…');
const duelCancel=m=>duelAct(async()=>{
 const cur=duel.matches.find(x=>x.id===m.id);if(!cur||cur.status!=='pending'||cur.side!=='a')throw Error('This challenge has changed; refresh the list');
 await duelSave(cur.id,'a',{...cur.a,closed:true,cancelled:true,at:Date.now()});
},'Canceling challenge…');
const duelPatch=(m,patch,label='Saving duel…')=>duelAct(()=>{
 const cur=duel.matches.find(x=>x.id===m.id);
 if(!cur||cur.status!=='active')throw Error('This duel is no longer active');
 if('began' in patch&&(cur.turn!==cur.side||cur.round!==m.round||cur.abandoned))throw Error('This round has already started or the turn has changed');
 if('scores' in patch&&(cur.turn!==cur.side||cur.mine.length!==m.mine.length))throw Error('This round has changed; refresh the list');
 return duelSave(cur.id,cur.side,{...mySide(cur),...patch,at:Date.now()});
},label);

/* Your round: the seeded course, with your track sent out for spectators. */
// A round is marked as begun before the dive starts, so closing the game part-way
// cannot be used to try a round again: an unfinished round counts as 0.
async function duelDive(m){
 if(m.status!=='active'||m.turn!==m.side||duel.run||duel.pendingRound)return;
 if(m.abandoned){if(await duelPatch(m,{scores:[...m.mine,0]}))duelFlash('Round '+(m.round+1)+' was left unfinished, so it counts as 0.');return}
 if(!await duelPatch(m,{began:m.round},'Preparing round…'))return;
 const now=duel.matches.find(x=>x.id===m.id)||m;if(now.status!=='active'||now.turn!==now.side||duel.run){duelFlash('Could not start: this duel now reads as '+(now.status==='active'?m.opp+'’s turn':now.status)+'. Check the list below.');return}
 duel.saved={diffId,practice};duel.run={id:m.id,side:m.side,round:m.round,R:m.R,opp:m.opp,samples:[],seq:0,lastSample:-1,timer:0,writing:false};
 courseSeed=duelSeed(m,m.round);diffId=m.diff;practice=false;start();courseSeed=null;show('restartPause',false);
 toast('DUEL / ROUND '+(m.round+1)+' OF '+m.R,'Against '+m.opp+', on the same course '+(m.side==='a'?'they will dive next':'they just dived')+'. Highest total wins.',4);
 duel.run.timer=setInterval(()=>duelLive(duel.run,false),500);
}
function duelSample(r=duel.run){
 if(t-r.lastSample<.1)return;r.lastSample=t;
 r.samples.push([+t.toFixed(2),Math.round(sub.x),Math.round(sub.y),Math.round(sub.v),score(),hull,+(o2/S.o2).toFixed(2)]);
 if(r.samples.length>40)r.samples.splice(0,r.samples.length-40);
}
async function duelLive(r,over){
 if(!r||!duel.dir)return;
 if(r.liveJob){if(!over)return;await r.liveJob}
 const dead=gates.filter(g=>g.dead[0]||g.dead[1]).map(g=>[Math.round(g.x),+g.dead[0],+g.dead[1]]);
 r.liveJob=duelWrite('l-'+r.id+'-'+r.side+'.dat',{id:r.id,round:r.round,seq:++r.seq,sub:subId,samples:r.samples.slice(-20),dead,over,score:score(),cause:over?deathCause:''},over?6:1).catch(()=>{});
 try{await r.liveJob}finally{r.liveJob=null}
}
// Called from finish(): posts the round score and points the wreck screen back to the duel.
async function duelRoundOver(final){
 const r=duel.run;duel.run=null;clearInterval(r.timer);duel.after=r;
 if(duel.saved){diffId=duel.saved.diffId;practice=duel.saved.practice;duel.saved=null}
 $('overLabel').textContent='DUEL / ROUND '+(r.round+1)+' OF '+r.R;$('again').lastChild.textContent='BACK TO DUEL';
 duel.pendingRound={id:r.id,side:r.side,round:r.round,score:Math.max(0,Math.floor(final)),name:callsign()};
 duel.roundBackupSafe=store.set('undertow.duel-round.v1',duel.pendingRound);
 $('cause').textContent=deathCause+' Saving your round score…';
 r.lastSample=-1;duelSample(r);await duelLive(r,true);
 const ok=await duelPostRound();
 $('cause').textContent=deathCause+(ok?' Round '+(r.round+1)+' score saved and verified.':duel.roundBackupSafe?' Your round score is backed up on this computer. Open Duel and retry saving.':' Your score is held in this open game. Keep it open and retry saving from Duel.');

}
// Retry is idempotent: never append the same round twice or overwrite a newer one.
async function duelPostRound(){
 const r=duel.pendingRound;if(!r||duelIdentity(r.name)!==duelIdentity(callsign()))return false;
 duel.lastRoundRetry=Date.now();
 const ok=await duelAct(async()=>{
  const m=duel.matches.find(x=>x.id===r.id&&x.side===r.side);
  if(!m)throw Error('The duel is not available in this shared folder. Your score remains backed up');
  if(m.mine.length>r.round){if(m.mine[r.round]!==r.score)throw Error('This round already has a different score');return}
  if(m.status!=='active'||m.turn!==m.side||m.mine.length!==r.round)throw Error('This duel is not ready for the saved round score');
  await duelSave(m.id,m.side,{...mySide(m),scores:[...m.mine,r.score],at:Date.now()});
 },'Saving round score…');
 if(ok&&duel.pendingRound===r){duel.pendingRound=null;store.set('undertow.duel-round.v1',null);renderDuel()}
 if(!ok&&duel.pendingRound)saveStatus('duel','queued','Round score waiting for the shared drive. Retrying automatically; you can also retry from Duel.');
 return ok;
}
function againOrDuel(){if(campAgain())return;if(duel.after){home();openPanel('duel')}else start()}

/* Watching: rebuild the same course and replay the rival's track about a second behind. */
function duelWatch(m){
 const side=m.side==='a'?'b':'a';if(m.status!=='active'||m.turn!==side||duel.run)return;
 const w={id:m.id,side,round:m.round,R:m.R,name:m.opp,buf:[],pt:null,seq:-1,over:false,endAt:0,score:0,shown:0,dead:[],cause:'',timer:0,reading:false};
 duel.saved={diffId,practice};duel.watch=w;
 courseSeed=duelSeed(m,m.round);diffId=m.diff;practice=false;reset();courseSeed=null;
 state='watching';panel=null;['menu','footer','paused','help','over','board','hangar','ach','duel'].forEach(id=>show(id,false));
 show('hud',true);$('hud').classList.add('watching');$('hud').classList.remove('ended');show('watchBar',true);$('hint').style.opacity='0';
 duelWatchText();w.timer=setInterval(duelWatchPoll,600);duelWatchPoll();last=performance.now();
}
async function duelWatchPoll(){
 const w=duel.watch;if(!w||w.reading||!duel.dir)return;w.reading=true;
 const d=await duelReadLive('l-'+w.id+'-'+w.side+'.dat');w.reading=false;if(duel.watch!==w)return;
 // The round may already be posted and the duel's files cleared before the last update arrives.
 const m=duel.matches.find(x=>x.id===w.id);if(!d&&w.buf.length&&!(m&&m.status==='active'&&m.turn===w.side&&m.round===w.round)){w.over=true;duelWatchText();return}
 if(!d||d.id!==w.id||d.round!==w.round||d.seq<=w.seq)return;
 w.seq=d.seq;if(SUB_BY_ID[d.sub]&&S.id!==d.sub){S=SUB_BY_ID[d.sub];buildPips()}
 const lastT=w.buf.length?w.buf[w.buf.length-1][0]:-1;
 for(const s of Array.isArray(d.samples)?d.samples:[])if(Array.isArray(s)&&s.length>=7&&s.every(Number.isFinite)&&s[0]>lastT)w.buf.push(s);
 if(w.buf.length>300)w.buf.splice(0,w.buf.length-300);
 w.dead=Array.isArray(d.dead)?d.dead:[];w.score=+d.score||0;if(d.over){w.over=true;w.cause=String(d.cause||'')}
 duelWatchText();
}
function duelWatchText(){const w=duel.watch;if(w)$('watchText').textContent='WATCHING '+w.name.toUpperCase()+' / ROUND '+(w.round+1)+' OF '+w.R+(w.buf.length?'':' / WAITING FOR THEM TO DIVE')}
function duelWatchStep(dt){
 const w=duel.watch;if(!w)return;const B=w.buf;
 if(B.length){
  const end=B[B.length-1][0];if(w.pt===null||end-w.pt>4)w.pt=Math.max(B[0][0],end-1.2);w.pt=Math.min(w.pt+dt,end);
  let i=0;while(i<B.length-2&&B[i+1][0]<=w.pt)i++;
  const a=B[i],b=B[Math.min(i+1,B.length-1)],k=b[0]>a[0]?clamp((w.pt-a[0])/(b[0]-a[0]),0,1):1;
  if(b[0]>a[0])speed=(b[1]-a[1])/(b[0]-a[0]);
  sub.x=mix(a[1],b[1],k);sub.y=mix(a[2],b[2],k);sub.v=mix(a[3],b[3],k);t=w.pt;hull=a[5];o2=a[6]*S.o2;w.shown=mix(a[4],b[4],k);
 }
 distance=sub.x*.1;difficulty=clamp(sub.x/D.ramp,0,1);night=smooth(TP.night,TP.night+3500,sub.x);populate();
 for(const [x,d0,d1] of w.dead){const g=gates.find(g=>Math.round(g.x)===x);if(g){if(d0)g.dead[0]=true;if(d1)g.dead[1]=true}}
 updateSonar(dt);const z=terrain(sub.x);camY=mix(camY,Math.max(-130,mix(z.centre,sub.y,.35)-vh*.53),1-Math.exp(-dt*2));
 if(t>toastUntil)$('toast').classList.remove('show');
 if(ambient-lastHud>.15){lastHud=ambient;updateHUD(z);$('score').textContent=fmt(w.shown)}
 if(w.over&&!w.endAt&&(!B.length||w.pt>=B[B.length-1][0])){w.endAt=ambient;toast(w.name.toUpperCase()+' SURFACED','Round '+(w.round+1)+' score: '+fmt(w.score)+'. '+w.cause,4)}
 if(w.endAt&&ambient-w.endAt>4)duelLeaveWatch();
}
function duelLeaveWatch(){
 const w=duel.watch;if(!w)return;clearInterval(w.timer);duel.watch=null;
 if(duel.saved){diffId=duel.saved.diffId;practice=duel.saved.practice;duel.saved=null}
 $('hud').classList.remove('watching');show('watchBar',false);home();openPanel('duel');
}

/* ---- Duel screen ---- */
// The game's own yes/no box. Resolves true for yes; Escape, Cancel or a click outside mean no.
let askDone=null;
function askBox(title,body,yes='Yes'){
 if(askDone)askDone(false);$('askTitle').textContent=title;$('askBody').textContent=body;$('askYes').textContent=yes;show('askBox',true);$('askNo').focus({preventScroll:true});
 return new Promise(res=>{askDone=v=>{askDone=null;show('askBox',false);res(v)}});
}
$('askYes').onclick=()=>askDone&&askDone(true);$('askNo').onclick=()=>askDone&&askDone(false);$('askBox').onclick=e=>{if(e.target.id==='askBox'&&askDone)askDone(false)};
function duelButton(label,fn,cls){
 const b=document.createElement('button');b.className='act'+(cls?' '+cls:'');b.textContent=label;
 if(fn)b.onclick=async()=>{
  if(duel.action||b.disabled)return;
  duel.actionButton=label;b.disabled=true;b.setAttribute('aria-busy','true');
  const spinner=duelEl('span','save-spinner');spinner.setAttribute('aria-hidden','true');b.prepend(spinner);
  try{await fn()}catch(e){duelFlash('Could not complete the action: '+(e.message||e))}
  finally{duel.actionButton='';b.removeAttribute('aria-busy');spinner.remove();b.disabled=false;renderDuel()}
 };else b.disabled=true;
 if(fn&&duel.action){b.disabled=true;if(label===duel.actionButton){b.setAttribute('aria-busy','true');b.textContent=duel.action;b.prepend(duelEl('span','save-spinner'))}}
 return b;
}

function duelEl(tag,cls,text){const e=document.createElement(tag);if(cls)e.className=cls;if(text!=null)e.textContent=text;return e}
// One line in a duel list: optional lead (dot or badge), title and detail, optional tail, then buttons.
function duelRow(box,title,detail,buttons,lead,tail){
 const it=duelEl('div','dm-item'),tx=duelEl('div','dm-txt');tx.append(duelEl('span','dm-t',title));if(detail)tx.append(duelEl('span','dm-d',detail));
 if(lead)it.append(lead);it.append(tx);if(tail)it.append(tail);
 if(buttons&&buttons.length){const a=duelEl('div','dm-acts');a.append(...buttons);it.append(a)}
 box.append(it);
}
function duelEmpty(box,text){box.append(duelEl('div','dm-empty',text))}
function duelRounds(m){const n=Math.max(m.mine.length,m.theirs.length),v=(a,i)=>i<a.length?fmt(a[i]):'–';return Array.from({length:n},(_,i)=>'R'+(i+1)+' '+v(m.mine,i)+':'+v(m.theirs,i)).join(' · ')}
const duelHead=m=>(DIFFS[m.diff]||DIFFS.officer).label+' / '+m.R+' round'+(m.R>1?'s':'');
function duelRecord(){const r={won:0,lost:0,drew:0};for(const h of duel.history)if(h.result in r)r[h.result]++;return r}
// The big card for a match under way: who, level, round, per-round scores, and what to do next.
function duelCard(m){
 const mineTurn=m.turn===m.side,opp=duel.online.find(p=>p.key===duelIdentity(m.opp)),live=opp&&opp.online&&opp.status==='in a duel';
 const card=duelEl('div','dm-card'+(mineTurn?' mine':'')),top=duelEl('div','dm-card-top'),who=duelEl('div'),vs=duelEl('div','dm-vs');
 vs.append(callsign(),duelEl('span',null,'vs'),m.opp);
 who.append(vs,duelEl('div','dm-meta',(duelHead(m)+' / round '+(m.round+1)+' of '+m.R).toUpperCase()));
 top.append(who,duelEl('div','dm-turn'+(m.abandoned?' warn':mineTurn?' mine':''),m.abandoned?'UNFINISHED':mineTurn?'YOUR TURN':live?m.opp.toUpperCase()+' DIVING':m.opp.toUpperCase()+'’S TURN'));
 const wrap=duelEl('div','dm-score-wrap'),tb=duelEl('table','dm-score'),thead=duelEl('thead'),tbody=duelEl('tbody'),hr=duelEl('tr');
 hr.append(duelEl('th',null,''));for(let i=0;i<m.R;i++)hr.append(duelEl('th',i===m.round?'cur':null,'R'+(i+1)));hr.append(duelEl('th','tot','TOTAL'));
 const T1=total(m.mine),T2=total(m.theirs);
 const row=(name,arr,T,lead)=>{const tr=duelEl('tr');tr.append(duelEl('td',null,name));
  for(let i=0;i<m.R;i++)tr.append(duelEl('td',((i===m.round?'cur ':'')+(i<arr.length?'':'pend')).trim()||null,i<arr.length?fmt(arr[i]):'–'));
  tr.append(duelEl('td','tot'+(lead?' lead':''),fmt(T)));return tr};
 thead.append(hr);tbody.append(row('You',m.mine,T1,T1>T2),row(m.opp,m.theirs,T2,T2>T1));tb.append(thead,tbody);wrap.append(tb);
 const acts=duelEl('div','dm-card-acts');
 acts.append(duel.pendingRound?duelButton('Save the pending round score first',null,'off big'):mineTurn?(m.abandoned?duelButton('Score round '+(m.round+1)+' as 0',()=>duelDive(m),'warn big'):duelButton('Dive round '+(m.round+1),()=>duelDive(m),'go big'))
  :live?duelButton('Watch live',()=>duelWatch(m),'go big'):duelButton(opp&&opp.online?'Their turn, waiting for them to dive':'Waiting for '+m.opp,null,'off big'));
 acts.append(duelButton('Forfeit',async()=>{if(await askBox('Forfeit this duel?','Your duel with '+m.opp+' ends now and counts as a loss.','Forfeit'))await duelPatch(m,{forfeit:true},'Saving forfeit…')},'warn'));
 card.append(top,wrap);
 if(m.abandoned)card.append(duelEl('p','dm-empty','Round '+(m.round+1)+' was started but not finished, so it counts as 0.'));
 card.append(acts);return card;
}
async function duelConnectionAction(button,fn,text){
 if(button.disabled||duel.action)return;
 const label=button.querySelector('span'),original=label.textContent;
 button.disabled=true;button.setAttribute('aria-busy','true');label.textContent=text;
 const spinner=duelEl('span','save-spinner');spinner.setAttribute('aria-hidden','true');button.prepend(spinner);
 try{await fn()}catch(e){duelFlash('Connection failed: '+(e.message||e))}
 finally{spinner.remove();button.disabled=false;button.removeAttribute('aria-busy');label.textContent=original;renderDuel()}
}
function renderDuel(){
 renderDuelChip();if(panel!=='duel')return;
 const connected=lb.dir&&lb.perm==='granted',ready=duelReady(),here=duel.online.filter(p=>p.online&&Date.now()-p.seenAt<ONLINE_MS),checking=duel.online.filter(p=>p.checking),published=ready&&duel.presenceName===callsign()&&duel.presenceAt&&Date.now()-duel.presenceAt<ONLINE_MS&&!duel.beatError;
 $('duelStatus').textContent=!lb.supported?'Duels go through the shared folder, so they need Microsoft Edge or Google Chrome.':!connected?'Connect the shared folder first. Duels are kept in a data folder next to '+BOARD_FILE+'.':callsign()==='Anonymous'?'Set a callsign on the home screen so other sailors can find and challenge you.':duel.action?duel.action:!published?(duel.beatError||'Connecting to duels and publishing your online status…'):duel.note?'Connection trouble. Refreshing the player list…':'You are online as '+callsign()+'. '+(here.length?here.length+' other sailor'+(here.length>1?'s':'')+' online.':'No one else is online yet.');
 const warns=[];if(Date.now()<duel.flashUntil)warns.push(duel.flash);
 if(duel.dupe)warns.push('Another game is online with the callsign '+callsign()+'. Each player needs their own callsign to see each other.');if(duel.note)warns.push(duel.note);if(duel.beatError)warns.push(duel.beatError);
 $('duelLine').className='dm-line'+(published&&!warns.length?' on':connected?' warn':'');
 const fl=$('duelFlash');fl.hidden=!warns.length;fl.textContent=warns.join(' ');
 const bad=duel.check&&Object.entries(duel.check).filter(([,v])=>v!=='ok');
 $('duelFoot').textContent=(bad&&bad.length?'Drive check: '+bad.map(([k,v])=>k+' failed ('+v+')').join('; ')+'.'+(duel.swap?' Live-track saves will delete and rewrite files instead.':'')+' ':'')+(connected?'Shared folder: '+lb.dir.name+'. ':'')+'Everyone must connect the same shared folder. Online status is confirmed by two heartbeats (usually 4–10 seconds); disconnected players expire after 25 seconds. Build '+BUILD+'.';
 show('duelConnect',lb.supported);
 if(!$('duelConnect').hasAttribute('aria-busy'))$('duelConnect').querySelector('span').textContent=connected?'Change shared folder':'Connect shared folder';
 document.querySelectorAll('#duelRoundSeg button').forEach(b=>{b.disabled=!!duel.action;b.setAttribute('aria-pressed',String(+b.dataset.r===duel.rounds))});
 document.querySelectorAll('#duelDiffSeg button').forEach(b=>{b.disabled=!!duel.action;b.setAttribute('aria-pressed',String(b.dataset.diff===duel.diff))});
 const rec=duelRecord(),recText='W '+rec.won+' · L '+rec.lost+' · D '+rec.drew;
 $('duelMe').textContent=callsign();$('duelRecordTop').textContent='RECORD '+recText;$('duelRecord').textContent=recText;
 // Your matches under way, your turn first.
 const active=duel.matches.filter(m=>m.status==='active').sort((x,y)=>(y.turn===y.side)-(x.turn===x.side)).slice(0,12);
 const cur=$('duelCurrent');cur.textContent='';
 if(duel.pendingRound){const mine=duelIdentity(duel.pendingRound.name)===duelIdentity(callsign());duelRow(cur,'Round score waiting to save',mine?(duel.roundBackupSafe?'Your score is backed up on this computer.':'Keep this game open: local backup failed. Retry saving to the shared drive.'):'Switch your callsign back to '+duel.pendingRound.name+' to save their backed-up score.',[duelButton('Retry saving score',mine?duelPostRound:null,'go')])}
 for(const m of active)cur.append(duelCard(m));
 $('duelCurN').textContent=active.length>1?active.length+' UNDER WAY':'';
 if(!active.length&&!duel.pendingRound)duelEmpty(cur,ready?'No duel under way. Challenge someone from Sailors online, or accept an incoming challenge, and your match shows up here.':'Your matches show up here once you are connected with a callsign.');
 // Challenges, kept apart from matches.
 const pend=duel.matches.filter(m=>m.status==='pending'),inc=pend.filter(m=>m.side==='b').slice(0,12),sent=pend.filter(m=>m.side!=='b').slice(0,12);
 const ib=$('duelIncoming'),sb=$('duelSent');ib.textContent='';sb.textContent='';
 for(const m of inc)duelRow(ib,m.opp+' challenges you',duelHead(m),[duelButton('Accept',()=>duelReply(m,true),'go'),duelButton('Decline',()=>duelReply(m,false),'warn')],duelEl('i','dm-dot busy'));
 if(!inc.length)duelEmpty(ib,'No challenges waiting for you.');
 for(const m of sent)duelRow(sb,'To '+m.opp,duelHead(m)+' / waiting for a reply',[duelButton('Cancel',()=>duelCancel(m),'warn')]);
 if(!sent.length)duelEmpty(sb,'Nothing sent. Use Challenge next to a sailor who is online.');
 $('duelChN').textContent=inc.length?inc.length+' NEW':'';
 // Sailors online.
 const busyWith=new Set(duel.matches.filter(m=>m.status==='active'||m.status==='pending').map(m=>duelIdentity(m.opp)));
 const on=$('duelPeople');on.textContent='';$('duelOnN').textContent=here.length?here.length+' ONLINE':'';
 for(const p of here){const vsMe=busyWith.has(p.key),busy=vsMe||p.status!=='in port';
  duelRow(on,p.name,(p.status||'online').toUpperCase()+(vsMe?' / DUELING YOU':''),[vsMe?duelButton('In a duel',null,'off'):duelButton('Challenge',()=>duelChallenge(p.name),'go')],duelEl('i','dm-dot'+(busy?' busy':'')))}
 for(const p of checking)duelRow(on,p.name,'CHECKING CONNECTION…',[duelButton('Checking…',null,'off')],duelEl('i','dm-dot busy'));
 if(!here.length&&!checking.length)duelEmpty(on,ready?'Looking for players. Everyone must open the game, set a unique callsign, and connect the same shared folder.':'Online sailors appear here once you are connected.');
 // Finished duels, kept on this computer.
 const hb=$('duelHistory');hb.textContent='';
 for(const h of duel.history){
  const a=h.side==='a',scored=h.result==='won'||h.result==='lost'||h.result==='drew';
  const title={won:'Won vs '+h.opp,lost:'Lost vs '+h.opp,drew:'Drew with '+h.opp,declined:a?h.opp+' declined your challenge':'You declined '+h.opp+'’s challenge',expired:'Your challenge to '+h.opp+' expired'}[h.result]||h.opp;
  duelRow(hb,title,duelHead(h)+(scored&&h.rounds?' / '+h.rounds:''),null,duelEl('span','dm-badge '+h.result,{won:'W',lost:'L',drew:'D'}[h.result]||'–'),scored?duelEl('span','dm-pts',fmt(h.mine)+' : '+fmt(h.theirs)):null);
 }
 if(!duel.history.length)duelEmpty(hb,'No finished duels yet. Results are kept on this computer.');
}
function renderDuelChip(){
 const ch=$('duelChip');ch.hidden=!lb.supported;if(ch.hidden)return;
 const inc=duel.matches.find(m=>m.status==='pending'&&m.side==='b'),mine=duel.matches.find(m=>m.status==='active'&&m.turn===m.side);
 const diving=duel.matches.find(m=>m.status==='active'&&m.turn!==m.side&&duel.online.some(p=>p.online&&p.key===duelIdentity(m.opp)&&p.status==='in a duel'));
 const n=duel.online.filter(p=>p.online&&Date.now()-p.seenAt<ONLINE_MS).length;
 ch.querySelector('span').textContent=!duelReady()?'1V1 DUELS / CONNECT TO PLAY':duel.note||duel.beatError?'1V1 DUELS / CONNECTION TROUBLE':!duel.presenceAt||Date.now()-duel.presenceAt>=ONLINE_MS?'1V1 DUELS / CONNECTING…':inc?'1V1 / '+inc.opp.toUpperCase()+' CHALLENGED YOU':mine?'1V1 / YOUR TURN VS '+mine.opp.toUpperCase():diving?'1V1 / '+diving.opp.toUpperCase()+' IS DIVING / WATCH':'1V1 DUELS / '+n+' ONLINE';
 ch.classList.toggle('alert',!!(inc||mine));ch.classList.toggle('on',duelReady()&&!!duel.presenceAt&&!duel.beatError&&!duel.note&&!inc&&!mine);
 $('duelCount').textContent=inc||mine?'Duel (!)':'Duel';
}

