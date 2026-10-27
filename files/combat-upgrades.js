'use strict';
const FLEET_LEVELS={gato:1,virginia:5,type212:10,seawolf:15,astute:22,akula:28,ohio:34,typhoon:45,turtle:75};
const fleetLevel=()=>levelOf(profXp());
const fleetOpen=id=>!!SUB_BY_ID[id]&&(secretAdmin.active||fleetLevel()>=(FLEET_LEVELS[id]||1));
const fleetAvailable=()=>SUBS.filter(s=>fleetOpen(s.id)).map(s=>s.id);
function ensureFleetSelection(){if(!fleetOpen(subId)){subId='gato';S=SUB_BY_ID.gato}if(!fleetOpen(camp.data.sub))camp.data.sub='gato'}
const rack={rounds:3,until:0},hardCombat=()=>DIFF_RANK[diffId]>=2;
function resetRack(){rack.rounds=3;rack.until=0;patrolContacts=[];nextPatrolAt=9;screenBombAt=-99}
function rackTick(){if(rack.until&&t>=rack.until){rack.rounds=3;rack.until=0;lastHud=-1;sfx.pickup()}}
function reloadRack(){
 if(state!=='playing'||!hardCombat()||cr&&cr.expedition||rack.until||rack.rounds===3)return false;
 rack.until=t+reloadTime();lastHud=-1;toast('RELOADING','Loading three tubes. Maneuver while the crew works.',1.4);return true;
}
function rackCanFire(){rackTick();if(!hardCombat())return true;if(rack.until)return false;if(!rack.rounds){toast('TUBES EMPTY','Press R or tap RELOAD to load three rockets.',1.6);return false}return true}
function rackButton(){
 let b=$('reloadRack');if(!b){b=document.createElement('button');b.id='reloadRack';b.type='button';b.onclick=reloadRack;document.body.append(b)}
 b.hidden=state!=='playing'||!hardCombat()||!!(cr&&cr.expedition);if(!b.hidden){b.textContent=rack.until?'RELOAD '+Math.max(0,rack.until-t).toFixed(1)+'s':'R · RELOAD '+rack.rounds+'/3';b.disabled=!!rack.until||rack.rounds===3}
}
let patrolContacts=[],nextPatrolAt=9,screenBombAt=-99;
function patrolSafeY(x,y){return clamp(y,ceilAt(x)+S.hy+65,terrain(x).bottom-S.hy-65)}
function spawnPatrolContact(){
 const x=sub.x+clamp(vw*.65,360,900),y=patrolSafeY(x,sub.y+90);
 const p={x,y,hp:diffId==='admiral'?3:2,max:diffId==='admiral'?3:2,born:t,until:t+17,next:t+3.2,aim:null,hit:-99};patrolContacts.push(p);return p;
}
function patrolStep(dt){
 if(cm||!hardCombat())return;
 if(t>=nextPatrolAt&&patrolContacts.length===0){spawnPatrolContact();nextPatrolAt=t+(diffId==='admiral'?19:25);toast('HUNTER SUBMARINE','Amber line: its aim is locked. Change depth or intercept the torpedo.',3.5,true)}
 for(let i=patrolContacts.length-1;i>=0;i--){const p=patrolContacts[i];
  p.x=sub.x+clamp(vw*.65,360,900);p.y=patrolSafeY(p.x,p.y);if(t>p.until){patrolContacts.splice(i,1);continue}
  if(active('silent')){p.aim=null;p.next=Math.max(p.next,t+1.5);continue}
  if(!p.aim&&t>=p.next)p.aim={y:sub.y,at:t,fire:t+2.2,curve:(Math.sin(t*2)>0?1:-1)*(diffId==='admiral'?85:65)};
  if(p.aim)p.y=patrolSafeY(p.x,p.y+clamp(p.aim.y-p.y,-90*dt,90*dt));
  if(p.aim&&t>=p.aim.fire){
   const y=p.aim.y,x=p.x;
   const duration=diffId==='admiral'?.95:1.2,travel=x-sub.x+S.hx+180;
   enemyMissiles.push({x,y,vx:speed-travel/duration,vy:0,air:false,life:duration+.5,turn:0,seek:0,err:0,sp:travel/duration,torp:true,route:{x,y,speed,travel,duration,curve:p.aim.curve||65,age:0},trail:[]});
   p.aim=null;p.next=t+(diffId==='admiral'?3.5:5);sfx.enemyLaunch();
  }
 }
}
function patrolAcquire(skip){return patrolContacts.find(p=>!skip.includes(p)&&p.x-sub.x<1400)}
function patrolHit(p,x,y){p.hp--;p.hit=t;boom(x,y,24);if(p.hp<=0){patrolContacts=patrolContacts.filter(q=>q!==p);shipsSunk++;bonus+=350;sfx.sunk();toast('HUNTER SUNK','+350. Torpedo lane cleared.',2)}}
function patrolMissile(m){const p=patrolContacts.find(p=>Math.abs(m.x-p.x)<50&&Math.abs(m.y-p.y)<22);if(!p)return false;patrolHit(p,m.x,m.y);return true}
function drawPatrolContacts(){
 for(const p of patrolContacts){c.save();c.translate(p.x,p.y);c.scale(-1,1);drawSubModel(SUB_BY_ID.akula,false);c.restore();c.save();tag(p.x,p.y-65,'HUNTER '+p.hp+'/'+p.max,'#e9b284');if(p.aim){
  const a=p.aim,end=sub.x-S.hx-180,curve=a.curve||65,point=u=>[mix(p.x,end,u),a.y+Math.sin(u*Math.PI)*curve],urgency=clamp((t-a.at)/(a.fire-a.at),0,1),pulse=reduced?1:.75+.25*Math.sin(ambient*(7+urgency*10));
  c.globalCompositeOperation='screen';const trace=()=>{c.beginPath();for(let i=0;i<=40;i++){const q=point(i/40);i?c.lineTo(...q):c.moveTo(...q)}};
  for(const [width,alpha] of [[28,.045],[13,.09],[5,.2],[1.7,.75]]){trace();c.lineWidth=width;c.strokeStyle='rgba(255,'+Math.round(190-urgency*70)+',90,'+alpha*pulse+')';c.stroke()}
  for(let i=0;i<8;i++){const u=(i/8+(reduced?0:ambient*.5))%1,q=point(u),q2=point(Math.min(1,u+.01)),ang=Math.atan2(q2[1]-q[1],q2[0]-q[0]);c.save();c.translate(...q);c.rotate(ang);path([[-6,-5],[1,0],[-6,5]],null,'#ffd69bcc',1.6);c.restore()}
  const impact=point(.82);circle(...impact,18+urgency*10,null,'#ffc57c77',1.5);c.globalCompositeOperation='source-over';tag(sub.x+150,a.y-105,'FAST TORPEDO · '+Math.max(0,a.fire-t).toFixed(1)+'s','#ffe0a7');
 }c.restore()}
}
function drawFastTorpedo(m){
 c.save();c.globalCompositeOperation='screen';for(let i=1;i<(m.trail||[]).length;i++){const a=m.trail[i-1],b=m.trail[i];c.strokeStyle='rgba(100,220,255,'+(i/m.trail.length*.6)+')';c.lineWidth=2+i/m.trail.length*5;c.beginPath();c.moveTo(a.x,a.y);c.lineTo(b.x,b.y);c.stroke()}
 glow(m.x,m.y,28,'#80ddff77');c.translate(m.x,m.y);c.rotate(Math.atan2(m.vy,m.vx));path([[-16,-4],[9,-4],[16,0],[9,4],[-16,4]],'#e4faff','#7fd8ef',1);c.fillStyle='#82e8ff';c.beginPath();c.ellipse(-20,0,12,3,0,0,TAU);c.fill();c.restore();
}
function turtleBomb(){
 const visible=(x,y)=>{const p=proj(x,y);return p[0]>=-50&&p[0]<=W+50&&p[1]>=-50&&p[1]<=H+50};
 for(const g of gates)for(let k=0;k<2;k++)if(!g.dead[k]&&visible(g.x,mineY(g,k)))detonateMine(g,k,true);
 enemyMissiles=enemyMissiles.filter(m=>{if(!visible(m.x,m.y))return true;boom(m.x,m.y,20);intercepts++;bonus+=40;return false});
 for(const s of ships)if(!s.sinking&&visible(s.x,SURFACE)){s.hp=1;hitShip(s,s.x,SURFACE)}
 for(const p of [...patrolContacts])if(visible(p.x,p.y)){p.hp=1;patrolHit(p,p.x,p.y)}
 if(cr){
  cr.hz=cr.hz.filter(h=>{if(!visible(h.x,h.y??h.base??sub.y))return true;boom(h.x,h.y??sub.y,25);return false});
  for(const f of cr.foes)if(!f.dead&&visible(f.x,f.y)){if(Number.isFinite(f.hp)&&f.hp>0){f.hp=1;foeHit(f,f.x,f.y)}else f.dead=t||.001}
  const b=cr.boss;if(b&&!b.dead&&visible(b.x,b.y)){if(b.k==='kchase'){cr.boss=null;cr.chased=true;cr.hz=[]}else{b.hp=1;bossHit(b,b.x,b.y)}}
 }
 screenBombAt=t;boom(sub.x,sub.y,45);flash=reduced?.04:.2;shake=reduced?0:8;
}
function drawScreenBomb(){const age=t-screenBombAt;if(age<0||age>1.3)return;const p=proj(sub.x,sub.y);c.save();c.strokeStyle='rgba(255,213,130,'+((1-age/1.3)*.75)+')';c.lineWidth=8*(1-age/1.3)+1;c.beginPath();c.arc(p[0],p[1],age*Math.max(W,H),0,TAU);c.stroke();c.restore()}
function drawTurtleModel(m,lamp){
 c.save();const x=m.hx,y=m.hy,g=c.createLinearGradient(-x,0,x,0);g.addColorStop(0,'#352616');g.addColorStop(.4,'#bd9256');g.addColorStop(1,'#594024');c.fillStyle=g;c.strokeStyle='#c4a76c';c.lineWidth=1.5;c.beginPath();c.ellipse(0,0,x,y,0,0,TAU);c.fill();c.stroke();
 c.save();c.clip();for(let i=-x;i<=x;i+=6){c.strokeStyle='#3e2c1a';c.beginPath();c.moveTo(i,-y);c.quadraticCurveTo(i+3,0,i,y);c.stroke()}for(const yy of [-y*.55,y*.55]){c.fillStyle='#72674b';c.fillRect(-x,yy,x*2,3)}c.restore();
 c.fillStyle='#a18d54';c.fillRect(-6,-y-5,12,6);circle(x*.4,-3,6,'#12373d','#d2b76d',2);circle(x*.4+1,-4,2,'#82b8b0');c.strokeStyle='#af9a67';c.beginPath();c.moveTo(-x,2);c.lineTo(-x-10,2);c.stroke();c.fillStyle='#ab955f';c.fillRect(-x-10,-6*Math.sin(ambient*18),2,12*Math.sin(ambient*18)||1);
 if(lamp)glow(x*.5,-3,20,'#a6e3d522');c.restore();
}
