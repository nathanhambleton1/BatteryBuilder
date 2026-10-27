const {chromium}=require('playwright'),path=require('path'),fs=require('fs'),os=require('os');
(async()=>{
 const browser=await chromium.launch({channel:'msedge',headless:true}),out=fs.mkdtempSync(path.join(os.tmpdir(),'undertow-3d-'));
 try{
 const page=await browser.newPage({viewport:{width:1440,height:900}}),errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.goto('file:///'+path.resolve(__dirname,'../undertow.html').replaceAll('\\','/'));
 const result=await page.evaluate(()=>{
  soundOn=false;musicOn=false;const checks=[],failures=[],check=(name,ok)=>{checks.push(name);if(!ok)failures.push(name)};
  function boot(){cm=MISSIONS[1];subId='gato';diffId=cm.diff;courseSeed=campSeed(cm);camp.data=blankCamp();camp.run={m:cm,cp:0,snap:null,clean:true,deaths:0,loot:[0,0,0],time:0,cuts:{}};reset();state='playing';panel=null;['menu','paused','sfGate','footer'].forEach(id=>show(id,false));expeditionStart(cr.wrecks[0]);return cr.expedition}
  let e=boot();check('WebGL context available',!!DroneWorld.gl);const bat=e.battery,x=sub.x,time=t,air=o2;for(let i=0;i<390;i++)physics(1/120);
  check('deployment enters pilot automatically',e.phase==='pilot');check('deployment preserves battery',e.battery>bat-.1);check('mothership physics frozen',sub.x===x&&t===time&&o2===air);
  e.x=e.target.x;e.y=e.target.y;e.z=e.target.z+8;e.scan=6;inputKeys.add('KeyF');for(let i=0;i<150;i++)expeditionStep(1/120);check('tool requires depth-axis proximity',e.grip===0);clearInput();
  e=boot();e.phase='pilot';const z0=e.z;inputKeys.add('KeyW');for(let i=0;i<120;i++)expeditionStep(1/120);check('forward movement uses third axis',e.z<z0-3);clearInput();
  const y0=e.y;inputKeys.add('Space');for(let i=0;i<100;i++)expeditionStep(1/120);check('space changes altitude',e.y>y0+2);check('space does not operate tool',e.grip===0);clearInput();
  e=boot();e.phase='pilot';e.x=10;e.y=4;e.z=0;e.vx=1;const battery=e.battery;pause();expeditionStep(1);check('pause freezes sortie',e.x===10&&e.battery===battery);resume();
  e.x=1;e.y=1;e.z=-22;e.vx=5;expeditionStep(1/120);check('wreck collision resolves penetration',Math.abs(e.x-1)>=1.04||Math.abs(e.y-1.1)>=1.84);check('fast impact damages hull',e.hp<3);
  e=boot();e.phase='pilot';e.x=0;e.y=0;e.z=10;expeditionStep(1/120);check('seabed is solid',e.y>=droneFloor(e.x,e.z)+.69);
  e.x=55;expeditionStep(1/120);check('tether boundary is enforced',e.x<=49);
  e=boot();e.phase='pilot';e.battery=0;expeditionStep(1/120);check('battery failure clears controls and leaves wreck retryable',!cr.expedition&&!cr.wrecks[0].done&&!cr.wrecks[0].busy&&!document.body.classList.contains('rov-active'));
  e=boot();e.phase='pilot';e.cargo=true;e.x=e.dock.x;e.y=e.dock.y;e.z=e.dock.z;const w=e.w;expeditionStep(1/120);check('dock begins recovery cutscene',e.phase==='dock'&&!w.done);for(let i=0;i<200&&cr.expedition;i++)expeditionStep(1/120);check('recovery transfers cargo once',w.done&&cr.salv.size===1&&!cr.expedition);
  e=boot();e.phaseTime=1.5;draw();check('3D rendering has no GPU errors',DroneWorld.gl.getError()===DroneWorld.gl.NO_ERROR);
  return {checks,failures};
 });
 await page.screenshot({path:path.join(out,'deployment.png')});await page.locator('#rovSkip').click();
 const before=await page.evaluate(()=>cr.expedition.yaw);await page.mouse.move(650,400);await page.mouse.down();await page.mouse.move(820,450,{steps:10});await page.mouse.up();
 if(await page.evaluate(()=>cr.expedition.yaw)<=before+.5)result.failures.push('mouse drag look');else result.checks.push('mouse drag look');
 await page.keyboard.down('ArrowLeft');await page.waitForTimeout(180);await page.keyboard.up('ArrowLeft');
 const altitude=await page.evaluate(()=>cr.expedition.y);await page.keyboard.down('KeyC');await page.waitForTimeout(450);await page.keyboard.up('KeyC');if(await page.evaluate(()=>cr.expedition.y)>=altitude-.3)result.failures.push('C descend keyboard binding');else result.checks.push('C descend keyboard binding');
 await page.evaluate(()=>{const e=cr.expedition;e.x=9;e.y=8;e.z=-7;e.yaw=-.32;e.pitch=-.3;e.vx=e.vy=e.vz=0;draw()});
 await page.screenshot({path:path.join(out,'wreck-site-desktop.png')});
 await page.setViewportSize({width:390,height:844});await page.screenshot({path:path.join(out,'wreck-site-mobile.png')});
 const y=await page.evaluate(()=>cr.expedition.y);const rise=page.locator('[data-rov="Space"]');
 // Real pointer capture exercises the touch-style controls using browser input.
 const bounds=await rise.boundingBox();await page.mouse.move(bounds.x+bounds.width/2,bounds.y+bounds.height/2);await page.mouse.down();await page.waitForTimeout(500);await page.mouse.up();
 if(await page.evaluate(()=>cr.expedition.y)<=y+.4)result.failures.push('on-screen ascend');else result.checks.push('on-screen ascend');
 await page.locator('#rovPause').click();const frozen=await page.evaluate(()=>cr.expedition.battery);await page.waitForTimeout(200);if(await page.evaluate(()=>cr.expedition.battery)!==frozen)result.failures.push('UI pause battery');await page.locator('#resume').click();
 await page.locator('#rovRecall').click();if(await page.evaluate(()=>!!cr.expedition||inputKeys.size))result.failures.push('recall input cleanup');
 console.log(JSON.stringify({checks:result.checks.length,failures:result.failures,errors,artifacts:out},null,2));fs.writeFileSync(path.join(out,'results.json'),JSON.stringify({...result,errors},null,2));if(result.failures.length||errors.length)process.exitCode=1;
 }finally{await browser.close()}
})().catch(e=>{console.error(e);process.exit(1)});
