'use strict';
// One status surface for local persistence, shared uploads, profiles and admin edits.
const saveJobs=new Map();
function saveStatus(scope,stage,message){saveJobs.set(scope,{stage,message,at:Date.now()});renderSaveStatus()}
function renderSaveStatus(){
 let box=$('saveStatus');if(!box){box=document.createElement('div');box.id='saveStatus';box.setAttribute('role','status');box.setAttribute('aria-live','polite');box.innerHTML='<span class="save-spinner" aria-hidden="true"></span><span class="save-copy"></span>';document.body.append(box)}
 const jobs=[...saveJobs.entries()],priority=j=>j[1].stage==='error'?5:j[0]==='admin'&&j[1].stage==='busy'?4:j[1].stage==='busy'?3:j[1].stage==='queued'?2:1;
 jobs.sort((a,b)=>priority(b)-priority(a)||b[1].at-a[1].at);const job=jobs[0]&&jobs[0][1];box.hidden=!job;if(!job)return;
 box.dataset.stage=job.stage;box.querySelector('.save-copy').textContent=job.message;
}
