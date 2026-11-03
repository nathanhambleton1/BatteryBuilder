'use strict';
/* ---- Manual save ------------------------------------------------------------
   This edition only touches the shared folder when a player clicks. Between clicks,
   scores (score journal), profile, medals, preferences (profile) and activity
   (analytics) build up in this browser. Save sends all of it in one pass:
     1. profile   profiles\<name>.dat: read, merge, write only if it changed
     2. scores    bin.dat: read; only when something is new, lock, merge, write, verify
     3. activity  analytics\<session>.dat: write each changed record and read it back
   Refresh on the Leaderboard, Statistics and admin screens only reads. Nothing runs
   on a timer, on focus or on page close, so an idle game never touches the drive. */
const saveJob={busy:false,at:Math.max(0,+store.get('undertow.saved-at',0)||0),changed:Math.max(0,+store.get('undertow.changed-at',0)||0),openTimer:0};
const FOLDER_ACCESS={mode:'readwrite'};
function saveMarkChanged(){saveJob.changed=Date.now();store.set('undertow.changed-at',saveJob.changed);renderSaveStatus()}
// Called from a click (the browser only asks for folder access during one). Uses the remembered
// folder when there is one, otherwise lets the player choose it.
async function saveFolder(){
 if(!lb.supported){lb.note='This browser cannot use shared folders. Use Microsoft Edge or Google Chrome.';return false}
 if(!lb.dir)return lbPick();
 try{if(await lb.dir.queryPermission(FOLDER_ACCESS)==='granted'||await lb.dir.requestPermission(FOLDER_ACCESS)==='granted'){lb.perm='granted';return true}}
 catch(e){lb.note='The remembered folder could not be opened ('+(e&&e.message||e)+'). Choose it again from the Leaderboard screen.';return false}
 lb.perm='prompt';lb.note='Folder access was not allowed. Press Save again and choose Allow (or Allow on every visit).';return false;
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
// Read-only: the latest bin.dat, for the Leaderboard, Statistics and admin screens.
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
 saveJobs.clear();
 if(!await saveFolder()){saveStatus('folder','error',lb.note||'The shared folder is not available.');saveShowDetails();return}
 saveJob.busy=true;renderSaveStatus();renderBoard();
 const started=Date.now();let ok=true;
 try{
  analyticsTick();
  // Profile first: it can turn up runs from another PC that never reached the board.
  if(prof.key&&prof.key!=='anonymous')ok=await profSync()&&ok;
  const queued=pending().length;saveStatus('scores','busy','Saving scores…');
  try{
   const r=await lbRead();journalReconcile(r);lbTake(r);
   if(pending().length||!playerCurrent(lb.players)){const job=lbChain.then(()=>lbFlush());lbChain=job.catch(()=>{});await job;lbTake({entries:lb.shared,players:lb.players,admin:lb.admin})}
   lb.note='';saveStatus('scores','done',queued?queued+' score'+(queued>1?'s':'')+' posted to the shared leaderboard':'Leaderboard up to date');
  }catch(e){ok=false;lb.note='Could not update '+BOARD_FILE+': '+(e&&e.message||e)+'. Your scores are kept on this computer.';saveStatus('scores','error','Scores not saved: '+(e&&e.message||e))}
  await analyticsSync();if(analytics.dirty.size)ok=false;
  if(ok){saveJob.at=started;store.set('undertow.saved-at',started)}
 }finally{saveJob.busy=false;renderBoard();renderSaveStatus();renderRank();if(panel==='ach')renderAch();if(panel==='statistics')analyticsRender()}
 saveShowDetails();
}
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
