const {chromium}=require('playwright'),path=require('path'),fs=require('fs');
(async()=>{
 const browser=await chromium.launch({channel:'msedge',headless:true});
 try{
 const page=await browser.newPage({viewport:{width:1440,height:900}}),errors=[];
 page.on('pageerror',e=>errors.push(e.message));
 await page.goto('file:///'+path.resolve(__dirname,'../undertow.html').replaceAll('\\','/'));
 const result=await page.evaluate(()=>{
  soundOn=false;musicOn=false;const failures=[],coverage=[],trajectories=[];
  function boot(m,id='gato',cp=0){cm=m;subId=id;diffId=m.diff;courseSeed=campSeed(m);camp.data=blankCamp();camp.run={m,cp,snap:null,clean:true,deaths:0,loot:[0,0,0],time:0,cuts:{}};reset();state='playing';panel=null;clearInput()}
  for(const m of MISSIONS){boot(m);coverage.push({id:m.id,kind:m.field.kind,zones:cr.fields.length});if(!cr.fields.length)failures.push(m.id+' no field sections');
   for(const z of cr.fields)if(cr.wrecks.some(w=>w.required&&z.x0<w.x+600&&z.x1>w.x-1050)||(m.recon||[]).some(r=>z.x0<r.x1+500&&z.x1>r.x0-650))failures.push(m.id+' overlaps operation');
   for(const z of cr.fields){sub.x=z.x0;sub.y=fieldY(z,sub.x);camX=z.x0-100;fieldStep(.01);draw()}
   for(const vessel of SUBS)for(const fault of [false,true]){
    boot(m,vessel.id);ballastUntil=fault?1e6:0;
    for(const z of cr.fields){
     sub.x=z.x0-450;sub.y=terrain(sub.x).centre;sub.v=0;let rock=false;const start=camp.data.earn.scrap;
     while(sub.x<=z.x1+5){
      const ag=S.agility*(fault?.55:1),v=fieldSpeed(campTerrainSpeed(600)),target=fieldY(z,sub.x+v*.35),up=sub.y+sub.v*.35>target;
      sub.v=clamp(sub.v+((up?-470:660)*ag-2.6*sub.v)/60,-185*ag,235*ag);sub.x+=v/60;sub.y+=sub.v/60;t+=1/60;speed=v;fieldStep(1/60);
      for(const dx of [-S.hx,0,S.hx]){const q=terrain(sub.x+dx);if(sub.y-S.hy<ceilAt(sub.x+dx)||sub.y+S.hy>q.bottom)rock=true}
     }
     trajectories.push(1);if(rock||!z.success)failures.push({mission:m.id,boat:vessel.id,fault,id:z.id,rock,hits:z.hits,progress:z.progress/z.total,heat:z.heat});
     const earned=camp.data.earn.scrap;fieldStep(1/60);if(earned!==camp.data.earn.scrap||earned-start!==2)failures.push(m.id+' duplicate/missing reward');
    }
   }
   boot(m,'gato',m.cps.length);if(cr.fields.some(z=>z.x1<sub.x&&!z.done))failures.push(m.id+' replayed completed checkpoint');
  }
  for(const m of MISSIONS.filter(m=>m.race)){boot(m);const z=cr.fields[0];sub.x=z.x0+100;cr.rival.x=sub.x;cr.inStream=true;speed=fieldSpeed(600);const before=cr.rival.x;updateRace(1/60);if(cr.rival.x-before>speed/60)failures.push(m.id+' rival ignores field speed limit')}
  boot(MISSIONS[2]);let z=cr.fields[0];sub.x=z.x0;sub.y=fieldY(z,sub.x);fieldStep(1);run.fired++;sub.x=z.x1+1;fieldStep(1);if(z.success)failures.push('silent fire not detected');
  boot(MISSIONS[14]);const w=cr.wrecks[0];expeditionStart(w);const e=cr.expedition;e.phase='pilot';e.x=e.target.x;e.y=e.target.y;e.z=e.target.z;e.clock=3;e.scan=6;inputKeys.add('KeyF');expeditionStep(1/120);if(e.grip!==0)failures.push('red disarm window accepted tool');e.clock=4.8;expeditionStep(1/120);if(e.grip<=0)failures.push('green disarm window rejected tool');
  boot(MISSIONS[6]);expeditionStart(cr.wrecks[0]);const r=cr.expedition;r.phase='pilot';r.x=r.nodes[1].x;r.y=r.nodes[1].y;r.z=r.nodes[1].z;expeditionScan();if(r.nodes[1].done)failures.push('relay sequence bypassed');
  // Every authored shot must render at different sizes and times, including reduced motion.
  const cv=document.createElement('canvas');cv.width=1440;cv.height=900;const g=cv.getContext('2d');let shots=0;
  for(const name of Object.keys(SCENES))for(const sec of [0,3,9]){paintScene(g,name,1440,900,sec);shots++}
  for(const name of Object.keys(SCENES))paintScene(g,name,390,600,3);
  state='paused';return {failures,coverage,trajectories:trajectories.length,shots};
 });
 console.log(JSON.stringify({...result,errors},null,2));
 const out=path.join(__dirname,'field-results.json');fs.writeFileSync(out,JSON.stringify({...result,errors},null,2));
 await page.evaluate(()=>{cm=MISSIONS[0];subId='gato';diffId=cm.diff;courseSeed=campSeed(cm);camp.run={m:cm,cp:0,snap:null,clean:true,deaths:0,loot:[0,0,0],time:0,cuts:{}};reset();state='paused';panel=null;['menu','paused','sfGate','footer'].forEach(id=>show(id,false));const z=cr.fields[0];sub.x=z.x0+100;sub.y=fieldY(z,sub.x);camX=sub.x-vw*.24;camY=sub.y-vh*.5;fieldStep(.1);draw()});
 await page.screenshot({path:path.join(__dirname,'field-desktop.png')});
 await page.setViewportSize({width:390,height:844});await page.evaluate(()=>draw());await page.screenshot({path:path.join(__dirname,'field-mobile.png')});
 await page.setViewportSize({width:1440,height:900});
 for(const tm of [2,5,9]){await page.evaluate(tm=>{let cv=document.getElementById('shot-preview');if(!cv){cv=document.createElement('canvas');cv.id='shot-preview';cv.width=1440;cv.height=900;cv.style='position:fixed;inset:0;z-index:99999;width:100vw;height:100vh';document.body.append(cv)}paintScene(cv.getContext('2d'),'kraken_chase',1440,900,tm)},tm);await page.screenshot({path:path.join(__dirname,'pursuit-'+tm+'.png')})}
 if(result.failures.length||errors.length)process.exitCode=1;
 }finally{await browser.close()}
})().catch(e=>{console.error(e);process.exit(1)});
