const {chromium}=require('playwright'),path=require('path');
(async()=>{const browser=await chromium.launch({channel:'msedge',headless:true}),page=await browser.newPage({viewport:{width:1400,height:950}}),errors=[];page.on('pageerror',e=>errors.push(e.message));
await page.goto('file:///'+path.join(__dirname,'..','undertow.html').replaceAll('\\','/'));await page.evaluate(()=>{lb.gate.offline=true;show('sfGate',false);soundOn=false;musicOn=false;$('callsign').value='AdminTest';profSwitch();});
for(let i=0;i<5;i++)await page.locator('#build').click();await page.locator('#adminPassword').fill('wrong');await page.locator('#adminLogin button').click();if(await page.evaluate(()=>secretAdmin.active))throw Error('Wrong password accepted');
await page.locator('#adminPassword').fill('subs');await page.locator('#adminLogin button').click();
const unlocked=await page.evaluate(()=>({missions:MISSIONS.every((_,i)=>campOpen(i)),boats:campSubs().length,saved:Object.keys(camp.data.done).length}));if(!unlocked.missions||unlocked.boats!==8||unlocked.saved)throw Error('Temporary unlock failed');
await page.locator('#adminNew').click();await page.locator('#adminEditor [name=name]').fill('Edited sailor');await page.locator('#adminEditor [name=score]').fill('123456');await page.locator('#adminEditor button').click();await page.waitForFunction(()=>$('adminMessage').textContent==='Leaderboard change saved.');
const local=await page.evaluate(()=>adminRows().find(r=>r.name==='Edited sailor'));if(local.score!==123456)throw Error('Local editor did not save');
if(!await page.evaluate(()=>adminRows().filter(r=>r.name==='Edited sailor').length===1&&secretAdmin.id===adminRows().find(r=>r.name==='Edited sailor').id))throw Error('New score ID mismatch or duplication');
await page.locator('#adminEditor [name=score]').fill('42');await page.locator('#adminEditor button').click();await page.waitForFunction(()=>adminRows().find(r=>r.name==='Edited sailor').score===42);
await page.reload();await page.evaluate(()=>{lb.gate.offline=true;show('sfGate',false);});if(await page.evaluate(()=>secretAdmin.active||campOpen(23)||campSubs().length!==1))throw Error('Unlock survived refresh');
if(!await page.evaluate(()=>boardAdminEntries(lb.local,localBoardAdmin()).some(r=>r.name==='Edited sailor'&&r.score===42)))throw Error('Saved board edit lost on refresh');
for(const key of ['ArrowUp','ArrowUp','ArrowDown','ArrowDown','ArrowLeft','ArrowRight','ArrowLeft','ArrowRight','b','a'])await page.keyboard.press(key);
await page.locator('#adminPassword').fill('subs');await page.locator('#adminLogin button').click();
await page.locator('#adminRecords').selectOption(local.id);await page.locator('#adminDelete').click();await page.waitForFunction(()=>!adminRows().some(r=>r.name==='Edited sailor'));
const shared=await page.evaluate(async()=>{
 // An in-memory File System Access test double. No real shared board is opened.
 const files=new Map(),entry={id:'test-entry',name:'Tester',score:9000,distance:200,ships:2,sub:'gato',diff:'officer',date:'2026-10-26'},aid=ACHS[0].id;
 files.set(BOARD_FILE,seal(JSON.stringify({entries:[entry],players:{tester:{name:'Tester',xp:900,ach:{[aid]:'2026-10-26'}}}})));
 lb.dir={name:'TestOnly',queryPermission:async()=> 'granted',requestPermission:async()=> 'granted',removeEntry:async n=>files.delete(n),getFileHandle:async(n,o={})=>{if(!files.has(n)&&!o.create)throw new DOMException('Missing','NotFoundError');return {getFile:async()=>({text:async()=>files.get(n)||''}),createWritable:async()=>{let data='';return {write:async s=>{data=s},close:async()=>files.set(n,data),abort:async()=>{}}}}}};lb.perm='granted';prof.pulled=true;store.set('undertow.pending.v1',[]);
 await lbSync(false);await adminCommit('shared',entry.id,{...entry,score:12});store.set('undertow.pending.v1',[entry]);await lbSync(false);if(lb.shared[0].score!==12)throw Error('Sync restored old score');
 await adminCommit('players','tester',{name:'Tester',xp:7,ach:{}});store.set('undertow.pending.v1',[{...entry,id:'other'}]);await lbSync(false);if(lb.players.tester.xp!==7||Object.keys(lb.players.tester.ach).length)throw Error('Sync restored achievement record');
 await adminCommit('shared',entry.id,null);store.set('undertow.pending.v1',[entry]);await lbSync(false);if(lb.shared.some(e=>e.id===entry.id)||pending().length)throw Error('Deleted score reappeared');
 const before=files.get(BOARD_FILE);secretAdmin.active=false;let rejected=false;try{await adminCommit('shared','other',null)}catch{rejected=true}if(!rejected||before!==files.get(BOARD_FILE))throw Error('Locked console could write');
 return {scoreEdit:true,achievementEdit:true,deletion:true,staleSync:true,lockedWriteRejected:true,backup:files.has(BACKUP_FILE)};
});console.log({unlocked,shared,errors});await browser.close();if(errors.length)process.exitCode=1;
})().catch(e=>{console.error(e);process.exit(1)});

