const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const source=name=>fs.readFileSync(require('node:path').join(__dirname,'../files',name),'utf8');
const context=vm.createContext({console,Date,Map,Set,crypto:require('node:crypto').webcrypto});
vm.runInContext(`
const SUB_BY_ID={turtle:{},gato:{}},DIFFS={officer:{},admiral:{}};
const fleetOrdered=()=>Object.keys(SUB_BY_ID).map(id=>({id,name:id}));
const store={get:()=>({})},lb={shared:[],local:[],players:{},admin:{entries:{},players:{}},dir:{},perm:'granted'};
let lbChain=Promise.resolve(),panel='',disk={entries:[],players:{},admin:{entries:{},players:{}}},renders=0;
const lbPermitted=async()=>true,withLock=async f=>f(true,async()=>{}),seal=x=>x;
const BOARD_FILE='board',BACKUP_FILE='backup',renderBoard=()=>{},renderAch=()=>{};
const writeText=async(file,text)=>{if(file===BOARD_FILE)disk=JSON.parse(text)};
const lbRead=async()=>JSON.parse(JSON.stringify(disk));
const lbSync=async()=>{const b=await lbRead();lb.admin=b.admin;lb.shared=b.entries;return true};
const $=()=>null;
`+source('leaderboard.js').split('function mergePlayer')[0].split('const BOARD_CAP')[1].replace(/^.*?\n/,'')+
source('secret-admin.js').split('const adminCode=')[0]+source('analytics.js'),context);
(async()=>{
await vm.runInContext(`(async()=>{
 secretAdmin.active=true;
 const now=Date.now(),day=analyticsDay(now),entry={id:'score-turtle',name:'Ada',score:100,distance:200,sub:'turtle',diff:'officer',date:day,at:now};
 disk.entries=[entry];lb.shared=[entry];lb.local=[entry];
 const row={id:'session',name:'Ada',day,rev:2,seconds:{survival:30},runs:[{...entry,id:'activity-turtle',scoreId:entry.id,mode:'survival',outcome:'lost',seconds:30}]};
 analytics.remote.set(row.id,row);analytics.local.set(row.id,row);
 globalThis.filters={period:'all',player:'',mode:'',diff:''};
 globalThis.snapshot=()=>JSON.parse(JSON.stringify(analyticsData(filters)));
 globalThis.before=snapshot();
 await adminCommit('shared',entry.id,{...entry,score:800,distance:900,sub:'gato',diff:'admiral',name:'Ben'});
 globalThis.edited=snapshot();
 await adminCommit('shared',entry.id,null);
 globalThis.deleted=snapshot();
 // A second client starts with stale board/activity caches and refreshes stats.
 lb.admin={entries:{},players:{}};lb.shared=[entry];
 lb.dir={getDirectoryHandle:async()=>({entries:async function*(){yield ['session.dat',{kind:'file',getFile:async()=>({text:async()=>JSON.stringify({...row,v:1})})}]}})};
 globalThis.unseal=x=>x;
 await analyticsRead();
 globalThis.refreshed=snapshot();
 // Legacy scores have no activity record and must honor the same corrections.
 analytics.local.clear();analytics.remote.clear();
 globalThis.legacyDeleted=snapshot();
 lb.admin=disk.admin={entries:{[entry.id]:{at:now,value:{...entry,score:400}}},players:{}};
 globalThis.legacyEdited=snapshot();
})()`,context);
const result=name=>JSON.parse(vm.runInContext('JSON.stringify('+name+')',context));
assert.equal(result('before').runs.length,1);
const edited=result('edited');assert.equal(edited.runs.length,1);assert.equal(edited.runs[0].score,800);assert.equal(edited.runs[0].seconds,30);assert.equal(edited.runs[0].mode,'survival');assert.equal(edited.runs[0].name,'Ben');assert.equal(edited.ships.find(s=>s.id==='turtle').uses,0);assert.equal(edited.ships.find(s=>s.id==='gato').points,800);
for(const name of ['deleted','refreshed','legacyDeleted'])assert.equal(result(name).runs.length,0,name);
assert.equal(result('legacyEdited').runs[0].score,400);
console.log('PASS: shared admin edits/deletions, stale local backups, linked activity, second-client refresh, and legacy scores');
})().catch(e=>{console.error(e);process.exitCode=1});
