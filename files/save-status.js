'use strict';
// The Save button in the top right. Its details list what is waiting and what the last Save did.
const saveJobs=new Map();
function saveStatus(scope,stage,message){saveJobs.set(scope,{stage,message,at:Date.now()});renderSaveStatus()}
const SAVE_ICONS={
 busy:'<span class="save-spinner"></span>',
 done:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="m5 12 4 4L19 6"/></svg>',
 dirty:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6"><path d="M5 4h11l3 3v13H5z"/><path d="M8 4v5h7V4M8 20v-6h8v6"/></svg>',
 error:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="m6 6 12 12M18 6 6 18"/></svg>'};
function renderSaveStatus(){
 let box=$('saveStatus');if(!box){
  box=document.createElement('div');box.id='saveStatus';box.innerHTML='<button type="button" id="saveStatusButton" aria-describedby="saveStatusDetails" title="Save to the shared folder (Ctrl+S)"><span class="save-symbol" aria-hidden="true"></span><span class="save-label"></span><span class="save-count" hidden></span></button><div id="saveStatusDetails" role="tooltip"></div>';
  document.querySelector('.tools').prepend(box);
  $('saveStatusButton').onclick=()=>saveAll();
  document.addEventListener('pointerdown',e=>{if(!box.contains(e.target))box.classList.remove('open')});
 }
 // Scripts after this one (score journal, manual save) are not loaded yet on the first call.
 if(typeof saveJob==='undefined'||typeof journalPending!=='function')return;
 // Until the first Save, progress from the shared folder has not been loaded either.
 const jobs=[...saveJobs.values()],failed=jobs.some(j=>j.stage==='error'),scores=lb.supported?pending().length:0,changed=saveJob.changed>saveJob.at||!saveJob.at;
 const stage=saveJob.busy?'busy':failed?'error':scores||changed?'dirty':'done';
 box.dataset.stage=stage;
 box.querySelector('.save-symbol').innerHTML=SAVE_ICONS[stage];
 // Save may run once a minute; the label counts down the rest of that minute.
 const wait=saveJob.busy?0:saveWait(),clock=wait?' '+Math.floor(wait/60)+':'+String(wait%60).padStart(2,'0'):'';
 box.querySelector('.save-label').textContent=({busy:'SAVING…',error:'RETRY SAVE',dirty:'SAVE',done:'SAVED'}[stage])+clock;
 const count=box.querySelector('.save-count');count.hidden=!scores||saveJob.busy;count.textContent=scores;
 $('saveStatusButton').disabled=saveJob.busy||!!wait;box.classList.toggle('cooling',!!wait);
 const headline={busy:'Saving to the shared folder…',error:'The last save did not finish',dirty:'You have unsaved progress',done:'Everything is saved'}[stage];
 const lines=[];
 if(!lb.supported)lines.push('This browser cannot use shared folders. Use Microsoft Edge or Google Chrome.');
 if(scores)lines.push(scores+' score'+(scores>1?'s':'')+' waiting for the shared leaderboard.');
 if(saveJob.changed>saveJob.at)lines.push('Progress, medals or preferences changed since the last save.');
 // What the last Save did, until something new needs saving.
 if(stage==='done'||stage==='error')for(const text of new Set(jobs.map(j=>j.message)))lines.push(text);
 lines.push(saveJob.at?'Last saved '+whenText({at:saveJob.at})+'.':'Not saved from this computer yet.');
 if(wait)lines.push('Save is available again in '+wait+' second'+(wait>1?'s':'')+'.');
 lines.push('The shared folder is only used when you press Save or Refresh. Save can be used once a minute.');
 const details=$('saveStatusDetails');details.textContent='';const title=document.createElement('strong');title.textContent=headline;details.append(title);
 for(const text of lines){const line=document.createElement('span');line.textContent=text;details.append(line)}
 $('saveStatusButton').setAttribute('aria-label',['Save',headline,...lines].join('. '));
}
addEventListener('DOMContentLoaded',renderSaveStatus);
