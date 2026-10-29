const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..'),read=f=>fs.readFileSync(path.join(root,f),'utf8');
const html=read('undertow.html');
for(const [,file] of html.matchAll(/(?:src|href)="(files\/[^\"]+)"/g))assert(fs.existsSync(path.join(root,file)),file);
assert(!fs.existsSync(path.join(root,'undertow-offline.html')));
const campaign=read('files/campaign.js'),combat=read('files/combat-upgrades.js');
const campOpen=campaign.match(/^const campOpen=.*$/m)[0],fleetOpen=combat.match(/^const fleetOpen=.*$/m)[0];
const context=vm.createContext({assert});
vm.runInContext(`const MISSIONS=[{id:'first'},{id:'second'}],camp={data:{done:{}}},SUB_BY_ID={virginia:{},turtle:{}},FLEET_LEVELS={virginia:1,turtle:75};let level=1;const fleetLevel=()=>level;${campOpen}\n${fleetOpen}\nassert(campOpen(0));assert(campOpen(1));assert(!campOpen(-1));assert(!campOpen(2));camp.data.done.first=1;assert(campOpen(1));assert(fleetOpen('virginia'));assert(fleetOpen('turtle'));assert(!fleetOpen('missing'));level=75;assert(fleetOpen('turtle'));`,context);
assert(!html.includes('files/secret-admin.js'));
for(const source of [campaign,combat])assert(!source.includes('secretAdmin.active'));
console.log('PASS: offline entry-point assets and menu unlock logic without admin module');

assert(!html.includes('id="callsign"'));
assert(read('files/save-status.js').includes('OFFLINE VERSION'));
assert(!read('files/save-status.js').includes('pending()'));
