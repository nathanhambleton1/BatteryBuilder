'use strict';
// One writer per random page session: cumulative snapshots make retries idempotent.
const ANALYTICS_PREFIX='undertow.analytics.v1.',analytics={session:crypto.randomUUID(),local:new Map(),remote:new Map(),dirty:new Set(),last:Date.now(),context:null,active:null,sync:null,reading:null,loaded:0,note:'',timer:0};
const analyticsDay=ms=>{const d=new Date(ms);return d.getFullYear()+'-'+String(d.getMonth()+1).padStart(2,'0')+'-'+String(d.getDate()).padStart(2,'0')};
function analyticsClean(r){
 if(!r||r.v!==1||!/^\d{4}-\d{2}-\d{2}$/.test(r.day)||typeof r.id!=='string'||!/^[\w-]+$/.test(r.id))return null;
 const num=(n,max=1e9)=>Number.isFinite(+n)?Math.max(0,Math.min(max,+n)):0,seconds={};
 for(const mode of ['campaign','practice','duel','survival','paused','spectating','leaderboard','statistics','menus'])seconds[mode]=num(r.seconds&&r.seconds[mode],86400);
 const runs=(Array.isArray(r.runs)?r.runs:[]).filter(x=>x&&typeof x.id==='string'&&SUB_BY_ID[x.sub]&&DIFFS[x.diff]).map(x=>({...x,name:undefined,id:x.id.slice(0,80),score:num(x.score),distance:num(x.distance),seconds:num(x.seconds,86400),at:num(x.at,1e14),mode:['campaign','practice','duel','survival'].includes(x.mode)?x.mode:'survival',outcome:['lost','won','abandoned','incomplete'].includes(x.outcome)?x.outcome:'incomplete'}));
 return {...r,name:String(r.name||'Anonymous').slice(0,16),seconds,runs,rev:num(r.rev)};
}
function analyticsContext(){return {name:prof.name||callsign(),mode:state==='playing'?(cm?'campaign':practice?'practice':duel.run?'duel':'survival'):cm&&['cut','cine','debrief'].includes(state)?'campaign':state==='paused'?'paused':state==='watching'?'spectating':panel==='board'?'leaderboard':panel==='statistics'?'statistics':'menus'}}
function analyticsRow(name,day){const id=analytics.session+'-'+day+'-'+Array.from(name.toLowerCase()).map(x=>x.codePointAt(0).toString(16)).join('_');let r=analytics.local.get(id);if(!r){r={v:1,id,day,name,seconds:{},runs:[],rev:0,at:Date.now()};analytics.local.set(id,r)}return r}
function analyticsPersist(r){r.rev++;r.at=Date.now();analytics.dirty.add(r.id);if(!store.set(ANALYTICS_PREFIX+r.id,r))saveStatus('analytics','error','Activity backup could not be saved. Keep this page open.');}
function analyticsTick(now=Date.now()){
 const elapsed=Math.max(0,Math.min(5000,now-analytics.last)),ctx=analytics.context;
 if(ctx&&elapsed){let at=now-elapsed;while(at<now){const midnight=new Date(at);midnight.setHours(24,0,0,0);const end=Math.min(now,+midnight),r=analyticsRow(ctx.name,analyticsDay(at));r.seconds[ctx.mode]=(Number(r.seconds[ctx.mode])||0)+(end-at)/1000;analyticsPersist(r);at=end}}
 analytics.last=now;analytics.context=!document.hidden&&document.hasFocus()?analyticsContext():null;
 if(analytics.active&&analytics.active.ref===run&&!analytics.active.done){const a=analytics.active;a.data.score=score();a.data.distance=Math.floor(distance);a.data.seconds=t;a.data.hits=run.hits;a.data.fired=run.fired;a.data.abilities=run.ability;analyticsPersist(a.row)}
}
function analyticsBegin(){
 if(analytics.active&&analytics.active.ref===run)return;
 analyticsTick();const row=analyticsRow(prof.name||callsign(),analyticsDay(Date.now())),data={id:crypto.randomUUID(),at:Date.now(),sub:S.id,diff:diffId,mode:cm?'campaign':practice?'practice':duel.run?'duel':'survival',mission:cm?cm.id:null,outcome:'incomplete',score:0,distance:0,seconds:0};
 row.runs.push(data);analytics.active={ref:run,row,data,done:false};analyticsPersist(row);analytics.context=!document.hidden&&document.hasFocus()?analyticsContext():null;
}
function analyticsEnd(outcome,scoreId){const a=analytics.active;if(!a||a.done)return;analyticsTick();a.data.outcome=outcome;if(scoreId)a.data.scoreId=scoreId;a.done=true;analyticsPersist(a.row);void analyticsSync()}
async function analyticsSync(){
 if(analytics.sync)return analytics.sync;
 if(!analytics.dirty.size)return;
 if(!lb.dir||lb.perm!=='granted'){saveStatus('analytics','queued','Activity upload pending · Connect the shared drive · Backup safe');return}
 const root=lb.dir;
 analytics.sync=(async()=>{saveStatus('analytics','busy','Saving activity to the shared drive…');try{
 const dir=await root.getDirectoryHandle('analytics',{create:true});
 for(const id of [...analytics.dirty]){const row=analytics.local.get(id);if(!row)continue;const snap=JSON.parse(JSON.stringify(row)),file=id+'.dat',text=seal(JSON.stringify(snap));await writeText(file,text,dir);const verified=analyticsClean(JSON.parse(unseal(await readText(file,dir))));if(!verified||verified.id!==id||verified.rev!==snap.rev)throw Error('Activity verification failed');analytics.remote.set(id,verified);if(row.rev===snap.rev){analytics.dirty.delete(id);store.set(ANALYTICS_PREFIX+id,{...row,synced:row.rev})}}
 saveStatus('analytics',analytics.dirty.size?'busy':'done',analytics.dirty.size?'Saving latest activity to the shared drive…':'Activity saved to the shared drive');
 }catch(e){analytics.note='Activity upload pending. Automatic retries continue.';saveStatus('analytics','queued','Shared-drive activity upload failed · Retrying automatically · Backup safe')}
 })().finally(()=>{analytics.sync=null});return analytics.sync;
}
async function analyticsRead(){
 if(analytics.reading)return analytics.reading;if(!lb.dir||lb.perm!=='granted'){analytics.note='Shared drive not connected. Showing available records and this computer’s backup.';analyticsRender();return}
 analytics.reading=(async()=>{analytics.note='Loading fleet activity…';analyticsRender();try{await analyticsSync();let dir;try{dir=await lb.dir.getDirectoryHandle('analytics')}catch(e){if(e.name!=='NotFoundError')throw e}const rows=new Map();let bad=0;if(dir)for await(const [name,handle]of dir.entries()){if(handle.kind!=='file'||!name.endsWith('.dat'))continue;try{const row=analyticsClean(JSON.parse(unseal(await (await handle.getFile()).text())));if(row)rows.set(row.id,row);else bad++}catch(_){bad++}}analytics.remote=rows;analytics.loaded=Date.now();analytics.note='Shared activity refreshed'+(bad?' · '+bad+' unreadable record(s) excluded.':'.')}catch(e){analytics.note='Shared drive unavailable. Showing cached activity; uploads keep retrying.'}finally{analytics.reading=null;analyticsRender()}})();return analytics.reading;
}
function analyticsRows(){const rows=new Map(analytics.remote);for(const [id,r]of analytics.local)if(!rows.has(id)||r.rev>=rows.get(id).rev)rows.set(id,r);return [...rows.values()]}
function analyticsRange(period,now=Date.now()){const d=new Date(now);d.setHours(0,0,0,0);if(period==='week')d.setDate(d.getDate()-(d.getDay()+6)%7);if(period==='month')d.setDate(1);return period==='all'?'0000-00-00':analyticsDay(+d)}
function analyticsData(filters){
 const since=analyticsRange(filters.period),rows=analyticsRows(),known=new Set(rows.flatMap(r=>r.runs.map(x=>x.scoreId).filter(Boolean))),legacy=mergeEntries(lb.shared,lb.local).filter(e=>!known.has(e.id)).map(e=>({...e,mode:'legacy',outcome:'completed',at:e.at||Date.parse(e.date+'T12:00:00'),seconds:null,legacy:true}));
 let runs=[...rows.filter(r=>r.day>=since).flatMap(r=>r.runs.map(x=>({...x,name:r.name,day:r.day}))),...legacy.filter(r=>analyticsDay(r.at)>=since)];
 runs=runs.filter(r=>(!filters.player||r.name.toLowerCase()===filters.player)&&(!filters.mode||r.mode===filters.mode)&&(!filters.diff||r.diff===filters.diff));
 const ships=fleetOrdered().map(s=>{const all=runs.filter(r=>r.sub===s.id),done=all.filter(r=>['lost','won','completed'].includes(r.outcome)),timed=done.filter(r=>Number.isFinite(r.seconds)),points=done.reduce((n,r)=>n+(+r.score||0),0);return {id:s.id,name:s.name,uses:all.length,completed:done.length,points,average:done.length?points/done.length:0,distance:done.reduce((n,r)=>n+(+r.distance||0),0),duration:timed.length?timed.reduce((n,r)=>n+r.seconds,0)/timed.length:null,wins:done.filter(r=>r.outcome==='won').length,campaign:done.filter(r=>r.mode==='campaign').length}});
 const players=new Map(),daily=new Map();for(const r of rows){if(r.day<since||filters.player&&r.name.toLowerCase()!==filters.player)continue;const key=r.name.toLowerCase(),p=players.get(key)||{name:r.name,total:0,campaign:0,survival:0,menus:0,days:new Set()};p.days.add(r.day);for(const [mode,value]of Object.entries(r.seconds)){const v=Math.max(0,+value||0);p.total+=v;if(mode==='campaign')p.campaign+=v;else if(['survival','duel','practice'].includes(mode))p.survival+=v;else p.menus+=v;daily.set(r.day,(daily.get(r.day)||0)+v)}players.set(key,p)}
 return {ships,runs,players:[...players.values()].sort((a,b)=>b.total-a.total),daily:[...daily].sort((a,b)=>b[0].localeCompare(a[0]))};
}
const analyticsTime=s=>s==null?'—':s<60?Math.round(s)+'s':s<3600?Math.floor(s/60)+'m '+Math.round(s%60)+'s':Math.floor(s/3600)+'h '+Math.floor(s%3600/60)+'m';
function analyticsRender(){
 if(!$('statistics')||panel!=='statistics')return;
 const select=$('statsPlayer'),selected=select.value,names=[...new Set([...analyticsRows().map(r=>r.name),...lb.shared.map(r=>r.name),...lb.local.map(r=>r.name)])].sort();select.textContent='';select.add(new Option('All players',''));for(const name of names)select.add(new Option(name,name.toLowerCase()));select.value=selected;
 const filters={period:$('statsPeriod').value,player:select.value,mode:$('statsMode').value,diff:$('statsDiff').value},data=analyticsData(filters),metric=$('statsMetric').value;
 $('statsNote').textContent=analytics.note||'Tracking starts with this update. Existing leaderboard scores are included as historical runs; past online time is unavailable.';
 $('statsSummary').textContent=data.runs.length+' recorded attempts · '+data.players.length+' active players · '+analyticsTime(data.players.reduce((n,p)=>n+p.total,0))+' focused time';
 const chart=$('statsChart');chart.textContent='';const sorted=[...data.ships].sort((a,b)=>b[metric]-a[metric]),max=Math.max(1,...sorted.map(s=>s[metric]));for(const ship of sorted){const row=document.createElement('div');row.className='stats-bar';const name=document.createElement('span');name.textContent=ship.name;const track=document.createElement('span');track.className='stats-track';const bar=document.createElement('i');bar.style.width=ship[metric]/max*100+'%';track.append(bar);const value=document.createElement('b');value.textContent=Math.round(ship[metric]).toLocaleString();row.append(name,track,value);chart.append(row)}
 const table=(id,rows)=>{const body=$(id);body.textContent='';for(const cells of rows){const tr=document.createElement('tr');for(const text of cells){const td=document.createElement('td');td.textContent=text;tr.append(td)}body.append(tr)}};
 table('statsShips',sorted.map(s=>[s.name,s.uses,s.completed,s.points.toLocaleString(),Math.round(s.average).toLocaleString(),analyticsTime(s.duration),s.campaign?Math.round(s.wins/s.campaign*100)+'%':'—',s.uses<10?'Small sample':'']));
 table('statsPlayers',data.players.map(p=>[p.name,analyticsTime(p.total),analyticsTime(p.survival),analyticsTime(p.campaign),analyticsTime(p.menus),data.runs.filter(r=>r.name.toLowerCase()===p.name.toLowerCase()).length,p.days.size]));
 table('statsDaily',data.daily.map(([day,total])=>[day,analyticsTime(total),data.runs.filter(r=>(r.day||analyticsDay(r.at))===day).length]));
}
function analyticsInit(){
 try{for(let i=0;i<localStorage.length;i++){const key=localStorage.key(i);if(!key.startsWith(ANALYTICS_PREFIX))continue;const row=analyticsClean(store.get(key,null));if(row){analytics.local.set(row.id,row);if(row.synced!==row.rev)analytics.dirty.add(row.id)}}}catch(_){}
 analytics.last=Date.now();analytics.context=!document.hidden&&document.hasFocus()?analyticsContext():null;
 $('statsOpen').onclick=()=>{openPanel('statistics');analyticsTick();analyticsRender();void analyticsRead()};$('statsClose').onclick=closePanel;$('statsDismiss').onclick=closePanel;$('statsRefresh').onclick=()=>analyticsRead();
 for(const id of ['statsPeriod','statsPlayer','statsMode','statsDiff','statsMetric'])$(id).onchange=analyticsRender;
 setInterval(()=>{analyticsTick();if(++analytics.timer%15===0){void analyticsSync();if(panel==='statistics')analyticsRender()}},1000);
 for(const event of ['blur','focus','pagehide'])addEventListener(event,()=>{analyticsTick();if(event!=='focus')analytics.context=null;void analyticsSync()});
 document.addEventListener('visibilitychange',()=>{analyticsTick();if(document.hidden)analytics.context=null;void analyticsSync()});addEventListener('online',()=>analyticsSync());
}
