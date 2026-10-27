()=>{
 const checks=[],failures=[];const random=Math.random;Math.random=mulberry(20261026);
 const check=(name,ok,detail)=>{checks.push({name,ok,detail});if(!ok)failures.push({name,detail})};
 function boot(m,id='gato',cp=0,snap=null){cm=m;subId=id;diffId=m.diff;courseSeed=campSeed(m);camp.data=blankCamp();camp.run={m,cp,snap,clean:true,deaths:0,loot:[0,0,0],time:0,cuts:{}};reset();state='playing';panel=null;clearInput();}
 // Recover actual payloads using the same 120 Hz movement and tool code as play.
 for(const kind of ['ship','relay','mineRig','core'])for(let variant=0;variant<3;variant++){
  boot(MISSIONS[1]);const w=cr.wrecks[variant];w.k=kind;expeditionStart(w);const e=cr.expedition;
  function move(x,y){let n=0;while(cr.expedition&&Math.hypot(e.x-x,e.y-y)>8&&n++<3600){inputKeys.clear();if(Math.abs(x-e.x-e.vx*.24)>3)inputKeys.add(x>e.x+e.vx*.24?'ArrowRight':'ArrowLeft');if(Math.abs(y-e.y-e.vy*.24)>3)inputKeys.add(y>e.y+e.vy*.24?'ArrowDown':'ArrowUp');expeditionStep(1/120)}inputKeys.clear();for(let i=0;i<90&&cr.expedition;i++)expeditionStep(1/120)}
  for(const n of e.nodes){move(n.x,n.y);expeditionScan()}
  move(e.target.x,130);move(e.target.x,e.target.y);
  let n=0;while(cr.expedition&&!e.cargo&&n++<1500){inputKeys.clear();if(e.clock-e.pulse>=2)expeditionScan();if(e.kind!=='core'||e.heat<.78)inputKeys.add('Space');expeditionStep(1/120)}
  check('payload tool '+kind+'/'+variant,e.cargo,{hp:e.hp,time:e.clock,grip:e.grip,nodes:e.nodes});
  move(e.target.x,130);move(130,130);
  check('payload delivery '+kind+'/'+variant,w.done&&cr.salv.has(w.i)&&!cr.expedition,{hp:e.hp,time:e.clock,salv:[...cr.salv]});
 }
 boot(MISSIONS[1]);expeditionStart(cr.wrecks[0]);const originalX=sub.x,originalTime=t,originalO2=o2;physics(1/120);check('mothership holds during expedition',sub.x===originalX&&t===originalTime&&o2===originalO2);
 cr.expedition.hp=0;expeditionStep(1/120);check('failed expedition stays retryable',!cr.expedition&&!cr.wrecks[0].done&&!cr.wrecks[0].busy);
 boot(MISSIONS[1],'gato',2,{salv:[],clues:[]});check('old salvage checkpoint repaired',cr.wrecks.filter(w=>w.required&&!w.done).every(w=>w.x>sub.x));
 for(const m of MISSIONS){boot(m);const ids=campRequiredWrecks(m),o=m.obj||{};check(m.id+' objectives available',ids.length>=(o.sub||o.salv||0)&&(!o.need||ids.some(i=>m.wrecks[i][1]==='core')));for(const w of cr.wrecks.filter(w=>w.required)){sub.x=w.x-200;check(m.id+' holds at operation '+w.i,campSpeed()===0)}}
 // Track each generated escape gap with an ordinary two-direction helm controller,
 // including an initial reaction delay and full-speed reversal in damaged boats.
 let cases=0,armFailures=[];
 for(const mi of [7,19,15])for(const vessel of SUBS)for(const fault of [false,true])for(const depth of [.22,.5,.78])for(const direction of [-1,0,1]){
  boot(MISSIONS[mi],vessel.id);sub.x=(cm.boss?cm.boss.at:cm.chase.from)+1600;t=5;ballastUntil=fault?99:0;
  const ag=S.agility*(fault?.55:1),z=terrain(sub.x);sub.y=mix(ceilAt(sub.x)+S.hy+50,z.bottom-S.hy-50,depth);sub.v=direction<0?-185*ag:direction>0?235*ag:0;
  speed=campCombatSpeed();cr.hz=[];spawnArms({},2,'kraken');if(!cr.hz.length)continue;cases++;const target=cr.escape.y;let hit=false,rock=false;
  for(let step=0;step<540;step++){const up=step<54?direction<0:sub.y+sub.v*.38>target;const down=step<54?direction>0:!up;
   sub.v=clamp(sub.v+((up?-470:down?660:360)*ag-2.6*sub.v)/120,-185*ag,(down?235:150)*ag);sub.x+=speed/120;sub.y+=sub.v/120;t+=1/120;
   const tz=terrain(sub.x);if((tz.cave>.002&&sub.y-S.hy<tz.top)||sub.y+S.hy>tz.bottom)rock=true;
   for(const h of cr.hz){const reach=tentReach(h);if(reach>.2)for(const [x,y,w] of tentPts(h,reach,8))if(hitsSub(x,y,w*.85))hit=true}
  }
  if(hit||rock)armFailures.push({mission:cm.id,sub:vessel.id,fault,depth,direction,hit,rock,target});
 }
 check('tentacle escape trajectories '+cases,armFailures.length===0,armFailures);
 // Worst helm reversal needed to leave a sweep or ram corridor in open water.
 let reversals=0,bad=[];
 for(const vessel of SUBS)for(const fault of [false,true])for(const direction of [-1,1]){
  boot(MISSIONS[19],vessel.id);t=1;ballastUntil=fault?99:0;const ag=S.agility*(fault?.55:1),v=direction<0?-185*ag:235*ag;
  const end=campVerticalReach(0,v,2.0,direction>0);reversals++;if(Math.abs(end)<44+S.hy*.6+15)bad.push({sub:vessel.id,fault,direction,end});
 }
 check('sweep and ram reversal margin '+reversals,bad.length===0,bad);
 let volleys=0,volleyFailures=[];
 for(const vessel of SUBS)for(const fault of [false,true])for(const depth of [.25,.5,.75])for(const direction of [-1,0,1]){
  boot(MISSIONS[22],vessel.id);sub.x=cm.boss.at+1600;t=5;ballastUntil=fault?99:0;const ag=S.agility*(fault?.55:1),z=terrain(sub.x);sub.y=mix(SURFACE+80,z.bottom-80,depth);sub.v=direction<0?-185*ag:direction>0?235*ag:0;speed=campCombatSpeed();enemyMissiles=[];campVolley(sub.x+440,sub.y,5,60);
  if(!cr.escape)continue;volleys++;const target=cr.escape.y;let hit=false;
  for(let step=0;step<420;step++){const up=step<54?direction<0:sub.y+sub.v*.38>target,down=step<54?direction>0:!up;sub.v=clamp(sub.v+((up?-470:down?660:360)*ag-2.6*sub.v)/120,-185*ag,(down?235:150)*ag);sub.x+=speed/120;sub.y+=sub.v/120;for(const m of enemyMissiles){m.x+=m.vx/120;if(((m.x-sub.x)/(S.hx+4))**2+((m.y-sub.y)/(S.hy+5))**2<1)hit=true}}
  if(hit)volleyFailures.push({sub:vessel.id,fault,depth,direction,target});
 }
 check('broadside escape trajectories '+volleys,volleyFailures.length===0,volleyFailures);
 boot(MISSIONS[22],'virginia');startBoss('leviathan');abilityAt=-99;useAbility();check('Virginia salvo targets campaign boss',missiles.length===3);
 boot(MISSIONS[4]);sub.x=cm.recon[0].x1-250;check('recon holds until beacon return',campSpeed()===0);cm.recon[0].clues.forEach((_,j)=>cr.clues.add('0:'+j));check('recon releases after beacon return',campSpeed()>0);
 boot(MISSIONS[19]);pickups=[];speed=200;campSupplyTick();check('air supply independent of minefields',pickups.length===1);
 const terrainFailures=[];let courses=0;
 for(const m of MISSIONS)for(const vessel of SUBS){boot(m,vessel.id);const end=m.L||m.boss.at+5000;let steps=0,crashed=false;
  while(sub.x<end&&steps++<24000){const ag=S.agility,base=D.speed[1]*S.speed*(m.race?1.3*1.55:1),v=campTerrainSpeed(base),target=terrain(sub.x+v*.5).centre,up=sub.y+sub.v*.35>target;
   sub.v=clamp(sub.v+((up?-470:660)*ag-2.6*sub.v)/60,-185*ag,235*ag);sub.x+=v/60;sub.y+=sub.v/60;
   const z=terrain(sub.x);if((z.cave>.002&&sub.y-S.hy<z.top)||sub.y+S.hy>z.bottom){crashed=true;break}
  }courses++;if(crashed||sub.x<end)terrainFailures.push({m:m.id,sub:vessel.id,x:sub.x,y:sub.y});
 }
 check('terrain navigation at maximum cruise/boost '+courses,terrainFailures.length===0,terrainFailures);
 const normalFailures=[];let normalStarts=0;cm=null;cr=null;courseSeed=null;
 for(const id of Object.keys(DIFFS))for(const vessel of SUBS){diffId=id;subId=vessel.id;reset();state='playing';for(let i=0;i<120;i++)physics(1/120);draw();normalStarts++;if(state!=='playing'||D!==DIFFS[id]||S!==SUB_BY_ID[vessel.id])normalFailures.push({id,sub:vessel.id,state})}
 check('standard mode launch smoke checks '+normalStarts,normalFailures.length===0,normalFailures);
 Math.random=random;state='paused';return {checks,failures};
}
