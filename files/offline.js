'use strict';
// Local-only persistence boundary. Never restore or request a filesystem handle.
Object.defineProperty(lb,'dir',{value:null,writable:false});
lb.source='local';lb.gate.offline=true;
lbPick=async()=>false;lbPermitted=async()=>false;lbSync=async()=>false;
sfCheck=async()=>{};
readText=async()=>{throw Error('Filesystem access is disabled in the offline edition')};
writeText=async()=>{throw Error('Filesystem access is disabled in the offline edition')};
duelTick=async()=>{};duelBeat=async()=>{};
profSync=async()=>false;
profDirty=function(settings){if(!prof.key)return;if(settings)prof.at=Date.now();profSaveLocal()};
backgroundSaveTick=()=>{};
initializeSharedScores=async()=>{renderBoard()};
persistScore=async function(entry){
 const e=cleanEntry(entry);if(!e)throw Error('Invalid score');
 lb.local=mergeEntries(lb.local,[e]).slice(0,100);
 lb.mine.add(e.id);prof.scores=mergeEntries(prof.scores,[e]).slice(0,PROFILE_RUNS);
 const saved=store.set('undertow.local.v1',lb.local);
 store.set('undertow.mine.v1',[...lb.mine]);profDirty(false);
 saveStatus('scores',saved?'done':'error',saved?'Saved on this computer':'Browser storage unavailable');
 renderBoard();return saved?'local':'storage-error';
};
renderChip=()=>{$('lbChip').querySelector('span').textContent='OFFLINE / THIS COMPUTER'};
for(const id of ['duelOpen','duelChip','statsOpen','lbConnect','srcSeg','sfGate','duelConnect','duelRefresh']){
 const node=$(id);if(node){node.hidden=true;node.style.display='none'}
}
$('duelOpen').closest('.tile').style.display='none';
$('ach').querySelector('p').textContent='Earn medals as you play. All submarines and campaign missions are available from the start.';

for(const id of ['boardOpen','statsOpen'])$(id).closest('.tile').style.display='none';
for(const id of ['lbChip','overBoard','achSeg'])$(id).style.display='none';
const offlineOpenPanel=openPanel;openPanel=id=>{if(['board','statistics','duel','sfGate'].includes(id))return;offlineOpenPanel(id)};
