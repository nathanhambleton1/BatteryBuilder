const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict'),crypto=require('node:crypto');
let clock=1800000000000;
class Element{
 constructor(tag='div'){this.tag=tag;this.children=[];this.attributes={};this.disabled=false;this.hidden=false;this.dataset={};this.classList={add(){},remove(){},toggle(){}};this.lastChild={textContent:''}}
 set textContent(v){this.text=String(v);this.children=[]}get textContent(){return (this.text||'')+this.children.map(c=>typeof c==='string'?c:c.textContent).join('')}
 append(...v){this.children.push(...v)}prepend(...v){this.children.unshift(...v)}remove(){}
 setAttribute(k,v){this.attributes[k]=String(v)}removeAttribute(k){delete this.attributes[k]}hasAttribute(k){return k in this.attributes}
 querySelector(){if(!this.child)this.child=new Element('span');return this.child}focus(){}
}
function drive(){
 const files=new Map(),state={fail:false,omit:false,beforeWrite:null};
 const directory={
 async getFileHandle(name,opts={}){
  if(!files.has(name)&&!opts.create)throw Object.assign(Error('Missing'),{name:'NotFoundError'});
  return {kind:'file',async getFile(){if(state.fail)throw Error('Drive disconnected');const text=files.get(name)||'';return {lastModified:1,size:100,text:async()=>text}},
   async createWritable(){if(state.fail)throw Error('Drive disconnected');let content;return {async write(t){if(state.beforeWrite)await state.beforeWrite();content=t},async close(){files.set(name,content)},async abort(){}}}};
 },
 async removeEntry(n){if(state.fail)throw Error('Drive disconnected');files.delete(n)},
 async *entries(){if(state.fail)throw Error('Drive disconnected');if(state.omit)return;for(const n of [...files.keys()])yield [n,await this.getFileHandle(n)]}
 };
 return {files,state,directory,async getDirectoryHandle(){if(state.fail)throw Error('Drive disconnected');return directory}};
}
const code=fs.readFileSync(path.join(__dirname,'../files/duel.js'),'utf8');
function client(name,root,offset=0,backup=new Map()){
 const elements=new Map(),timers=[];
 class LocalDate extends Date{static now(){return clock+offset}}
 const ctx=vm.createContext({console,Date:LocalDate,crypto:crypto.webcrypto,Map,Set,Element,root,backup,timers,structuredClone,setInterval:fn=>{timers.push(fn);return timers.length},clearInterval(){},addEventListener(){},document:{createElement:t=>new Element(t),querySelectorAll:()=>[]},node:id=>{if(!elements.has(id))elements.set(id,new Element());return elements.get(id)}});
 vm.runInContext(`
let name=${JSON.stringify(name)},state='menu',panel='duel',practice=false,courseSeed=null,diffId='officer',deathCause='Test',t=0,S={o2:80},gates=[],subId='gato',sub={x:100,y:200,v:0},hull=3,o2=70;
const store={get:(k,d)=>backup.has(k)?structuredClone(backup.get(k)):d,set:(k,v)=>{backup.set(k,structuredClone(v));return true}};
const lb={dir:root,perm:'granted',supported:true},BOARD_FILE='bin.dat',BUILD='test',DIFFS={officer:{label:'Officer'}};
const callsign=()=>name,$=node,seal=x=>x,unseal=x=>x,sleep=async()=>{},clamp=(n,a,b)=>Math.max(a,Math.min(b,n));
const writeText=async(n,t,d)=>{const w=await(await d.getFileHandle(n,{create:true})).createWritable();await w.write(t);await w.close()};
const show=(id,v)=>{node(id).hidden=!v},profDirty=()=>{},ach={st:{duels:0,wins:0}},achCheck=()=>{},saveJobs=[];
const saveStatus=(scope,stage,message)=>saveJobs.push({scope,stage,message});
const start=()=>{state='playing'},toast=()=>{},score=()=>123;
`+code,ctx);
 return {ctx,elements,backup,run:s=>vm.runInContext(s,ctx),json:s=>JSON.parse(vm.runInContext('JSON.stringify('+s+')',ctx))};
}
(async()=>{
 const root=drive(),a=client('Ada',root,6*3600000),b=client('Ben',root,-5*3600000);
 await a.run('duelTick()');await b.run('duelTick()');await a.run('duelTick()');
 assert.equal(a.json('duel.online[0].online'),false);assert.equal(a.json('duel.online[0].checking'),true);
 clock+=5000;await b.run('duelTick()');await a.run('duelTick()');await b.run('duelTick()');
 assert.equal(a.json('duel.online[0].online'),true);assert.equal(b.json('duel.online[0].online'),true);
 assert.equal(a.json("node('duelStatus').textContent").includes('You are online as Ada'),true);
 // Legacy presence overwrites with identical timestamps and sizes are read afresh.
 root.files.set('p-legacy-pc.dat',JSON.stringify({name:'Legacy',pc:'legacy',beat:1,at:1,status:'in port'}));
 await a.run('duelTick()');root.files.set('p-legacy-pc.dat',JSON.stringify({name:'Legacy',pc:'legacy',beat:2,at:1,status:'in port'}));await a.run('duelTick()');
 assert.equal(a.json("duel.online.find(p=>p.name==='Legacy').online"),true);
 // A short cached/empty directory listing does not make everyone disappear.
 root.state.omit=true;await a.run('duelTick()');assert.equal(a.json("duel.online.find(p=>p.name==='Ben').online"),true);root.state.omit=false;
 // Filesystem-safe names can collide; player identities must not.
 root.files.set('p-same-pc.dat',JSON.stringify({name:'Ben!',pc:'distinct',beat:1,at:1,status:'in port'}));await a.run('duelTick()');
 root.files.set('p-same-pc.dat',JSON.stringify({name:'Ben!',pc:'distinct',beat:2,at:1,status:'in port'}));await a.run('duelTick()');
 assert.equal(a.json("duel.online.filter(p=>p.online&&p.name.startsWith('Ben')).length"),2);
 assert.equal(await a.run("duelChallenge('Ben')"),true);await b.run('duelTick()');
 const id=a.json("duel.matches.find(m=>m.opp==='Ben').id");
 assert.equal(b.json("duel.matches[0].status"),'pending');
 assert.equal(await b.run('duelReply(duel.matches[0],true)'),true);await a.run('duelTick()');
 assert.equal(a.json('duel.matches[0].status'),'active');
 // A successful begin marker is persisted before starting the round.
 await a.run('duelDive(duel.matches[0])');assert.equal(a.json('duel.run.round'),0);
 await a.run('duelRoundOver(456)');assert.equal(a.json('duel.pendingRound'),null);
 await b.run('duelTick()');assert.equal(b.json('duel.matches[0].theirs[0]'),456);assert.equal(b.json('duel.matches[0].turn'),'b');
 // Failed final score saves survive a reload and retry exactly once.
 await b.run('duelDive(duel.matches[0])');root.state.fail=true;await b.run('duelRoundOver(789)');
 assert.equal(b.json('duel.pendingRound.score'),789);
 const restored=client('Ben',root,-5*3600000,b.backup);root.state.fail=false;
 await restored.run('timers[0]()');assert.equal(restored.json('duel.pendingRound'),null);
 await a.run('duelTick()');assert.equal(a.json('duel.matches[0].theirs.length'),1);
 // Already posted retries are idempotent even if local acknowledgement was lost.
 restored.run(`duel.pendingRound={id:'${id}',side:'b',round:0,score:789,name:'Ben'}`);
 assert.equal(await restored.run('duelPostRound()'),true);await a.run('duelTick()');assert.equal(a.json('duel.matches[0].theirs.length'),1);
 // Busy actions keep the clicked spinner visible across rerenders and ignore duplicates.
 let release,entered;const enteredPromise=new Promise(r=>entered=r),gate=new Promise(r=>release=r);root.state.beforeWrite=async()=>{entered();await gate};
 a.run("globalThis.button=duelButton('Forfeit',()=>duelPatch(duel.matches[0],{forfeit:true},'Saving forfeit…'));");
 const saving=a.run('button.onclick()');await enteredPromise;
 assert.equal(a.json('duel.action'),'Saving forfeit…');
 assert.equal(a.run("duelButton('Forfeit',()=>{}).attributes['aria-busy']"),'true');
 assert.equal(a.run("duelButton('Accept',()=>{}).attributes['aria-busy']"),undefined);
 assert.equal(await a.run("duelPatch(duel.matches[0],{forfeit:true})"),false);
 release();root.state.beforeWrite=null;await saving;assert.equal(a.json('duel.action'),'');assert.equal(a.run("button.attributes['aria-busy']"),undefined);
 // Permission loss is visible and never reports this client as online.
 root.state.fail=true;clock+=30000;await a.run('duelTick()');
 assert(a.json('duel.beatError').length);assert(!a.json("node('duelStatus').textContent").includes('You are online as'));
 assert(a.json('duel.online.every(p=>!p.online)'));
 // Switching folders never merges cached matches into another drive.
 const second=drive();a.ctx.second=second;a.run('lb.dir=second');await a.run('duelTick()');
 assert.equal(a.json('duel.matches.length'),0);assert.equal(a.json('duel.own.size'),0);

 // A full one-round duel records both results and acknowledges cleanup.
 const finalDrive=drive(),c=client('Chris',finalDrive),d=client('Dana',finalDrive);
 await c.run('duelTick()');await d.run('duelTick()');await c.run('duelTick()');
 clock+=5000;await d.run('duelTick()');await c.run('duelTick()');await d.run('duelTick()');
 c.run('duel.rounds=1');assert.equal(await c.run("duelChallenge('Dana')"),true);
 await d.run('duelTick()');const first=d.json('duel.matches[0].id');await d.run('duelReply(duel.matches[0],true)');await c.run('duelTick()');
 await c.run('duelDive(duel.matches[0])');await c.run('duelRoundOver(100)');await d.run('duelTick()');
 await d.run('duelDive(duel.matches[0])');await d.run('duelRoundOver(200)');
 await c.run('duelTick()');await d.run('duelTick()');await c.run('duelTick()');
 assert.equal(c.json('duel.history[0].result'),'lost');assert.equal(d.json('duel.history[0].result'),'won');
 assert(![...finalDrive.files.keys()].some(n=>n.startsWith('m-'+first)));
 // Cancelled challenges cannot be accepted by an old button.
 await c.run("duelChallenge('Dana')");await d.run('duelTick()');d.run('globalThis.oldChallenge=duel.matches.find(m=>m.status==="pending")');
 await c.run('duelCancel(duel.matches.find(m=>m.status==="pending"))');
 assert.equal(await d.run('duelReply(oldChallenge,true)'),false);
 // An unreadable new revision blocks actions instead of replaying stale state.
 c.run("duel.files=new Map([['m-example-a-1.dat',{data:{id:'example',a:'Chris',b:'Dana',scores:[]}}],['m-example-a-2.dat',{data:null}]])");
 assert.equal(c.json('duelMatchList().length'),0);
 // A third party must never delete someone else's orphan reply.
 finalDrive.files.set('m-orphan-b-1.dat',JSON.stringify({id:'orphan',owner:'Someone else',closed:true,scores:[]}));
 await c.run('duelTick()');await c.run('duelTick()');
 assert(finalDrive.files.has('m-orphan-b-1.dat'));
 // Same callsigns are reported explicitly and cannot write competing match sides.
 const e=client('Dana',finalDrive);await e.run('duelTick()');await d.run('duelTick()');
 clock+=5000;await e.run('duelTick()');await d.run('duelTick()');
 assert.equal(d.json('duel.dupe'),true);assert.equal(await d.run("duelAct(async()=>{},'Test…')"),false);
 console.log('PASS: clock skew, fixed metadata, legacy heartbeat reads, omitted listings, distinct identities, challenge/accept, turns, score recovery/reload, idempotency, action spinners, duplicate clicks, disconnects, folder changes');
})().catch(e=>{console.error(e);process.exitCode=1});
