'use strict';
/* ---- Profiles -----------------------------------------------------------------
   Everything a sailor builds up lives under their callsign: achievements and their
   progress, lifetime totals (and so their level), best score, their own top runs, duel
   history, and the level, mission, boat and duel settings they last used. It is kept
   sealed in this browser and in profiles\<callsign>.dat in the shared folder, so
   entering a callsign on any PC loads that sailor's record. When both copies exist they
   merge: achievements and runs are unions, totals and bests take the larger value, and
   settings come from whichever copy changed them last. */
const PROFILE_DIR='profiles';
const blankProfile=name=>({name,ach:{un:{},best:{},st:cleanSt({})},best:0,scores:[],duels:[],set:null,camp:blankCamp(),at:0});
function cleanProfile(p,name){
 if(!p||typeof p!=='object')return blankProfile(name);
 const a=p.ach&&typeof p.ach==='object'?p.ach:{},un={},bst={},s=p.set&&typeof p.set==='object'?p.set:null;
 if(a.un&&typeof a.un==='object')for(const [id,d] of Object.entries(a.un))if(ACH_BY_ID[id])un[id]=String(d||'').slice(0,10);
 if(a.best&&typeof a.best==='object')for(const [id,v] of Object.entries(a.best))if(ACH_BY_ID[id])bst[id]=Math.max(0,Math.floor(+v||0));
 return {name:String(p.name||name).slice(0,16),ach:{un,best:bst,st:cleanSt(a.st)},best:Math.max(0,Math.floor(+p.best||0)),
  scores:(Array.isArray(p.scores)?p.scores:[]).map(cleanEntry).filter(Boolean).slice(0,PROFILE_RUNS),
  duels:(Array.isArray(p.duels)?p.duels:[]).filter(h=>h&&typeof h==='object'&&h.id).slice(0,20),camp:cleanCamp(p.camp),
  set:s&&{diff:DIFFS[s.diff]?s.diff:'officer',practice:!!s.practice,sub:SUB_BY_ID[s.sub]?s.sub:'virginia',rounds:[1,3,5].includes(+s.rounds)?+s.rounds:3,duelDiff:DIFFS[s.duelDiff]?s.duelDiff:'officer'},
  adminAt:Math.max(0,+p.adminAt||0),at:Math.max(0,+p.at||0)};
}
function mergeProfiles(a,b){
 if((a.adminAt||0)!==(b.adminAt||0))return cleanProfile((b.adminAt||0)>(a.adminAt||0)?b:a,a.name);
 const un={...a.ach.un};for(const [id,d] of Object.entries(b.ach.un))if(!un[id]||d<un[id])un[id]=d;
 const bst={...a.ach.best};for(const [id,v] of Object.entries(b.ach.best))bst[id]=Math.max(bst[id]||0,v);
 const st={};for(const k of ST_NUM)st[k]=Math.max(a.ach.st[k],b.ach.st[k]);
 for(const k of ST_MAP){st[k]={...a.ach.st[k]};for(const [id,v] of Object.entries(b.ach.st[k]))st[k][id]=Math.max(st[k][id]||0,v)}
 const newer=b.at>a.at?b:a,duels=[...new Map([...b.duels,...a.duels].map(h=>[h.id,h])).values()].sort((x,y)=>(+y.at||0)-(+x.at||0)).slice(0,20);
 return {name:newer.name,ach:{un,best:bst,st},best:Math.max(a.best,b.best),scores:mergeEntries(a.scores,b.scores).slice(0,PROFILE_RUNS),duels,set:newer.set||a.set||b.set,camp:mergeCamp(a.camp,b.camp),adminAt:a.adminAt||0,at:Math.max(a.at,b.at)};
}
// During a campaign mission the globals hold the mission's level and boat, so the sailor's own come from camp.saved.
function profSnapshot(){const own=camp.saved||{diffId,subId,practice};return cleanProfile({name:prof.name,ach:{un:ach.un,best:ach.best,st:ach.st},best,scores:prof.scores,duels:duel.history,
 set:{diff:own.diffId,practice:own.practice,sub:own.subId,rounds:duel.rounds,duelDiff:duel.diff},camp:camp.data,adminAt:prof.adminAt||0,at:prof.at},prof.name)}
// Settings only change between dives; mid-dive, only the record is taken in.
function profApply(p,settings=state==='menu'&&!cm){
 prof.adminAt=p.adminAt||0;ach.un=p.ach.un;ach.best=p.ach.best;ach.st=p.ach.st;best=p.best;camp.data=p.camp;prof.scores=p.scores;prof.at=p.at;duel.history=p.duels;
 if(p.scores.length){lb.local=mergeEntries(lb.local,p.scores).slice(0,100);store.set('undertow.local.v1',lb.local)}
 if(settings&&p.set){diffId=p.set.diff;subId=p.set.sub;D=DIFFS[diffId];S=SUB_BY_ID[subId];setMission(p.set.practice);duel.rounds=p.set.rounds;duel.diff=p.set.duelDiff;duel.diffSet=true;
  store.set('undertow.diff',diffId);store.set('undertow.sub',subId)}
 if(state==='menu'){reset();updateMenu()}else renderRank();
 if(panel==='duel')renderDuel();if(panel==='ach')renderAch();if(panel==='board')renderBoard();if(panel==='camp')renderCamp();campTile();
}
const profSaveLocal=()=>{const ok=store.set(PROFILE_PREFIX+prof.key,profSnapshot());if(!ok)saveStatus('profile','error','Profile could not be saved locally: storage is unavailable.');return ok};
// Saved here at once; the shared copy follows a moment later so a burst of changes is one write.
function profDirty(settings){if(!prof.key)return;if(settings)prof.at=Date.now();profSaveLocal();clearTimeout(prof.timer);prof.timer=setTimeout(()=>profSync(),2500)}
/* Reads the shared copy, merges it with this one, writes the result back if it differs,
   then takes in anything new (progress from another PC). Runs one at a time. */
async function profSync(){
 const key=prof.key,snap=profSnapshot();
 if(!key||key==='anonymous'||!lb.dir||lb.perm!=='granted')return false;
 if(prof.syncJob&&prof.syncKey===key)return prof.syncJob.then(()=>true,()=>false);
 prof.pulled=true;saveStatus('profile','busy','Saving progress to the shared drive…');
 const job=prof.chain.then(async()=>{
  const dir=await lb.dir.getDirectoryHandle(PROFILE_DIR,{create:true}),file=key+'.dat';let remote=null;
  try{const text=unseal(await readText(file,dir));if(text)remote=cleanProfile(JSON.parse(text),snap.name)}catch(e){if(!e||e.name!=='NotFoundError')throw e}
  const merged=remote?mergeProfiles(snap,remote):snap;
  if(!remote||JSON.stringify(merged)!==JSON.stringify(remote))for(let i=0;;i++){try{await writeText(file,seal(JSON.stringify(merged)),dir);break}catch(e){if(i>=4)throw e;await sleep(200*(i+1)+Math.random()*200)}}
  return {merged,found:!!remote};
 });
 prof.chain=job.catch(()=>{});prof.syncJob=job;prof.syncKey=key;
 try{
  const {merged,found}=await job;if(prof.key!==key)return true;
  // Merge again with this copy as it is now, in case it changed while the drive was busy.
  const now=mergeProfiles(profSnapshot(),merged);profApply(now);profSaveLocal();
  if(found&&prof.note==='new')prof.note='Loaded '+now.name+'’s profile from the shared folder.';
  else if(prof.note==='new'||prof.note==='local'||!prof.note)prof.note='Profile saved to the shared folder.';
  // Runs this sailor posted from a PC that never reached bin.dat.
  const miss=now.scores.filter(e=>!lb.admin.entries[e.id]&&!included(lb.shared,e)&&!pending().some(q=>q.id===e.id));
  if(miss.length){for(const e of miss)journalWrite(e);lbSync(false)}
  saveStatus('profile','done','Progress saved to the shared drive');renderRank();return true;
 }catch(e){saveStatus('profile','queued','Progress upload pending · Retrying automatically · Backup safe');if(prof.key===key){prof.pulled=false;prof.note='The shared profile could not be reached ('+(e&&e.message||e)+'). Progress is kept on this computer and syncs later.';renderRank()}return false}finally{if(prof.syncJob===job)prof.syncJob=null}
}
// Called when the callsign changes: save the old sailor, then load the new one.
function profSwitch(){
 const name=callsign(),key=duelKey(name);if(key===prof.key)return false;analyticsTick();analytics.context=null;
 if(prof.key){clearTimeout(prof.timer);profSaveLocal();profSync()}
 prof.key=key;prof.name=name;prof.pulled=false;prof.at=0;
 const local=store.get(PROFILE_PREFIX+key,null);
 const p=local?cleanProfile(local,name):blankProfile(name);p.name=name;
 prof.note=key==='anonymous'?'':local?'local':'new';
 profApply(p);if(!local)profSaveLocal();profSync();renderRank();return true;
}
// First load. The first time profiles exist, what this browser already holds belongs to its saved callsign.
function profInit(){
 const name=callsign(),key=duelKey(name),local=store.get(PROFILE_PREFIX+key,null);
 let migrated=false;try{migrated=!!localStorage.getItem('undertow.profiles');localStorage.setItem('undertow.profiles','1')}catch(_){}
 prof.key=key;prof.name=name;prof.note=key==='anonymous'?'':'local';
 if(local)profApply(cleanProfile(local,name));
 else if(!migrated){prof.scores=lb.local.filter(e=>duelKey(e.name)===key).slice(0,PROFILE_RUNS);prof.at=Date.now();profSaveLocal()}
 else profApply(blankProfile(name));
}
function renderRank(){
 const x=profXp(),L=levelOf(x),lo=xpFor(L),hi=xpFor(L+1),max=L>=LEVEL_MAX;
 $('rankName').textContent='LEVEL '+L+' / '+rankTitle(L);
 $('rankXp').textContent=max?x.toLocaleString()+' XP':(x-lo).toLocaleString()+' / '+(hi-lo).toLocaleString()+' XP TO LEVEL '+(L+1);
 $('xpBar').style.width=(max?100:clamp((x-lo)/(hi-lo),0,1)*100)+'%';
 const connected=lb.dir&&lb.perm==='granted',n=prof.note;
 $('profNote').textContent=prof.key==='anonymous'?'Enter a callsign to keep your level, achievements and settings.':
  n==='new'?(connected?'Looking for '+prof.name+' in the shared folder...':'New callsign. Connect the shared folder to load a saved profile or carry this one to other PCs.'):
  n==='local'?(connected?'Profile loaded. Syncing with the shared folder...':'Profile loaded from this computer. Connect the shared folder to sync it.'):n;
}
