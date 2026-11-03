'use strict';
/* Each finished run has its own atomic localStorage record, so another round or
   browser tab cannot replace the upload queue. IndexedDB is a second local copy. */
const SCORE_PREFIX='undertow.score.v2.',scoreMemory=new Map();
function journalRows(){
 const rows=new Map(scoreMemory);try{for(const k of storeKeys(SCORE_PREFIX)){const r=store.get(k,null),e=r&&cleanEntry(r.entry);if(e)rows.set(e.id,{...r,entry:e})}}catch(_){}return [...rows.values()];
}
function journalWrite(entry,uploaded=false){const row={entry:cleanEntry(entry),uploaded};if(!row.entry)return false;scoreMemory.set(entry.id,row);const ok=store.set(SCORE_PREFIX+entry.id,row);idbSet(SCORE_PREFIX+entry.id,row).catch(()=>{});return ok}
function journalPending(){
 const rows=new Map();for(const e of (store.get('undertow.pending.v1',[])||[]).map(cleanEntry).filter(Boolean))rows.set(e.id,e);
 for(const r of journalRows())if(!r.uploaded)rows.set(r.entry.id,r.entry);return [...rows.values()];
}
function journalAcknowledge(queue){
 for(const e of queue)journalWrite(e,true);
 store.set('undertow.pending.v1',(store.get('undertow.pending.v1',[])||[]).filter(e=>!queue.some(q=>q.id===e.id)));
}
function journalReconcile(board){
 const admin=cleanBoardAdmin(board.admin),remote=new Set(board.entries.map(e=>e.id));
 for(const r of journalRows())if(r.uploaded&&!remote.has(r.entry.id)&&!admin.entries[r.entry.id])journalWrite(r.entry,false);
}
async function journalRestore(){
 // Recover the redundant copy and migrate old, bounded local score lists.
 try{const rows=await idb('readonly',s=>s.getAll());for(const r of rows||[]){const e=r&&cleanEntry(r.entry);if(e&&!store.get(SCORE_PREFIX+e.id,null)){scoreMemory.set(e.id,{entry:e,uploaded:!!r.uploaded});store.set(SCORE_PREFIX+e.id,{entry:e,uploaded:!!r.uploaded})}}}catch(_){}
 const existing=new Set(journalRows().map(r=>r.entry.id));for(const e of [...lb.local,...(store.get('undertow.pending.v1',[])||[])])if(!existing.has(e.id)){journalWrite(e);existing.add(e.id)}
 try{for(const k of storeKeys(PROFILE_PREFIX)){for(const e of (store.get(k,{})||{}).scores||[])if(!existing.has(e.id)){journalWrite(e);existing.add(e.id)}}}catch(_){}
 lb.local=mergeEntries(lb.local,journalRows().map(r=>r.entry));renderBoard();
}
async function persistScore(entry){
 const e=cleanEntry({...entry});if(!e)throw Error('Invalid score.');
 // This happens synchronously, before the first shared-drive await.
 const stored=journalWrite(e);lb.local=mergeEntries(lb.local,[e]);store.set('undertow.local.v1',lb.local);
 lb.mine.add(e.id);store.set('undertow.mine.v1',[...lb.mine]);prof.scores=mergeEntries(prof.scores,[e]).slice(0,PROFILE_RUNS);profDirty(false);
 if(!stored){saveStatus('scores','busy','Securing score backup before upload…');try{await idbSet(SCORE_PREFIX+e.id,{entry:e,uploaded:false})}catch(_){saveStatus('scores','error','Local storage is full or unavailable. Score is only held in this open game.');return 'storage-error'}}
 // It waits here until the player presses Save; nothing is sent to the shared drive automatically.
 renderSaveStatus();
 return lb.supported?'pending':'local';
}
// Another tab of this game finished a run: show it here too.
addEventListener('storage',ev=>{const k=ev.key&&ev.key.replace(/^offline\./,'');if(k&&(k.startsWith(SCORE_PREFIX)||k==='undertow.pending.v1')){lb.local=mergeEntries(lb.local,journalRows().map(r=>r.entry));renderBoard();renderSaveStatus()}});
addEventListener('pagehide',()=>{if(prof.key)profSaveLocal()});
