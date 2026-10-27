'use strict';
/* Seafloor operations use their own clock. The mothership and combat simulation
   hold while the pilot explores; pause, retry and profile saves remain unchanged. */
function expeditionStart(w){
 const seed=mulberry(campSeed(cm)+w.i*977),kind=w.k==='core'?'core':w.k==='relay'?'relay':w.k==='mineRig'?'disarm':'salvage';
 const e={w,kind,x:130,y:130,vx:0,vy:0,clock:0,battery:75+8*(camp.data.up.drone||0),hp:3,hit:-9,scan:0,pulse:-9,grip:0,cargo:false,extra:0,notice:'Scan the wreck, secure the payload, return to the dock.',noticeUntil:5};
 e.target={x:790,y:440};e.rocks=[{x:340,y:445,r:65},{x:570,y:515,r:58},{x:940,y:330,r:50}];
 e.vents=[{x:450,phase:seed()*6},{x:680,phase:seed()*6}];
 e.items=[{x:300,y:285,taken:false},{x:560,y:240,taken:false}];
 e.mines=[{x:610,y:340,r:22},{x:870,y:220,r:22}];
 e.heading=1;cr.expedition=e;w.busy=true;clearInput();expeditionPanel(true);csfx.drone();
 e.nodes=kind==='relay'?[{x:310,y:210,done:false},{x:620,y:180,done:false}]:[];
 e.heat=0;
 if(w.i%3===1){e.rocks[0].x=330;e.rocks[0].y=350;e.mines[0].x=600;e.mines[0].y=270;e.target.y=475}
 if(w.i%3===2){e.rocks[0].y=470;e.rocks[1].x=530;e.mines[1].x=770;e.mines[1].y=290;e.target.x=860}
}
function expeditionPanel(on){
 let box=$('expedition');
 if(!box){box=document.createElement('section');box.id='expedition';box.setAttribute('aria-label','Seafloor drone controls');
  box.innerHTML='<div class="rov-top"><span>REMORA / REMOTE OPERATIONS</span><button id="rovRecall">Recall drone</button></div><div class="rov-bottom"><div class="rov-steer"><button data-rov="ArrowLeft" aria-label="Move left">←</button><button data-rov="ArrowUp" aria-label="Move up">↑</button><button data-rov="ArrowDown" aria-label="Move down">↓</button><button data-rov="ArrowRight" aria-label="Move right">→</button></div><div class="rov-actions"><button id="rovScan">Q · SONAR</button><button data-rov="Space">HOLD · GRAB / TOOL</button><button id="rovPause">Pause</button></div></div>';
  document.body.append(box);
  box.querySelectorAll('[data-rov]').forEach(b=>{const key=b.dataset.rov;b.addEventListener('pointerdown',ev=>{ev.preventDefault();inputKeys.add(key);b.setPointerCapture(ev.pointerId)});for(const event of ['pointerup','pointercancel','lostpointercapture'])b.addEventListener(event,()=>inputKeys.delete(key))});
  $('rovScan').onclick=expeditionScan;$('rovRecall').onclick=()=>expeditionEnd(false,'Drone recalled. The payload is still on the bottom.');$('rovPause').onclick=pause;
 }
 box.hidden=!on;
 document.body.classList.toggle('rov-active',on);
}
function expeditionScan(){const e=cr&&cr.expedition;if(!e||state!=='playing'||e.clock-e.pulse<2)return;e.pulse=e.clock;e.scan=6;csfx.radio();for(const n of e.nodes)if(Math.hypot(e.x-n.x,e.y-n.y)<135)n.done=true}
function expeditionEnd(success,msg){
 const e=cr&&cr.expedition;if(!e)return;e.w.busy=false;cr.expedition=null;expeditionPanel(false);clearInput();
 if(success){deliver(e.w);if(e.extra)addParts([e.extra,0,0]);o2=Math.min(S.o2,o2+S.o2*.18)}
 else toast('DRONE RECOVERED',msg,3,true);
 cr.droneCool=t+.25;
}
function expeditionStep(dt){
 const e=cr.expedition;e.clock+=dt;camp.run.time+=dt;e.battery-=dt;e.scan=Math.max(0,e.scan-dt);
 const axis=(a,b)=>(inputKeys.has(a)?1:0)-(inputKeys.has(b)?1:0);
 const ax=axis('ArrowRight','ArrowLeft')+axis('KeyD','KeyA'),ay=axis('ArrowDown','ArrowUp')+axis('KeyS','KeyW');
 const mass=(e.cargo?.76:1)*(1+.15*(camp.data.up.drone||0)),flow=cm.ch>=2?Math.sin(e.clock*.7+e.y/180)*22:0;
 e.vx+=(clamp(ax,-1,1)*480*mass+flow-e.vx*4)*dt;e.vy+=(clamp(ay,-1,1)*480*mass-e.vy*4)*dt;
 e.x=clamp(e.x+e.vx*dt,32,1000);e.y=clamp(e.y+e.vy*dt,72,555);if(Math.abs(e.vx)>8)e.heading=Math.sign(e.vx);
 const hit=message=>{if(e.clock-e.hit<1.5)return;e.hit=e.clock;e.hp--;e.notice=message;e.noticeUntil=e.clock+2;csfx.alarm()};
 for(const r of e.rocks){const dx=e.x-r.x,dy=e.y-r.y,d=Math.hypot(dx,dy),lim=r.r+16;if(d<lim){e.x=r.x+dx/(d||1)*lim;e.y=r.y+dy/(d||1)*lim;if(Math.hypot(e.vx,e.vy)>65)hit('Hull contact. Ease off near the wreck.');e.vx*=.15;e.vy*=.15}}
 for(const v of e.vents){const phase=(e.clock+v.phase)%6;if(phase>3.3&&phase<5.2&&Math.abs(e.x-v.x)<30&&e.y>350){hit('Thermal plume. Watch the amber warning.');e.vy-=200*dt}}
 for(const m of e.mines)if(Math.hypot(e.x-m.x,e.y-m.y)<m.r+14)hit('Live charge. Give it room.');
 const near=Math.hypot(e.x-e.target.x,e.y-e.target.y)<54,tool=inputKeys.has('Space')||inputKeys.has('KeyF');
 const ready=e.nodes.every(n=>n.done),working=!e.cargo&&near&&tool&&e.scan>0&&ready&&Math.hypot(e.vx,e.vy)<55;
 e.heat=clamp(e.heat+(working?.48:-.8)*dt,0,1);
 if(working&&!(e.kind==='core'&&e.heat>.88)){e.grip+=dt/(e.kind==='core'?3.2:e.kind==='disarm'?1.8:1.1);if(e.grip>=1){e.cargo=true;e.notice=e.kind==='relay'?'Signal decoded. Return the recorder to the dock.':'Payload secured. Return to the dock.';e.noticeUntil=e.clock+4;if(e.kind==='disarm')e.mines=[];csfx.salvage()}}
 else if(!e.cargo)e.grip=Math.max(0,e.grip-dt*.3);
 for(const item of e.items)if(!item.taken&&tool&&Math.hypot(e.x-item.x,e.y-item.y)<38){item.taken=true;e.extra+=2;csfx.relic()}
 if(e.cargo&&Math.hypot(e.x-130,e.y-130)<48)return expeditionEnd(true);
 if(e.hp<=0||e.battery<=0)return expeditionEnd(false,e.hp<=0?'Recovery tether saved the drone. Relaunch to try again.':'Battery exhausted. Relaunch from the recovery dock.');
}
function expeditionDraw(){
 const e=cr.expedition;if(!e)return;c.save();
 c.fillStyle='#020b13';c.fillRect(0,0,W,H);
 const compact=W<700,k=compact?Math.min(W/500,(H-250)/610):Math.min(W/1060,(H-150)/610),viewW=W/k;
 const camera=compact?clamp(e.x-viewW*.4,0,1060-viewW):0,ox=compact?-camera*k:(W-1060*k)/2,oy=compact?105+(H-250-610*k)/2:65+(H-150-610*k)/2;
 c.save();c.beginPath();c.rect(0,oy,W,610*k);c.clip();c.translate(ox,oy);c.scale(k,k);
 const bg=c.createLinearGradient(0,0,0,610);bg.addColorStop(0,'#123f50');bg.addColorStop(1,'#030d17');c.fillStyle=bg;c.fillRect(0,0,1060,610);
 c.strokeStyle='#69cfc012';c.lineWidth=1;for(let x=0;x<1060;x+=60){c.beginPath();c.moveTo(x,0);c.lineTo(x,610);c.stroke()}for(let y=0;y<610;y+=60){c.beginPath();c.moveTo(0,y);c.lineTo(1060,y);c.stroke()}
 for(let i=0;i<70;i++){const x=(hash(i)*1060+e.clock*(4+hash(i+1)*7))%1060,y=hash(i+13)*610;c.fillStyle='#aed9d044';c.fillRect(x,y,2,2)}
 c.fillStyle='#0b2630';c.beginPath();c.moveTo(0,610);for(let x=0;x<=1060;x+=12)c.lineTo(x,580+Math.sin(x/45)*10+Math.sin(x/17)*4);c.lineTo(1060,610);c.fill();
 // The broken hull and ribs give the pickup a physical location.
 c.save();c.translate(790,485);c.rotate(-.09);c.fillStyle='#223b42';c.strokeStyle='#54706a';c.lineWidth=2;c.beginPath();c.ellipse(0,0,145,44,0,0,TAU);c.fill();c.stroke();
 for(let x=-90;x<120;x+=30){c.strokeRect(x,-28,12,56)}c.fillStyle='#08151e';c.fillRect(-40,-38,75,28);c.restore();
 for(const r of e.rocks){circle(r.x,r.y,r.r,'#142f3b','#36525a',2);circle(r.x-15,r.y-15,r.r*.45,'#1d3b46')}
 for(const v of e.vents){const p=(e.clock+v.phase)%6,hot=p>3.3&&p<5.2,warn=p>2.3&&p<=3.3;c.fillStyle=hot?'#ff9d5266':warn?'#eac56a22':'#558b9722';c.fillRect(v.x-26,hot?335:530,52,hot?245:50);circle(v.x,575,18,'#1c2730',hot?'#ff9368':warn?'#ffd68a':'#46727c',3);if(warn){c.fillStyle='#ffd68a';c.font='12px monospace';c.fillText('VENTING',v.x-26,515)}}
 for(const m of e.mines){circle(m.x,m.y,m.r,'#162631','#d17a69',2);for(let i=0;i<8;i++){const a=i*TAU/8;c.strokeStyle='#d17a69';c.beginPath();c.moveTo(m.x+Math.cos(a)*m.r,m.y+Math.sin(a)*m.r);c.lineTo(m.x+Math.cos(a)*(m.r+8),m.y+Math.sin(a)*(m.r+8));c.stroke()}circle(m.x,m.y,4,'#ff795e')}
 for(const item of e.items)if(!item.taken){c.fillStyle='#d8bb78';c.fillRect(item.x-9,item.y-8,18,16);if(e.scan>0){c.strokeStyle='#edd59c';c.strokeRect(item.x-16,item.y-15,32,30)}}
 for(const n of e.nodes){circle(n.x,n.y,26,null,n.done?'#a6ead5':'#ebc47c',2);c.fillStyle=n.done?'#a6ead5':'#ebc47c';c.font='12px monospace';c.fillText(n.done?'SYNCED':'Q / SCAN',n.x-25,n.y+4)}
 c.strokeStyle='#78d8c5';c.lineWidth=3;c.strokeRect(86,98,88,64);c.fillStyle='#a6ead5';c.font='12px monospace';c.fillText('RECOVERY DOCK',78,85);
 c.strokeStyle='#85b8b344';c.lineWidth=1.5;c.beginPath();c.moveTo(130,155);c.quadraticCurveTo((e.x+130)/2,Math.max(e.y,155)+55,e.x,e.y);c.stroke();
 if(!e.cargo){const p=e.target;circle(p.x,p.y,17,e.kind==='core'?'#f6b26a':'#8fe2c9','#dff8e9',2);if(e.scan>0){circle(p.x,p.y,30+Math.sin(e.clock*4)*3,null,'#a6ead5',1);c.font='13px monospace';c.fillStyle='#dff8e9';c.fillText(e.kind==='disarm'?'DISARM CONTROLLER':e.kind==='relay'?'BLACK BOX':e.kind==='core'?'THERMAL CORE':'SALVAGE CRATE',p.x-65,p.y-44)}if(e.grip>0){c.fillStyle='#163a41';c.fillRect(p.x-35,p.y+30,70,6);c.fillStyle='#a6ead5';c.fillRect(p.x-35,p.y+30,70*e.grip,6)}}
 const radius=(e.clock-e.pulse)*260;if(radius<1500){c.globalAlpha=Math.max(0,1-radius/1500);circle(e.x,e.y,radius,null,'#96e9d3',2);c.globalAlpha=1}
 c.save();c.translate(e.x,e.y);c.rotate(e.vx*.0015);c.fillStyle='#efc37c';c.strokeStyle='#fff0cb';c.lineWidth=2;c.fillRect(-19,-10,38,20);c.strokeRect(-19,-10,38,20);circle(-21,0,7,'#12303e','#7cb4b4',2);circle(21,0,7,'#12303e','#7cb4b4',2);circle(e.heading*14,-2,4,'#e8fff3');
 c.strokeStyle='#dbe6c4';c.beginPath();c.moveTo(-9,10);c.lineTo(-12,22);c.lineTo(-5,27);c.moveTo(9,10);c.lineTo(12,22);c.lineTo(5,27);c.stroke();if(e.cargo){c.fillStyle='#a6ead5';c.fillRect(-9,21,18,15)}c.restore();
 const light=c.createRadialGradient(e.x,e.y,65,e.x,e.y,460);light.addColorStop(0,'#01061000');light.addColorStop(1,'#010610aa');c.fillStyle=light;c.fillRect(0,0,1060,610);
 const title=e.kind==='core'?'CORE EXTRACTION':e.kind==='disarm'?'MINE NETWORK / DISARM':e.kind==='relay'?'ACOUSTIC RELAY / RECOVERY':'SEAFLOOR / SALVAGE DIVE';
 if(!compact){c.fillStyle='#d7ede7';c.font='bold 19px monospace';c.fillText(title,24,30);
 c.font='13px monospace';c.fillStyle=e.battery<15?'#ff947c':'#a6ead5';c.fillText('BATTERY '+Math.ceil(e.battery)+'s   HULL '+e.hp+'/3   BONUS '+e.extra+' SCRAP',24,52)}
 if(e.kind==='core'&&!e.cargo){c.fillStyle=e.heat>.8?'#ff916d':'#e8c37f';c.fillRect(750,36,220*e.heat,6);c.font='12px monospace';c.fillText('TOOL HEAT · RELEASE TO COOL',750,27)}
 c.fillStyle='#e8d6b3';c.font='14px monospace';const instruction=e.clock<e.noticeUntil?e.notice:e.cargo?'RETURN TO THE GREEN DOCK':e.nodes.some(n=>!n.done)?'SCAN BOTH AMBER RELAYS FROM CLOSE RANGE':e.kind==='core'&&e.heat>.8?'RELEASE THE TOOL TO COOL IT':Math.hypot(e.x-e.target.x,e.y-e.target.y)<70?'SCAN · STOP MOVING · HOLD GRAB TO SECURE':'PILOT TO THE WRECK · SONAR REVEALS THE PAYLOAD';if(!compact)c.fillText(instruction,24,598);
 c.restore();
 if(compact){c.fillStyle='#d7ede7';c.font='bold 15px monospace';c.fillText(title,14,82);c.font='12px monospace';c.fillStyle='#a6ead5';c.fillText('BAT '+Math.ceil(e.battery)+'s  HULL '+e.hp+'/3  SCRAP +'+e.extra,14,103);
  c.fillStyle='#e8d6b3';c.font='12px monospace';let line='',lineY=H-174;for(const word of instruction.split(' ')){if(c.measureText(line+word).width>W-28){c.fillText(line,14,lineY);lineY+=17;line=''}line+=word+' '}c.fillText(line,14,lineY);
  const target=e.cargo?{x:130,y:130}:e.nodes.find(n=>!n.done)||e.target,tx=(target.x-camera)*k,ty=oy+target.y*k;if(tx<20||tx>W-20){c.fillStyle='#a6ead5';c.font='bold 13px monospace';c.fillText(tx<20?'← DOCK':'OBJECTIVE →',tx<20?12:W-110,clamp(ty,oy+25,oy+610*k-20))}}
 c.restore();
}
// Capture only the drone keys; pause and audio stay with the normal game handler.
addEventListener('keydown',e=>{if(!cr||!cr.expedition||state!=='playing')return;
 if(['KeyQ','Space','KeyF','KeyE','KeyW','KeyA','KeyS','KeyD','ArrowUp','ArrowDown','ArrowLeft','ArrowRight'].includes(e.code)){e.preventDefault();e.stopImmediatePropagation();if(e.code==='KeyQ'){if(!e.repeat)expeditionScan()}else inputKeys.add(e.code)}},true);
