const {chromium}=require('playwright'),path=require('path');
(async()=>{const browser=await chromium.launch({channel:'msedge',headless:true});try{
const page=await browser.newPage(),errors=[];page.on('pageerror',e=>errors.push(e.message));
await page.goto('file:///'+path.resolve(__dirname,'../undertow.html').replaceAll('\\','/'));
const result=await page.evaluate(()=>{
soundOn=musicOn=false;show('sfGate',false);lb.gate.offline=true;
const failures=[];let checks=0;const check=(name,ok)=>{checks++;if(!ok)failures.push(name)};
for(const diff of ['cadet','officer','captain','admiral']){
cm=null;cr=null;diffId=diff;subId='virginia';reset();state='playing';panel=null;ships=[];gates=[];enemyMissiles=[];missiles=[];t=10;
fire();check(diff+' single rocket',missiles.length===1);t+=.31;fire();check(diff+' original cooldown',missiles.length===1);
t=lastFire+reloadTime()+.01;fire();check(diff+' automatic reload',missiles.length===2);
missiles=[];useAbility();check(diff+' original special',missiles.length===3);
draw();check(diff+' no reload button',!document.getElementById('reloadRack'));
}
check('added hunter removed',typeof patrolStep==='undefined');
check('Akula preserved',SUB_BY_ID.akula.ability.cd===26&&SUB_BY_ID.akula.o2===75);
check('progression preserved',FLEET_LEVELS.typhoon===45&&FLEET_LEVELS.turtle===75);
subId='turtle';reset();state='playing';t=10;camX=sub.x-vw*.24;camY=0;enemyMissiles=[{x:sub.x,y:sub.y}];useAbility();check('Turtle preserved',enemyMissiles.length===0&&S.ability.cd===30);draw();
return {checks,failures};});
console.log(JSON.stringify({...result,errors},null,2));if(result.failures.length||errors.length)process.exitCode=1;
}finally{await browser.close()}})().catch(e=>{console.error(e);process.exit(1)});
