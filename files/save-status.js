'use strict';
const saveJobs=new Map();
function saveStatus(scope,stage,message){saveJobs.set(scope,{stage,message,at:Date.now()});renderSaveStatus()}
function renderSaveStatus(){
 let box=$('saveStatus');if(!box){
  box=document.createElement('div');box.id='saveStatus';box.innerHTML='<button type="button" class="icon" id="saveStatusButton" aria-describedby="saveStatusDetails" aria-expanded="false"><span class="save-symbol" aria-hidden="true"></span></button><div id="saveStatusDetails" role="tooltip"></div>';
  document.querySelector('.tools').prepend(box);
  const button=$('saveStatusButton');button.onclick=()=>{const open=box.classList.toggle('open');button.setAttribute('aria-expanded',String(open))};
  document.addEventListener('pointerdown',e=>{if(!box.contains(e.target)){box.classList.remove('open');button.setAttribute('aria-expanded','false')}});
  button.addEventListener('keydown',e=>{if(e.key==='Escape'){box.classList.remove('open');button.setAttribute('aria-expanded','false');button.blur()}});
 }
 const jobs=[...saveJobs.values()],failed=jobs.some(j=>j.stage==='error'),busy=jobs.some(j=>j.stage==='busy'),queued=jobs.some(j=>j.stage==='queued');
 const connected=lb.perm==='granted',count=pending().length;
 const stage=failed?'error':busy?'busy':queued||!connected?'error':count?'busy':'done';
 const headline=stage==='done'?'Saved to the shared drive':stage==='busy'?'Saving to the shared drive…':'Shared-drive save needs attention';
 box.dataset.stage=stage;
 box.querySelector('.save-symbol').innerHTML=stage==='busy'?'<span class="save-spinner"></span>':stage==='done'?'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="m5 12 4 4L19 6"/></svg>':'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="m6 6 12 12M18 6 6 18"/></svg>';
 const details=$('saveStatusDetails');details.textContent='';const title=document.createElement('strong');title.textContent=headline;details.append(title);
 const lines=[...new Set(jobs.map(j=>j.message))];if(!connected)lines.push('Allow access to the shared folder to resume uploads.');if(count)lines.push(count+' score(s) waiting for the shared drive.');if(stage==='error')lines.push('Automatic retries remain active.');
 for(const text of lines){const line=document.createElement('span');line.textContent=text;details.append(line)}
 $('saveStatusButton').setAttribute('aria-label',[headline,...lines].join('. '));
}
addEventListener('DOMContentLoaded',renderSaveStatus);
