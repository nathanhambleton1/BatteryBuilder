'use strict';
// This offline game's service password is a convenience gate, not a security
// boundary. Access lives only in memory. Saved board corrections are independent.
const secretAdmin={active:false,source:'shared',id:'',busy:false,keys:[],clicks:0,lastClick:0};
function cleanBoardAdmin(raw){
 const out={entries:{},players:{}};if(!raw||typeof raw!=='object')return out;
 for(const type of ['entries','players'])for(const [id,r] of Object.entries(raw[type]||{})){
  if(!r||!Number.isFinite(r.at)||r.at<=0||id==='__proto__'||id==='constructor'||id==='prototype')continue;
  const value=r.value===null?null:type==='entries'?cleanEntry({...r.value,id}):cleanPlayers({[id]:r.value})[id];
  if(value!==undefined&&(value!==null||r.value===null))out[type][id]={at:r.at,value};
 }return out;
}
function boardAdminEntries(entries,admin){
 const map=new Map(entries.map(e=>[e.id,e]));for(const [id,r] of Object.entries(admin&&admin.entries||{})){if(r.value===null)map.delete(id);else map.set(id,r.value)}
 return [...map.values()].sort((a,b)=>b.score-a.score);
}
function boardAdminPlayers(players,admin){const out={...players};for(const [id,r] of Object.entries(admin&&admin.players||{})){if(r.value===null)delete out[id];else out[id]=r.value}return out}
const localBoardAdmin=()=>cleanBoardAdmin(store.get('undertow.board-admin.v1',{}));
function adminShow(){
 if(duel.run||duel.watch||cine.on)return;
 if(state==='playing')pause();
 let box=$('secretAdmin');if(!box){
  box=document.createElement('section');box.id='secretAdmin';box.className='view overlay';box.setAttribute('role','dialog');box.setAttribute('aria-modal','true');box.setAttribute('aria-label','Service panel');
  box.innerHTML='<div class="panel wide"><div class="eyebrow">SERVICE ACCESS</div><h2>Captain’s console</h2><form id="adminLogin"><label>Password <input id="adminPassword" type="password" autocomplete="off" required></label><button class="launch">Unlock</button></form><div id="adminTools" hidden><p>All campaign missions and boats are available until refresh. All edits are saved to the shared drive and verified before confirmation.</p><label>Board <select id="adminSource"><option value="shared">Scores · shared fleet</option><option value="players">Achievements / XP · shared fleet</option></select></label><button id="adminRefresh" type="button">Refresh board</button><input id="adminSearch" placeholder="Find callsign or record ID" aria-label="Find record"><select id="adminRecords" size="7" aria-label="Leaderboard records"></select><form id="adminEditor"></form><div class="admin-actions"><button id="adminNew" type="button">New score</button><button id="adminDelete" type="button">Delete selected record</button></div></div><p id="adminMessage" role="status"></p><button id="adminClose" class="launch">Close</button></div>';
  document.body.append(box);
  $('adminLogin').onsubmit=ev=>{ev.preventDefault();if($('adminPassword').value!=='subs'){$('adminMessage').textContent='Incorrect password.';$('adminPassword').value='';return}secretAdmin.active=true;$('adminPassword').value='';adminRender();lbSync(false).then(()=>{if(secretAdmin.active)adminRender()});if(panel==='camp')renderCamp()};
  $('adminClose').onclick=()=>{box.hidden=true;if(panel==='camp')renderCamp()};
  $('adminSource').onchange=()=>{secretAdmin.source=$('adminSource').value;secretAdmin.id='';adminRender()};
  $('adminSearch').oninput=adminList;
  $('adminRecords').onchange=()=>{secretAdmin.id=$('adminRecords').value;adminEditor()};
  $('adminRefresh').onclick=async()=>{try{if(secretAdmin.source!=='local'){if(!await lbPermitted(true))throw Error('Connect the shared folder from the Leaderboard screen first.');await lbSync(false)}adminRender()}catch(e){$('adminMessage').textContent=e.message}};
  $('adminNew').onclick=()=>{secretAdmin.id='';adminEditor(true)};
  $('adminDelete').onclick=()=>adminSave(true);
 }
 box.hidden=false;adminRender();(secretAdmin.active?$('adminSource'):$('adminPassword')).focus();
}
function adminRows(){return secretAdmin.source==='players'?Object.entries(boardAdminPlayers(lb.players,lb.admin)).map(([id,p])=>({id,...p})):boardAdminEntries(lb.shared,lb.admin)}
function adminRender(){
 $('adminLogin').hidden=secretAdmin.active;$('adminTools').hidden=!secretAdmin.active;$('adminMessage').textContent=secretAdmin.active?'Session access active. Refreshing the page locks this console and restores normal campaign access.':'';
 if(secretAdmin.active){$('adminSource').value=secretAdmin.source;adminList();adminEditor()}
}
function adminList(){
 const select=$('adminRecords'),q=$('adminSearch').value.toLowerCase();select.textContent='';
 for(const r of adminRows().filter(r=>(r.name+' '+r.id).toLowerCase().includes(q))){const o=document.createElement('option');o.value=r.id;o.textContent=r.name+' · '+(secretAdmin.source==='players'?Object.keys(r.ach).length+' achievements / '+r.xp+' XP':r.score.toLocaleString()+' · '+DIFFS[r.diff].label);select.append(o)}
 select.value=secretAdmin.id;
}
function adminEditor(fresh=false){
 const form=$('adminEditor');form.textContent='';const player=secretAdmin.source==='players',r=adminRows().find(r=>r.id===secretAdmin.id);
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
 const type=source==='players'?'players':'entries',correction=cleanBoardAdmin({[type]:{[id]:{at:Date.now(),value}}})[type][id];if(!correction)throw Error('Invalid leaderboard record.');
 if(!['shared','players'].includes(source))throw Error('Admin edits must target the shared drive.');
 if(!await lbPermitted(true))throw Error('Connect the shared folder from the Leaderboard screen first.');
 const job=lbChain.then(()=>withLock(async (locked,owns)=>{
  if(!locked)throw Error('The shared leaderboard is busy. Try saving again.');
  const board=await lbRead(),admin=cleanBoardAdmin(board.admin);admin[type][id]=correction;
  const result={game:'UNDERTOW',version:5,updated:new Date().toISOString(),entries:boardAdminEntries(board.entries,admin),players:boardAdminPlayers(board.players,admin),admin};
  // Save the previous readable version before replacing the board.
  await owns();await writeText(BACKUP_FILE,seal(JSON.stringify(board)));await owns();await writeText(BOARD_FILE,seal(JSON.stringify(result)));await owns();
  const verified=await lbRead();if(JSON.stringify(verified.admin[type][id])!==JSON.stringify(correction))throw Error('The change could not be verified. Refresh the board before retrying.');
  lb.admin=verified.admin;lb.shared=verified.entries;lb.players=verified.players;
 }));lbChain=job.catch(()=>{});await job;lb.source='shared';renderBoard();if(panel==='ach')renderAch();
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
