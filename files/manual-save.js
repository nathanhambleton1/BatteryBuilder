'use strict';
/* ---- Manual save ------------------------------------------------------------
   This edition only touches the shared folder when a player clicks. Between clicks,
   scores (score journal), profile, medals and preferences (profile) build up in this
   browser. Save sends them in one pass, at most once a minute:
     1. profile   profiles\<callsign>.dat: read, merge, write only if it changed
     2. scores    bin.dat: only with a new score or medal: read, lock, merge, write, verify
   Refresh on the Leaderboard and admin screens only reads bin.dat; Save never refreshes
   the board unless it has to post to it. Nothing runs on a timer, on focus or on page
   close, so an idle game never touches the drive. */
const saveJob={busy:false,at:Math.max(0,+store.get('undertow.saved-at',0)||0),changed:Math.max(0,+store.get('undertow.changed-at',0)||0),tried:Math.max(0,+store.get('undertow.save-tried-at',0)||0),openTimer:0,tick:0};
const SAVE_COOLDOWN=60000;
// Seconds until Save may run again (kept across reloads, so reopening the game does not skip it).
const saveWait=()=>Math.max(0,Math.ceil((saveJob.tried+SAVE_COOLDOWN-Date.now())/1000));
const FOLDER_ACCESS={mode:'readwrite'};
function saveMarkChanged(){saveJob.changed=Date.now();store.set('undertow.changed-at',saveJob.changed);renderSaveStatus()}
/* Called from a click. A web page cannot open a folder by its path, so each browser is pointed at
   SHARED_DIR once; the folder is remembered (IndexedDB) and from then on Save, Refresh and admin
   edits only bring up the browser's own "Allow" prompt. The folder window opens again only if the
   remembered folder can no longer be used, or from the admin console's Change shared folder. */
async function saveFolder(){
 if(!lb.supported){lb.note='This browser cannot use shared folders. Use Microsoft Edge or Google Chrome.';return false}
 if(lb.dir)try{if(await lb.dir.queryPermission(FOLDER_ACCESS)==='granted'||await lb.dir.requestPermission(FOLDER_ACCESS)==='granted'){lb.perm='granted';return true}lb.perm='prompt';lb.note='Folder access was not allowed. Press the button again and choose Allow (or Allow on every visit).';return false}
 catch(_){lb.dir=null}
 if(!confirm('One-time setup for this computer: in the next window, open\n\n'+SHARED_DIR+'\n\nand choose Select Folder. The game remembers it, so after this you only see the browser\'s Allow prompt.'))return false;
 return lbPick();
}
// Choose the shared folder. One without the leaderboard is probably the wrong one, so starting a new board there must be deliberate.
async function lbPick(){
 if(!lb.supported)return false;let dir;
 try{const o={id:'undertow',mode:'readwrite'};try{dir=await window.showDirectoryPicker(lb.dir?{...o,startIn:lb.dir}:o)}catch(e){if(e&&e.name==='AbortError')throw e;dir=await window.showDirectoryPicker(o)}}
 catch(e){lb.note=e&&e.name==='AbortError'?'No folder was chosen.':'Could not open the folder: '+(e&&e.message||e);renderBoard();renderSaveStatus();return false}
 let found=false;for(const name of [BOARD_FILE,BACKUP_FILE,LEGACY_FILE]){try{await dir.getFileHandle(name);found=true;break}catch(_){}}
 if(!found&&!confirm('"'+dir.name+'" has no '+BOARD_FILE+', so it is not the team’s shared game folder yet.\n\nStart a new shared leaderboard in this folder?')){lb.note='Choose the folder that holds '+BOARD_FILE+'.';renderBoard();return false}
 lb.dir=dir;lb.perm='granted';lb.note='';lb.source='shared';try{await idbSet('folder',dir)}catch(_){}
 renderBoard();renderSaveStatus();return true;
}
// Read-only: the latest bin.dat, for the Leaderboard and admin screens.
async function boardRefresh(){
 if(saveJob.busy)return false;
 if(!await saveFolder()){renderBoard();renderSaveStatus();return false}
 saveJob.busy=true;renderBoard();renderSaveStatus();
 try{lbTake(await lbRead());lb.note='';return true}
 catch(e){lb.note='Could not read '+BOARD_FILE+': '+(e&&e.message||e);return false}
 finally{saveJob.busy=false;renderBoard();renderSaveStatus();if(panel==='ach')renderAch()}
}
async function saveAll(){
 if(saveJob.busy)return;
 if(saveWait()){saveShowDetails();return}
 saveJobs.clear();
 if(!await saveFolder()){saveStatus('folder','error',lb.note||'The shared folder is not available.');saveShowDetails();return}
 saveJob.busy=true;saveJob.tried=Date.now();store.set('undertow.save-tried-at',saveJob.tried);renderSaveStatus();renderBoard();
 const started=Date.now();let ok=true;
 try{
  // Profile first: it can turn up runs from another PC that never reached the board.
  if(prof.key&&prof.key!=='anonymous')ok=await profSync()&&ok;
  // The board is only opened when there is something to post: a new score, or medals/XP newer than
  // the copy last seen. Otherwise Save leaves bin.dat alone (Refresh is the way to read it).
  const queued=pending().length;
  if(queued||!playerCurrent(lb.players)){
   saveStatus('scores','busy','Saving scores…');
   try{const job=lbChain.then(()=>lbFlush());lbChain=job.catch(()=>{});await job;lbTake({entries:lb.shared,players:lb.players,admin:lb.admin});lb.note='';
    saveStatus('scores','done',queued?queued+' score'+(queued>1?'s':'')+' posted to the shared leaderboard':'Medals and level posted to the shared leaderboard')}
   catch(e){ok=false;lb.note='Could not update '+BOARD_FILE+': '+(e&&e.message||e)+'. Your scores are kept on this computer.';saveStatus('scores','error','Scores not saved: '+(e&&e.message||e))}
  }else saveStatus('scores','done','No new scores to post');
  if(ok){saveJob.at=started;store.set('undertow.saved-at',started)}
 }finally{saveJob.busy=false;renderBoard();renderSaveStatus();renderRank();if(panel==='ach')renderAch()}
 saveShowDetails();
}
// Count the cooldown down on the button; only the label changes, nothing is read or written.
setInterval(()=>{if(saveWait()||saveJob.tick){saveJob.tick=saveWait();renderSaveStatus()}},1000);
// Show what the Save did for a few seconds, then fold it back under the button.
function saveShowDetails(){const box=$('saveStatus');if(!box)return;box.classList.add('open');clearTimeout(saveJob.openTimer);saveJob.openTimer=setTimeout(()=>box.classList.remove('open'),4500)}
addEventListener('keydown',e=>{if((e.ctrlKey||e.metaKey)&&e.code==='KeyS'&&!e.repeat){e.preventDefault();e.stopPropagation();void saveAll()}},true);
// Leaving with scores that never reached the shared leaderboard gets the browser's "Leave site?" check.
addEventListener('beforeunload',e=>{if(lb.supported&&pending().length){e.preventDefault();e.returnValue=''}});

// Duels need constant polling of the shared folder, so this edition leaves them out.
duelTick=async()=>{};duelBeat=async()=>{};
for(const id of ['duelChip','sfGate','duelConnect','duelRefresh']){const node=$(id);if(node){node.hidden=true;node.style.display='none'}}
$('duelOpen').closest('.tile').style.display='none';
$('ach').querySelector('p').textContent='Earn medals as you play. All submarines and campaign missions are available from the start.';
const manualOpenPanel=openPanel;openPanel=id=>{if(['duel','sfGate'].includes(id))return;manualOpenPanel(id)};
