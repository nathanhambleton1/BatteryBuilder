'use strict';
/* ---- Campaign drawing -----------------------------------------------------------
   World-space layers for campaign missions (drawn inside the world transform, like
   mines and ships), a screen-space overlay, the camera focus used while the spotter
   drone flies, and the painted backdrops for cutscenes. */

// Camera focus: the boat, or the spotter drone while it flies, eased between the two.
function campFocus(){
 if(!cr)return;const dt=clamp(ambient-cr.fa,0,.1);cr.fa=ambient;
 if(state==='cut'&&cam3d)orbitYaw=clamp(orbitYaw+dt*.3,-.9,.9);
 if(!cr.air&&!cr.ret){cr.fx=sub.x;cr.fy=sub.y;return}
 const k=1-Math.exp(-dt*3.5),tx=cr.air?cr.air.x:sub.x,ty=cr.air?cr.air.y:sub.y;
 cr.fx=mix(cr.fx,tx,k);cr.fy=mix(cr.fy,ty,k);
 if(!cr.air&&Math.abs(cr.fx-sub.x)<6&&Math.abs(cr.fy-sub.y)<6&&Math.abs(cr.camK-camLead)<.02)cr.ret=false;
 // Flying out the drone leads on the right of the view; flying home, on the left.
 cr.camK=mix(cr.camK,cr.air?(cr.air.dir>0?.3:.7):camLead,k);fX=cr.fx;fY=cr.fy;camX=fX-vw*cr.camK;
}

/* ---- Shapes ---- */
// A tapered limb along spine points [x,y,halfWidth], with suckers on one side.
function drawLimb(pts,fill,edge,sucker){
 if(pts.length<2)return;const L=[],Rr=[];
 for(let i=0;i<pts.length;i++){const a=pts[Math.max(0,i-1)],b=pts[Math.min(pts.length-1,i+1)],dx=b[0]-a[0],dy=b[1]-a[1],d=Math.hypot(dx,dy)||1,nx=-dy/d,ny=dx/d,[x,y,w]=pts[i];L.push([x+nx*w,y+ny*w]);Rr.push([x-nx*w,y-ny*w])}
 c.beginPath();L.forEach((p,i)=>i?c.lineTo(p[0],p[1]):c.moveTo(p[0],p[1]));for(let i=Rr.length-1;i>=0;i--)c.lineTo(Rr[i][0],Rr[i][1]);c.closePath();c.fillStyle=fill;c.fill();c.strokeStyle=edge;c.lineWidth=1.2;c.stroke();
 if(sucker)for(let i=1;i<pts.length-1;i++){const [x,y,w]=pts[i],p=Rr[i];circle(mix(x,p[0],.55),mix(y,p[1],.55),Math.max(1,w*.32),sucker)}
}
function star5(x,y,r,fill){c.beginPath();for(let i=0;i<10;i++){const a=-Math.PI/2+i*Math.PI/5,rr=i%2?r*.42:r;i?c.lineTo(x+Math.cos(a)*rr,y+Math.sin(a)*rr):c.moveTo(x+Math.cos(a)*rr,y+Math.sin(a)*rr)}c.closePath();c.fillStyle=fill;c.fill()}
function subAt(m,x,y,ang,k,alpha=1){c.save();c.globalAlpha*=alpha;c.translate(x,y);c.rotate(ang);c.scale(k,k);drawSubModel(m,false);c.restore()}
function tag(x,y,text,col){c.save();c.font='8px ui-monospace,monospace';c.fillStyle=col;c.strokeStyle=col;c.lineWidth=1.2;c.globalAlpha*=.9;c.beginPath();c.moveTo(x-7,y+8);c.lineTo(x,y+15);c.lineTo(x+7,y+8);c.stroke();c.fillText(text,x-c.measureText(text).width/2,y);c.restore()}
function drawCruiser(x,y,k,hit){
 c.save();c.translate(x,y);c.scale(k,k);
 const hullC=rgb([78,88,92],[34,42,48],night),deck=rgb([120,128,130],[50,60,66],night),dark=rgb([38,46,52],[14,20,26],night);
 path([[-170,-12],[150,-12],[178,-24],[162,6],[120,18],[-150,18],[-172,4]],hullC,'#0a161d88',1);path([[-172,4],[-150,18],[120,18],[162,6],[163,2],[-172,2]],'#4a2420');
 path([[-110,-12],[-106,-34],[-30,-34],[-26,-12]],deck);path([[-80,-34],[-76,-56],[-44,-56],[-40,-34]],deck);path([[-74,-52],[-48,-52],[-48,-47],[-74,-47]],'#1a2a33');
 path([[-20,-12],[-16,-46],[4,-46],[8,-12]],dark);c.fillStyle=dark;c.fillRect(-14,-62,14,16);
 path([[30,-12],[34,-26],[86,-26],[90,-12]],deck);for(const tx of [-140,48,112]){path([[tx-14,-12],[tx-12,-22],[tx+12,-22],[tx+14,-12]],deck);c.strokeStyle=deck;c.lineWidth=3;c.beginPath();c.moveTo(tx+8,-18);c.lineTo(tx+30,-24);c.stroke()}
 c.strokeStyle=dark;c.lineWidth=2;c.beginPath();c.moveTo(-60,-56);c.lineTo(-60,-104);c.moveTo(-74,-90);c.lineTo(-46,-90);c.stroke();
 path([[-60,-104],[-36,-100],[-60,-94]],'#c0392b');
 if(night>.3){circle(-60,-104,2,'#ff6a5a');glow(-60,-104,14,'#ff6a5a66')}
 if(!reduced)for(let i=0;i<5;i++){const a=(ambient*.6+i/5)%1;c.globalAlpha=.35*(1-a);circle(-7-a*40,-66-a*50,6+a*16,'#2b3338')}c.globalAlpha=1;
 if(hit)glow(0,-14,120,`rgba(255,150,80,${hit})`);
 c.restore();
}
function drawWreck(w,near){
 const {x,y,k}=w;c.save();c.translate(x,y);
 if(k==='ship'){c.rotate(-.12);const a=rgb([52,62,60],[22,30,32],night),b=rgb([84,62,48],[34,26,22],night);
  path([[-120,-4],[-20,-6],[-12,8],[-110,10]],a,'#0006');path([[-8,-8],[96,-14],[118,-4],[100,10],[0,8]],a,'#0006');path([[-100,-4],[-80,-24],[-48,-24],[-40,-6]],b);
  c.strokeStyle=b;c.lineWidth=2.5;c.beginPath();c.moveTo(40,-10);c.lineTo(62,-62);c.stroke();c.lineWidth=1;c.beginPath();c.moveTo(62,-62);c.lineTo(100,-12);c.stroke();
  for(let i=0;i<5;i++)circle(-90+i*18,2,2,'#0b151a')}
 else if(k==='plane'){c.rotate(.08);const a=rgb([96,104,98],[34,40,42],night);
  path([[-50,-4],[40,-6],[54,-2],[40,4],[-46,4]],a,'#0006');path([[-6,-4],[12,-30],[22,-30],[10,-4]],a);path([[-44,-4],[-52,-18],[-44,-18],[-36,-4]],a);path([[-6,2],[20,16],[28,14],[12,2]],rgb([70,78,74],[26,32,34],night))}
 else{const m=SUB_BY_ID[k==='akula'?'akula':k==='sub'?'gato':'virginia'],tilt=k==='sub'?.22:k==='akula'?-.3:.1;
  c.save();c.filter='brightness(.5) saturate(.4) sepia(.35)';subAt(m,0,-m.hy*.5,tilt,k==='akula'?1.2:1);c.restore();
  if(k==='meridian'||k==='core'){c.save();c.rotate(tilt);c.font='bold 7px ui-monospace,monospace';c.fillStyle='#b9c7b499';c.fillText('MERIDIAN',-18,-4);c.restore()}
  if(k==='core'&&!w.done){const p=.6+.4*Math.sin(ambient*3);c.save();c.globalCompositeOperation='screen';glow(6,-8,70*p,'rgba(255,140,50,.55)');c.restore();circle(6,-8,5,'#ffd08a')}}
 c.restore();
 // Marker: what the drone can reach now, and what has been picked clean.
 if(!w.done){const a=near?1:.35,p=.5+.5*Math.sin(ambient*4);c.save();c.globalAlpha=a;c.strokeStyle='#ecc69b';c.lineWidth=1.3;
  const top=y-70;for(const s of [-1,1]){c.beginPath();c.moveTo(x+s*40,top+8);c.lineTo(x+s*40,top);c.lineTo(x+s*28,top);c.stroke()}
  c.font='8px ui-monospace,monospace';c.fillStyle='#ecc69b';const label=w.k==='core'?'THERMAL CORE':w.busy?'DRONE WORKING':near?'SALVAGE / Q':'SALVAGE';c.fillText(label,x-c.measureText(label).width/2,top-6);
  if(near){c.globalAlpha=p;c.beginPath();c.moveTo(x-6,top+14);c.lineTo(x,top+20);c.lineTo(x+6,top+14);c.stroke()}c.restore()}
 else{c.save();c.globalAlpha=.3;c.font='7px ui-monospace,monospace';c.fillStyle='#a6ead5';c.fillText('RECOVERED',x-20,y-50);c.restore()}
}
// A checkpoint: a light curtain from roof to seabed, a ring gate on the boat's line and a
// buoy (or a roof lamp in a cave). Passed ones stay, in green, marked SAVED.
function drawMarker(x,label,rgb,passed,finish,flash){
 const top0=ceilAt(x),bot0=terrain(x).bottom,top=Math.max(camY-40,top0),bot=Math.min(camY+vh+40,bot0),p=.5+.5*Math.sin(ambient*2.4),col=a=>`rgba(${flash?'255,255,255':rgb},${a})`;
 if(bot>top){c.save();c.globalCompositeOperation='screen';let g=c.createLinearGradient(x-26,0,x+26,0);g.addColorStop(0,'rgba(0,0,0,0)');g.addColorStop(.5,col(passed?.14:.3+.14*p));g.addColorStop(1,'rgba(0,0,0,0)');c.fillStyle=g;c.fillRect(x-26,top,52,bot-top);
  c.strokeStyle=col(passed?.3:.85);c.lineWidth=1.2;c.beginPath();for(let y=top-((ambient*40)%(finish?18:26));y<bot;y+=finish?18:26){c.moveTo(x-5,y);c.lineTo(x,y+(finish?9:7));c.lineTo(x+5,y)}c.stroke();c.restore()}
 const gy=clamp(route(x),top0+70,bot0-70);
 c.save();c.globalCompositeOperation='screen';c.strokeStyle=col(passed?.35:.9);c.lineWidth=3;c.beginPath();c.ellipse(x,gy,16,74,0,0,TAU);c.stroke();c.lineWidth=1;c.beginPath();c.ellipse(x,gy,22,82+p*6,0,0,TAU);c.stroke();glow(x,gy-74,18,col(.5));glow(x,gy+74,18,col(.5));c.restore();
 if(terrain(x).cave<.002){const by=SURFACE+Math.sin(ambient*2+x)*2;path([[x-9,by],[x+9,by],[x+6,by+10],[x-6,by+10]],passed?'#3a7a5a':finish?'#c98a3a':'#2a8a8a','#000a',1);c.strokeStyle='#d8e4e0';c.lineWidth=1.4;c.beginPath();c.moveTo(x,by);c.lineTo(x,by-34);c.stroke();path([[x,by-34],[x+18,by-29],[x,by-24]],col(.95));if(Math.floor(ambient*2.5)%2){circle(x,by-36,2.2,col(1));glow(x,by-36,16,col(.6))}}
 else{c.strokeStyle='#6a7a76';c.lineWidth=1.2;c.beginPath();c.moveTo(x,top0);c.lineTo(x,top0+22);c.stroke();circle(x,top0+25,4,col(.95));if(Math.floor(ambient*2.5)%2)glow(x,top0+25,20,col(.6))}
 c.save();c.font='9px ui-monospace,monospace';c.fillStyle=col(passed?.7:.95);const ty=clamp(gy-96,top+14,bot-10);c.fillText(passed?label+' / SAVED':label,x+14,ty);c.restore();
}
function drawStream(){
 c.save();c.globalCompositeOperation='screen';c.lineWidth=1.4;
 for(let k=-2;k<=2;k++){c.strokeStyle=`rgba(160,240,255,${.16-Math.abs(k)*.035})`;c.beginPath();
  for(let x=Math.floor(camX/90)*90-90;x<camX+vw+90;x+=90){const xx=x+((ambient*320)%90),y=streamY(xx)+k*22;c.moveTo(xx,y);c.lineTo(xx+44,streamY(xx+44)+k*22)}c.stroke()}
 c.restore();
}
function drawVent(v){const p=.6+.4*Math.sin(ambient*5+v.x);c.save();c.globalCompositeOperation='screen';glow(v.x,v.y,46,`rgba(255,150,60,${.35*p})`);c.restore();
 circle(v.x,v.y,16,null,'#ffb26a',1.6);c.strokeStyle='#ffd29a';c.lineWidth=1.6;for(const dx of [-5,3]){c.beginPath();c.moveTo(v.x+dx-3,v.y-6);c.lineTo(v.x+dx+3,v.y);c.lineTo(v.x+dx-3,v.y+6);c.stroke()}}
function drawOcto(x,y,k,look,hit,alpha=1){
 c.save();c.globalAlpha*=alpha;c.translate(x,y);c.scale(k,k);
 for(let i=0;i<5;i++){const a=.6+i*.35,pts=[];for(let j=0;j<=12;j++){const u=j/12;pts.push([30+Math.cos(a)*u*190+Math.sin(u*5+ambient*1.6+i)*22*u,40+Math.sin(a)*u*170+Math.cos(u*4+ambient*1.3+i)*18*u,26*(1-.75*u)])}drawLimb(pts,'#5a1f2e','#2a0c14','#c4797d55')}
 let g=c.createRadialGradient(10,-40,10,40,-20,150);g.addColorStop(0,'#a8435a');g.addColorStop(.6,'#64203a');g.addColorStop(1,'#2a0c1a');
 c.beginPath();c.ellipse(40,-30,130,100,-.35,0,TAU);c.fillStyle=g;c.fill();
 for(let i=0;i<14;i++)circle(40+Math.cos(i*2.3)*90*hash(i),-30+Math.sin(i*2.3)*70*hash(i+3),3+hash(i+9)*6,'#d0708033');
 const ex=-95,ey=-8;circle(ex,ey,36,'#e8d6a0');const ga=c.createRadialGradient(ex,ey,4,ex,ey,30);ga.addColorStop(0,'#ffe27a');ga.addColorStop(1,'#a8701a');circle(ex,ey,30,ga);
 c.save();c.translate(ex+look[0]*8,ey+look[1]*6);c.fillStyle='#120608';c.beginPath();c.ellipse(0,0,18,5,0,0,TAU);c.fill();c.restore();
 c.strokeStyle='#3a0c18';c.lineWidth=5;c.beginPath();c.ellipse(ex,ey,38,38,0,0,TAU);c.stroke();
 if(hit)glow(ex,ey,90,`rgba(255,220,120,${hit})`);c.restore();
}
function drawKraken(x,y,k,open,look,hit,alpha=1){
 c.save();c.globalAlpha*=alpha;c.translate(x,y);c.scale(k,k);
 for(let i=0;i<7;i++){const a=-1.1+i*.42,pts=[];for(let j=0;j<=14;j++){const u=j/14;pts.push([60+Math.cos(a)*u*280+Math.sin(u*4+ambient*1.1+i)*30*u,40+Math.sin(a)*u*260+Math.cos(u*3+ambient+i)*26*u,40*(1-.8*u)])}drawLimb(pts,'#173a3a','#071a1c','#7fd6c033')}
 let g=c.createRadialGradient(0,-40,20,40,-10,240);g.addColorStop(0,'#2c6b62');g.addColorStop(.55,'#173f3d');g.addColorStop(1,'#061718');
 c.beginPath();c.ellipse(60,-40,230,170,-.25,0,TAU);c.fillStyle=g;c.fill();
 for(let i=0;i<24;i++){const px=60+Math.cos(i*2.1)*190*hash(i),py=-40+Math.sin(i*2.1)*140*hash(i+5),p=.5+.5*Math.sin(ambient*2+i);glow(px,py,10,`rgba(120,255,220,${.25*p})`);circle(px,py,2,'#9fffe6aa')}
 const ex=-150,ey=-30;circle(ex,ey,62,'#0b1b1c');
 const ga=c.createRadialGradient(ex,ey,6,ex,ey,52);ga.addColorStop(0,'#fff7b0');ga.addColorStop(.5,'#f0c030');ga.addColorStop(1,'#7a4a08');circle(ex,ey,52,ga);
 c.save();c.translate(ex+look[0]*14,ey+look[1]*10);c.fillStyle='#0b0602';c.beginPath();c.ellipse(0,0,10,36,0,0,TAU);c.fill();c.restore();
 // The lid: armour plates that close over the eye.
 const lid=1-open;if(lid>.01){c.save();c.beginPath();c.arc(ex,ey,56,0,TAU);c.clip();c.fillStyle='#21403c';c.fillRect(ex-60,ey-60,120,60*lid);c.fillRect(ex-60,ey+60-60*lid,120,60*lid);c.strokeStyle='#4f8c80';c.lineWidth=2;c.beginPath();c.moveTo(ex-60,ey-60+60*lid);c.lineTo(ex+60,ey-60+60*lid);c.moveTo(ex-60,ey+60-60*lid);c.lineTo(ex+60,ey+60-60*lid);c.stroke();c.restore()}
 if(open>.5){c.save();c.globalCompositeOperation='screen';glow(ex,ey,120,`rgba(255,220,90,${.25*open})`);c.restore()}
 if(hit)glow(ex,ey,130,`rgba(255,240,160,${hit})`);c.restore();
}
function ufo(x,y,v,lamp){const a=clamp(v/600,-.3,.3);c.save();c.translate(x,y);c.rotate(a);
 path([[-12,-1],[10,-2],[15,0],[10,2],[-12,2]],'#c9d2cf','#0006',.6);path([[-3,-1],[2,-12],[6,-12],[4,-1]],'#9aa7a4');path([[-3,1],[2,12],[6,12],[4,1]],'#7e8b88');path([[-12,0],[-16,-6],[-13,-6],[-9,0]],'#9aa7a4');
 c.globalAlpha=.5;c.fillStyle='#e5f0ec';c.beginPath();c.ellipse(-15,0,1.2,5+Math.abs(Math.sin(ambient*40))*2,0,0,TAU);c.fill();c.globalAlpha=1;
 if(lamp)circle(2,-12,1.4,Math.floor(ambient*3)%2?'#ff5a4a':'#5aff8a');c.restore()}

/* ---- World layers ---- */
function campDrawBack(){
 if(!cr)return;const m=cm,lo=camX-300,hi=camX+vw+300;
 if(m.race)drawStream();
 m.cps.forEach((x,i)=>{if(x>lo&&x<hi)drawMarker(x,'CHECKPOINT '+(i+1),cr.cpNext>i?'120,230,160':'166,234,213',cr.cpNext>i,false,t-cr.cpFlash<1.2&&cr.cpNext===i+1)});
 if(!m.boss&&m.L>lo&&m.L<hi)drawMarker(m.L,m.race?'FINISH':'RENDEZVOUS','236,198,155',false,true,false);
 if(m.recon)for(const z of m.recon){if(z.x1<lo||z.x0>hi)continue;const live=sub.x>=z.x0&&sub.x<=z.x1;
  c.save();c.setLineDash([10,8]);c.strokeStyle=live?'#ecc69bcc':'#ecc69b55';c.lineWidth=1.4;c.beginPath();c.moveTo(z.x0,SURFACE+3);c.lineTo(z.x1,SURFACE+3);c.stroke();c.restore();
  for(const bx of [z.x0,z.x1]){const by=SURFACE+Math.sin(ambient*2+bx)*2;path([[bx-6,by],[bx+6,by],[bx+4,by+8],[bx-4,by+8]],'#c96a3a');c.strokeStyle='#ddd';c.lineWidth=1.2;c.beginPath();c.moveTo(bx,by);c.lineTo(bx,by-26);c.stroke();path([[bx,by-26],[bx+14,by-22],[bx,by-18]],'#ecc69b');if(Math.floor(ambient*2)%2)circle(bx,by-28,1.6,'#ffd27a')}
  c.save();c.font='9px ui-monospace,monospace';c.fillStyle=live?'#ecc69b':'#ecc69b99';c.fillText(live?(surfaced?'RECON POINT / PRESS Q TO LAUNCH':'RECON POINT / SURFACE HERE'):'RECON POINT',z.x0+10,SURFACE-36);c.restore();
  // Beacons the spotter can find over the islands ahead.
  z.clues.forEach(([cx,h],j)=>{if(cx<lo||cx>hi)return;const id=cm.recon.indexOf(z)+':'+j,cy=clueY(cx,h),g0=clueY(cx,0),p=.5+.5*Math.sin(ambient*3+j);
   // A beacon already logged stays on the map: amber while it rides the drone, green once it is home.
   if(cr.clues.has(id)||(cr.air&&cr.air.held.has(id))){const home=cr.clues.has(id);c.save();c.globalAlpha=.7;c.strokeStyle=home?'#78e6a0':'#ffd29a';c.lineWidth=1.5;c.beginPath();c.moveTo(cx-6,cy);c.lineTo(cx-1,cy+5);c.lineTo(cx+7,cy-6);c.stroke();c.restore();tag(cx,cy-16,home?'LOGGED':'ON DRONE',home?'#78e6a0':'#ffd29a');return}
   c.save();c.globalCompositeOperation='screen';let g=c.createLinearGradient(0,cy,0,g0);g.addColorStop(0,'rgba(255,200,120,.35)');g.addColorStop(1,'rgba(255,200,120,0)');c.fillStyle=g;c.fillRect(cx-3,cy,6,g0-cy);glow(cx,cy,40,`rgba(255,190,110,${.3+.2*p})`);c.restore();
   c.save();c.translate(cx,cy);c.rotate(ambient);c.strokeStyle='#ffd29a';c.lineWidth=1.5;c.strokeRect(-7,-7,14,14);c.restore();tag(cx,cy-20,'BEACON','#ffd29a')});
  if(z.relic&&!cr.relicGot){const [rx,rh]=z.relic;if(rx>lo&&rx<hi){const ry=clueY(rx,rh);c.save();c.globalCompositeOperation='screen';glow(rx,ry,34,'rgba(220,190,255,.4)');c.restore();circle(rx,ry,5,'#e8d8ff')}}
 }
 for(const w of cr.wrecks)if(w.x>lo-200&&w.x<hi+200)drawWreck(w,!w.done&&!w.busy&&!cr.drone&&w.x-sub.x>-420&&w.x-sub.x<1100);
 if(cr.vents)for(const v of cr.vents)if(!v.taken&&v.x>lo&&v.x<hi)drawVent(v);
 const b=cr.boss;if(b&&(b.k==='mother'||b.k==='kraken'||b.k==='kchase')){
  const sink=b.dead?(t-b.dead)*30:0,al=b.dead?clamp(1-(t-b.dead-1.2)/2,0,1):b.k==='kchase'?.8:1,hit=clamp(.6-(t-b.hitAt)*2.4,0,.6),look=[clamp((sub.x-b.x)/600,-1,1),clamp((sub.y-b.y)/300,-1,1)];
  if(b.k==='mother')drawOcto(b.x+40,b.y+sink,1,look,hit,al);
  else drawKraken(b.x+40,b.y+sink+(b.k==='kchase'?60:0),b.k==='kchase'?1.15:1,b.k==='kraken'?(b.open?Math.min(1,(b.openUntil-t)*3,1):0):.15,look,hit,al)}
}
function campDrawFront(){
 if(!cr)return;const lo=camX-300,hi=camX+vw+300,b=cr.boss;
 for(const h of cr.hz){
  if(h.k==='tent'){const e=tentReach(h);if(e<0)continue;const a=t-h.born;
   if(a<h.warn&&a>=0){const p=.5+.5*Math.sin(a*18);c.save();c.globalCompositeOperation='screen';glow(h.x,h.base,46,`rgba(255,90,60,${.35+.3*p})`);c.restore();c.save();c.setLineDash([4,8]);c.strokeStyle='rgba(255,120,90,.35)';c.lineWidth=2;c.beginPath();c.moveTo(h.x,h.base);c.lineTo(h.x,h.tip);c.stroke();c.restore();
    if(Math.random()<.4)debris.push({x:h.x+rnd(-20,20),y:h.base+(h.top?8:-8),vx:rnd(-20,20),vy:h.top?rnd(10,40):rnd(-40,-10),life:.6,r:1+Math.random()*2})}
   if(e>0){const kr=h.who!=='mother';drawLimb(tentPts(h,e,14),kr?'#1d4a46':'#6a2236',kr?'#0a1f1d':'#2a0c14',kr?'#8fe0c855':'#e0a0a855')}}
  else if(h.k==='sweep'&&b){const e=sweepReach(h);if(e<0)continue;const a=t-h.born;
   if(a<h.warn){const p=.5+.5*Math.sin(a*14);c.save();c.fillStyle=`rgba(255,60,40,${.08+.1*p})`;c.fillRect(sub.x-600,h.y-h.h,b.x-sub.x+600,h.h*2);c.strokeStyle=`rgba(255,90,60,${.4+.3*p})`;c.lineWidth=1;c.strokeRect(sub.x-600,h.y-h.h,b.x-sub.x+600,h.h*2);c.restore()}
   if(e>0&&h.tipX!==undefined){const pts=[],x0=b.x-100;for(let i=0;i<=16;i++){const u=i/16;pts.push([mix(x0,h.tipX,u),h.y+Math.sin(u*6+ambient*4)*10*u,34*(1-.7*u)])}drawLimb(pts,'#1d4a46','#0a1f1d','#8fe0c855')}}
  else if(h.k==='ink'){const k=clamp(1-(t-h.born-h.life+2)/2,0,1);for(let i=0;i<6;i++){const r=h.r*(.55+.25*hash(i)),ox=Math.cos(i*1.7+t*.3)*h.r*.35,oy=Math.sin(i*2.1+t*.25)*h.r*.3,g=c.createRadialGradient(h.x+ox,h.y+oy,0,h.x+ox,h.y+oy,r);g.addColorStop(0,`rgba(4,6,14,${.85*k})`);g.addColorStop(1,'rgba(4,6,14,0)');c.fillStyle=g;c.fillRect(h.x+ox-r,h.y+oy-r,r*2,r*2)}}
  else if(h.k==='charge'){const p=.5+.5*Math.sin(ambient*10);c.save();c.setLineDash([3,6]);c.strokeStyle=`rgba(255,110,80,${.25+.3*p})`;c.lineWidth=1;c.beginPath();c.moveTo(h.x,h.y);c.lineTo(h.x,h.ty);c.stroke();c.setLineDash([6,6]);c.lineWidth=1.4;c.beginPath();c.ellipse(h.x,h.ty,h.r*.8,h.r*.8,0,0,TAU);c.stroke();c.restore();
   c.save();c.translate(h.x,h.y);c.rotate(h.spin);path([[-6,-9],[6,-9],[7,9],[-7,9]],'#3b4446','#0008',.8);c.fillStyle='#c0392b';c.fillRect(-6,-2,12,3);c.restore();if(Math.floor(ambient*8)%2)circle(h.x,h.y-10,1.5,'#ff6a5a')}
  else if(h.k==='fmine'){const y=h.y+Math.sin(ambient*1.2+h.ph)*6;if(h.x>lo&&h.x<hi){mine(h.x,y,1,0);if(Math.floor(ambient*3+h.ph)%2)circle(h.x+6,y-6,1.8,'#ff5a4a')}}
 }
 for(const f of cr.foes){if(f.k==='ambush'||f.x<lo-200||f.x>hi+200)continue;const sink=f.dead?(t-f.dead)*30:0,al=f.dead?clamp(1-(t-f.dead-.8)/1.6,0,1):1,hit=clamp(.6-(t-f.hitAt)*2.4,0,.6);
  if(f.k==='hunter'){subAt(SUB_BY_ID.type212,f.x,f.y+sink,f.dead?.3:clamp((f.y-(f.py||f.y))*2,-.15,.15),1.25,al);f.py=f.y;c.save();c.globalAlpha=al;star5(f.x-6,f.y-28+sink,3.5,'#d0392b');c.restore();if(hit){c.save();c.globalCompositeOperation='screen';glow(f.x,f.y,60,`rgba(255,150,80,${hit})`);c.restore()}}
  else if(f.k==='destroyer'){c.save();c.translate(f.x,SURFACE+sink);c.rotate(f.dead?Math.min(.35,(t-f.dead)*.15):Math.sin(ambient*.9+f.ph)*.012);c.globalAlpha=al;drawCruiser(0,0,.72,hit);c.restore()}
  else if(f.k==='octopod')drawOcto(f.x+22,f.y+sink,.55,[clamp((sub.x-f.x)/600,-1,1),clamp((sub.y-f.y)/300,-1,1)],hit,al);
  if(!f.dead){const ty=f.k==='destroyer'?SURFACE-98:f.y-62;tag(f.x,ty,FOES[f.k].name,'#f0a08c');for(let i=0;i<f.max;i++){c.fillStyle=i<f.hp?'#e3785f':'#e3785f33';c.fillRect(f.x-f.max*5+i*10+1,ty-16,8,3)}}}
 if(b&&!b.leaving){const sink=b.dead?(t-b.dead)*26:0,al=b.dead?clamp(1-(t-b.dead-1.4)/2,0,1):1,hit=clamp(.6-(t-b.hitAt)*2.4,0,.6);
  if(b.k==='warden'){c.save();c.translate(b.x,SURFACE+sink);c.rotate(b.dead?Math.min(.3,(t-b.dead)*.1):Math.sin(ambient*.8)*.01);c.globalAlpha=al;drawCruiser(0,0,1.15,hit);c.restore();if(!b.dead)tag(b.x,SURFACE-150,'GROZNY','#f0a08c')}
  else if(b.k==='vepr'||b.k==='leviathan'){const B=BOSS[b.k],m=SUB_BY_ID[B.sub],ang=clamp((b.lunge?0:(b.y-(b.py||b.y))*2),-.15,.15);b.py=b.y;
   if(b.k==='leviathan'&&b.lunge&&t-b.lunge.t0<1.3){c.save();c.globalCompositeOperation='screen';glow(b.x,b.y,200,`rgba(255,50,30,${.25+.2*Math.sin(ambient*20)})`);c.restore()}
   subAt(m,b.x,b.y+sink,ang+(b.dead?.25:0),B.scale,al);
   c.save();c.globalAlpha=al;star5(b.x-10*B.scale,b.y-24*B.scale+sink,4*B.scale,'#d0392bdd');c.restore();
   if(b.k==='leviathan'&&!b.dead){const shield=t>=b.vulnUntil;
    if(shield){c.save();c.globalCompositeOperation='screen';c.strokeStyle=`rgba(160,220,255,${.45+.15*Math.sin(ambient*6)})`;c.lineWidth=2;c.beginPath();c.ellipse(b.x,b.y,130,52,0,0,TAU);c.stroke();glow(b.x,b.y,140,'rgba(120,190,255,.12)');c.restore()}
    else for(let i=0;i<6;i++){const hx=b.x+(10+i*12)*B.scale-40,hy=b.y-18*B.scale;glow(hx,hy,10,'rgba(255,160,70,.6)');circle(hx,hy,1.8,'#ffd08a')}}
   if(!b.dead)tag(b.x,b.y-38*B.scale-20,b.k==='vepr'?'VEPR':'LEVIATHAN','#f0a08c')}}
 // Weak points: an amber reticle when open, grey when armoured.
 if(b&&!b.dead&&!b.leaving&&BOSS[b.k].pts){for(const p of BOSS[b.k].pts(b).slice(0,b.k==='warden'?1:9)){const q=b.k==='warden'?{x:b.x,y:SURFACE-2,r:46}:p;const k=.5+.5*Math.sin(ambient*5);c.save();c.strokeStyle=p.armor?'rgba(160,180,190,.35)':`rgba(236,198,155,${.45+.35*k})`;c.lineWidth=1.3;const r=(q.ry?q.ry:q.r)+8+k*3;c.beginPath();c.arc(q.x,q.y,r,0,TAU);c.stroke();for(let i=0;i<4;i++){const a=i*Math.PI/2+ambient*.6;c.beginPath();c.moveTo(q.x+Math.cos(a)*(r+2),q.y+Math.sin(a)*(r+2));c.lineTo(q.x+Math.cos(a)*(r+9),q.y+Math.sin(a)*(r+9));c.stroke()}c.restore()}}
 const r=cr.rival;if(r&&r.x>lo&&r.x<hi){subAt(SUB_BY_ID[r.k],r.x,r.y,0,r.k==='typhoon'?1:.95);star5(r.x-8,r.y-24,4,'#d0392bdd');tag(r.x,r.y-60,r.k==='typhoon'?'TYPHOON / VOLKOV':'VEPR / VOLKOV','#f0a08c')}
 if(cr.relicAt){const [rx,ry]=cr.relicAt;if(rx>lo&&rx<hi){const p=.6+.4*Math.sin(ambient*3);c.save();c.globalCompositeOperation='screen';glow(rx,ry,40,`rgba(220,190,255,${.35*p})`);c.restore();c.save();c.translate(rx,ry);c.rotate(Math.sin(ambient)*.3);path([[-9,-4],[9,-4],[11,0],[9,4],[-9,4],[-11,0]],'#cbb7e8','#4a3a6a',1);c.font='bold 5px ui-monospace,monospace';c.fillStyle='#2a1a44';c.fillText('LOG',-5,2);c.restore();tag(rx,ry-18,'JOURNAL PAGE','#d8c3f0')}}
 const d=cr.drone;if(d){c.save();c.strokeStyle='rgba(236,198,155,.5)';c.lineWidth=.8;c.beginPath();c.moveTo(sub.x,sub.y+S.hy*.6);c.quadraticCurveTo(mix(sub.x,d.x,.5),Math.max(sub.y,d.y)+40,d.x,d.y);c.stroke();c.restore();
  c.save();c.globalCompositeOperation='screen';glow(d.x+10,d.y+12,40,'rgba(255,230,170,.3)');c.restore();path([[d.x-8,d.y-5],[d.x+8,d.y-5],[d.x+9,d.y+5],[d.x-9,d.y+5]],'#e2b64a','#3a2a08',.8);circle(d.x+8,d.y,2,'#fff6d0');circle(d.x-9,d.y,2.5,null,'#3a2a08',1)}
 const a=cr.air;if(a){for(const f of a.flak){const age=t-f.born;if(age<.75){c.save();c.globalAlpha=Math.floor(age*16)%2?.9:.35;circle(f.x,f.y,52*(age/.75),null,'#ff6a5a',1);circle(f.x,f.y,3,'#ff6a5a');c.restore()}else{const k=(age-.75)/.95;c.save();c.globalAlpha=.75*(1-k);for(let i=0;i<5;i++)circle(f.x+Math.cos(i*1.3)*14*k,f.y+Math.sin(i*1.3)*12*k,14+k*24,'#20262a');c.restore()}}
  for(const bd of a.birds){if(bd.x<lo||bd.x>hi)continue;const f=Math.sin(ambient*14+bd.ph)*4;c.strokeStyle='#e8eef0';c.lineWidth=1.4;c.beginPath();c.moveTo(bd.x-7,bd.y-f);c.lineTo(bd.x,bd.y);c.lineTo(bd.x+7,bd.y-f);c.stroke()}
  c.save();c.translate(a.x,a.y);c.scale(1.9*a.dir,1.9);ufo(0,0,a.v*a.dir,true);c.restore();
  for(let i=0;i<a.held.size+(a.relic?1:0);i++)circle(a.x-8+i*8,a.y-20,2.6,i<a.held.size?'#ffd29a':'#e8d8ff');
  if(t-a.gust<.5){c.save();c.strokeStyle='rgba(230,240,240,.4)';c.lineWidth=1;for(let i=0;i<4;i++){c.beginPath();c.moveTo(a.x-60+i*25,a.y-30+i*14);c.lineTo(a.x-20+i*25,a.y-30+i*14);c.stroke()}c.restore()}
  // Landing pad on the deck.
  const [dx,dy]=deckAt(),pp=.5+.5*Math.sin(ambient*6);c.save();c.strokeStyle=`rgba(166,234,213,${.5+.4*pp})`;c.lineWidth=1.5;c.beginPath();c.ellipse(dx,dy,30,9,0,0,TAU);c.stroke();c.restore();tag(dx,dy-26,a.dir<0?'LAND HERE':'DECK','#a6ead5')}
}
// Screen space: ink blindness and the spotter drone's camera frame.
function campDrawScreen(){
 if(!cr)return;
 if(t<cr.inked){const [sx,sy]=proj(sub.x,sub.y),g=c.createRadialGradient(sx,sy,30,sx,sy,Math.max(W,H)*.6);g.addColorStop(0,'rgba(2,4,10,.55)');g.addColorStop(1,'rgba(2,4,10,.94)');c.fillStyle=g;c.fillRect(0,0,W,H)}
 const a=cr.air;if(!a)return;
 c.save();c.strokeStyle='rgba(225,240,232,.7)';c.lineWidth=1.5;const m=26,l=34;
 for(const [x,y,dx,dy] of [[m,m+50,1,1],[W-m,m+50,-1,1],[m,H-m,1,-1],[W-m,H-m,-1,-1]]){c.beginPath();c.moveTo(x,y+dy*l);c.lineTo(x,y);c.lineTo(x+dx*l,y);c.stroke()}
 // Feed readouts sit top and bottom centre, clear of the HUD in the corners.
 c.font='10px ui-monospace,monospace';c.fillStyle='rgba(225,240,232,.85)';c.textAlign='center';const top=Math.min(150,H*.2);
 c.fillText('SPOTTER FEED / ALT '+Math.max(0,Math.round((SURFACE-a.y)*.1))+' M',W/2,top);if(Math.floor(ambient*2)%2)circle(W/2-100,top-4,3.5,'#ff5a4a');
 c.fillStyle=a.dir<0?'#a6ead5':'#ffd29a';c.fillText((a.dir<0?'RETURNING TO THE BOAT':'OUTBOUND / Q TURNS BACK')+' / '+a.held.size+' ON DRONE',W/2,top+16);
 // Where the boat is, when it is off the feed.
 const [ddx,ddy]=deckAt(),[px,py]=proj(ddx,ddy),dist=Math.round(Math.abs(a.x-ddx)*.1);if(px<30||px>W-30){const left=px<30,ex=left?40:W-40,ey=clamp(py,90,H-120);c.fillStyle='#a6ead5';c.beginPath();c.moveTo(ex+(left?-14:14),ey);c.lineTo(ex+(left?6:-6),ey-10);c.lineTo(ex+(left?6:-6),ey+10);c.fill();c.fillText('BOAT '+dist+' M',ex+(left?40:-40),ey+4)}
 c.fillStyle='rgba(225,240,232,.85)';
 const bw=160,frac=clamp(a.bat/airBattery(),0,1),by=H-Math.min(130,H*.2);c.strokeRect(W/2-bw/2,by,bw,8);c.fillStyle=frac<.25?'#ff8a6a':'#a6ead5';c.fillRect(W/2-bw/2+1,by+1,(bw-2)*frac,6);c.fillStyle='rgba(225,240,232,.85)';c.fillText('BATTERY '+Math.ceil(Math.max(0,a.bat))+' S',W/2,by+24);c.textAlign='start';
 if(!reduced){c.globalAlpha=.05;c.fillStyle='#fff';for(let y=(ambient*60)%4;y<H;y+=4)c.fillRect(0,y,W,1)}c.restore();
}

/* ---- Cutscene backdrops ---------------------------------------------------------
   Painted in CSS pixels on the cutscene canvas, with tm seconds into the scene.
   Drawing helpers that use the global context are borrowed by swapping c. */
function wash(w,h,stops){const g=c.createLinearGradient(0,0,0,h);stops.forEach(([o,col])=>g.addColorStop(o,col));c.fillStyle=g;c.fillRect(0,0,w,h)}
function motes(w,h,tm,col,n=70){for(let i=0;i<n;i++){const x=(hash(i)*w+tm*(6+hash(i+3)*14))%w,y=(hash(i+7)*h+tm*(3+hash(i+1)*6))%h;c.globalAlpha=.2+.4*hash(i+9);circle(x,y,.6+hash(i+5)*1.6,col)}c.globalAlpha=1}
function rays(w,h,tm,a){c.save();c.globalCompositeOperation='screen';for(let i=0;i<6;i++){const x=(i/6)*w+Math.sin(tm*.2+i)*40,gg=c.createLinearGradient(0,0,0,h);gg.addColorStop(0,`rgba(170,235,215,${a})`);gg.addColorStop(1,'rgba(170,235,215,0)');path([[x,0],[x+60,0],[x+260,h],[x+80,h]],gg)}c.restore()}
function seabed(w,h,col,y0){c.fillStyle=col;c.beginPath();c.moveTo(0,h);for(let x=0;x<=w+20;x+=20)c.lineTo(x,y0+Math.sin(x/90)*14+Math.sin(x/31)*5);c.lineTo(w,h);c.fill()}
function campBoat(){return SUB_BY_ID[camp.data.sub]||SUB_BY_ID.gato}
const SCENES={
 title(w,h,tm){wash(w,h,[[0,'#0a2430'],[1,'#020a10']]);c.save();c.globalCompositeOperation='screen';for(let i=0;i<4;i++){const r=((tm*90+i*w*.18)%(w*.75));c.strokeStyle=`rgba(131,239,203,${.18*(1-r/(w*.75))})`;c.lineWidth=1.4;c.beginPath();c.arc(w/2,h*.46,r,0,TAU);c.stroke()}c.restore();
  c.strokeStyle='rgba(166,234,213,.05)';c.lineWidth=1;for(let x=0;x<w;x+=48){c.beginPath();c.moveTo(x,0);c.lineTo(x,h);c.stroke()}for(let y=0;y<h;y+=48){c.beginPath();c.moveTo(0,y);c.lineTo(w,y);c.stroke()}motes(w,h,tm,'#9fd8cf')},
 sea(w,h,tm){wash(w,h,[[0,'#1d6a74'],[.5,'#0b3a4a'],[1,'#03141e']]);rays(w,h,tm,.06);seabed(w,h,'#06202a',h*.86);
  for(let j=0;j<3;j++)for(let i=0;i<8;i++){const fx=((w*1.2-tm*(30+j*10)+j*300+hash(i+j*9)*80)%(w*1.3))-50,fy=h*(.25+j*.12)+hash(i*3+j)*30;c.globalAlpha=.35;c.fillStyle='#9ac6c5';c.beginPath();c.ellipse(fx,fy,5,1.5,0,0,TAU);c.fill()}c.globalAlpha=1;
  const k=Math.min(w,h)/150;subAt(campBoat(),w*.42+Math.sin(tm*.3)*20,h*.52+Math.sin(tm*.7)*6,Math.sin(tm*.5)*.03,k);
  for(let i=0;i<20;i++){const a=(tm*.6+i/20)%1;c.globalAlpha=.4*(1-a);circle(w*.42-55*k-a*160,h*.52+Math.sin(i)*8-a*60,1+hash(i)*3,null,'#b2dacf')}c.globalAlpha=1;motes(w,h,tm,'#a7e0dc',50)},
 core(w,h,tm){wash(w,h,[[0,'#1a1410'],[1,'#060404']]);c.strokeStyle='rgba(255,180,120,.06)';for(let y=20;y<h;y+=36){c.beginPath();c.moveTo(0,y);c.lineTo(w,y);c.stroke()}
  const cx=w/2,cy=h*.5,s=Math.min(w,h)/5,p=.75+.25*Math.sin(tm*2.2);c.save();c.globalCompositeOperation='screen';glow(cx,cy,s*3.2*p,'rgba(255,120,40,.45)');c.restore();
  const gg=c.createLinearGradient(cx-s*.6,0,cx+s*.6,0);gg.addColorStop(0,'#5a2a10');gg.addColorStop(.5,`rgb(255,${Math.round(150+60*p)},90)`);gg.addColorStop(1,'#5a2a10');c.fillStyle=gg;c.fillRect(cx-s*.55,cy-s,s*1.1,s*2);
  c.fillStyle='#2a2a2a';c.fillRect(cx-s*.7,cy-s*1.15,s*1.4,s*.2);c.fillRect(cx-s*.7,cy+s*.95,s*1.4,s*.2);for(let i=-3;i<=3;i++){c.fillStyle=i%2?'#e8b43a':'#222';c.fillRect(cx+i*s*.2-s*.1,cy+s*.95,s*.2,s*.2)}
  c.strokeStyle='rgba(255,200,140,.25)';c.lineWidth=1.5;for(let i=0;i<6;i++){c.beginPath();for(let y=0;y<s*1.6;y+=6){const x=cx-s*.8+i*s*.32+Math.sin(y*.06-tm*3+i)*6;y?c.lineTo(x,cy-s*1.2-y):c.moveTo(x,cy-s*1.2-y)}c.stroke()}motes(w,h,tm,'#ffb07a',40)},
 hq(w,h,tm){wash(w,h,[[0,'#0e2a2c'],[1,'#04100f']]);c.strokeStyle='rgba(166,234,213,.08)';c.lineWidth=1;for(let x=0;x<w;x+=40){c.beginPath();c.moveTo(x,0);c.lineTo(x,h);c.stroke()}for(let y=0;y<h;y+=40){c.beginPath();c.moveTo(0,y);c.lineTo(w,y);c.stroke()}
  for(let k=0;k<5;k++){const cx=w*(.12+hash(k)*.8),cy=h*(.15+hash(k+4)*.7),r=60+hash(k+8)*90;c.beginPath();for(let i=0;i<=40;i++){const a=i/40*TAU,rr=r*(.7+.3*Math.sin(a*3+k)+.12*Math.sin(a*7+k*2));i?c.lineTo(cx+Math.cos(a)*rr,cy+Math.sin(a)*rr*.7):c.moveTo(cx+Math.cos(a)*rr,cy+Math.sin(a)*rr*.7)}c.closePath();c.fillStyle='#1f3d33';c.fill();c.strokeStyle='#5e8c74';c.stroke()}
  const prog=clamp(tm/5,0,1);c.save();c.setLineDash([8,6]);c.lineDashOffset=-tm*20;c.strokeStyle='#ecc69b';c.lineWidth=2;c.beginPath();for(let i=0;i<=60*prog;i++){const u=i/60,x=w*(.08+.84*u),y=h*(.7-.4*u)+Math.sin(u*9)*h*.08;i?c.lineTo(x,y):c.moveTo(x,y)}c.stroke();c.restore();
  for(let i=0;i<6;i++){const u=(i+.5)/6,x=w*(.08+.84*u),y=h*(.7-.4*u)+Math.sin(u*9)*h*.08;if(u>prog)break;circle(x,y,5,i===5?'#e3785f':'#ecc69b');if(Math.floor(tm*2+i)%2)circle(x,y,10,null,'#ecc69b88',1)}
  c.save();c.globalCompositeOperation='screen';glow(w*.9,h*.1,w*.4,'rgba(255,220,160,.12)');c.restore()},
 bridge(w,h,tm){const al=.5+.15*Math.sin(tm*1.3);wash(w,h,[[0,'#2a0d0d'],[1,'#0a0303']]);c.save();c.globalCompositeOperation='screen';glow(w/2,h*.2,w*.6,`rgba(255,60,40,${.18*al})`);c.restore();
  c.strokeStyle='#3a1a18';c.lineWidth=10;for(const y of [h*.12,h*.18,h*.86]){c.beginPath();c.moveTo(0,y);c.lineTo(w,y);c.stroke()}
  const px=w*.5;let gg=c.createLinearGradient(px-24,0,px+24,0);gg.addColorStop(0,'#1a0a08');gg.addColorStop(.5,'#5a2a22');gg.addColorStop(1,'#1a0a08');c.fillStyle=gg;c.fillRect(px-22,0,44,h*.7);c.fillStyle='#2a1210';c.fillRect(px-46,h*.66,92,26);c.fillRect(px-60,h*.66,14,40);c.fillRect(px+46,h*.66,14,40);
  for(const [gx,gy,r] of [[w*.14,h*.36,40],[w*.26,h*.3,28],[w*.8,h*.34,38],[w*.9,h*.46,24]]){circle(gx,gy,r,'#160807','#6a3a30',2);const a=-2.3+Math.sin(tm*.8+gx)*.4+1.8*hash(gx);c.strokeStyle='#ffb08a';c.lineWidth=2;c.beginPath();c.moveTo(gx,gy);c.lineTo(gx+Math.cos(a)*r*.8,gy+Math.sin(a)*r*.8);c.stroke()}
  const sx=w*.82,sy=h*.7,sr=Math.min(w,h)*.12;circle(sx,sy,sr,'#031a10','#2a6a40',2);c.strokeStyle='rgba(120,255,160,.6)';c.lineWidth=1.5;c.beginPath();c.moveTo(sx,sy);c.lineTo(sx+Math.cos(tm*1.6)*sr,sy+Math.sin(tm*1.6)*sr);c.stroke();for(let i=0;i<4;i++){const a=hash(i)*TAU,rr=hash(i+3)*sr*.85,f=(tm*1.6-a)%TAU;circle(sx+Math.cos(a)*rr,sy+Math.sin(a)*rr,2,`rgba(150,255,180,${clamp(1-((f+TAU)%TAU)/3,0,1)})`)}
  c.fillStyle='#050101';for(const [cx,s] of [[w*.2,1],[w*.36,.9],[w*.66,1.05]]){c.beginPath();c.arc(cx,h*.78,28*s,0,TAU);c.fill();c.beginPath();c.ellipse(cx,h,70*s,h*.18,0,Math.PI,0);c.fill()}},
 wreck(w,h,tm){wash(w,h,[[0,'#0b2e3a'],[1,'#020c12']]);rays(w,h,tm,.035);seabed(w,h,'#071c22',h*.78);
  c.save();c.translate(w*.5,h*.74);c.rotate(-.1);const k=Math.min(w,h)/260;c.scale(k,k);path([[-130,-6],[-20,-8],[-12,10],[-120,12]],'#1c2a2c','#0006');path([[-8,-10],[110,-18],[130,-6],[110,12],[0,10]],'#1c2a2c','#0006');path([[-110,-6],[-90,-30],[-50,-30],[-40,-8]],'#2a221c');c.strokeStyle='#2a221c';c.lineWidth=3;c.beginPath();c.moveTo(40,-14);c.lineTo(66,-80);c.stroke();c.restore();
  const dx=w*.5+Math.sin(tm*.6)*w*.2,dy=h*.48+Math.cos(tm*.8)*20;c.save();c.globalCompositeOperation='screen';let gg=c.createLinearGradient(dx,dy,dx,dy+h*.3);gg.addColorStop(0,'rgba(255,230,170,.35)');gg.addColorStop(1,'rgba(255,230,170,0)');path([[dx-4,dy],[dx+4,dy],[dx+70,dy+h*.3],[dx-70,dy+h*.3]],gg);c.restore();path([[dx-12,dy-8],[dx+12,dy-8],[dx+13,dy+6],[dx-13,dy+6]],'#e2b64a','#3a2a08');circle(dx,dy+6,3,'#fff6d0');motes(w,h,tm,'#a7e0dc',60)},
 volkov(w,h,tm,typh){wash(w,h,[[0,'#2a0e10'],[.6,'#120608'],[1,'#050203']]);c.save();c.globalCompositeOperation='screen';for(let i=0;i<3;i++){const r=((tm*120+i*200)%600);c.strokeStyle=`rgba(255,100,80,${.25*(1-r/600)})`;c.lineWidth=1.5;c.beginPath();c.arc(w*.62,h*.5,r,0,TAU);c.stroke()}c.restore();
  const m=SUB_BY_ID[typh?'typhoon':'akula'],k=Math.min(w,h)/(typh?150:170),x=w*.55+Math.sin(tm*.25)*30,y=h*.5;subAt(m,x,y,0,k);star5(x-8*k,y-24*k,4*k,'#d0392bdd');
  c.save();c.globalCompositeOperation='screen';glow(x+45*k,y,90,'rgba(255,90,70,.25)');c.restore();motes(w,h,tm,'#ff9a8a',40)},
 typhoon(w,h,tm){SCENES.volkov(w,h,tm,true)},
 island(w,h,tm){wash(w,h,[[0,'#2c2a52'],[.45,'#e4875a'],[.62,'#f6c38a'],[.63,'#1e5a68'],[1,'#062a36']]);const sy=h*.62;
  c.save();c.globalCompositeOperation='screen';glow(w*.7,sy-10,w*.25,'rgba(255,190,120,.4)');c.restore();circle(w*.7,sy-14,26,'#ffd8a0');
  c.fillStyle='#1a1e24';c.beginPath();c.moveTo(w*.15,sy);for(let x=w*.15;x<=w*.6;x+=10)c.lineTo(x,sy-Math.sin((x-w*.15)/(w*.45)*Math.PI)*h*.22-Math.sin(x*.05)*6);c.lineTo(w*.6,sy);c.fill();c.strokeStyle='#1a1e24';c.lineWidth=3;c.beginPath();c.moveTo(w*.36,sy-h*.21);c.lineTo(w*.36,sy-h*.32);c.stroke();c.beginPath();c.ellipse(w*.36,sy-h*.33,16,6,Math.sin(tm)*.6,0,TAU);c.stroke();
  c.strokeStyle='rgba(255,230,200,.35)';c.lineWidth=1;for(let i=0;i<14;i++){const x=(hash(i)*w+tm*8)%w,y=sy+6+hash(i+3)*h*.3;c.beginPath();c.moveTo(x,y);c.lineTo(x+20+hash(i)*40,y);c.stroke()}
  const k=Math.min(w,h)/260;subAt(campBoat(),w*.78,sy+4,0,k);const ax=w*.2+((tm*60)%(w*.7)),ay=sy-h*.3+Math.sin(tm*1.5)*20;c.save();c.translate(ax,ay);c.scale(2.2,2.2);ufo(0,0,0,true);c.restore();
  for(let i=0;i<4;i++){const bx=(w-((tm*40+i*130)%w)),by=h*.2+i*14,f=Math.sin(tm*8+i)*4;c.strokeStyle='#2a2030';c.lineWidth=1.5;c.beginPath();c.moveTo(bx-7,by-f);c.lineTo(bx,by);c.lineTo(bx+7,by-f);c.stroke()}},
 octopus(w,h,tm){wash(w,h,[[0,'#0c0a14'],[1,'#030206']]);c.fillStyle='#0e1418';c.beginPath();c.moveTo(0,0);for(let x=0;x<=w;x+=20)c.lineTo(x,h*.12+Math.sin(x/70)*18);c.lineTo(w,0);c.fill();c.beginPath();c.moveTo(0,h);for(let x=0;x<=w;x+=20)c.lineTo(x,h*.88+Math.sin(x/60)*16);c.lineTo(w,h);c.fill();
  const k=Math.min(w,h)/420,o=clamp(tm/2.5,0,1);drawOcto(w*.62,h*.52,k*1.4,[Math.sin(tm*.7)*.6,Math.cos(tm*.5)*.4],0,o);motes(w,h,tm,'#d0a0b0',40)},
 kraken(w,h,tm){wash(w,h,[[0,'#06181a'],[1,'#010506']]);const k=Math.min(w,h)/520,rise=clamp(tm/4,0,1);drawKraken(w*.64,h*(.95-.38*rise),k*1.5,clamp((tm-1.8)/1.5,0,1),[-.6,-.4],0,1);
  const sx=w*.18,sy=h*.22;subAt(campBoat(),sx,sy,.05,Math.min(w,h)/420);c.save();c.globalCompositeOperation='screen';let gg=c.createLinearGradient(sx,sy,sx+w*.4,sy);gg.addColorStop(0,'rgba(172,226,212,.25)');gg.addColorStop(1,'rgba(172,226,212,0)');path([[sx+30,sy-2],[sx+w*.4,sy-60],[sx+w*.4,sy+60],[sx+30,sy+2]],gg);c.restore();motes(w,h,tm,'#7fd6c0',50)},
 alarm(w,h,tm){SCENES.bridge(w,h,tm);const f=Math.max(0,Math.sin(tm*7));c.fillStyle=`rgba(255,20,10,${.25*f})`;c.fillRect(0,0,w,h);for(let i=0;i<30;i++){const a=(tm*2+hash(i))%1;c.globalAlpha=1-a;circle(w*(.3+hash(i+2)*.4)+Math.cos(i)*a*80,h*.3+a*a*h*.5,1.5,'#ffd08a')}c.globalAlpha=1;
  c.strokeStyle='rgba(180,220,255,.35)';c.lineWidth=2;for(let i=0;i<8;i++){const x=w*.1+i*w*.03;c.beginPath();c.moveTo(x,h*.15);c.quadraticCurveTo(x+20,h*.4,x+10+Math.sin(tm*9+i)*6,h*.7);c.stroke()}},
 warden(w,h,tm){wash(w,h,[[0,'#3a8a90'],[.18,'#1a5a68'],[1,'#03141e']]);rays(w,h,tm,.08);c.save();c.translate(w*.5,h*.12);c.scale(Math.min(w,h)/520,Math.min(w,h)/520);c.fillStyle='#071a20';c.beginPath();c.moveTo(-300,-10);c.lineTo(300,-10);c.lineTo(260,30);c.quadraticCurveTo(0,60,-260,30);c.closePath();c.fill();c.restore();
  for(let i=0;i<5;i++){const a=((tm*.35+i*.21)%1),x=w*(.3+i*.1),y=h*.18+a*h*.7;c.save();c.translate(x,y);c.rotate(tm*2+i);path([[-6,-9],[6,-9],[7,9],[-7,9]],'#0a1a20','#000',.8);c.restore();for(let j=0;j<4;j++)circle(x+Math.sin(j+tm)*3,y-12-j*10,1.5,null,'#b2dacf88')}motes(w,h,tm,'#a7e0dc',40)},
 port(w,h,tm){wash(w,h,[[0,'#3c3a6a'],[.35,'#f0a888'],[.55,'#ffe0b0'],[.56,'#4a7a88'],[1,'#0e2a36']]);const sy=h*.56;c.save();c.globalCompositeOperation='screen';glow(w*.3,sy,w*.3,'rgba(255,210,150,.45)');c.restore();circle(w*.3,sy-6,30,'#fff0c8');
  c.fillStyle='#1b2430';c.fillRect(w*.55,sy-12,w*.45,12);for(let i=0;i<3;i++){const x=w*(.62+i*.12);c.fillRect(x,sy-h*.3,6,h*.3);c.beginPath();c.moveTo(x-30,sy-h*.3);c.lineTo(x+60,sy-h*.3);c.lineTo(x+60,sy-h*.3+6);c.lineTo(x-30,sy-h*.3+6);c.fill();c.strokeStyle='#1b2430';c.lineWidth=1;c.beginPath();c.moveTo(x+50,sy-h*.3);c.lineTo(x+50,sy-h*.12);c.stroke()}
  c.strokeStyle='rgba(255,240,210,.4)';for(let i=0;i<16;i++){const x=(hash(i)*w+tm*6)%w,y=sy+5+hash(i+3)*h*.35;c.beginPath();c.moveTo(x,y);c.lineTo(x+20+hash(i)*30,y);c.stroke()}
  subAt(campBoat(),w*.42+tm*4,sy+3,0,Math.min(w,h)/240);for(let i=0;i<5;i++){const bx=(w*.1+((tm*30+i*90)%(w*.8))),by=h*.18+Math.sin(i*2)*20,f=Math.sin(tm*7+i)*4;c.strokeStyle='#3a3048';c.lineWidth=1.5;c.beginPath();c.moveTo(bx-7,by-f);c.lineTo(bx,by);c.lineTo(bx+7,by-f);c.stroke()}},
};
