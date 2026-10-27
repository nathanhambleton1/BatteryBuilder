'use strict';
/* ---- Cutscenes: character portraits and painted scenes ---------------------------
   Every line of dialogue can carry its own scene, so a cutscene cuts between shots
   instead of holding one backdrop. Scenes paint in CSS pixels with tm seconds since
   the shot began; paintScene adds a slow push-in, letterbox bars and a vignette.
   Speakers get a drawn bust in the dialogue box (and in close-up shots), with
   blinking, breathing and a moving mouth while their line types out. */
function paintScene(g,name,w,h,tm){
 const saved=c,sN=night,sA=ambient;c=g;night=0;ambient=tm;
 try{
  c.save();const action=/chase|sink|last|retreat|escape|attack/.test(name),motion=reduced?0:tm;const z=1.03+(action?.12:.06)*smooth(0,12,motion),dx=Math.sin(motion*(action?.24:.09)+name.length)*w*.012;c.translate(w/2+dx,h/2);c.scale(z,z);c.translate(-w/2,-h/2);
  (SCENES[name]||SCENES.title)(w,h,reduced?2:tm);
  cineDepth(name,w,h,motion);c.restore();
  const v=c.createRadialGradient(w/2,h/2,Math.min(w,h)*.35,w/2,h/2,Math.max(w,h)*.75);v.addColorStop(0,'rgba(0,0,0,0)');v.addColorStop(1,'rgba(0,0,0,.55)');c.fillStyle=v;c.fillRect(0,0,w,h);
  const bar=Math.round(h*.065);c.fillStyle='#000';c.fillRect(0,0,w,bar);c.fillRect(0,h-bar,w,bar);
 }finally{c=saved;night=sN;ambient=sA}
}
const U=(w,h)=>Math.min(w,h)/600;
function ell(x,y,rx,ry,fill,rot=0){c.beginPath();c.ellipse(x,y,Math.max(.1,rx),Math.max(.1,ry),rot,0,TAU);c.fillStyle=fill;c.fill()}
function sky(w,h,y,top,mid,low){const g=c.createLinearGradient(0,0,0,y);g.addColorStop(0,top);g.addColorStop(.7,mid);g.addColorStop(1,low);c.fillStyle=g;c.fillRect(0,0,w,y)}
function sea(w,h,y,a,b){const g=c.createLinearGradient(0,y,0,h);g.addColorStop(0,a);g.addColorStop(1,b);c.fillStyle=g;c.fillRect(0,y,w,h-y);c.strokeStyle='rgba(255,255,255,.12)';c.lineWidth=1;for(let i=0;i<22;i++){const x=(hash(i)*w+ambient*(6+hash(i+1)*10))%w,yy=y+4+hash(i+3)*(h-y)*.6;c.beginPath();c.moveTo(x,yy);c.lineTo(x+18+hash(i)*36,yy);c.stroke()}}
function stars(w,h,y,n=90){for(let i=0;i<n;i++){c.globalAlpha=.3+.6*hash(i+2)*(.6+.4*Math.sin(ambient*2+i));circle(hash(i)*w,hash(i+9)*y,.5+hash(i+4),'#e6f0ff')}c.globalAlpha=1}
function bubs(x,y,tm,n,spread,col='#b2dacf'){for(let i=0;i<n;i++){const a=(tm*.5+i/n)%1;c.globalAlpha=.5*(1-a);circle(x+Math.sin(i*2.3+tm)*spread*a,y-a*spread*3,1+hash(i)*3,null,col,1)}c.globalAlpha=1}
function smoke(x,y,tm,s,col='#22282c'){for(let i=0;i<7;i++){const a=(tm*.25+i/7)%1;c.globalAlpha=.5*(1-a);circle(x-a*s*2.2,y-a*s*2.6,s*(.3+a*.9),col)}c.globalAlpha=1}
function flames(x,y,tm,s){c.save();c.globalCompositeOperation='screen';glow(x,y,s*2.4,'rgba(255,120,40,.5)');for(let i=0;i<6;i++){const a=(tm*1.6+i/6)%1;circle(x+Math.sin(i*3+tm*5)*s*.3,y-a*s*1.6,s*.35*(1-a),`rgba(255,${160+i*12},60,${.8*(1-a)})`)}c.restore()}
function spot(x,y,ang,len,spread,a){c.save();c.globalCompositeOperation='screen';const ex=x+Math.cos(ang)*len,ey=y+Math.sin(ang)*len,nx=-Math.sin(ang)*spread,ny=Math.cos(ang)*spread,g=c.createLinearGradient(x,y,ex,ey);g.addColorStop(0,`rgba(255,240,200,${a})`);g.addColorStop(1,'rgba(255,240,200,0)');path([[x,y],[ex+nx,ey+ny],[ex-nx,ey-ny]],g);c.restore()}
function rocks(w,h,top,col){c.fillStyle=col;c.beginPath();if(top){c.moveTo(0,0);for(let x=0;x<=w+20;x+=20)c.lineTo(x,h*.14+Math.sin(x/70)*h*.04+Math.sin(x/23)*h*.012);c.lineTo(w,0)}else{c.moveTo(0,h);for(let x=0;x<=w+20;x+=20)c.lineTo(x,h*.84+Math.sin(x/60)*h*.04+Math.sin(x/19)*h*.01);c.lineTo(w,h)}c.fill()}
function deep(w,h,tm,a='#0b3442',b='#020a10',ray=.04){wash(w,h,[[0,a],[1,b]]);if(ray)rays(w,h,tm,ray)}

/* ---- Portraits ---- */
const SKIN={HALE:'#e2b694',JUNO:'#bd8661',RIGGS:'#f0c6a4',VANCE:'#e4bd9c',VOLKOV:'#d4a984',YOU:'#273038'};
const UNIFORM={HALE:'#17243c',JUNO:'#c76d22',RIGGS:'#577fa2',VANCE:'#e6eaea',VOLKOV:'#2c312c',YOU:'#10181e'};
function drawBust(who,x,y,s,tm,talk){
 if(!SKIN[who])return;const sk=SKIN[who],u=UNIFORM[who],blink=(tm+hash(who.length)*3)%4.2<.13,mo=talk?(.5+.5*Math.sin(tm*17))*3:0;
 c.save();c.translate(x,y+Math.sin(tm*1.5)*s*.006);c.scale(s/100,s/100);
 // Hair and hats behind the head.
 if(who==='HALE')ell(0,-74,13,11,'#b5b5bb');
 if(who==='JUNO'){c.fillStyle='#14100e';c.beginPath();c.moveTo(-21,-50);c.quadraticCurveTo(-24,-86,0,-84);c.quadraticCurveTo(24,-86,21,-50);c.closePath();c.fill()}
 path([[-50,0],[-46,-21],[-28,-31],[28,-31],[46,-21],[50,0]],u);
 c.fillStyle=sk;c.fillRect(-8,-42,16,13);
 // Collars and kit.
 if(who==='HALE'){path([[-10,-31],[0,-18],[10,-31]],'#eef2f4');path([[-2,-30],[2,-30],[3,-16],[0,-12],[-3,-16]],'#0c1018');c.fillStyle='#d8b04a';c.fillRect(-44,-25,16,5);c.fillRect(28,-25,16,5);for(let i=0;i<3;i++)circle(-16+i*3,-12+i*5,1.3,'#d8b04a');for(let i=0;i<3;i++)circle(16-i*3,-12+i*5,1.3,'#d8b04a')}
 if(who==='JUNO'){c.strokeStyle='#8a4a14';c.lineWidth=1.5;c.beginPath();c.moveTo(0,-30);c.lineTo(0,0);c.stroke();path([[-12,-31],[0,-24],[12,-31],[10,-34],[-10,-34]],'#a8581a');c.fillStyle='#6a6a6a';c.fillRect(20,-20,9,12);c.fillStyle='#d6d6d6';c.fillRect(22,-26,2,8)}
 if(who==='RIGGS'){path([[-11,-31],[0,-22],[11,-31]],'#cfe0ec');c.strokeStyle='#3c5a76';c.lineWidth=1;c.beginPath();c.moveTo(0,-22);c.lineTo(0,0);c.stroke()}
 if(who==='VANCE'){path([[-14,-31],[-4,-6],[-22,0],[-30,-28]],'#d8dede');path([[14,-31],[4,-6],[22,0],[30,-28]],'#d8dede');path([[-7,-31],[0,-20],[7,-31]],'#9bb8d8');path([[-2,-24],[2,-24],[3,-8],[0,-5],[-3,-8]],'#a33b32');c.fillStyle='#2a5a8a';c.fillRect(18,-20,2,9)}
 if(who==='VOLKOV'){path([[-14,-31],[-6,-12],[-22,-6],[-30,-28]],'#3a403a');path([[14,-31],[6,-12],[22,-6],[30,-28]],'#3a403a');c.fillStyle='#b8272b';c.fillRect(-25,-27,7,5);c.fillRect(18,-27,7,5);for(let i=0;i<3;i++)circle(0,-20+i*8,1.6,'#c8a24a')}
 if(who==='YOU'){path([[-10,-31],[0,-20],[10,-31]],'#2a3a44');c.strokeStyle='#3a4a54';c.lineWidth=2;c.beginPath();c.moveTo(-10,-29);c.quadraticCurveTo(0,-14,10,-29);c.stroke();c.fillStyle='#0a0e12';c.fillRect(-9,-16,7,8);c.fillRect(2,-16,7,8)}
 // Head.
 ell(-17,-58,3,5,sk);ell(17,-58,3,5,sk);
 {const hg=c.createRadialGradient(-6,-70,3,0,-58,26);hg.addColorStop(0,'rgba(255,240,225,.35)');hg.addColorStop(.55,'rgba(0,0,0,0)');hg.addColorStop(1,'rgba(40,20,10,.35)');ell(0,-60,17,21,sk);ell(0,-60,17,21,hg)}
 if(who!=='YOU'){ell(0,-38.5,7,1.8,'rgba(40,20,10,.16)');ell(-10,-52,4,2.5,'rgba(220,90,80,.12)');ell(10,-52,4,2.5,'rgba(220,90,80,.12)')}
 if(who==='YOU'){c.strokeStyle='rgba(166,234,213,.55)';c.lineWidth=1.6;c.beginPath();c.ellipse(0,-60,17,21,0,-1.2,1.2);c.stroke()}
 else{
  const ey=-62,eye=blink?null:'#1a1410';
  if(eye){ell(-6.5,ey,2.3,1.7,eye);ell(6.5,ey,2.3,1.7,eye);circle(-6,ey-.5,.6,'#fff');circle(7,ey-.5,.6,'#fff')}else{c.strokeStyle='#3a2a20';c.lineWidth=1;c.beginPath();c.moveTo(-9,ey);c.lineTo(-4,ey);c.moveTo(4,ey);c.lineTo(9,ey);c.stroke()}
  c.strokeStyle='rgba(90,50,30,.4)';c.lineWidth=1;c.beginPath();c.moveTo(-.5,-61);c.quadraticCurveTo(-3,-54,-1,-52.5);c.stroke();ell(1,-52.6,3,1.2,'rgba(90,50,30,.22)');
  ell(0,-46.5,4.2,.9+mo*.45,'#5a2622');
  const brow=who==='VOLKOV'||who==='VANCE'?'#9a9894':who==='RIGGS'?'#b5602a':who==='HALE'?'#8c8c90':'#1a120e';c.strokeStyle=brow;c.lineWidth=1.8;c.beginPath();c.moveTo(-10,-67);c.lineTo(-3,-68);c.moveTo(3,-68);c.lineTo(10,-67);c.stroke();
 }
 // Hair, hats and faces in front.
 if(who==='HALE'){c.fillStyle='#c4c4ca';c.beginPath();c.ellipse(0,-74,18,10,0,Math.PI,0);c.fill();ell(-15,-66,4,8,'#c4c4ca',.2);ell(15,-66,4,8,'#c4c4ca',-.2);ell(0,-82,22,7,'#1b2a44');c.fillStyle='#1b2a44';c.fillRect(-18,-80,36,6);path([[-17,-74],[17,-74],[21,-70],[-21,-70]],'#0a0e14');c.strokeStyle='#d8b04a';c.lineWidth=1.4;c.beginPath();c.moveTo(-16,-72);c.lineTo(16,-72);c.stroke();circle(0,-79,2.4,'#d8b04a');c.strokeStyle='rgba(120,70,50,.35)';c.lineWidth=.8;c.beginPath();c.moveTo(-11,-50);c.lineTo(-8,-46);c.moveTo(11,-50);c.lineTo(8,-46);c.stroke()}
 if(who==='JUNO'){c.fillStyle='#14100e';c.beginPath();c.moveTo(-18,-66);c.quadraticCurveTo(-4,-86,18,-68);c.lineTo(18,-74);c.quadraticCurveTo(0,-90,-18,-74);c.fill();c.fillStyle='#2a2420';c.fillRect(-19,-77,38,4);for(const gx of [-8,8]){circle(gx,-76,6,'#2a2420');circle(gx,-76,4.2,'#e9a83a');circle(gx-1.2,-77.2,1.2,'#fff3c8')}ell(9,-52,3,2,'rgba(40,30,24,.35)')}
 if(who==='RIGGS'){ell(0,-77,16,7,'#b8602a');c.strokeStyle='#202428';c.lineWidth=4;c.beginPath();c.arc(0,-62,22,Math.PI*1.08,Math.PI*1.92);c.stroke();ell(-20,-58,5,8,'#2a2e33');ell(20,-58,5,8,'#2a2e33');c.strokeStyle='#202428';c.lineWidth=1.5;c.beginPath();c.moveTo(-20,-52);c.quadraticCurveTo(-16,-44,-6,-45);c.stroke();circle(-6,-45,1.8,'#202428')}
 if(who==='VANCE'){c.fillStyle='#a8a8a6';c.beginPath();c.ellipse(-15,-66,4,9,.2,0,TAU);c.ellipse(15,-66,4,9,-.2,0,TAU);c.fill();c.fillStyle='#b4b4b2';c.beginPath();c.moveTo(-13,-48);c.quadraticCurveTo(0,-30,13,-48);c.quadraticCurveTo(0,-41,-13,-48);c.fill();c.strokeStyle='#2a2a2a';c.lineWidth=1.3;c.beginPath();c.arc(-6.5,-62,4.5,0,TAU);c.moveTo(11,-62);c.arc(6.5,-62,4.5,0,TAU);c.moveTo(-2,-62);c.lineTo(2,-62);c.stroke()}
 if(who==='VOLKOV'){c.fillStyle='#9c9a96';c.beginPath();c.moveTo(-16,-54);c.quadraticCurveTo(-14,-30,0,-30);c.quadraticCurveTo(14,-30,16,-54);c.quadraticCurveTo(0,-44,-16,-54);c.fill();ell(0,-49,8,2.2,'#8a8884');ell(0,-46.5,4,.9+mo*.45,'#3a1a16');
  ell(0,-82,25,8,'#3b4838');c.fillStyle='#3b4838';c.fillRect(-19,-82,38,6);c.fillStyle='#b8272b';c.fillRect(-19,-77,38,5);path([[-18,-72],[18,-72],[22,-68],[-22,-68]],'#0a0c0a');star5(0,-79,4,'#e23a34')}
 if(who==='YOU'){ell(0,-82,23,7,'#e8ecec');c.fillStyle='#14202a';c.fillRect(-18,-79,36,6);path([[-17,-73],[17,-73],[22,-68],[-22,-68]],'#05080a');circle(0,-76,2.6,'#d8b04a')}
 c.restore();
}
// A bust in a frame for the dialogue box.
function paintPortrait(g,who,w,h,tm,talk){
 const saved=c,sA=ambient;c=g;ambient=tm;
 try{const C=CAST[who]||CAST.NARR,bg=c.createLinearGradient(0,0,0,h);bg.addColorStop(0,'#0b1c22');bg.addColorStop(1,'#03090c');c.fillStyle=bg;c.fillRect(0,0,w,h);
  c.save();c.globalCompositeOperation='screen';glow(w*.5,h*.45,w*.7,C.c+'33');c.restore();
  if(who==='VANCE'){drawBust(who,w/2,h+4,h*1.05,tm,talk);c.fillStyle='rgba(200,170,255,.10)';c.fillRect(0,0,w,h);for(let y=(tm*40)%3;y<h;y+=3){c.fillStyle='rgba(0,0,0,.18)';c.fillRect(0,y,w,1)}}
  else drawBust(who,w/2,h+4,h*1.05,tm,talk);
 }finally{c=saved;ambient=sA}
}

/* ---- Shots ---- */
const boatFor=id=>()=>SUB_BY_ID[id];
function drydock(w,h,tm,m){
 const u=U(w,h);wash(w,h,[[0,'#151a1e'],[1,'#07090b']]);
 c.fillStyle='#20262a';c.fillRect(0,h*.78,w,h*.22);c.fillStyle='#2a3136';for(let i=0;i<8;i++)c.fillRect(i*w/8,h*.78,w/8-4,6);
 c.strokeStyle='#30383e';c.lineWidth=6*u;for(const x of [w*.12,w*.88]){c.beginPath();c.moveTo(x,0);c.lineTo(x,h*.78);c.stroke();for(let y=h*.1;y<h*.78;y+=h*.1){c.beginPath();c.moveTo(x-30*u,y);c.lineTo(x+30*u,y);c.stroke()}}
 spot(w*.2,0,1.15+Math.sin(tm*.5)*.12,h*1.1,90*u,.18);spot(w*.8,0,1.95+Math.sin(tm*.4+1)*.12,h*1.1,90*u,.18);
 for(const x of [.36,.5,.64]){c.fillStyle='#3a3430';c.fillRect(w*x-14*u,h*.7,28*u,h*.08)}
 subAt(m,w*.5,h*.6,0,Math.min(w,h)/(m.hx*2.6));
 for(let i=0;i<14;i++){const a=(tm*2+i/14)%1;c.globalAlpha=1-a;circle(w*.58+Math.cos(i*2.4)*a*60*u,h*.52+a*a*90*u,1.5,'#ffd08a')}c.globalAlpha=1;c.save();c.globalCompositeOperation='screen';glow(w*.58,h*.52,30*u*(.7+.3*Math.sin(tm*30)),'rgba(160,210,255,.7)');c.restore();
 c.font=`${Math.round(14*u)}px ui-monospace,monospace`;c.fillStyle='#ecc69b';c.textAlign='center';c.fillText(m.name.toUpperCase()+' CLASS / '+m.mark,w/2,h*.88);c.textAlign='start';
}
function bigScope(w,h,tm,inner){c.fillStyle='#000';c.fillRect(0,0,w,h);const r=Math.min(w,h)*.42;c.save();c.beginPath();c.arc(w/2,h/2,r,0,TAU);c.clip();inner(w,h,tm);c.restore();c.strokeStyle='rgba(180,220,200,.6)';c.lineWidth=1.4;c.beginPath();c.moveTo(w/2-r,h/2);c.lineTo(w/2+r,h/2);c.moveTo(w/2,h/2-r);c.lineTo(w/2,h/2+r);c.stroke();for(let i=-5;i<=5;i++){c.beginPath();c.moveTo(w/2+i*r/6,h/2-5);c.lineTo(w/2+i*r/6,h/2+5);c.stroke()}c.strokeStyle='#111';c.lineWidth=8;c.beginPath();c.arc(w/2,h/2,r,0,TAU);c.stroke()}
function sonarScreen(w,h,tm,blobs){wash(w,h,[[0,'#020c08'],[1,'#000']]);const r=Math.min(w,h)*.4,cx=w/2,cy=h/2;circle(cx,cy,r,'#031a10','#2a6a40',2);c.strokeStyle='rgba(70,200,120,.25)';c.lineWidth=1;for(let i=1;i<4;i++){c.beginPath();c.arc(cx,cy,r*i/4,0,TAU);c.stroke()}c.beginPath();c.moveTo(cx-r,cy);c.lineTo(cx+r,cy);c.moveTo(cx,cy-r);c.lineTo(cx,cy+r);c.stroke();
 const a=tm*1.4;c.save();c.globalCompositeOperation='screen';for(let k=0;k<20;k++){c.strokeStyle=`rgba(120,255,160,${.5*(1-k/20)})`;c.beginPath();c.moveTo(cx,cy);c.lineTo(cx+Math.cos(a-k*.03)*r,cy+Math.sin(a-k*.03)*r);c.stroke()}
 for(const [bx,by,br] of blobs){const ang=Math.atan2(by,bx),f=((a-ang)%TAU+TAU)%TAU,al=clamp(1-f/3.5,0,1);c.globalAlpha=al;ell(cx+bx*r,cy+by*r,br*r,br*r*.7,'rgba(150,255,180,.8)')}c.globalAlpha=1;c.restore()}
const SCENES_MORE={
 meridian_last(w,h,tm){deep(w,h,tm,'#0a2a36','#000306');const u=U(w,h),y=h*.35+tm*8*u;subAt(SUB_BY_ID.virginia,w*.5,y,.35+tm*.01,Math.min(w,h)/150,clamp(1-tm/14,.3,1));if(Math.floor(tm*1.5)%2){c.save();c.globalCompositeOperation='screen';glow(w*.48,y-30*u,80*u,'rgba(255,60,40,.6)');c.restore()}bubs(w*.5,y-20*u,tm,24,60*u);motes(w,h,tm,'#9fd8cf',50)},
 pier_night(w,h,tm){const u=U(w,h),sy=h*.6;sky(w,h,sy,'#030812','#0a1a2c','#1a2a3a');stars(w,h,sy);sea(w,h,sy,'#0a1c26','#020608');c.fillStyle='#14181c';c.fillRect(w*.55,sy-14*u,w*.45,16*u);for(let i=0;i<5;i++){const px=w*.6+i*w*.08;c.fillRect(px,sy-80*u,3*u,80*u);c.save();c.globalCompositeOperation='screen';glow(px,sy-80*u,40*u,'rgba(255,220,150,.5)');c.restore()}
  subAt(SUB_BY_ID.gato,w*.36,sy+2*u,0,Math.min(w,h)/220);c.fillStyle='#05070a';c.fillRect(w*.7,sy-58*u,10*u,44*u);ell(w*.7+5*u,sy-64*u,6*u,7*u,'#05070a');path([[w*.7-6*u,sy-14*u],[w*.7+16*u,sy-14*u],[w*.7+12*u,sy-50*u],[w*.7-2*u,sy-50*u]],'#05070a')},
 drydock(w,h,tm){drydock(w,h,tm,SUB_BY_ID.gato)},
 hale(w,h,tm){wash(w,h,[[0,'#13222a'],[1,'#060c10']]);const u=U(w,h);c.fillStyle='#24384a';c.fillRect(w*.08,h*.12,w*.3,h*.44);c.save();c.globalCompositeOperation='screen';glow(w*.23,h*.3,w*.3,'rgba(160,200,230,.25)');c.restore();c.strokeStyle='#0b1218';c.lineWidth=5*u;c.strokeRect(w*.08,h*.12,w*.3,h*.44);c.beginPath();c.moveTo(w*.23,h*.12);c.lineTo(w*.23,h*.56);c.stroke();
  c.fillStyle='#2a3a2e';c.fillRect(w*.62,h*.18,w*.3,h*.3);c.strokeStyle='#ecc69b';c.setLineDash([6,5]);c.beginPath();c.moveTo(w*.65,h*.4);c.quadraticCurveTo(w*.75,h*.22,w*.88,h*.3);c.stroke();c.setLineDash([]);drawBust('HALE',w*.3,h*.86,h*.6,tm,typer.i<typer.text.length)},
 juno(w,h,tm){wash(w,h,[[0,'#1c1612'],[1,'#080605']]);const u=U(w,h);c.strokeStyle='#3a2e24';c.lineWidth=8*u;for(const y of [h*.2,h*.3]){c.beginPath();c.moveTo(0,y);c.lineTo(w,y);c.stroke()}for(let i=0;i<6;i++){c.fillStyle='#2e2620';c.fillRect(w*.05+i*w*.15,h*.36,w*.1,h*.08)}
  for(let i=0;i<20;i++){const a=(tm*1.8+i/20)%1;c.globalAlpha=1-a;circle(w*.82+Math.cos(i*2.1)*a*90*u,h*.5+a*a*120*u,1.6,'#ffd08a')}c.globalAlpha=1;c.save();c.globalCompositeOperation='screen';glow(w*.82,h*.5,40*u*(.7+.3*Math.sin(tm*31)),'rgba(160,210,255,.6)');c.restore();drawBust('JUNO',w*.3,h*.86,h*.6,tm,typer.i<typer.text.length)},
 riggs(w,h,tm){sonarScreen(w,h,tm,[[.4,-.2,.04],[-.3,.35,.03]]);c.fillStyle='rgba(0,0,0,.45)';c.fillRect(0,0,w,h);drawBust('RIGGS',w*.3,h*.86,h*.6,tm,typer.i<typer.text.length)},
 volkov_bridge(w,h,tm){wash(w,h,[[0,'#2a0808'],[1,'#080202']]);const u=U(w,h);c.save();c.globalCompositeOperation='screen';glow(w*.7,h*.25,w*.5,`rgba(255,40,30,${.22+.06*Math.sin(tm*2)})`);c.restore();
  circle(w*.8,h*.3,60*u,'#3a0c0c','#7a1a1a',3);star5(w*.8,h*.3,40*u,'#c8302a');c.fillStyle='#1a0505';c.fillRect(w*.58,0,30*u,h*.62);for(let i=0;i<5;i++){circle(w*.12+i*40*u,h*.3,12*u,'#120404','#5a1a14',2)}drawBust('VOLKOV',w*.3,h*.86,h*.6,tm,typer.i<typer.text.length)},
 you(w,h,tm){SCENES.bridge(w,h,tm);c.fillStyle='rgba(0,0,0,.35)';c.fillRect(0,0,w,h);drawBust('YOU',w*.3,h*.86,h*.6,tm,false)},
 logtape(w,h,tm){wash(w,h,[[0,'#1a1426'],[1,'#07050c']]);const u=U(w,h),cx=w*.5,cy=h*.45;c.fillStyle='#2a2430';c.fillRect(cx-170*u,cy-90*u,340*u,190*u);for(const dx of [-80,80]){c.save();c.translate(cx+dx*u,cy-20*u);c.rotate(tm*(dx<0?2.2:2));circle(0,0,52*u,'#120e18','#6a5a80',2);for(let i=0;i<3;i++){c.rotate(TAU/3);c.fillStyle='#3a3048';c.fillRect(-4*u,8*u,8*u,36*u)}circle(0,0,8*u,'#6a5a80');c.restore()}
  c.strokeStyle='#8a7a6a';c.lineWidth=2;c.beginPath();c.moveTo(cx-80*u,cy+32*u);c.lineTo(cx+80*u,cy+32*u);c.stroke();for(let i=0;i<10;i++){const lv=.5+.5*Math.sin(tm*7+i*.7)*Math.sin(tm*3+i);c.fillStyle=i>7?'#e3785f':'#a6ead5';c.fillRect(cx-60*u+i*12*u,cy+70*u-lv*24*u,8*u,lv*24*u)}
  c.fillStyle='rgba(210,180,255,.08)';c.fillRect(0,0,w,h);c.font=`${Math.round(12*u)}px ui-monospace,monospace`;c.fillStyle='#d8c3f0';c.fillText('VANCE / PERSONAL LOG',cx-160*u,cy-100*u)},
 tender(w,h,tm){const u=U(w,h),sy=h*.58;sky(w,h,sy,'#2a2a4a','#d88a60','#f2c08a');c.save();c.globalCompositeOperation='screen';glow(w*.25,sy,w*.3,'rgba(255,200,140,.4)');c.restore();sea(w,h,sy,'#3a5a6a','#0c2028');
  c.fillStyle='#1a1e24';path([[w*.5,sy],[w*.92,sy],[w*.88,sy+18*u],[w*.54,sy+18*u]],'#1a1e24');c.fillRect(w*.7,sy-50*u,60*u,50*u);c.fillRect(w*.6,sy-30*u,20*u,30*u);c.fillRect(w*.83,sy-70*u,4*u,40*u);
  const rise=clamp(tm/3,0,1);subAt(SUB_BY_ID.gato,w*.3,sy+20*u*(1-rise),0,Math.min(w,h)/230);for(let i=0;i<20;i++){const a=(tm*.8+i/20)%1;c.globalAlpha=(1-a)*rise;circle(w*.3+(hash(i)-.5)*120*u,sy-a*40*u,1.5,'#e8f4f0')}c.globalAlpha=1},
 recorder(w,h,tm){deep(w,h,tm,'#0a2a34','#02090d');const u=U(w,h);seabed(w,h,'#0b2228',h*.72);c.save();c.translate(w*.5,h*.66);c.rotate(-.15);c.fillStyle='#d46a1a';c.fillRect(-80*u,-50*u,160*u,90*u);c.fillStyle='#1a1a1a';for(let i=0;i<8;i++)c.fillRect(-80*u+i*20*u,-50*u,10*u,6*u);c.font=`bold ${Math.round(13*u)}px ui-monospace,monospace`;c.fillStyle='#1a1a1a';c.fillText('FLIGHT RECORDER',-62*u,0);c.fillText('DO NOT OPEN',-46*u,18*u);if(Math.floor(tm*2)%2){circle(60*u,-30*u,5*u,'#ff4a3a');glow(60*u,-30*u,30*u,'rgba(255,60,40,.5)')}c.restore();spot(w*.2,h*.1,.9,h*.9,80*u,.25);motes(w,h,tm,'#a7e0dc',40)},
 periscope(w,h,tm){bigScope(w,h,tm,(w,h,tm)=>{const sy=h*.55;sky(w,h,sy,'#6a8a98','#a8bcbc','#c8d0c8');sea(w,h,sy,'#3a5a64','#1a2c34');c.save();c.translate(w*.5+Math.sin(tm*.3)*20,sy);drawCruiser(0,0,Math.min(w,h)/700,0);c.restore()});c.font=`${Math.round(11*U(w,h))}px ui-monospace,monospace`;c.fillStyle='#a6ead5';c.fillText('BRG 045 / RNG 6400',w*.5+Math.min(w,h)*.2,h*.5+Math.min(w,h)*.3)},
 radio(w,h,tm){wash(w,h,[[0,'#101814'],[1,'#040806']]);const u=U(w,h);for(let i=0;i<4;i++){c.fillStyle='#1c2620';c.fillRect(w*.06+i*w*.23,h*.18,w*.2,h*.5);for(let k=0;k<6;k++)circle(w*.1+i*w*.23+k*14*u,h*.6,4*u,k%2?'#3a4a3a':'#6a8a5a')}
  c.fillStyle='#020a04';c.fillRect(w*.3,h*.24,w*.4,h*.24);c.strokeStyle='#7aff9a';c.lineWidth=2;c.beginPath();for(let x=0;x<=w*.4;x+=3){const v=Math.sin(x*.08+tm*9)*Math.sin(x*.013+tm*2)*h*.08*(.4+.6*Math.abs(Math.sin(tm*1.3)));x?c.lineTo(w*.3+x,h*.36+v):c.moveTo(w*.3,h*.36+v)}c.stroke();
  if(Math.floor(tm*3)%2)circle(w*.8,h*.22,6*u,'#ff4a3a');c.font=`${Math.round(12*u)}px ui-monospace,monospace`;c.fillStyle='#e3785f';c.fillText('INTERCEPT / 4.7 MHZ / RUSSIAN',w*.3,h*.2)},
 grozny_sink(w,h,tm){const u=U(w,h),sy=h*.55;sky(w,h,sy,'#3a3a44','#8a6a5a','#b07a5a');sea(w,h,sy,'#2a3c44','#0a141a');const k=Math.min(w,h)/360,s=clamp(tm/10,0,1);
  for(const [side,dx] of [[-1,-30],[1,30]]){c.save();c.beginPath();c.rect(0,0,w,sy+4*u);c.clip();c.translate(w*.5+dx*u*(1+s*2),sy+s*60*u);c.rotate(side*(.12+s*.35));c.save();c.beginPath();side<0?c.rect(-400,-300,400,600):c.rect(0,-300,400,600);c.clip();drawCruiser(0,0,k,0);c.restore();c.restore()}
  flames(w*.47,sy-20*u,tm,30*u);flames(w*.55,sy-10*u,tm,24*u);smoke(w*.5,sy-40*u,tm,40*u);bubs(w*.5,sy+30*u,tm,30,80*u,'#e8f4f0')},
 drone_launch(w,h,tm){const u=U(w,h),sy=h*.62;sky(w,h,sy,'#3c4a7a','#e8a070','#f4c890');sea(w,h,sy,'#2a5868','#0a2028');subAt(campBoat(),w*.45,sy+3*u,0,Math.min(w,h)/220);const lift=clamp(tm/4,0,1),dx=w*.45+lift*lift*w*.25,dy=sy-30*u-lift*h*.32;c.save();c.translate(dx,dy);c.scale(3*u,3*u);ufo(0,0,-lift*100,true);c.restore();for(let i=0;i<10;i++){const a=(tm*2+i/10)%1;c.globalAlpha=(1-a)*(1-lift);circle(w*.45+(hash(i)-.5)*60*u,sy-a*10*u,1.5,'#fff')}c.globalAlpha=1},
 gulls(w,h,tm){const u=U(w,h),sy=h*.8;sky(w,h,sy,'#4a6a9a','#a8c0d0','#e0e8e8');sea(w,h,sy,'#3a6a7a','#1a3a48');for(let i=0;i<14;i++){const x=w-((tm*(60+hash(i)*40)*u+i*90*u)%(w+200)),y=h*(.2+hash(i+3)*.45),f=Math.sin(tm*9+i)*8*u,s=(1+hash(i)*1.5)*u;c.strokeStyle='#f4f6f8';c.lineWidth=3*s;c.beginPath();c.moveTo(x-16*s,y-f);c.quadraticCurveTo(x-6*s,y-6*s,x,y);c.quadraticCurveTo(x+6*s,y-6*s,x+16*s,y-f);c.stroke()}c.save();c.translate(w*.3+Math.sin(tm)*20,h*.4+Math.sin(tm*1.7)*30*u);c.scale(3*u,3*u);ufo(0,0,Math.cos(tm*1.7)*200,true);c.restore()},
 graveyard(w,h,tm){deep(w,h,tm,'#0a2630','#02080b',.03);const u=U(w,h);for(let layer=0;layer<3;layer++){const k=(.5+layer*.3)*u,y=h*(.6+layer*.1),a=.3+layer*.3;for(let i=0;i<4;i++){c.save();c.globalAlpha=a;c.translate(((i*w*.32+layer*80*u-tm*(4+layer*3)*u)%(w+300))-100,y);c.rotate((hash(i+layer)-.5)*.4);c.scale(k*2,k*2);path([[-90,-4],[60,-10],[80,-2],[60,8],[-80,8]],'#0e2228');c.fillStyle='#0e2228';c.fillRect(-10,-40,4,36);c.restore()}}c.globalAlpha=1;seabed(w,h,'#051216',h*.86);motes(w,h,tm,'#a7e0dc',80)},
 sonar(w,h,tm){sonarScreen(w,h,tm,[[.3,-.2,.05],[-.4,.3,.03],[.1,.5,.03]])},
 sonar_big(w,h,tm){sonarScreen(w,h,tm,[[.25,.2,.32+.03*Math.sin(tm*2)],[-.5,-.4,.03]])},
 tentacles(w,h,tm){deep(w,h,tm,'#0e0a18','#030206',0);const u=U(w,h);subAt(campBoat(),w*.5,h*.5,0,Math.min(w,h)/170);for(let i=0;i<5;i++){const pts=[],side=i%2?-1:1;for(let j=0;j<=16;j++){const s=j/16,a=s*Math.PI*1.4*clamp(tm/3,0,1)+i;pts.push([w*(.25+i*.12)+Math.sin(a)*40*u*s,h*(side>0?1.1:-.1)-side*s*h*.55+Math.cos(a)*30*u*s,22*u*(1-.75*s)])}drawLimb(pts,'#5a1f2e','#2a0c14','#c4797d55')}motes(w,h,tm,'#d0a0b0',30)},
 octo_retreat(w,h,tm){wash(w,h,[[0,'#0c0a14'],[1,'#030206']]);rocks(w,h,true,'#0e1418');rocks(w,h,false,'#0e1418');const s=clamp(1-tm/8,.25,1);drawOcto(w*(.6+tm*.01),h*.55,U(w,h)*.9*s,[.5,0],0,s);for(let i=0;i<6;i++){const r=(60+tm*20)*U(w,h)*(1+hash(i)),g=c.createRadialGradient(w*.4+i*20,h*.55,0,w*.4+i*20,h*.55,r);g.addColorStop(0,'rgba(2,2,8,.8)');g.addColorStop(1,'rgba(2,2,8,0)');c.fillStyle=g;c.fillRect(0,0,w,h)}},
 divesuit(w,h,tm){deep(w,h,tm,'#0c2a30','#02080a');const u=U(w,h);seabed(w,h,'#0a2026',h*.72);c.save();c.translate(w*.48,h*.66);c.rotate(.2);circle(0,0,60*u,'#8a6a3a','#3a2a14',3);circle(0,-6*u,28*u,'#0c1a20','#b89a5a',4);for(const a of [0,2.1,4.2])circle(Math.cos(a)*44*u,Math.sin(a)*44*u,9*u,'#a8884a');c.fillStyle='#d8d8d8';c.fillRect(-30*u,40*u,60*u,14*u);c.font=`bold ${Math.round(9*u)}px ui-monospace,monospace`;c.fillStyle='#1a2a3a';c.fillText('MERIDIAN',-26*u,51*u);c.restore();spot(w*.15,h*.15,.75,h,90*u,.28);motes(w,h,tm,'#a7e0dc',50)},
 stream(w,h,tm){deep(w,h,tm,'#0b3a4a','#031218',.05);const u=U(w,h);c.save();c.globalCompositeOperation='screen';for(let k=0;k<9;k++){c.strokeStyle=`rgba(160,240,255,${.12+.05*Math.sin(k)})`;c.lineWidth=2;c.beginPath();for(let x=-((tm*400)%120);x<w;x+=120){const y=h*(.3+k*.05);c.moveTo(x,y);c.lineTo(x+70,y)}c.stroke()}c.restore();
  subAt(campBoat(),w*.38+Math.sin(tm*.8)*20*u,h*.48,0,Math.min(w,h)/230);subAt(SUB_BY_ID.akula,w*.66+Math.sin(tm*.6+1)*30*u,h*.62,0,Math.min(w,h)/220);star5(w*.66-10*u,h*.62-26*u,5*u,'#d0392b')},
 limpet(w,h,tm){deep(w,h,tm,'#14202a','#04080c',0);const u=U(w,h),k=Math.min(w,h)/220;subAt(SUB_BY_ID.akula,w*.75-tm*6*u,h*.32,0,k*.8);const a=clamp(tm/5,0,1),mx=mix(w*.7,w*.42,a),my=mix(h*.38,h*.55,a);subAt(campBoat(),w*.38,h*.62,0,k);c.save();c.translate(mx,my);path([[-8*u,-6*u],[8*u,-6*u],[10*u,6*u],[-10*u,6*u]],'#3a3a3a','#000',1);if(Math.floor(tm*4)%2){circle(0,-8*u,3*u,'#ff3a2a');glow(0,-8*u,22*u,'rgba(255,60,40,.6)')}c.restore()},
 flood(w,h,tm){wash(w,h,[[0,'#2a0a0a'],[1,'#080202']]);const u=U(w,h);for(let i=0;i<4;i++){circle(w*(.2+i*.2),h*.38,40*u,'#1a0a08','#6a3a30',4);circle(w*(.2+i*.2),h*.38,26*u,'#050202')}const lvl=h*(.95-.35*clamp(tm/8,0,1)),g=c.createLinearGradient(0,lvl,0,h);g.addColorStop(0,'rgba(80,140,170,.75)');g.addColorStop(1,'rgba(10,40,60,.95)');c.fillStyle=g;c.beginPath();c.moveTo(0,h);for(let x=0;x<=w;x+=10)c.lineTo(x,lvl+Math.sin(x*.03+tm*4)*6*u);c.lineTo(w,h);c.fill();
  c.strokeStyle='rgba(200,230,255,.55)';c.lineWidth=3;for(let i=0;i<5;i++){const x=w*(.15+i*.18);c.beginPath();c.moveTo(x,h*.1);c.quadraticCurveTo(x+18*u,h*.3,x+6*u+Math.sin(tm*9+i)*5,lvl);c.stroke()}if(Math.sin(tm*6)>0){c.fillStyle='rgba(255,20,10,.18)';c.fillRect(0,0,w,h)}},
 sunken_subs(w,h,tm){deep(w,h,tm,'#0a2630','#02080b',.03);const u=U(w,h),k=Math.min(w,h)/230;seabed(w,h,'#0a2026',h*.74);c.save();c.filter='brightness(.5) saturate(.4)';subAt(SUB_BY_ID.gato,w*.3,h*.7,.25,k);subAt(SUB_BY_ID.type212,w*.72,h*.73,-.18,k);c.restore();const dx=w*.5+Math.sin(tm*.7)*w*.2;spot(dx,h*.4,1.35,h*.4,40*u,.35);path([[dx-10*u,h*.4-6*u],[dx+10*u,h*.4-6*u],[dx+11*u,h*.4+6*u],[dx-11*u,h*.4+6*u]],'#e2b64a','#3a2a08');motes(w,h,tm,'#a7e0dc',40)},
 weld(w,h,tm){wash(w,h,[[0,'#1a1e22'],[1,'#07090b']]);const u=U(w,h);c.fillStyle='#3a4248';c.fillRect(0,h*.2,w,h*.6);for(let i=0;i<12;i++){c.strokeStyle='#2a3036';c.lineWidth=2;c.beginPath();c.moveTo(i*w/12,h*.2);c.lineTo(i*w/12,h*.8);c.stroke();for(let j=0;j<6;j++)circle(i*w/12+8,h*.25+j*h*.1,2.5*u,'#5a646a')}
  const x=w*(.3+.4*((tm*.05)%1)),y=h*.5;c.strokeStyle='#ffb070';c.lineWidth=3*u;c.beginPath();c.moveTo(w*.3,y);c.lineTo(x,y);c.stroke();c.save();c.globalCompositeOperation='screen';glow(x,y,90*u*(.7+.3*Math.sin(tm*40)),'rgba(170,220,255,.9)');c.restore();for(let i=0;i<40;i++){const a=(tm*2.5+i/40)%1;c.globalAlpha=1-a;circle(x+Math.cos(i*2.4)*a*140*u,y+Math.sin(i*1.7)*a*60*u+a*a*120*u,2,'#ffd08a')}c.globalAlpha=1},
 tubes(w,h,tm){deep(w,h,tm,'#2a0e10','#060203',0);const u=U(w,h),cx=w*.5,cy=h*.5,R=Math.min(w,h)*.38;ell(cx,cy,R,R*.9,'#2a3438');ell(cx,cy,R*.92,R*.82,'#344046');for(let i=0;i<6;i++){const a=i/6*TAU+.5,x=cx+Math.cos(a)*R*.5,y=cy+Math.sin(a)*R*.45,o=clamp((tm-i*.4)/1.2,0,1);circle(x,y,R*.15,'#0a0c0e');c.save();c.translate(x,y);c.rotate(o*1.6);c.fillStyle='#4a565c';c.fillRect(-R*.15,-R*.15,R*.3*(1-o),R*.3);c.restore()}star5(cx,cy-R*.62,R*.08,'#d0392b');bubs(cx,cy,tm,20,R*.3)},
 vepr_surface(w,h,tm){const u=U(w,h),sy=h*.56;sky(w,h,sy,'#2a2a3a','#7a5a5a','#a07060');sea(w,h,sy,'#1e2c34','#06100c');c.save();c.globalCompositeOperation='screen';for(let i=0;i<6;i++){const g=c.createLinearGradient(w*.2,0,w*.9,0);g.addColorStop(0,'rgba(120,60,160,0)');g.addColorStop(.5,`rgba(${80+i*20},${60+i*25},160,.12)`);g.addColorStop(1,'rgba(60,160,120,0)');c.fillStyle=g;c.fillRect(w*.15,sy+i*6*u,w*.75,5*u)}c.restore();
  c.save();c.beginPath();c.rect(0,0,w,sy+6*u);c.clip();subAt(SUB_BY_ID.akula,w*.55,sy+8*u,.08,Math.min(w,h)/200);c.restore();smoke(w*.6,sy-30*u,tm,30*u);for(let i=0;i<4;i++){c.fillStyle='#0a0a0a';c.fillRect(w*(.5+i*.03),sy-36*u,3*u,10*u)}},
 akula_wreck(w,h,tm){deep(w,h,tm,'#0a2228','#020608',.03);const u=U(w,h);seabed(w,h,'#0a1c22',h*.74);c.save();c.filter='brightness(.45) saturate(.3) sepia(.3)';subAt(SUB_BY_ID.akula,w*.5,h*.66,-.35,Math.min(w,h)/170);c.restore();star5(w*.48,h*.52,6*u,'#6a1a16');spot(w*.1,h*.1,.7,h,100*u,.22);spot(w*.9,h*.15,2.3,h,100*u,.18);motes(w,h,tm,'#a7e0dc',60)},
 radar_island(w,h,tm){const u=U(w,h),sy=h*.68;sky(w,h,sy,'#0c1020','#2a2a44','#4a3a4a');stars(w,h,sy,60);sea(w,h,sy,'#0c1820','#020608');c.fillStyle='#0a0c10';c.beginPath();c.moveTo(w*.1,sy);for(let x=w*.1;x<=w*.75;x+=10)c.lineTo(x,sy-Math.sin((x-w*.1)/(w*.65)*Math.PI)*h*.26);c.lineTo(w*.75,sy);c.fill();
  for(const [x,hh] of [[.32,.42],[.5,.46]]){c.strokeStyle='#0a0c10';c.lineWidth=3*u;c.beginPath();c.moveTo(w*x,sy-h*.2);c.lineTo(w*x,sy-h*hh);c.stroke();c.save();c.translate(w*x,sy-h*hh);c.rotate(tm*1.2+x*9);c.fillStyle='#0a0c10';c.fillRect(-20*u,-4*u,40*u,8*u);c.restore()}
  spot(w*.4,sy-h*.22,-1.9+Math.sin(tm*.7)*.5,h*.8,30*u,.25);spot(w*.55,sy-h*.2,-1.2+Math.sin(tm*.9+2)*.5,h*.8,30*u,.25);
  for(let i=0;i<8;i++){const a=(tm*.6+i/8)%1,x=w*(.2+hash(i)*.7),y=h*(.1+hash(i+3)*.35);if(a<.15){c.globalAlpha=1;circle(x,y,6*u,'#ffd08a');glow(x,y,30*u,'rgba(255,180,90,.6)')}else{c.globalAlpha=.6*(1-a);circle(x,y,(10+a*30)*u,'#14181c')}}c.globalAlpha=1;c.save();c.translate(w*.7,h*.3);c.scale(2.5*u,2.5*u);ufo(0,0,Math.sin(tm*2)*200,true);c.restore()},
 gate(w,h,tm){wash(w,h,[[0,'#06151a'],[1,'#000']]);const u=U(w,h);for(const side of [-1,1]){c.fillStyle='#081418';c.beginPath();const x0=w*.5+side*w*.12;c.moveTo(side<0?0:w,0);for(let y=0;y<=h;y+=20)c.lineTo(x0+side*(Math.sin(y*.02)*30*u+Math.sin(y*.07)*10*u),y);c.lineTo(side<0?0:w,h);c.fill()}
  const g=c.createLinearGradient(w*.38,0,w*.62,0);g.addColorStop(0,'rgba(0,0,0,.4)');g.addColorStop(.5,'#000');g.addColorStop(1,'rgba(0,0,0,.4)');c.fillStyle=g;c.fillRect(w*.38,0,w*.24,h);
  if(tm>2&&Math.sin(tm*.9)>.6){ell(w*.5,h*.62,10*u,3*u,'rgba(255,220,90,.7)')}subAt(campBoat(),w*.24,h*.3,.06,Math.min(w,h)/400);spot(w*.24+20*u,h*.3,.3,w*.3,30*u,.25)},
 kraken_shadow(w,h,tm){deep(w,h,tm,'#0a2a34','#010406',.04);const u=U(w,h);subAt(campBoat(),w*.5,h*.28,0,Math.min(w,h)/260);c.save();c.globalAlpha=.85;c.translate(w*(1.2-tm*.06),h*.78);c.scale(2.2*u,1.3*u);ell(0,0,320,90,'#020608');for(let i=0;i<6;i++){c.fillStyle='#020608';c.beginPath();c.ellipse(-280-i*30,Math.sin(tm+i)*20,140,14,.1*i,0,TAU);c.fill()}c.restore();if(Math.sin(tm*.7)>.7)ell(w*(1.2-tm*.06)-200*u,h*.76,8*u,4*u,'rgba(255,220,90,.8)')},
 kraken_eye(w,h,tm){wash(w,h,[[0,'#04100f'],[1,'#000']]);const u=U(w,h),R=Math.min(w,h)*.34,open=clamp((tm-.6)/1.5,0,1),cx=w/2,cy=h/2;ell(cx,cy,R*1.5,R*1.15,'#0c2826');for(let i=0;i<20;i++){const a=i/20*TAU;glow(cx+Math.cos(a)*R*1.3,cy+Math.sin(a)*R,10*u,'rgba(120,255,220,.3)')}
  const g=c.createRadialGradient(cx,cy,R*.1,cx,cy,R);g.addColorStop(0,'#fff6b0');g.addColorStop(.5,'#f0c030');g.addColorStop(1,'#6a3a06');circle(cx,cy,R,g);c.save();c.translate(cx+Math.sin(tm*.5)*R*.15,cy);ell(0,0,R*.16,R*.75,'#0a0602');c.restore();
  const lid=1-open;if(lid>.01){c.save();c.beginPath();c.arc(cx,cy,R*1.02,0,TAU);c.clip();c.fillStyle='#1c3a36';c.fillRect(cx-R*1.1,cy-R*1.1,R*2.2,R*1.1*lid);c.fillRect(cx-R*1.1,cy+R*1.1-R*1.1*lid,R*2.2,R*1.1*lid);c.restore()}c.save();c.globalCompositeOperation='screen';glow(cx,cy,R*2,`rgba(255,220,90,${.2*open})`);c.restore()},
 kraken_lair(w,h,tm){wash(w,h,[[0,'#06100e'],[1,'#000']]);const u=U(w,h);rocks(w,h,true,'#0a1412');rocks(w,h,false,'#0a1412');c.save();c.globalCompositeOperation='screen';glow(w*.7,h*.58,140*u*(.8+.2*Math.sin(tm*2)),'rgba(255,130,50,.55)');c.restore();
  for(let i=0;i<4;i++){const pts=[];for(let j=0;j<=14;j++){const s=j/14;pts.push([w*(.45+i*.13)+Math.sin(s*4+tm+i)*30*u,h*.9-s*h*.45+Math.cos(s*3+tm*.8)*20*u,26*u*(1-.7*s)])}drawLimb(pts,'#173a3a','#071a1c','#7fd6c033')}c.save();c.filter='brightness(.4)';subAt(SUB_BY_ID.virginia,w*.25,h*.8,.3,Math.min(w,h)/260);c.restore();for(let i=0;i<6;i++)ell(w*(.1+i*.13),h*.86,14*u,4*u,'#c8c0a8')},
 kraken_sink(w,h,tm){deep(w,h,tm,'#06181a','#000',0);const s=clamp(tm/8,0,1);drawKraken(w*.6,h*(.55+s*.45),U(w,h)*1.2*(1-s*.4),clamp(1-tm/3,0,1),[0,-.5],0,1-s*.6);subAt(campBoat(),w*.2,h*.22,0,Math.min(w,h)/380);motes(w,h,tm,'#7fd6c0',40)},
 kraken_chase(w,h,tm){deep(w,h,tm,'#06181a','#010405',0);const u=U(w,h);subAt(campBoat(),w*.68+Math.sin(tm*2)*8*u,h*.45,Math.sin(tm*1.4)*.05,Math.min(w,h)/220);for(let i=0;i<4;i++){const pts=[],reach=w*(.35+.15*Math.sin(tm*1.5+i));for(let j=0;j<=16;j++){const s=j/16;pts.push([-40*u+s*reach,h*(.2+i*.2)+Math.sin(s*5+tm*3+i)*30*u,30*u*(1-.75*s)])}drawLimb(pts,'#1d4a46','#0a1f1d','#8fe0c855')}for(let i=0;i<30;i++){const a=(tm+i/30)%1;c.globalAlpha=.3*(1-a);circle(w*.6-a*w*.5,h*.45+(hash(i)-.5)*40*u,2,null,'#b2dacf')}c.globalAlpha=1},
 sweep(w,h,tm){deep(w,h,tm,'#06181a','#010405',0);const u=U(w,h),y=h*.5,p=.5+.5*Math.sin(tm*12);c.fillStyle=`rgba(255,40,30,${.12+.1*p})`;c.fillRect(0,y-50*u,w,100*u);const reach=clamp((tm-1.4)/.6,0,1);if(reach>0){const pts=[];for(let j=0;j<=18;j++){const s=j/18;pts.push([w*1.05-s*w*1.1*reach,y+Math.sin(s*6+tm*5)*14*u*s,46*u*(1-.7*s)])}drawLimb(pts,'#1d4a46','#0a1f1d','#8fe0c855')}subAt(campBoat(),w*.3,h*.24,-.1,Math.min(w,h)/300)},
 meridian_debris(w,h,tm){deep(w,h,tm,'#0a1e26','#010406',.03);const u=U(w,h);seabed(w,h,'#08181c',h*.76);c.save();c.filter='brightness(.5) saturate(.4)';subAt(SUB_BY_ID.virginia,w*.3,h*.72,.4,Math.min(w,h)/240);c.restore();for(let i=0;i<7;i++){c.save();c.translate(w*(.45+hash(i)*.5),h*(.72+hash(i+2)*.1));c.rotate(hash(i+5)*3);c.fillStyle='#1a2a2e';c.fillRect(-30*u*hash(i+1)-10*u,-6*u,40*u*hash(i+1)+20*u,12*u);c.restore()}
  c.save();c.translate(w*.62,h*.66);c.rotate(-.1);c.fillStyle='#24363c';c.fillRect(-90*u,-26*u,180*u,52*u);c.font=`bold ${Math.round(22*u)}px ui-monospace,monospace`;c.fillStyle='#b9c7b4aa';c.fillText('MERIDIAN',-62*u,8*u);c.restore();spot(w*.5,0,1.57,h*.9,120*u,.15);motes(w,h,tm,'#a7e0dc',50)},
 core_found(w,h,tm){deep(w,h,tm,'#0e0c0a','#020101',0);const u=U(w,h);c.fillStyle='#14100c';c.fillRect(0,0,w,h);c.save();c.beginPath();c.ellipse(w*.5,h*.5,w*.28,h*.3,.2,0,TAU);c.clip();SCENES.core(w,h,tm);c.restore();c.strokeStyle='#3a2a1a';c.lineWidth=10*u;c.beginPath();c.ellipse(w*.5,h*.5,w*.28,h*.3,.2,0,TAU);c.stroke();const dx=w*(.1+clamp(tm/6,0,1)*.25);path([[dx-12*u,h*.62-7*u],[dx+12*u,h*.62-7*u],[dx+13*u,h*.62+7*u],[dx-13*u,h*.62+7*u]],'#e2b64a','#3a2a08');spot(dx,h*.62,0,w*.3,40*u,.35)},
 wolfpack(w,h,tm){const u=U(w,h);wash(w,h,[[0,'#4a8a94'],[.15,'#1a5a68'],[1,'#03141e']]);rays(w,h,tm,.07);for(let i=0;i<3;i++){c.save();c.translate(w*(.2+i*.32)+Math.sin(tm*.3+i)*20*u,h*.17);c.scale(Math.min(w,h)/900,-Math.min(w,h)/900);c.fillStyle='#061418';c.beginPath();c.moveTo(-180,10);c.lineTo(160,10);c.lineTo(140,-30);c.quadraticCurveTo(0,-50,-150,-30);c.closePath();c.fill();c.restore()}
  for(let i=0;i<9;i++){const a=((tm*.3+i*.11)%1),x=w*(.15+hash(i)*.7),y=h*.14+a*h*.75;c.save();c.translate(x,y);c.rotate(tm*2+i);path([[-5*u,-8*u],[5*u,-8*u],[6*u,8*u],[-6*u,8*u]],'#0a1a20');c.restore()}subAt(campBoat(),w*.5,h*.78,0,Math.min(w,h)/300)},
 typhoon_turn(w,h,tm){deep(w,h,tm,'#1a0a0c','#030102',0);const k=Math.min(w,h)/120*(1+tm*.03);subAt(SUB_BY_ID.typhoon,w*.5,h*.55,-.06,k);star5(w*.5-10*k,h*.55-26*k,4*k,'#d0392b');c.save();c.globalCompositeOperation='screen';glow(w*.5+60*k,h*.55,120*k,'rgba(255,60,40,.18)');c.restore();motes(w,h,tm,'#ff9a8a',40)},
 typhoon_shield(w,h,tm){SCENES.typhoon(w,h,tm);const u=U(w,h);c.save();c.globalCompositeOperation='screen';c.strokeStyle=`rgba(160,220,255,${.5+.2*Math.sin(tm*5)})`;c.lineWidth=3;c.beginPath();c.ellipse(w*.55,h*.5,w*.36,h*.2,0,0,TAU);c.stroke();glow(w*.55,h*.5,w*.4,'rgba(120,190,255,.14)');c.restore()},
 ram(w,h,tm){deep(w,h,tm,'#2a0606','#050101',0);const k=Math.min(w,h)/(180-Math.min(tm,4)*25);subAt(SUB_BY_ID.typhoon,w*.5,h*.5,0,k);c.save();c.globalCompositeOperation='screen';glow(w*.5+50*k,h*.5,90*k,`rgba(255,40,20,${.3+.2*Math.sin(tm*14)})`);c.restore();for(let i=0;i<40;i++){const a=(tm*1.5+i/40)%1;c.globalAlpha=a*.6;c.strokeStyle='#e8a0a0';c.beginPath();const ang=hash(i)*TAU;c.moveTo(w/2+Math.cos(ang)*a*w*.6,h/2+Math.sin(ang)*a*h*.6);c.lineTo(w/2+Math.cos(ang)*(a*w*.6+30),h/2+Math.sin(ang)*(a*h*.6+30));c.stroke()}c.globalAlpha=1},
 typhoon_surface(w,h,tm){const u=U(w,h),sy=h*.6;sky(w,h,sy,'#04060c','#0c1424','#1a2a3a');stars(w,h,sy);sea(w,h,sy,'#0a1820','#020608');c.save();c.beginPath();c.rect(0,0,w,sy+8*u);c.clip();subAt(SUB_BY_ID.typhoon,w*.5,sy+14*u,0,Math.min(w,h)/190);c.restore();const on=[1,1,0,1,0,1,1,1,0,0,1,0][Math.floor(tm*3)%12];if(on){c.save();c.globalCompositeOperation='screen';glow(w*.47,sy-62*u,60*u,'rgba(255,240,200,.85)');c.restore();circle(w*.47,sy-62*u,4*u,'#fffbe8')}for(let i=0;i<6;i++){c.fillStyle='#05070a';c.fillRect(w*(.35+i*.05),sy-30*u,3*u,10*u)}},
 city_lights(w,h,tm){const u=U(w,h),sy=h*.62;sky(w,h,sy,'#05060e','#141a34','#3a2a44');stars(w,h,sy*.6,60);sea(w,h,sy,'#0c1620','#020407');const lit=clamp(tm/6,0,1);for(let i=0;i<40;i++){const bw=(14+hash(i)*30)*u,bh=(30+hash(i+5)*h*.25),x=i*w/40;c.fillStyle='#0a0c14';c.fillRect(x,sy-bh,bw,bh);for(let j=0;j<bh/10;j++)for(let q=0;q<bw/8;q++)if(hash(i*31+j*7+q)<lit*.7){c.fillStyle='#ffd88a';c.fillRect(x+2+q*8*u*.9,sy-bh+4+j*10,3*u,4)}}
  c.save();c.globalCompositeOperation='screen';glow(w*.5,sy,w*.6,`rgba(255,200,120,${.3*lit})`);c.restore();for(let i=0;i<30;i++){if(hash(i+90)>lit)continue;c.globalAlpha=.4;c.fillStyle='#ffd88a';c.fillRect(hash(i)*w,sy+6+hash(i+2)*h*.3,20*u,1.5)}c.globalAlpha=1},
 port_pier(w,h,tm){const u=U(w,h),sy=h*.6;sky(w,h,sy,'#4a4a7a','#f0a888','#ffe0b0');sea(w,h,sy,'#4a7a88','#0e2a36');c.fillStyle='#1b2430';c.fillRect(w*.45,sy-16*u,w*.55,16*u);for(let i=0;i<14;i++){const x=w*(.5+i*.035),hh=(26+hash(i)*10)*u;c.fillStyle=['#2a3a5a','#5a2a2a','#2a4a3a','#4a4a2a'][i%4];c.fillRect(x,sy-16*u-hh,7*u,hh*.7);ell(x+3.5*u,sy-16*u-hh,3.5*u,4*u,'#e2b694');c.save();c.translate(x+3.5*u,sy-16*u-hh*.7);c.rotate(Math.sin(tm*6+i)*.8);c.fillStyle=['#2a3a5a','#5a2a2a','#2a4a3a','#4a4a2a'][i%4];c.fillRect(0,-1.5*u,10*u,3*u);c.restore()}subAt(campBoat(),w*.32,sy+4*u,0,Math.min(w,h)/220);for(let i=0;i<25;i++){const a=(tm*.4+i/25)%1;c.globalAlpha=1-a;c.fillStyle=['#e3785f','#ecc69b','#a6ead5','#9fdcf0'][i%4];c.fillRect(w*(.4+hash(i)*.6),h*a*.6,4*u,6*u)}c.globalAlpha=1},
};
for(const s of SUBS)SCENES_MORE['drydock_'+s.id]=(w,h,tm)=>drydock(w,h,tm,s);
Object.assign(SCENES,SCENES_MORE);
// The chart: the campaign's route with each mission as a marker, lit as far as the sailor has got.
SCENES.map=function(w,h,tm){
 const u=U(w,h);wash(w,h,[[0,'#0e2a2c'],[1,'#04100f']]);c.strokeStyle='rgba(166,234,213,.07)';c.lineWidth=1;for(let x=0;x<w;x+=40){c.beginPath();c.moveTo(x,0);c.lineTo(x,h);c.stroke()}for(let y=0;y<h;y+=40){c.beginPath();c.moveTo(0,y);c.lineTo(w,y);c.stroke()}
 for(let k=0;k<6;k++){const cx=w*(.1+hash(k+20)*.8),cy=h*(.12+hash(k+24)*.7),r=(50+hash(k+28)*80)*u;c.beginPath();for(let i=0;i<=40;i++){const a=i/40*TAU,rr=r*(.7+.3*Math.sin(a*3+k)+.12*Math.sin(a*7+k*2));i?c.lineTo(cx+Math.cos(a)*rr,cy+Math.sin(a)*rr*.7):c.moveTo(cx+Math.cos(a)*rr,cy+Math.sin(a)*rr*.7)}c.closePath();c.fillStyle='#1f3d33';c.fill();c.strokeStyle='#5e8c74';c.stroke()}
 const P=i=>{const s=i/(MISSIONS.length-1);return [w*(.08+.84*s),h*(.72-.42*s)+Math.sin(s*11)*h*.1]},done=Object.keys(camp.data.done).length,prog=clamp(tm/3,0,1);
 c.save();c.setLineDash([7,6]);c.lineDashOffset=-tm*24;c.strokeStyle='#ecc69b88';c.lineWidth=2;c.beginPath();for(let i=0;i<MISSIONS.length;i++){const [x,y]=P(i);i?c.lineTo(x,y):c.moveTo(x,y)}c.stroke();c.restore();
 MISSIONS.forEach((m,i)=>{const [x,y]=P(i),got=i<done,cur=i===Math.min(done,MISSIONS.length-1);if(i>done*prog+1&&!got)c.globalAlpha=.35;circle(x,y,(m.boss?7:4.5)*u,got?'#a6ead5':cur?'#ecc69b':'#3a5a50');if(m.boss)circle(x,y,11*u,null,got?'#a6ead5':'#e3785f',1.4);if(cur&&Math.floor(tm*2)%2)circle(x,y,16*u,null,'#ecc69b',1.5);c.globalAlpha=1});
 c.font=`${Math.round(11*u)}px ui-monospace,monospace`;c.fillStyle='#ecc69b';CHAPTERS.forEach((ch,i)=>{const [x,y]=P(MISSIONS.findIndex(m=>m.ch===i));c.fillText(ch.n+' / '+ch.name,x-10*u,y+26*u)});
 c.save();c.globalCompositeOperation='screen';glow(w*.9,h*.1,w*.4,'rgba(255,220,160,.12)');c.restore();
};

// Foreground silhouettes move faster than the distant scene to establish scale.
function cineDepth(name,w,h,tm){
 if(!/meridian_last|kraken|tentacles|octopus|core_found|trench|retreat|escape/.test(name))return;
 c.save();const chase=/chase|escape/.test(name),speed=chase?140:18;
 for(let i=0;i<18;i++){const layer=1+hash(i+60)*2,x=((hash(i+20)*w-tm*speed*layer)%(w+100)+w+100)%(w+100)-50,y=hash(i+40)*h;
 c.globalAlpha=.12+layer*.07;c.fillStyle='#8aa9a6';c.beginPath();c.ellipse(x,y,layer*(chase?7:2),layer,0,0,TAU);c.fill()}
 c.globalAlpha=1;const fog=c.createLinearGradient(0,h*.7,0,h);fog.addColorStop(0,'#010a1000');fog.addColorStop(1,'#010a10bb');c.fillStyle=fog;c.fillRect(0,h*.7,w,h*.3);
 if(chase){c.globalAlpha=.65;c.fillStyle='#020b10';for(let i=0;i<5;i++){const x=((i*w/4-tm*95)%(w+200)+w+200)%(w+200)-100;c.beginPath();c.moveTo(x-100,h);c.lineTo(x,h*(.81+hash(i)*.12));c.lineTo(x+110,h);c.fill()}}
 c.restore();
}

// A staged pursuit: the eye emerges, an arm commits, the boat dives beneath it,
// and the creature falls behind. The action has a beginning and an escape beat.
SCENES.kraken_chase=function(w,h,tm){
 deep(w,h,tm,'#082832','#01050b',.025);
 const u=U(w,h),reveal=smooth(0,3,tm),strike=smooth(3,5,tm),escape=smooth(6,10,tm);
 const bx=w*(.62+.2*escape),by=h*(.43+.18*smooth(4,6,tm)-.06*escape);
 drawKraken(w*(-.15+.22*reveal-.22*escape),h*.52,Math.min(w,h)/550,.15+.85*reveal,[1,0],0,.8);
 const pts=[];for(let j=0;j<=22;j++){const f=j/22;pts.push([w*(-.1+f*(.35+.48*strike-.3*escape)),h*.36+Math.sin(f*4+tm)*22*u+f*f*35*u,40*u*(1-.9*f)])}
 drawLimb(pts,'#235352','#0c292f','#91d4bc66');
 subAt(campBoat(),bx,by,.16*(smooth(4,5,tm)-smooth(6,8,tm)),Math.min(w,h)/220);
 bubs(bx-65*u,by,tm,36,65*u);
 spot(bx+55*u,by,0,w*.35,80*u,.16);
 for(let i=0;i<35;i++){const x=((hash(i)*w-tm*(70+hash(i+3)*90))%w+w)%w,y=hash(i+8)*h;c.strokeStyle='#9ddfdc22';c.beginPath();c.moveTo(x,y);c.lineTo(x+12+20*hash(i),y);c.stroke()}
};
