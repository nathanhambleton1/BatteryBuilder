'use strict';
// Use the actual dive-plane acceleration, drag and damage modifier. Forward speed
// is limited during combat rather than making heavy boats steer like light boats.
function campCombatSpeed(){return 245*S.agility*(t<ballastUntil?.55:1)}
function campTerrainSpeed(v,x=sub.x){
 const ag=S.agility*(t<ballastUntil?.55:1);
 for(let d=0;d<1000;d+=250){const slope=(terrain(x+d+250).centre-terrain(x+d).centre)/250;if(Math.abs(slope)>.08)v=Math.min(v,(slope<0?85:110)*ag/Math.abs(slope))}
 return v;
}
function campLimitSpeed(v){
 v=campTerrainSpeed(v);
 if(cr&&(cr.boss||cr.foes.some(f=>!f.dead)||cr.hz.some(h=>h.k==='tent'||h.k==='sweep')))return Math.min(v,campCombatSpeed());
 return v;
}
function campVerticalReach(y,v,seconds,up){
 const ag=S.agility*(t<ballastUntil?.55:1),dt=1/120;
 for(let s=0;s<seconds;s+=dt){const step=Math.min(dt,seconds-s);v=clamp(v+((up?-470:660)*ag-2.6*v)*step,-185*ag,235*ag);y+=v*step}
 return y;
}
function campArmRouteClear(target,forward){
 let x=sub.x,y=sub.y,v=sub.v;const ag=S.agility*(t<ballastUntil?.55:1),dir=Math.sign(v),dt=1/60;
 for(let time=0;time<4.5;time+=dt){
  const up=time<.45?dir<0:y+v*.38>target,down=time<.45?dir>0:!up;
  v=clamp(v+((up?-470:down?660:360)*ag-2.6*v)*dt,-185*ag,(down?235:150)*ag);x+=forward*dt;y+=v*dt;
  for(const dx of [-S.hx,0,S.hx]){const z=terrain(x+dx);if((z.cave>.002&&y-S.hy-8<z.top)||y+S.hy+8>z.bottom)return false}
 }
 return true;
}
function campVolley(x,y,n,spacing){
 // A broadside leaves a marked corridor; it cannot demand that a heavy boat
 // cross the entire fan before the first torpedo reaches its bow.
 const eta=Math.max(.8,(x-sub.x-S.hx-20)/180),px=sub.x+campCombatSpeed()*eta;
 const top=ceilAt(px)+S.hy+35,bot=terrain(px).bottom-S.hy-35;
 const lo=Math.max(top,campVerticalReach(sub.y,sub.v,Math.max(.3,eta-.6),true));
 const hi=Math.min(bot,campVerticalReach(sub.y,sub.v,Math.max(.3,eta-.6),false));
 if(lo>hi)return;
 const gap=clamp(sub.y+(sub.y>(top+bot)/2?-65:65),lo,hi);
 for(let i=0;i<n;i++){const ty=y+(i-(n-1)/2)*spacing;if(ty>top&&ty<bot&&Math.abs(ty-gap)>S.hy+38)torp(x,ty,0)}
 cr.escape={x:px,y:gap,until:t+eta+.8};
}
function campRequiredWrecks(m){
 const o=m.obj||{},ws=m.wrecks||[],n=o.sub||o.salv||0,valid=ws.map((w,i)=>i).filter(i=>!o.sub||['sub','akula'].includes(ws[i][1])),ids=[];
 if(o.need==='core'){const i=ws.findIndex(w=>w[1]==='core');if(i>=0)ids.push(i)}
 for(let j=0;j<n&&valid.length;j++){const i=valid[Math.min(valid.length-1,Math.floor(j*valid.length/n))];if(!ids.includes(i))ids.push(i)}
 // The core counts as one salvage load.
 while(ids.length>n&&n>0){const j=ids.findLastIndex(i=>ws[i][1]!=='core');ids.splice(j,1)}
 return ids;
}
function campStation(){
 if(!cr)return null;
 const o=cm.obj||{},need=(o.sub?cr.subLoads<o.sub:cr.salv.size<(o.salv||0));
 const w=cr.wrecks.find(w=>w.required&&!w.done&&(need||w.k==='core'&&!cr.core)&&sub.x>=w.x-220&&sub.x<w.x+500);
 if(w)return {kind:'wreck',w,x:w.x-180};
 const z=inRecon(sub.x);if(z&&sub.x>=z.x1-260){const zi=cm.recon.indexOf(z);if(z.clues.some((_,j)=>!cr.clues.has(zi+':'+j)))return {kind:'recon',x:z.x1-240}}
 return null;
}
function campStationTick(){
 const station=campStation();if(!station){cr.stationKey='';return}
 const key=station.kind==='wreck'?'w'+station.w.i:'r'+station.x;
 if(cr.stationKey!==key){cr.stationKey=key;toast(station.kind==='wreck'?'SEAFLOOR OPERATION':'RECON STATION',station.kind==='wreck'?'Holding over the site. Press Q to pilot the drone.':'Surface and press Q. Recover the beacons before departing.',4);cr.foes.forEach(f=>f.until=Math.min(f.until,t));enemyMissiles=[];cr.hz=[]}
}
function campSupplyTick(){
 if(cr.air||cr.expedition||campStation()||sub.x<(cr.nextSupplyX||0))return;
 cr.nextSupplyX=sub.x+Math.max(700,speed*7);
 const x=sub.x+Math.max(600,speed*2),y=safeY(x,mix(sub.y,route(x),.5),50);
 if(!pickups.some(p=>!p.taken&&Math.abs(p.x-x)<400))pickups.push({x,y,cy:y,phase:0,taken:false});
}
// Keep radio exchanges moving while the player retains the helm.
function campaignRadioCut(lines){for(const [who,text] of lines)comms(who,text)}
