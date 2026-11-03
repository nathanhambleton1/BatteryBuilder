'use strict';
// This offline game's service password is a convenience gate, not a security
// boundary. Access lives only in memory. Saved board corrections are independent.
const secretAdmin={active:false,source:'shared',id:'',busy:false,keys:[],clicks:0,lastClick:0};
function cleanBoardAdmin(raw){
 const out={entries:{},players:{},aliases:{}};if(!raw||typeof raw!=='object')return out;
 // Username migrations: aliases[old lower-case callsign] = {at, value: new name}; value null once removed.
 for(const [id,r] of Object.entries(raw.aliases||{})){
  const k=String(id).toLowerCase().slice(0,16);if(!r||!Number.isFinite(r.at)||r.at<=0||['__proto__','constructor','prototype'].includes(k))continue;
  const value=r.value===null?null:String(r.value||'').replace(/[\u0000-\u001f]/g,'').trim().slice(0,16);
  if(value===null||value&&value.toLowerCase()!==k)out.aliases[k]={at:r.at,value};
 }
 for(const type of ['entries','players'])for(const [id,r] of Object.entries(raw[type]||{})){
  if(!r||!Number.isFinite(r.at)||r.at<=0||id==='__proto__'||id==='constructor'||id==='prototype')continue;
  const value=r.value===null?null:type==='entries'?cleanEntry({...r.value,id}):cleanPlayers({[id]:r.value})[id];
  if(value!==undefined&&(value!==null||r.value===null))out[type][id]={at:r.at,value};
 }return out;
}
// The name a callsign now counts as, following migrations (a few hops at most, so a loop cannot hang).
function aliasName(name,admin=lb.admin){const a=admin&&admin.aliases||{};let n=name;for(let i=0;i<8;i++){const r=a[String(n).toLowerCase()];if(!r||!r.value)break;n=r.value}return n}
function boardAdminEntries(entries,admin){
 const map=new Map(entries.map(e=>[e.id,e]));for(const [id,r] of Object.entries(admin&&admin.entries||{})){if(r.value===null)map.delete(id);else map.set(id,r.value)}
 return [...map.values()].map(e=>{const name=aliasName(e.name,admin);return name===e.name?e:{...e,name}}).sort((a,b)=>b.score-a.score);
}
function boardAdminPlayers(players,admin){
 const out={...players};for(const [id,r] of Object.entries(admin&&admin.players||{})){if(r.value===null)delete out[id];else out[id]=r.value}
 // A migrated callsign's medals and XP join the new name's record.
 for(const [id,p] of Object.entries(out)){const name=aliasName(p.name,admin),k=name.toLowerCase();if(k===id)continue;delete out[id];out[k]=mergePlayer(out[k],{...p,name})}
 return out;
}
const localBoardAdmin=()=>cleanBoardAdmin(store.get('undertow.board-admin.v1',{}));
function adminShow(){
 if(duel.run||duel.watch||cine.on)return;
 if(state==='playing')pause();
 let box=$('secretAdmin');if(!box){
  box=document.createElement('section');box.id='secretAdmin';box.className='view overlay';box.setAttribute('role','dialog');box.setAttribute('aria-modal','true');box.setAttribute('aria-label','Service panel');
  box.innerHTML='<div class="panel wide"><div class="eyebrow">SERVICE ACCESS</div><h2>Captain’s console</h2><form id="adminLogin"><label>Password <input id="adminPassword" type="password" autocomplete="off" required></label><button class="launch">Unlock</button></form><div id="adminTools" hidden><p>Records shown are from the last Save or Refresh. Each edit is written to the shared drive and verified when you confirm it.</p><label>Board <select id="adminSource"><option value="shared">Scores · shared fleet</option><option value="players">Achievements / XP · shared fleet</option><option value="profiles">Profiles / campaign · shared fleet</option><option value="migrate">Username migration · shared fleet</option></select></label><button id="adminRefresh" type="button">Refresh board</button><input id="adminSearch" placeholder="Search callsign, class, score, difficulty, date or ID" aria-label="Find record"><label>Sort by <select id="adminSort"><option value="name">Callsign</option><option value="sub">Ship class</option><option value="score">Score</option><option value="distance">Distance</option><option value="ships">Ships sunk</option><option value="diff">Difficulty</option><option value="date">Date</option><option value="xp">XP</option><option value="ach">Achievements</option><option value="id">Record ID</option></select></label><label>Order <select id="adminOrder"><option value="asc">Ascending</option><option value="desc">Descending</option></select></label><p id="adminCount"></p><select id="adminRecords" size="7" aria-label="Leaderboard records"></select><form id="adminEditor"></form><div class="admin-actions"><button id="adminNew" type="button">New score</button><button id="adminDelete" type="button">Delete selected record</button></div></div><p id="adminMessage" role="status"></p><button id="adminClose" class="launch">Close</button></div>';
  document.body.append(box);installPopupClose(box);
  $('adminLogin').onsubmit=ev=>{ev.preventDefault();if($('adminPassword').value!=='subs'){$('adminMessage').textContent='Incorrect password.';$('adminPassword').value='';return}secretAdmin.active=true;$('adminPassword').value='';adminRender();lbSync(false).then(()=>{if(secretAdmin.active)adminRender()});if(panel==='camp')renderCamp()};
  $('adminClose').onclick=()=>{box.hidden=true;if(panel==='camp')renderCamp()};
  $('adminSource').onchange=()=>{secretAdmin.source=$('adminSource').value;secretAdmin.id='';adminRender()};
  $('adminSearch').oninput=adminList;$('adminSort').onchange=adminList;$('adminOrder').onchange=adminList;
  $('adminRecords').onchange=()=>{secretAdmin.id=$('adminRecords').value;adminEditor()};
  $('adminRefresh').onclick=async()=>{if(!await boardRefresh()){$('adminMessage').textContent='The shared folder is not available. '+(lb.note||'');return}adminRender()};
  $('adminNew').onclick=()=>{secretAdmin.id='';adminEditor(true)};
  $('adminDelete').onclick=()=>adminSave(true);
 }
 box.hidden=false;adminRender();(secretAdmin.active?$('adminSource'):$('adminPassword')).focus();
}
function adminRows(){if(secretAdmin.source==='migrate')return adminCallsigns();return ['players','profiles'].includes(secretAdmin.source)?Object.entries(boardAdminPlayers(lb.players,lb.admin)).map(([id,p])=>({id,...p})):boardAdminEntries(lb.shared,lb.admin)}
function adminRender(){
 $('adminLogin').hidden=secretAdmin.active;$('adminTools').hidden=!secretAdmin.active;$('adminMessage').textContent=secretAdmin.active?'Session access active. Refreshing the page locks this console.':'';
 if(secretAdmin.active){$('adminSource').value=secretAdmin.source;adminList();adminEditor()}
}
function adminList(){
 const select=$('adminRecords'),q=$('adminSearch').value.toLowerCase().trim().split(/\s+/).filter(Boolean),key=$('adminSort').value,dir=$('adminOrder').value==='desc'?-1:1;select.textContent='';
 const val=r=>key==='ach'?Object.keys(r.ach||{}).length:key==='sub'?(SUB_BY_ID[r.sub]?.name||r.sub||''):r[key]??'';
 const rows=adminRows().filter(r=>{const text=[...Object.values(r),SUB_BY_ID[r.sub]?.name,DIFFS[r.diff]?.label,Object.keys(r.ach||{}).join(' ')].join(' ').toLowerCase();return q.every(term=>text.includes(term))}).sort((a,b)=>{const x=val(a),y=val(b);return dir*(typeof x==='number'&&typeof y==='number'?x-y:String(x).localeCompare(String(y),undefined,{numeric:true}))||a.id.localeCompare(b.id)});$('adminCount').textContent=rows.length+' matching records';
 for(const r of rows){const o=document.createElement('option');o.value=r.id;o.textContent=r.name+' · '+(secretAdmin.source==='migrate'?(r.to?'migrated to '+r.to:r.scores+' score(s) · best '+r.best.toLocaleString()):secretAdmin.source!=='shared'?Object.keys(r.ach).length+' achievements / '+r.xp+' XP':r.score.toLocaleString()+' · '+(SUB_BY_ID[r.sub]?.name||r.sub)+' · '+DIFFS[r.diff].label+' · '+r.date);select.append(o)}
 select.value=secretAdmin.id;
}
function adminEditor(fresh=false){
 const form=$('adminEditor');form.textContent='';if(secretAdmin.source==='profiles'){adminProfileEditor(form);return}if(secretAdmin.source==='migrate'){adminMigrateEditor(form);return}const player=secretAdmin.source==='players',r=adminRows().find(r=>r.id===secretAdmin.id);
 $('adminNew').hidden=player;$('adminDelete').disabled=!r||secretAdmin.busy;if(!r&&!fresh){form.textContent='Select a record to edit.';return}
 const field=(name,label,value,type='text')=>{const l=document.createElement('label'),i=document.createElement('input');l.textContent=label;i.name=name;i.type=type;i.value=value??'';i.required=true;if(type==='number'){i.min='0';i.max='1000000000';i.step='1'}if(name==='name')i.maxLength=16;l.append(i);form.append(l);return i};
 field('name','Callsign',r?r.name:'');
 if(player){form.elements.name.readOnly=true;field('xp','XP',r.xp,'number');const grid=document.createElement('div');grid.className='admin-achievements';
  for(const a of ACHS){const l=document.createElement('label'),i=document.createElement('input');i.type='checkbox';i.name='achievement';i.value=a.id;i.checked=!!r.ach[a.id];l.append(i,document.createTextNode(a.name));grid.append(l)}form.append(grid);
 }else{field('score','Score',r?r.score:0,'number');field('distance','Distance (m)',r?r.distance:0,'number');field('ships','Ships sunk',r?r.ships:0,'number');
  for(const [name,label,opts,def] of [['sub','Submarine',SUBS.map(s=>[s.id,s.name]),'gato'],['diff','Difficulty',Object.entries(DIFFS).map(([id,d])=>[id,d.label]),'officer']]){const l=document.createElement('label'),s=document.createElement('select');l.textContent=label;s.name=name;for(const [id,text] of opts){const o=document.createElement('option');o.value=id;o.textContent=text;s.append(o)}s.value=r?r[name]:def;l.append(s);form.append(l)}field('date','Date',r&&r.date||new Date().toISOString().slice(0,10),'date');
 }
 const save=document.createElement('button');save.type='submit';save.className='launch';save.textContent='Save leaderboard changes';form.append(save);form.onsubmit=ev=>{ev.preventDefault();adminSave(false)};
}
async function adminCommit(source,id,value){
 if(!secretAdmin.active)throw Error('Service access is locked.');
 const type=source==='players'?'players':source==='migrate'?'aliases':'entries',correction=cleanBoardAdmin({[type]:{[id]:{at:Date.now(),value}}})[type][id];if(!correction)throw Error('Invalid leaderboard record.');
 if(!['shared','players','migrate'].includes(source))throw Error('Admin edits must target the shared drive.');
 if(!await saveFolder())throw Error('Choose the shared folder first.');
 const job=lbChain.then(()=>withLock(async (locked,owns)=>{
  if(!locked)throw Error('The shared leaderboard is busy. Try saving again.');
  const board=await lbRead(),admin=cleanBoardAdmin(board.admin);admin[type][id]=correction;
  // Migrating back undoes the opposite mapping instead of making a loop.
  if(type==='aliases'&&value){const back=admin.aliases[value.toLowerCase()];if(back&&back.value&&back.value.toLowerCase()===id)admin.aliases[value.toLowerCase()]={at:correction.at,value:null}}
  const result={game:'UNDERTOW',version:5,updated:new Date().toISOString(),entries:boardAdminEntries(board.entries,admin),players:boardAdminPlayers(board.players,admin),admin};
  // Save the previous readable version before replacing the board.
  await owns();await writeText(BACKUP_FILE,seal(JSON.stringify(board)));await owns();await writeText(BOARD_FILE,seal(JSON.stringify(result)));await owns();
  const verified=await lbRead();if(JSON.stringify(verified.admin[type][id])!==JSON.stringify(correction))throw Error('The change could not be verified. Refresh the board before retrying.');
  lbTake(verified);
 }));lbChain=job.catch(()=>{});await job;lb.source='shared';renderBoard();analyticsRender();if(panel==='ach')renderAch();
}
async function adminSave(remove){
 if(secretAdmin.busy||!secretAdmin.active)return;const source=secretAdmin.source,old=adminRows().find(r=>r.id===secretAdmin.id);if(remove&&!old)return;
 let value=null,id=old?old.id:'admin-'+crypto.randomUUID().replaceAll('-','');
 if(!remove){const form=$('adminEditor');if(!form.reportValidity())return;const f=new FormData(form),name=String(f.get('name')).trim();if(!name){$('adminMessage').textContent='A callsign is required.';return}
  if(source==='players'){const ach={};for(const key of f.getAll('achievement'))ach[key]=old.ach[key]||new Date().toISOString().slice(0,10);value={name:old.name,xp:Number(f.get('xp')),ach}}
  else{value=cleanEntry({id,name,score:Number(f.get('score')),distance:Number(f.get('distance')),ships:Number(f.get('ships')),sub:f.get('sub'),diff:f.get('diff'),date:f.get('date'),...(old&&old.date===f.get('date')&&old.at?{at:old.at}:{})});if(!value){$('adminMessage').textContent='Invalid score.';return}}
 }
 secretAdmin.busy=true;saveStatus('admin','busy','Saving admin change to the shared drive…');$('adminMessage').textContent='Writing and verifying the shared-drive record…';$('adminSource').disabled=true;$('adminNew').disabled=true;$('adminRefresh').disabled=true;$('adminEditor').querySelectorAll('button').forEach(b=>b.disabled=true);$('adminDelete').disabled=true;
 try{await adminCommit(source,id,value);secretAdmin.id=remove?'':id;adminList();adminEditor();$('adminMessage').textContent=remove?'Shared-drive record deleted and verified.':'Shared-drive change saved and verified.';saveStatus('admin','done',$('adminMessage').textContent)}
 catch(e){$('adminMessage').textContent='Not saved to the shared drive: '+e.message;saveStatus('admin','error',$('adminMessage').textContent)}finally{secretAdmin.busy=false;$('adminSource').disabled=false;$('adminNew').disabled=false;$('adminRefresh').disabled=false;$('adminEditor').querySelectorAll('button').forEach(b=>b.disabled=false);$('adminDelete').disabled=!secretAdmin.id}
}
const adminCode=['ArrowUp','ArrowUp','ArrowDown','ArrowDown','ArrowLeft','ArrowRight','ArrowLeft','ArrowRight','KeyB','KeyA'];
addEventListener('keydown',e=>{
 if($('secretAdmin')&&!$('secretAdmin').hidden){e.stopImmediatePropagation();if(e.code==='Escape'){e.preventDefault();$('adminClose').click()}return}
 if(e.target.matches('input,textarea,select')||e.repeat||!['menu','paused'].includes(state))return;
 secretAdmin.keys.push(e.code);secretAdmin.keys=secretAdmin.keys.slice(-adminCode.length);
 if(secretAdmin.keys.join()===adminCode.join()){e.preventDefault();e.stopImmediatePropagation();secretAdmin.keys=[];adminShow()}
},true);
const secretButton=$('build');secretButton.setAttribute('role','button');secretButton.tabIndex=0;secretButton.style.pointerEvents='auto';
function secretTap(){const now=performance.now();secretAdmin.clicks=now-secretAdmin.lastClick<1400?secretAdmin.clicks+1:1;secretAdmin.lastClick=now;if(secretAdmin.clicks>=5){secretAdmin.clicks=0;adminShow()}}
secretButton.addEventListener('click',secretTap);secretButton.addEventListener('keydown',e=>{if(e.code==='Enter'||e.code==='Space'){e.preventDefault();e.stopPropagation();secretTap()}});

// Full saved profiles include campaign missions, checkpoints, upgrades and runs.
async function adminProfileEditor(form){
 $('adminNew').hidden=true;$('adminDelete').disabled=true;const id=secretAdmin.id,key=duelKey(adminRows().find(r=>r.id===id)?.name||id);
 if(!id){form.textContent='Select a player to load their saved profile.';return}
 form.textContent='Loading profile…';
 try{if(!await saveFolder())throw Error('Choose the shared folder first.');const dir=await lb.dir.getDirectoryHandle(PROFILE_DIR),raw=unseal(await readText(key+'.dat',dir));if(!raw)throw Error('Profile could not be decoded.');const p=cleanProfile(JSON.parse(raw),id);if(secretAdmin.source!=='profiles'||secretAdmin.id!==id)return;form.textContent='';
 const note=el('p',null,'Set campaign ships, mission awards and workshop upgrades above. The advanced editor includes checkpoints, parts, saved runs and other profile settings. Saving replaces this profile and takes priority over older copies.');
 const input=el('textarea');input.setAttribute('aria-label','Saved profile JSON');input.rows=20;input.style.width='100%';input.value=JSON.stringify(p,null,2);
 const controls=el('div','admin-campaign-controls'),shipLabel=el('label',null,'Campaign ship'),ship=el('select');ship.setAttribute('aria-label','Campaign ship');for(const boat of fleetOrdered()){const o=el('option',null,boat.name);o.value=boat.id;ship.append(o)}ship.value=p.camp.sub;shipLabel.append(ship);controls.append(shipLabel);
 const missionInputs=MISSIONS.map(m=>{const l=el('label',null,'Mission '+(m.i+1)+' / '+m.name),i=el('select');for(const [value,label] of [[0,'Incomplete'],[1,'Completed'],[3,'Completed, no losses'],[5,'Completed, journal found'],[7,'All three stars'],[2,'No losses only'],[4,'Journal only'],[6,'No losses and journal']]){const o=el('option',null,label);o.value=value;i.append(o)}i.value=p.camp.done[m.id]||0;l.append(i);controls.append(l);return [m.id,i]});
 const upgradeInputs=UPGRADES.map(u=>{const l=el('label',null,u.name+' (0–'+u.max+')'),i=el('input');i.type='number';i.min=0;i.max=u.max;i.step=1;i.value=p.camp.up[u.id]||0;l.append(i);controls.append(l);return [u.id,i]});
 const updateJSON=()=>{try{const v=JSON.parse(input.value);v.camp.sub=ship.value;for(const [id,i] of missionInputs){if(+i.value)v.camp.done[id]=+i.value;else delete v.camp.done[id]}for(const [id,i] of upgradeInputs){if(+i.value)v.camp.up[id]=+i.value;else delete v.camp.up[id]}input.value=JSON.stringify(v,null,2)}catch(e){$('adminMessage').textContent='Fix the profile JSON before changing campaign controls.'}};controls.onchange=updateJSON;
 const refreshControls=()=>{try{const v=JSON.parse(input.value);ship.value=v.camp.sub;for(const [id,i] of missionInputs)i.value=v.camp.done[id]||0;for(const [id,i] of upgradeInputs)i.value=v.camp.up[id]||0}catch(_){}};input.oninput=refreshControls;
 const save=el('button','launch','Save profile and campaign');save.type='submit';const advanced=el('details'),summary=el('summary',null,'Advanced: edit full profile, runs and checkpoint');advanced.append(summary,input);form.append(controls,note,advanced,save);
 form.onsubmit=async ev=>{ev.preventDefault();if(secretAdmin.busy||!secretAdmin.active)return;let value;try{value=JSON.parse(input.value);if(!value||typeof value!=='object'||!value.camp||!value.ach)throw Error('Include campaign and achievement data.');value=cleanProfile(value,p.name);value.name=p.name;value.adminAt=Math.max(Date.now(),p.adminAt+1||0);value.at=value.adminAt}catch(e){$('adminMessage').textContent='Invalid profile: '+e.message;return}
 secretAdmin.busy=true;save.disabled=true;try{await prof.chain;await writeText(key+'.backup.dat',raw,dir);await writeText(key+'.dat',seal(JSON.stringify(value)),dir);const verified=cleanProfile(JSON.parse(unseal(await readText(key+'.dat',dir))),p.name);if(JSON.stringify(verified)!==JSON.stringify(value))throw Error('Verification failed.');if(prof.key===key){profApply(value);profSaveLocal()}input.value=JSON.stringify(value,null,2);refreshControls();$('adminMessage').textContent='Profile and campaign saved and verified.'}catch(e){$('adminMessage').textContent='Profile save failed: '+e.message}finally{secretAdmin.busy=false;save.disabled=false}};
 }catch(e){if(secretAdmin.id===id)form.textContent=e.message}
}

/* Username migration. Old typed callsigns map to the Windows user names this edition signs in with.
   The mapping lives in bin.dat (admin.aliases), so every score, medal and activity record under the old
   name counts for the new one; optionally the old profile file is merged into the new one as well. */
function adminCallsigns(){
 const m=new Map(),add=(k,name)=>m.get(k)||m.set(k,{id:k,name,scores:0,best:0}).get(k);
 for(const e of lb.shared){const r=add(e.name.toLowerCase(),e.name);r.scores++;r.best=Math.max(r.best,e.score)}
 for(const [k,p] of Object.entries(lb.players))add(k,p.name);
 for(const [k,a] of Object.entries(lb.admin.aliases||{}))if(a.value)m.set(k,{id:k,name:k,scores:0,best:0,to:a.value});
 return [...m.values()];
}
function adminMigrateEditor(form){
 $('adminNew').hidden=true;$('adminDelete').disabled=true;const r=adminRows().find(r=>r.id===secretAdmin.id);
 if(!r){form.textContent='Select an old callsign to move its scores, medals and profile to a Windows user name.';return}
 form.append(el('p',null,r.to?r.name+' is migrated to '+r.to+'. To give the scores back, migrate '+r.to+' to '+r.name+'.':r.name+' has '+r.scores+' score(s) on the shared leaderboard'+(r.scores?' (best '+r.best.toLocaleString()+')':'')+'.'));
 const label=el('label',null,'New user name (Windows sign-in)'),input=el('input'),list=el('datalist');list.id='adminNames';
 for(const n of [...new Set(adminCallsigns().filter(x=>!x.to&&x.id!==r.id).map(x=>x.name))].sort()){const o=el('option');o.value=n;list.append(o)}
 input.name='target';input.required=true;input.maxLength=16;input.setAttribute('list','adminNames');input.value=r.to||'';label.append(input,list);form.append(label);
 const merge=el('label'),box=el('input');box.type='checkbox';box.checked=true;merge.append(box,document.createTextNode(' Also merge the saved profile (medals, XP, campaign, settings) into the new name'));form.append(merge);
 const save=el('button','launch',r.to?'Migrate to this name instead':'Migrate scores');save.type='submit';form.append(save);
 if(r.to){const undo=el('button',null,'Remove mapping');undo.type='button';undo.onclick=()=>adminMigrate(r,null,false);form.append(undo)}
 form.onsubmit=ev=>{ev.preventDefault();adminMigrate(r,input.value,box.checked)};
}
async function adminMigrate(r,target,withProfile){
 if(secretAdmin.busy||!secretAdmin.active)return;
 if(target!==null){target=String(target).replace(/[\u0000-\u001f]/g,'').trim().slice(0,16);if(!target||target.toLowerCase()===r.id){$('adminMessage').textContent='Enter a different user name.';return}}
 secretAdmin.busy=true;saveStatus('admin','busy','Saving username migration…');$('adminMessage').textContent='Writing and verifying the migration…';$('adminEditor').querySelectorAll('button').forEach(b=>b.disabled=true);
 try{
  await adminCommit('migrate',r.id,target);
  const note=target&&withProfile?' '+await adminMigrateProfile(r.name,target):'';
  secretAdmin.id=target?'':r.id;adminList();adminEditor();
  $('adminMessage').textContent=(target?r.name+'’s scores now count for '+target+'.':'Mapping removed. Scores already moved stay with their new name.')+note;saveStatus('admin','done',$('adminMessage').textContent);
 }catch(e){$('adminMessage').textContent='Not migrated: '+e.message;saveStatus('admin','error',$('adminMessage').textContent);adminEditor()}
 finally{secretAdmin.busy=false}
}
// The old career is added to the new one: totals add up, medals, records and runs combine, and the
// new name keeps its own settings. The old file stays as it was; the new one is backed up first.
function migrateProfiles(to,from,name){
 const m=mergeProfiles({...to,adminAt:0},{...from,adminAt:0,at:0});
 for(const k of ST_NUM)m.ach.st[k]=to.ach.st[k]+from.ach.st[k];
 return cleanProfile({...m,name,adminAt:to.adminAt||0},name);
}
async function adminMigrateProfile(oldName,newName){
 const dir=await lb.dir.getDirectoryHandle(PROFILE_DIR,{create:true}),key=duelKey(newName);
 const load=async file=>{try{const text=unseal(await readText(file,dir));if(!text)throw Error(file+' could not be decoded.');return {text,p:cleanProfile(JSON.parse(text),newName)}}catch(e){if(e&&e.name==='NotFoundError')return null;throw e}};
 const from=await load(duelKey(oldName)+'.dat');if(!from)return 'No saved profile was found for '+oldName+'.';
 const to=await load(key+'.dat'),merged=migrateProfiles(to?to.p:blankProfile(newName),from.p,newName);
 await prof.chain;if(to)await writeText(key+'.backup.dat',seal(to.text),dir);
 await writeText(key+'.dat',seal(JSON.stringify(merged)),dir);
 const check=await load(key+'.dat');if(!check||JSON.stringify(check.p)!==JSON.stringify(merged))throw Error('The merged profile could not be verified.');
 return 'Profile merged into '+newName+(to?' (previous copy kept as '+key+'.backup.dat).':'.');
}
