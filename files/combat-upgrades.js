'use strict';
const FLEET_LEVELS={gato:1,seawolf:5,type212:10,virginia:15,astute:22,ohio:28,akula:34,typhoon:45,turtle:75};
const fleetOrdered=()=>[...SUBS].sort((a,b)=>FLEET_LEVELS[a.id]-FLEET_LEVELS[b.id]);
const fleetLevel=()=>levelOf(profXp());
const fleetOpen=id=>!!SUB_BY_ID[id]&&(secretAdmin.active||fleetLevel()>=(FLEET_LEVELS[id]||1));
const fleetAvailable=()=>SUBS.filter(s=>fleetOpen(s.id)).map(s=>s.id);
function ensureFleetSelection(){if(!fleetOpen(subId)){subId='gato';S=SUB_BY_ID.gato}if(!fleetOpen(camp.data.sub))camp.data.sub='gato'}
let screenBombAt=-99;
function turtleBomb(){
 const visible=(x,y)=>{const p=proj(x,y);return p[0]>=-50&&p[0]<=W+50&&p[1]>=-50&&p[1]<=H+50};
 for(const g of gates)for(let k=0;k<2;k++)if(!g.dead[k]&&visible(g.x,mineY(g,k)))detonateMine(g,k,true);
 enemyMissiles=enemyMissiles.filter(m=>{if(!visible(m.x,m.y))return true;boom(m.x,m.y,20);intercepts++;bonus+=40;return false});
 for(const s of ships)if(!s.sinking&&visible(s.x,SURFACE)){s.hp=1;hitShip(s,s.x,SURFACE)}
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
