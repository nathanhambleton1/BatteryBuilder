const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..'),read=f=>fs.readFileSync(path.join(root,f),'utf8');
const html=read('undertow.html');
for(const [,file] of html.matchAll(/(?:src|href)="(files\/[^\"]+)"/g))assert(fs.existsSync(path.join(root,file)),file);
assert(!fs.existsSync(path.join(root,'undertow-offline.html')));
const campaign=read('files/campaign.js'),combat=read('files/combat-upgrades.js');
const campOpen=campaign.match(/^const campOpen=.*$/m)[0],fleetOpen=combat.match(/^const fleetOpen=.*$/m)[0];
const context=vm.createContext({assert});
vm.runInContext(`const MISSIONS=[{id:'first'},{id:'second'}],camp={data:{done:{}}},SUB_BY_ID={virginia:{},turtle:{}},FLEET_LEVELS={virginia:1,turtle:75};let level=1;const fleetLevel=()=>level;${campOpen}\n${fleetOpen}\nassert(campOpen(0));assert(campOpen(1));assert(!campOpen(-1));assert(!campOpen(2));camp.data.done.first=1;assert(campOpen(1));assert(fleetOpen('virginia'));assert(fleetOpen('turtle'));assert(!fleetOpen('missing'));level=75;assert(fleetOpen('turtle'));`,context);
for(const source of [campaign,combat])assert(!source.includes('secretAdmin.active'));
console.log('PASS: entry-point assets and menu unlock logic');

// Manual-save edition: admin console, typed callsign and Save button back; no OFFLINE tag, statistics or launcher.
assert(html.includes('files/secret-admin.js')&&html.includes('files/manual-save.js')&&!html.includes('files/offline.js'));
assert(html.includes('id="callsign"'));
assert(!html.includes('id="statistics"')&&!html.includes('id="statsOpen"'));
assert(!read('files/analytics.js').includes('writeText'));
assert(!fs.existsSync(path.join(root,'Play Undertow.cmd')));
assert(!read('files/save-status.js').includes('OFFLINE VERSION'));
assert(/SAVE_COOLDOWN=60000/.test(read('files/manual-save.js')));
// Nothing may reach the shared drive on a timer or page event: no intervals or listeners call the I/O paths.
for(const f of fs.readdirSync(path.join(root,'files')).filter(f=>f.endsWith('.js'))){
 const src=read('files/'+f);
 for(const m of src.matchAll(/(setInterval|setTimeout|addEventListener)\([^;]*?(saveAll|profSync|lbFlush|boardRefresh)\(/g))
  assert(f==='manual-save.js'&&m[0].includes("'keydown'"),f+': automatic shared-drive call '+m[0].slice(0,80));
}
// Finishing the callsign reads that sailor's profile; the read never writes.
assert(/addEventListener\('change',[^\n]*profSwitch\(\);profLoad\(\)/.test(read('files/main.js')));
const profLoadSrc=read('files/profile.js').match(/async function profLoad\(\)[\s\S]*?\n\}/)[0];
assert(!/writeText|saveAll|SAVE_COOLDOWN|saveJob\.tried/.test(profLoadSrc));
console.log('PASS: manual-save entry point, launcher, callsign load and no automatic shared-drive I/O');
