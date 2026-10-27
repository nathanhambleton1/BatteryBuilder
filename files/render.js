'use strict';
/* Drawing helpers. Every asset is rendered in world space using shaded paths,
   with a separate CSS-pixel UI. Raster resolution tracks device pixel ratio. */
function path(points,fill,stroke,width=1){c.beginPath();points.forEach((p,i)=>i?c.lineTo(p[0],p[1]):c.moveTo(p[0],p[1]));c.closePath();if(fill){c.fillStyle=fill;c.fill()}if(stroke){c.strokeStyle=stroke;c.lineWidth=width;c.stroke()}}
function circle(x,y,r,fill,stroke=null,w=1){c.beginPath();c.arc(x,y,r,0,TAU);if(fill){c.fillStyle=fill;c.fill()}if(stroke){c.strokeStyle=stroke;c.lineWidth=w;c.stroke()}}
function glow(x,y,r,color){let g=c.createRadialGradient(x,y,0,x,y,r);g.addColorStop(0,color);g.addColorStop(1,'rgba(0,0,0,0)');c.fillStyle=g;c.fillRect(x-r,y-r,r*2,r*2)}
function drawSky(){
 const surf=scrY(SURFACE),horizon=Math.max(0,surf),twilight=Math.sin(night*Math.PI),far=par(2600),near=par(900);
 if(horizon<=0)return;
 let g=c.createLinearGradient(0,0,0,horizon);g.addColorStop(0,rgb([54,104,118],[5,14,30],night));g.addColorStop(1,rgb([176+twilight*45,188-twilight*35,171-twilight*38],[18,39,54],night));c.fillStyle=g;c.fillRect(0,0,W,horizon);
 for(let i=0;i<75;i++){let x=((hash(i*4)*W+far)%W+W)%W,y=hash(i*4+1)*Math.max(160,surf-15);c.globalAlpha=night*hash(i*4+2)*.8;circle(x,y,.5+hash(i+6)*.8,'#d3e6e9')}c.globalAlpha=1;
 let sunx=W*.76+near,suny=surf-(1-night)*110*scale+night*35*scale;glow(sunx,suny,100*scale,`rgba(255,${Math.round(206-twilight*35)},147,${(1-night)*.23})`);circle(sunx,suny,19*scale,`rgba(255,224,179,${1-night})`);
 if(night>.25){const mx=W*.84+near,my=surf-165*scale;c.globalAlpha=night*.85;circle(mx,my,13*scale,'#d7e4e2');circle(mx-6*scale,my-5*scale,12*scale,'#0d1d30');c.globalAlpha=1;}
 const hp=par(1800);c.fillStyle=`rgba(11,37,48,${.3+night*.3})`;c.beginPath();c.moveTo(0,surf);for(let x=0;x<=W+40;x+=40){const hx=x-hp;c.lineTo(x,surf-(10+14*Math.sin(hx/180)+7*Math.sin(hx/43))*scale)}c.lineTo(W,surf);c.fill();
}
function drawWater(){
 const sy=scrY(SURFACE),deep=terrain(sub.x).cave;let g=c.createLinearGradient(0,sy,0,H);
 g.addColorStop(0,rgb([25,100,114],[5,22,37],night));g.addColorStop(.35,rgb([10,62,78],[3,18,30],night));g.addColorStop(1,rgb([3,24,39],[2,10,19],night));c.fillStyle=g;c.fillRect(0,Math.max(0,sy),W,H);
 c.save();c.beginPath();c.rect(0,Math.max(0,sy),W,H);c.clip();
 if(!reduced){c.globalCompositeOperation='screen';for(let i=0;i<7;i++){let x=((i*300-sub.x*.12-par(400)/scale)%(vw+500)+vw+500)%(vw+500)-250;let a=.025*(1-night)*(1-deep*.85);let gg=c.createLinearGradient(0,sy,0,H*.95);gg.addColorStop(0,`rgba(172,235,215,${a*3})`);gg.addColorStop(1,'#82ddcc00');path([[x*scale,sy],[(x+50)*scale,sy],[(x+360+Math.sin(ambient*.15+i)*50)*scale,H],[(x+160)*scale,H]],gg)}c.globalCompositeOperation='source-over';}
 // Layered distant escarpments move at a different rate from collision terrain.
 for(let layer=0;layer<3;layer++){c.beginPath();c.moveTo(0,H);for(let sx=-30;sx<=W+30;sx+=25){let wx=camX*(.18+layer*.12)+(sx-par(1500-layer*400))/scale;let y=terrain(wx+1900).bottom+120-layer*70+45*Math.sin(wx/(180-layer*30));c.lineTo(sx,scrY(y))}c.lineTo(W,H);c.closePath();c.fillStyle=rgb([[11,49,62],[9,42,55],[6,34,47]][layer],[[5,20,32],[4,18,29],[3,16,25]][layer],night);c.fill();}
 // Suspended marine snow; deterministic particles avoid allocation in the loop.
 for(let i=0;i<100;i++){let px=((hash(i+12)*vw*1.5-sub.x*.14*(.3+hash(i+2))-par(120+hash(i+3)*600)/scale)%vw+vw)%vw,py=((hash(i+45)*vh+ambient*(2+hash(i)*4))%vh);let a=(.07+hash(i+88)*.12)*(1-night*.6);circle(px*scale,py*scale,(.45+hash(i+5)*1.1)*scale,`rgba(167,224,220,${a})`)}
 // Tiny, distant fish schools.
 for(let j=0;j<3;j++){let fx=((j*490+330-sub.x*.25-ambient*12-par(700)/scale)%(vw+500)+vw+500)%(vw+500)-200,fy=210+j*128+Math.sin(ambient*.18+j)*20;for(let i=0;i<7;i++){let xx=(fx+hash(i+j*17)*90)*scale,yy=(fy+hash(i*3+j)*35-camY)*scale;c.globalAlpha=.2*(1-night*.7);c.fillStyle='#9ac6c5';c.beginPath();c.ellipse(xx,yy,4*scale,1.1*scale,0,0,TAU);c.fill();path([[xx+3*scale,yy],[xx+7*scale,yy-2*scale],[xx+7*scale,yy+2*scale]],'#9ac6c5')}}c.globalAlpha=1;c.restore();
}
/* ---- Orbit camera ------------------------------------------------------------
   Play stays on one flat plane (z=0), so collisions never change. The camera
   orbits a vertical axis through the boat (yaw) and looks down from slightly
   above (pitch). An oblique projection keeps the waterline level: depth z
   shifts a point sideways by sin(yaw) and up by cos(yaw)sin(pitch). The backdrop
   slides with depth parallax, rock is a slab with thickness, and the boat is a
   small lit 3D mesh. Positive z points away from the viewer. */
let cam3d=store.get('undertow.cam3d',true)!==false,yaw=0,pitch=0,orbitYaw=0,yawKick=0,shakeX=0,shakeY=0;
// fX/fY is the point the camera follows: the boat, or the campaign's spotter drone.
let cyw=1,syw=0,cpt=1,spt=0,Psx=0,Psy=0,fX=0,fY=0;
function updateCamera(dt){
 if(cr&&cr.expedition)return;
 const turn=(inputKeys.has('KeyD')||inputKeys.has('ArrowRight')?1:0)-(inputKeys.has('KeyA')||inputKeys.has('ArrowLeft')?1:0);
 if(cam3d&&turn)orbitYaw=clamp(orbitYaw+turn*dt*1.2,-.9,.9);else orbitYaw*=Math.exp(-dt*(state==='menu'?.3:.8));
 let ty=0,tp=0;
 if(cam3d){const climb=clamp(sub.v/185,-1,1);
  if(state==='dying'||state==='over'){ty=(reduced?-.35:Math.sin(ambient*.12)*.55-.1);tp=.24}
  else if(state==='menu'){ty=reduced?-.4:Math.sin(ambient*.2)*.75;tp=.2+(reduced?0:Math.sin(ambient*.13)*.06)}
  else{ty=-.22+(reduced?0:.08*Math.sin(ambient*.17)+airFx*.05*Math.sin(ambient*.8))+climb*.07;tp=.1+climb*.05+(surfaced?.05:0)+(reduced?0:airFx*.02*Math.sin(ambient*1.4))}
  // Keep the play field readable mid-dive; the menu showcase swings wider.
  const lim=state==='playing'?.6:.85;ty=clamp(ty+orbitYaw+yawKick,-lim,lim)}
 const k=1-Math.exp(-dt*2.5);yaw=mix(yaw,ty,k);pitch=mix(pitch,tp,k);yawKick*=Math.exp(-dt*3);
}
function toggleCam(){cam3d=!cam3d;store.set('undertow.cam3d',cam3d);$('camBtn').textContent='Camera: '+(cam3d?'3D orbit':'flat');if(state==='playing')toast(cam3d?'ORBIT CAMERA':'FLAT CAMERA',cam3d?'Hold A / D or the arrow keys to swing around the boat.':'Classic side view. Press C to return to 3D.',1.8)}
function camSetup(){cyw=Math.cos(yaw);syw=Math.sin(yaw);cpt=Math.cos(pitch);spt=Math.sin(pitch);Psx=(fX-camX)*scale;Psy=(fY-camY)*scale}
const flat=()=>Math.abs(yaw)<.003&&Math.abs(pitch)<.003;
// Screen position (CSS px) of a world point at depth z.
function proj(x,y,z=0){return [Psx+scale*((x-fX)*cyw+z*syw),Psy+scale*((y-fY)*cpt-z*cyw*spt)]}
// Horizontal screen shift of a backdrop at depth z; screen y of world height y.
const par=z=>z*syw*scale, scrY=y=>Psy+scale*cpt*(y-fY);
function worldTransform(){const k=dpr*scale;c.setTransform(k*cyw,0,0,k*cpt,dpr*Psx-k*cyw*fX,dpr*Psy-k*cpt*fY)}
// Undo the plane's squash locally, so round things stay round.
function billboard(){c.transform(1/cyw,0,0,1/cpt,0,0)}
// Widen camX/vw/camY/vh to the world area the squashed plane shows; returns a restore function.
function widenView(){const saved=[camX,camY,vw,vh];camX=fX-Psx/(scale*cyw);vw=W/(scale*cyw);camY=fY-Psy/(scale*cpt);vh=H/(scale*cpt);return()=>{[camX,camY,vw,vh]=saved}}
function drawSurface(){if(camY>100)return;c.strokeStyle=`rgba(174,220,214,${.23*(1-night*.7)})`;c.lineWidth=1.2;c.beginPath();for(let x=Math.floor(camX/12)*12;x<camX+vw+12;x+=12){let y=68+Math.sin(x*.032+ambient*1.1)*2+Math.sin(x*.076-ambient*.8);x===Math.floor(camX/12)*12?c.moveTo(x,y):c.lineTo(x,y)}c.stroke();for(let i=0;i<18;i++){let x=camX+hash(i+88)*vw;let y=72+hash(i)*18;c.strokeStyle=`rgba(188,217,205,${.1*(1-night)})`;c.beginPath();c.moveTo(x,y);c.lineTo(x+15+hash(i)*70,y);c.stroke()}}
/* A cavern's ceiling is the underside of an island: the rock rises out of the sea
   into the sky, so the surface and sky stay visible above the cave mouth. */
const islandH=(x,k)=>k*(95+40*Math.sin(x/310)+18*Math.sin(x/83));
function islandTop(x){return SURFACE-islandH(x,terrain(x).cave)}
function rockShape(top=false,start=Math.floor(camX/12)*12-24,end=camX+vw+30){c.beginPath();
 if(top){c.moveTo(start,islandTop(start));for(let x=start;x<=end;x+=12)c.lineTo(x,islandTop(x));for(let x=end;x>=start-12;x-=12)c.lineTo(x,terrain(x).top)}
 else{c.moveTo(start,camY+vh+200);for(let x=start;x<=end;x+=12)c.lineTo(x,terrain(x).bottom);c.lineTo(end,camY+vh+200)}
 c.closePath();}
function strokeEdge(fy,color,width){let start=Math.floor(camX/12)*12-24,end=camX+vw+30,on=false;c.beginPath();for(let x=start;x<=end;x+=12){if(terrain(x).cave>.002){const y=fy(x);on?c.lineTo(x,y):c.moveTo(x,y);on=true}else on=false}c.strokeStyle=color;c.lineWidth=width;c.stroke()}
/* Rock is a slab SLAB deep. Under the orbit its far face shifts by (ox, oy) in
   plane units, and the seabed floor, island tops and cliff walls show between. */
const SLAB=260;
function slabBand(edge,start,end,ox,oy,fill,only){let run=[];const flush=()=>{if(run.length>1){c.beginPath();run.forEach((x,i)=>i?c.lineTo(x,edge(x)):c.moveTo(x,edge(x)));for(let i=run.length-1;i>=0;i--)c.lineTo(run[i]+ox,edge(run[i])+oy);c.closePath();c.fillStyle=fill;c.fill()}run=[]};for(let x=start;x<=end;x+=12){if(!only||only(x))run.push(x);else flush()}flush()}
/* ---- 3D seabed ---------------------------------------------------------------
   Behind the play plane the seabed is a lit heightfield, so the orbit camera looks
   across real ground: ridges, rock spires, boulders and kelp, rising into hills or
   canyon walls by biome and fading into the water with distance. Row 0 is exactly
   the collision profile. Rows sit at fixed depths on a world-aligned grid, so the
   landscape stays put as the boat moves. Each depth band is shaded by slope against
   the sun, quantised to TONES colours and batched into one fill per tone, then drawn
   far to near so nearer ground hides what lies behind it. Islands get the same. */
const FDX=16,FROWS=22,FZMAX=950,TONES=12,FZ=Array.from({length:FROWS+1},(_,i)=>FZMAX*(i/FROWS)**1.4);
const IROWS=9,IZ=Array.from({length:IROWS+1},(_,i)=>SLAB*i/IROWS);
const mixc=(a,b,t)=>[mix(a[0],b[0],t),mix(a[1],b[1],t),mix(a[2],b[2],t)],css=a=>`rgb(${a[0]|0},${a[1]|0},${a[2]|0})`;
const lat=(i,j,s)=>hash(i*57.13+j*311.71+s);
// Smooth value noise in -1..1.
function vnoise(x,z,s){const i=Math.floor(x),j=Math.floor(z),u=x-i,v=z-j,a=u*u*(3-2*u),b=v*v*(3-2*v);
 return mix(mix(lat(i,j,s),lat(i+1,j,s),a),mix(lat(i,j+1,s),lat(i+1,j+1,s),a),b)*2-1}
// Sparse rock pinnacles, at most one per 300 x 300 cell, kept away from the play plane.
function spire(x,z){const C=300,i=Math.floor(x/C),j=Math.floor(z/C);if(j<1)return 0;const s=TP.sd+i*13.7+j*91.3;if(hash(s)>.3)return 0;
 const d=Math.hypot(x-(i+.3+.4*hash(s+1))*C,((j+.3+.4*hash(s+2))*C-z)*1.2)/(40+45*hash(s+3));return d<1?(90+150*hash(s+4))*(1-d)**1.25:0}
// Seabed height (y down) at x, depth z; T is terrain(x). Caverns close into a back wall.
function floorY(x,z,T){
 if(z<=0)return T.bottom;
 const w=smooth(0,200,z),s=TP.sd,ridge=1-Math.abs(vnoise(x/290,z/260,s));
 const up=(ridge*ridge*75+vnoise(x/105,z/90,s+7)*22+vnoise(x/38,z/34,s+13)*7)*(.55+.45*T.rough)+z*(.045+.09*T.basin+.04*Math.sin(x/1700+TP.p3))+spire(x,z)*(1-T.cave);
 let y=T.bottom-w*up;
 if(T.cave>0)y=mix(y,T.bottom-w*up*.35-(T.bottom-T.top-12)*smooth(SLAB*.45,SLAB*1.05,z),T.cave);
 return Math.max(y,mix(SURFACE+22,T.top+4,T.cave));
}
// Island top: matches islandTop() at the front and slopes to a far shore at z=SLAB.
function islandY(x,z,T){
 if(T.cave<=0)return SURFACE;const u=z/SLAB,s=TP.sd,arch=Math.sin(Math.PI*u);
 return Math.min(SURFACE,SURFACE-islandH(x,T.cave)*(1+.55*arch*(.6+.4*vnoise(x/220,3.7,s+21)))*(1-u**2.4)-T.cave*arch*(vnoise(x/70,z/60,s+29)*14+vnoise(x/30,z/26,s+31)*5));
}
let fH=new Float32Array(4096),fTone=new Uint8Array(512);const fT=[];
/* Draws one heightfield in plane units: row depths Z, height yAt(x,z,T), band
   palettes pal(i), light scale dim(k,y), column filter only(k), and extras(i,k0,n,a0,a1)
   for things standing in band i. Depth z shifts a point by (z*kx, z*ky). */
function drawField(Z,yAt,pal,dim,kx,ky,only,extras){
 const rows=Z.length,span=Z[rows-1]*kx,k0=Math.floor((camX-Math.max(0,span))/FDX)-2,n=Math.ceil((camX+vw-Math.min(0,span))/FDX)+3-k0;
 if(fH.length<n*rows)fH=new Float32Array(n*rows*2);if(fTone.length<n)fTone=new Uint8Array(n*2);
 for(let k=0;k<n;k++)fT[k]=terrain((k0+k)*FDX);
 for(let i=0;i<rows;i++)for(let k=0;k<n;k++)fH[i*n+k]=yAt((k0+k)*FDX,Z[i],fT[k]);
 for(let i=rows-2;i>=0;i--){
  const z0=Z[i],z1=Z[i+1],dz=z1-z0,P=pal(i),r0=i*n,r1=r0+n;
  const a0=Math.max(0,Math.floor((camX-Math.max(z0*kx,z1*kx))/FDX)-k0-1),a1=Math.min(n-2,Math.ceil((camX+vw-Math.min(z0*kx,z1*kx))/FDX)-k0+1);
  for(let k=a0;k<=a1;k++){
   if(only&&!only(k)){fTone[k]=255;continue}
   // Sun from above, right and in front: s = (.366, -.870, -.331), y down.
   const a=fH[r0+k],hx=(fH[r0+k+1]-a)/FDX,hz=(fH[r1+k]-a)/dz,L=Math.sqrt(hx*hx+1+hz*hz);
   fTone[k]=clamp(Math.round((((.366*hx+.87-.331*hz)/L-.5)/.45+.18*smooth(.93,.99,1/L))*dim(k,a)*(TONES-1)),0,TONES-1);
  }
  // Quads overlap their right and far neighbours slightly so no seams show.
  for(let tone=0;tone<TONES;tone++){let any=false;c.beginPath();
   for(let k=a0;k<=a1;k++){if(fTone[k]!==tone)continue;any=true;const X0=(k0+k)*FDX+z0*kx,X1=X0+dz*kx;
    c.moveTo(X0,fH[r0+k]+z0*ky);c.lineTo(X0+FDX+.8,fH[r0+k+1]+z0*ky);c.lineTo(X1+FDX+.8,fH[r1+k+1]+z1*ky-.8);c.lineTo(X1,fH[r1+k]+z1*ky-.8);c.closePath()}
   if(any){c.fillStyle=P[tone];c.fill()}}
  if(extras)extras(i,k0,n,a0,a1);
 }
}
function drawSeabed(kx,ky){
 const fogC=mixc(mixc([10,56,70],[3,17,29],night),[3,14,22],terrain(sub.x).cave*.6),lo=mixc([9,28,34],[3,11,17],night),hi=mixc([104,138,118],[38,62,66],night),kelp=mixc([40,97,91],[22,62,66],night);
 const fogAt=i=>.9*((FZ[i]+FZ[i+1])/2/FZMAX)**.55,pals=[];
 for(let i=0;i<FROWS;i++){const f=fogAt(i),P=[];for(let j=0;j<TONES;j++)P.push(css(mixc(mixc(lo,hi,j/(TONES-1)),fogC,f)));pals.push(P)}
 // Never draw ground above the waterline: the sky backdrop owns that part of the screen.
 c.save();c.beginPath();c.rect(camX-4000,SURFACE,vw+8000,8000);c.clip();
 drawField(FZ,floorY,i=>pals[i],(k,y)=>clamp(1.45-(y-SURFACE)/800,.35,1.1)*(1-.78*fT[k].cave),kx,ky,null,(i,k0,n,a0,a1)=>{
  if(i<1)return;
  const z0=FZ[i],z1=FZ[i+1],f=fogAt(i),P=pals[i],rocks=[],lights=[];c.beginPath();let weed=false;
  for(let k=a0;k<=a1;k++){const gx=k0+k,h=hash(gx*7.31+i*53.7+TP.sd);if(h>.1)continue;
   const T=fT[k],u=hash(gx*3.17+i*9.71),v=hash(gx*1.93+i*4.37),z=mix(z0,z1,v),r0=i*n+k,r1=r0+n;
   const y=mix(mix(fH[r0],fH[r0+1],u),mix(fH[r1],fH[r1+1],u),v),X=(gx+u)*FDX+z*kx,Y=y+z*ky,rockP=.045+.03*(T.rough-1);
   if(h<rockP)rocks.push(X,Y,(4+12*hash(gx+i*.37))*(.7+.3*T.rough));
   else if(h<rockP+.04){if(y<600&&T.cave<.3){const ht=22+50*hash(gx*.71+i),sw=Math.sin(ambient*.8+gx*.37+i)*ht*.15;weed=true;
    c.moveTo(X,Y);c.quadraticCurveTo(X-4,Y-ht*.55,X+sw,Y-ht);c.moveTo(X+3,Y);c.quadraticCurveTo(X+6,Y-ht*.4,X+3+sw*.8,Y-ht*.7)}}
   else if(h>.093&&night>.25)lights.push(X,Y-2);
  }
  if(weed){c.strokeStyle=css(mixc(kelp,fogC,f));c.lineWidth=1.5;c.stroke()}
  if(rocks.length)for(const lit of [0,1]){c.beginPath();
   for(let j=0;j<rocks.length;j+=3){const x=rocks[j],y=rocks[j+1],r=rocks[j+2],id=x*.13+y*.71,top=y-r*(.75+.5*hash(id));
    if(lit){c.moveTo(x-r*.35,top+r*.2);c.lineTo(x+r*(.1+.2*hash(id+1)),top);c.lineTo(x+r*.8,y-r*.45);c.lineTo(x+r*.2,y-r*.3)}
    else{c.moveTo(x-r,y);c.lineTo(x-r*(.7+.2*hash(id+2)),y-r*.5);c.lineTo(x-r*.35,top+r*.2);c.lineTo(x+r*(.1+.2*hash(id+1)),top);c.lineTo(x+r*.8,y-r*.45);c.lineTo(x+r,y)}
    c.closePath()}
   c.fillStyle=P[lit?9:2];c.fill()}
  for(let j=0;j<lights.length;j+=2){glow(lights[j],lights[j+1],8,`rgba(89,211,193,${(night-.25)*.3*(1-f)})`);circle(lights[j],lights[j+1],1.1,`rgba(140,236,214,${(night-.25)*.9*(1-f)})`)}
 });
 c.restore();
}
function drawIsland(kx,ky){
 const lo=mixc([30,40,40],[8,13,19],night),hi=mixc([150,156,118],[40,52,52],night),haze=mixc([170,184,166],[18,39,54],night),pals=[];
 for(let i=0;i<IROWS;i++){const f=.3*(IZ[i]+IZ[i+1])/2/SLAB,P=[];for(let j=0;j<TONES;j++)P.push(css(mixc(mixc(lo,hi,j/(TONES-1)),haze,f)));pals.push(P)}
 drawField(IZ,islandY,i=>pals[i],()=>1,kx,ky,k=>fT[k].cave>.002||fT[k+1].cave>.002);
}
function drawTerrainDepth(){
 if(flat())return;
 const kx=syw/cyw,ky=-cyw*spt/cpt;drawSeabed(kx,ky);
 const ox=SLAB*kx,oy=SLAB*ky,start=Math.floor((camX-Math.max(0,ox))/12)*12-24,end=camX+vw-Math.min(0,ox)+30;
 if(!caveNear(start,end))return;
 // The cavern ceiling's far face runs from the island's far shore down to the roof.
 c.beginPath();c.moveTo(start+ox,SURFACE+oy);for(let x=start;x<=end;x+=12)c.lineTo(x+ox,SURFACE+oy);for(let x=end;x>=start;x-=12)c.lineTo(x+ox,terrain(x).top+oy);c.closePath();c.fillStyle=rgb([8,29,36],[3,12,18],night);c.fill();
 slabBand(x=>terrain(x).top,start,end,ox,oy,rgb([12,33,41],[4,14,20],night),x=>terrain(x).cave>.002);
 drawIsland(kx,ky);
}
function drawTerrain(){
 for(const top of [false,true]){
 if(top&&!caveNear(camX-40,camX+vw+40))continue;
 c.save();rockShape(top);c.clip();
 let g=c.createLinearGradient(0,camY,0,camY+vh);g.addColorStop(0,top?'#0b202a':'#193b40');g.addColorStop(.55,top?'#122c33':'#112e35');g.addColorStop(1,'#05141d');c.fillStyle=g;c.fillRect(camX-40,camY-200,vw+80,vh+400);
 // The part of the island above the waterline is lit by the sky.
 if(top&&camY<SURFACE){let ig=c.createLinearGradient(0,SURFACE-150,0,SURFACE+40);ig.addColorStop(0,rgb([92,104,92],[24,32,38],night));ig.addColorStop(.75,rgb([60,74,72],[16,24,30],night));ig.addColorStop(1,'rgba(22,46,54,0)');c.fillStyle=ig;c.fillRect(camX-40,SURFACE-260,vw+80,300)}
 // Sedimentary strata and fractured, shaded rock faces.
 for(let layer=0;layer<7;layer++){c.beginPath();for(let x=Math.floor(camX/28)*28-28;x<=camX+vw+35;x+=28){let edge=top?terrain(x).top:terrain(x).bottom,y=edge+(top?-1:1)*(13+layer*23+8*Math.sin(x/110+layer));x===Math.floor(camX/28)*28-28?c.moveTo(x,y):c.lineTo(x,y)}c.lineWidth=layer===0?3:1;c.strokeStyle=`rgba(103,151,145,${(layer===0?.14:.08)*(1-night*.6)})`;c.stroke();}
 for(let i=Math.floor(camX/75)-1;i<(camX+vw)/75+1;i++){let x=i*75,edge=top?terrain(x).top:terrain(x).bottom,dir=top?-1:1,y=edge+dir*(12+hash(i)*70),r=25+hash(i+7)*45;path([[x-r,y],[x-r*.3,y-dir*r*.35],[x+r*.7,y+dir*r*.1],[x+r,y+dir*r*.9],[x-r*.7,y+dir*r*.6]],`rgba(61,90,91,${.13+hash(i+2)*.1})`,'#04121a55',1);c.strokeStyle='#abc1a416';c.beginPath();c.moveTo(x-r,y);c.lineTo(x-r*.3,y-dir*r*.35);c.lineTo(x+r*.7,y+dir*r*.1);c.stroke();}
 for(let i=Math.floor(camX/18);i<(camX+vw)/18+1;i++){let xx=i*18+hash(i+9)*17,edge=top?terrain(xx).top:terrain(xx).bottom;for(let k=0;k<5;k++){let yy=edge+(top?-1:1)*(5+hash(i*7+k)*170);c.fillStyle=k%2?'#a3c4a610':'#010b1366';c.fillRect(xx+hash(i+k)*12,yy,1+hash(i*2+k)*4,1+hash(i*3+k)*2)}}
 if(night){c.fillStyle=`rgba(0,6,13,${night*.35})`;c.fillRect(camX-30,camY-200,vw+60,vh+400)}c.restore();
 if(top){strokeEdge(x=>terrain(x).top,'#598f8a45',2);if(camY<SURFACE){strokeEdge(islandTop,rgb([96,128,88],[30,44,40],night),3);strokeEdge(x=>SURFACE+1.5+Math.sin(x*.05+ambient*2)*1.2,`rgba(225,244,238,${.35*(1-night*.6)})`,1.4)}}
 else{rockShape(false);c.lineWidth=2;c.strokeStyle='#9fd0bc85';c.stroke()}
 }
 // Kelp and cold-water coral attached to the actual seabed.
 for(let i=Math.floor(camX/43)-2;i<(camX+vw)/43+2;i++){let x=i*43+hash(i)*23,z=terrain(x),h=15+hash(i+1)*50;if(hash(i+5)>.38){c.strokeStyle=night>.7?'#163e42':'#28615b';c.lineWidth=2;let sway=Math.sin(ambient*.9+i)*h*.13;c.beginPath();c.moveTo(x,z.bottom+4);c.bezierCurveTo(x-5,z.bottom-h*.3,x+sway,z.bottom-h*.7,x+sway*.7,z.bottom-h);c.stroke();for(let k=1;k<4;k++){let yy=z.bottom-h*k/4,side=k%2?1:-1;path([[x,yy+7],[x+side*(9-k),yy-4],[x+sway*.4,yy-2]],night>.7?'#153c3d':'#26594f')}}
 if(hash(i+12)>.75){for(let k=0;k<4;k++){let xx=x+k*4,yy=z.bottom-5-hash(i+k)*10;glow(xx,yy,9,`rgba(89,211,193,${.07+night*.08})`);circle(xx,yy,1.2,'#6cb9b183')}}}
}
function mine(x,y,alpha,echo){
 c.save();c.globalAlpha=alpha;c.translate(x,y);billboard();c.rotate(Math.sin(ambient*.5+x)*.035);
 c.strokeStyle='#152128';c.lineWidth=5;for(let i=0;i<8;i++){let a=i*TAU/8;c.beginPath();c.moveTo(Math.cos(a)*15,Math.sin(a)*15);c.lineTo(Math.cos(a)*23,Math.sin(a)*23);c.stroke();c.strokeStyle='#536164';c.lineWidth=2;c.beginPath();c.moveTo(Math.cos(a)*16-1,Math.sin(a)*16-1);c.lineTo(Math.cos(a)*22-1,Math.sin(a)*22-1);c.stroke();c.strokeStyle='#152128';c.lineWidth=5;circle(Math.cos(a)*23,Math.sin(a)*23,2.5,'#445157');}
 let g=c.createRadialGradient(-7,-8,1,1,3,22);g.addColorStop(0,'#738183');g.addColorStop(.35,'#3d4e53');g.addColorStop(.72,'#1c2b32');g.addColorStop(1,'#09131b');circle(0,0,18,g,'#748a8844');c.strokeStyle='#929d8c55';c.lineWidth=.8;c.beginPath();c.ellipse(0,0,18,6,-.27,0,TAU);c.stroke();c.strokeStyle='#09171d';c.beginPath();c.ellipse(0,0,8,18,-.27,0,TAU);c.stroke();for(let i=0;i<5;i++){let a=i*1.3;circle(Math.cos(a)*13,Math.sin(a)*13,1,'#84908b88')}path([[-8,1],[-3,-7],[1,2]],'#a3915366');circle(6,-6,1.7,'#a55e38');c.restore();
 if(echo>.01){c.save();c.globalAlpha=echo;circle(x,y,29,null,'#9ef0cf',.9);c.strokeStyle='#9ef0cf';c.lineWidth=.7;for(let a=0;a<4;a++){let angle=a*Math.PI/2;c.beginPath();c.moveTo(x+Math.cos(angle)*32,y+Math.sin(angle)*32);c.lineTo(x+Math.cos(angle)*38,y+Math.sin(angle)*38);c.stroke()}c.font='8px ui-monospace,monospace';c.fillStyle='#ace9d1';c.fillText('CONTACT',x+36,y-8);c.restore();}
}
function drawMines(){const glow=sonarGlow();for(const g of gates){if(g.x<camX-80||g.x>camX+vw+80)continue;let z=terrain(g.x);for(let k=0;k<2;k++){if(g.dead[k])continue;let y=mineY(g,k),from=k?z.bottom:z.top,elapsed=t-g.echo[k],echo=elapsed>=0?clamp(1-elapsed/glow,0,1):0,nearLight=clamp(1-Math.hypot(g.x-sub.x,y-sub.y)/180,0,1)*.4;let a=clamp(1-night*.972+echo*.95+nearLight*night,.028,1);c.save();c.globalAlpha=a;c.strokeStyle='#7b8b85';c.lineWidth=1.5;c.beginPath();c.moveTo(g.x,from);c.lineTo(g.x,y);c.stroke();c.strokeStyle='#adc1ac55';c.lineWidth=.65;for(let yy=Math.min(y,from)+5;yy<Math.max(y,from)-5;yy+=11){c.beginPath();c.ellipse(g.x,yy,1.5,3.5,0,0,TAU);c.stroke()}path([[g.x-12,from],[g.x-7,from+(k?7:-7)],[g.x+9,from+(k?7:-7)],[g.x+13,from]],'#52666a');c.restore();mine(g.x,y,a,echo*night);}}
}
function drawPickups(){
 for(const p of pickups){if(p.taken||p.x<camX-60||p.x>camX+vw+60)continue;const y=p.cy,pulse=.7+.3*Math.sin(ambient*3+p.phase);
  c.save();c.globalCompositeOperation='screen';glow(p.x,y,48,`rgba(150,225,255,${.14*pulse+night*.1})`);c.restore();
  for(let i=4;i>=0;i--){const a=p.phase+i*1.7+ambient*.6,rr=i?3+hash(i+p.phase)*4:10,ox=i?Math.cos(a)*15:0,oy=i?Math.sin(a)*12:0,g=c.createRadialGradient(p.x+ox-rr*.35,y+oy-rr*.4,rr*.1,p.x+ox,y+oy,rr);g.addColorStop(0,'rgba(240,255,255,.9)');g.addColorStop(.45,'rgba(150,225,240,.3)');g.addColorStop(1,'rgba(120,210,230,.1)');circle(p.x+ox,y+oy,rr,g,'rgba(210,250,255,.7)',.8)}
  c.font='bold 7px ui-monospace,monospace';c.fillStyle='#08303c';c.fillText('O2',p.x-5,y+3);
 }
}
function drawShip(s){
 const sinkT=s.sinking?t-s.sinking:0;c.save();c.translate(s.x,SURFACE+2+sinkT*22+Math.sin(ambient*1.4+s.x)*1.2);c.rotate(s.sinking?Math.min(.32,sinkT*.09):Math.sin(ambient*.9+s.x)*.012);c.globalAlpha=s.sinking?clamp(1-(sinkT-2.5)/2.2,0,1):1;
 const hullC=rgb([86,100,106],[38,48,56],night),deck=rgb([128,140,144],[54,66,72],night),dark=rgb([42,54,60],[16,24,30],night);
 if(!s.sinking){c.strokeStyle=`rgba(220,240,235,${.35*(1-night*.5)})`;c.lineWidth=1.5;c.beginPath();c.moveTo(-100,-1);c.lineTo(-240,1);c.stroke();c.beginPath();c.moveTo(106,-3);c.quadraticCurveTo(116,0,124,2);c.stroke()}
 path([[-100,-10],[92,-10],[108,-17],[98,3],[72,12],[-86,12],[-100,2]],hullC,'#0a161d88',1);
 path([[-100,2],[-86,12],[72,12],[98,3],[99,0],[-100,0]],'#4a2c28');
 path([[-60,-10],[-58,-24],[-8,-24],[-6,-10]],deck);path([[-38,-24],[-36,-37],[-14,-37],[-12,-24]],deck);path([[-34,-34],[-16,-34],[-16,-31],[-34,-31]],'#1a2a33');
 path([[-54,-24],[-52,-35],[-44,-35],[-44,-24]],dark);path([[4,-10],[6,-22],[32,-22],[36,-10]],deck);
 c.strokeStyle=dark;c.lineWidth=1.6;c.beginPath();c.moveTo(-25,-37);c.lineTo(-25,-64);c.moveTo(-33,-56);c.lineTo(-17,-56);c.stroke();c.fillStyle=dark;c.fillRect(-29,-52,8,4);
 path([[56,-10],[58,-16],[68,-16],[70,-10]],deck);c.strokeStyle=deck;c.lineWidth=2;c.beginPath();c.moveTo(66,-14);c.lineTo(84,-18);c.stroke();
 c.fillStyle=dark;for(let x=40;x<52;x+=3)c.fillRect(x,-12,2,2);
 if(s.kind){path([[-90,-10],[-88,-16],[-70,-16],[-68,-10]],deck)}
 if(night>.3){circle(-25,-64,1.6,'#ff6a5a');glow(-25,-64,10,'#ff6a5a66');circle(30,-20,1.3,'#9ff0a8')}
 if(t-s.hitAt<.35||(s.hp<s.max&&!s.sinking)){glow(-20,-18,30,`rgba(255,150,80,${t-s.hitAt<.35?.6:.22})`)}
 if(s.sinking){glow(0,-10,60,`rgba(255,140,70,${clamp(.5-sinkT*.1,0,.5)})`)}
 c.restore();
 if(!s.sinking){c.save();c.globalAlpha=.85;c.strokeStyle='#e3785f';c.lineWidth=1.2;c.beginPath();c.moveTo(s.x-7,SURFACE-86);c.lineTo(s.x,SURFACE-78);c.lineTo(s.x+7,SURFACE-86);c.stroke();c.font='8px ui-monospace,monospace';c.fillStyle='#f0a08c';c.fillText('HOSTILE',s.x-17,SURFACE-92);for(let i=0;i<s.max;i++){c.fillStyle=i<s.hp?'#e3785f':'#e3785f33';c.fillRect(s.x-s.max*5+i*10+1,SURFACE-108,8,3)}c.restore()}
}
function drawShips(){for(const s of ships)if(s.x>camX-260&&s.x<camX+vw+260)drawShip(s)}
function drawMissile(m,enemy){const a=Math.atan2(m.vy,m.vx);c.save();c.translate(m.x,m.y);billboard();c.rotate(a);c.save();c.globalCompositeOperation='screen';glow(-11,0,18,enemy?'rgba(255,110,80,.4)':'rgba(255,214,150,.4)');c.restore();path([[-9,-2.2],[7,-2.2],[12,0],[7,2.2],[-9,2.2]],enemy?'#a45244':'#d9d3c0','#0008',.5);path([[-9,-2],[-13,-6],[-11,0],[-13,6],[-9,2]],enemy?'#6e2f27':'#8c8a7e');circle(-12,0,2.2,enemy?'#ffb08a':'#fff1cf');c.restore()}
function drawMissiles(){for(const m of enemyMissiles){if(m.route)drawFastTorpedo(m);else drawMissile(m,true)}for(const m of missiles)drawMissile(m,false)}
function drawSonar(){
 c.save();c.globalCompositeOperation='screen';
 for(const p of pings){let fade=Math.max(0,1-p.r/p.range);c.lineWidth=1.3;c.strokeStyle=`rgba(131,239,203,${fade*.36})`;circle(p.x,p.y,p.r,null,c.strokeStyle,1.3);if(p.r>8)circle(p.x,p.y,p.r-8,null,`rgba(107,217,200,${fade*.08})`,5)}
 for(const e of echoes){const sx=e.x,sy=e.y;glow(sx,sy,12,'#b4ffe136');circle(sx,sy,2,'#c9ffe9');c.strokeStyle='#b2f7d84a';c.lineWidth=1;c.beginPath();c.moveTo(sx,sy);let dx=e.ox-sx,dy=e.oy-sy,d=Math.hypot(dx,dy);if(d>0)c.lineTo(sx+dx/d*Math.min(d,30),sy+dy/d*Math.min(d,30));c.stroke()}
 c.restore();
}
/* Submarine models share one base drawing (45 x 17 units) and vary the sail,
   deck, stern, propulsor and paint per class, then scale to the class size. */
const SAILS={std:[[-18,-12],[-17,-28],[-9,-33],[6,-32],[12,-13]],fillet:[[-25,-12],[-18,-21],[-17,-29],[-9,-33],[6,-32],[11,-21],[19,-12]],slope:[[-18,-12],[-16,-31],[-2,-33],[5,-31],[16,-13]],small:[[-10,-11],[-9,-25],[-3,-28],[7,-27],[12,-11]],tower:[[-22,-13],[-21,-25],[-15,-29],[8,-29],[13,-25],[16,-13]],long:[[-31,-12],[-24,-25],[-12,-31],[5,-31],[13,-24],[17,-12]],planes:[[4,-13],[5,-30],[12,-34],[25,-33],[30,-13]],aft:[[-28,-15],[-26,-28],[-17,-32],[-1,-31],[7,-15]]};
function drawSubModel(m,lamp){
 if(m.look.turtle){drawTurtleModel(m,lamp);return}
 const L=m.look,P=PALS[L.pal];c.save();c.scale(m.hx/45,m.hy/17);
 if(lamp){c.save();c.globalCompositeOperation='screen';let g=c.createLinearGradient(42,0,270,0);g.addColorStop(0,`rgba(172,226,212,${.12+night*.09})`);g.addColorStop(1,'#a2dfc600');path([[42,-3],[270,-45],[270,48],[42,4]],g);c.restore();c.save();c.scale(1,.35);glow(0,35,100,'#000a');c.restore()}
 // Stern control surfaces.
 if(L.stern==='x'){path([[-34,-6],[-49,-20],[-55,-19],[-47,-4]],P[6],'#70929377',.8);path([[-34,6],[-49,20],[-55,19],[-47,4]],P[6],'#70929377',.8)}
 else path([[-38,-9],[-53,-21],[-58,-20],[-54,-3],[-54,5],[-58,18],[-53,18],[-37,8]],P[6],'#70929377',.8);
 if(L.pod){c.fillStyle=P[6];c.beginPath();c.ellipse(-55,-22,7,3,0,0,TAU);c.fill()}
 // Propulsor: shrouded pump-jet, single screw or twin screws.
 const spin=Math.sin(ambient*38);
 if(L.prop==='pump'){path([[-46,-8],[-57,-9],[-61,-6],[-61,6],[-57,9],[-46,8]],P[5],'#8fa9a466',.8);c.strokeStyle='#8fa9a444';c.lineWidth=.6;for(const x of [-57,-53]){c.beginPath();c.moveTo(x,-8);c.lineTo(x,8);c.stroke()}}
 else for(const oy of L.prop==='twin'?[-5,5]:[0]){c.strokeStyle='#687e80';c.lineWidth=2;c.beginPath();c.moveTo(-48,oy);c.lineTo(-61,oy);c.stroke();c.fillStyle='#8b9a83';c.beginPath();c.ellipse(-60,oy,2,Math.abs(spin)*(oy?8:13)+2,.15,0,TAU);c.fill()}
 // Missile decks.
 if(L.deck==='hump'){path([[-40,-11],[-34,-18],[2,-18],[6,-13]],P[2],'#819c9955',.7);c.strokeStyle='#0a1a2477';c.lineWidth=.6;for(let x=-32;x<0;x+=4.5){c.beginPath();c.moveTo(x,-18);c.lineTo(x,-15.5);c.stroke()}}
 if(L.deck==='fore'){path([[8,-14],[13,-20],[40,-19],[48,-12]],P[2],'#819c9955',.7);c.strokeStyle='#0a1a2477';c.lineWidth=.6;for(let x=15;x<40;x+=4){c.beginPath();c.moveTo(x,-19.5);c.lineTo(x,-16.5);c.stroke()}}
 // Sail or conning tower, with masts.
 const sp=SAILS[L.sail]||SAILS.std,top=Math.min(...sp.map(p=>p[1])),mx=(sp[1][0]+sp[sp.length-2][0])/2;
 path(sp,P[3],'#819c9977',.8);c.strokeStyle='#64817c';c.lineWidth=1.4;c.beginPath();c.moveTo(sp[1][0]+1,sp[1][1]+1);for(let i=2;i<sp.length-1;i++)c.lineTo(sp[i][0],sp[i][1]+1);c.stroke();
 c.fillStyle='#293e49';c.fillRect(mx-5,top-12,2.6,14);c.fillRect(mx+4,top-7,1.8,9);c.fillStyle='#9daf9f';c.fillRect(mx-5,top-12,7,2.5);c.fillStyle='#13252e';c.fillRect(mx+1,top-11,3,3);
 if(L.sail==='planes'){c.fillStyle=P[6];c.fillRect(0,-25,34,2.6)}
 if(L.sail==='tower'){c.strokeStyle='#9fb3ad66';c.lineWidth=.5;c.beginPath();c.moveTo(-44,-16);c.lineTo(46,-16);c.stroke();for(let x=-42;x<=44;x+=8){c.beginPath();c.moveTo(x,-16);c.lineTo(x,-13);c.stroke()}path([[20,-13],[22,-18],[29,-18],[30,-13]],P[3]);c.strokeStyle=P[1];c.lineWidth=1.6;c.beginPath();c.moveTo(27,-16.5);c.lineTo(38,-19);c.stroke()}
 // Pressure hull.
 let hullG=c.createLinearGradient(0,-17,0,18);[0,.14,.37,.52,.78,1].forEach((s,i)=>hullG.addColorStop(s,P[i]));
 c.beginPath();c.moveTo(-48,-8);
 if(L.bow==='ship'){c.lineTo(-42,-13);c.lineTo(38,-13);c.quadraticCurveTo(53,-12,57,-6);c.bezierCurveTo(54,6,42,13,30,13);c.bezierCurveTo(10,17,-29,14,-48,8)}
 else{c.bezierCurveTo(-23,-18,17,-18,36,-11);c.bezierCurveTo(59,-5,59,8,36,13);c.bezierCurveTo(13,19,-29,14,-48,8)}
 c.quadraticCurveTo(-53,0,-48,-8);c.closePath();c.fillStyle=hullG;c.fill();c.strokeStyle='#9ebcb34d';c.lineWidth=.8;c.stroke();
 if(L.pal==='ru'){c.save();c.clip();c.fillStyle='rgba(120,40,32,.45)';c.fillRect(-60,7,120,20);c.restore()}
 c.save();c.beginPath();c.ellipse(1,0,48,15,0,0,TAU);c.clip();for(let x=-31;x<=31;x+=13){c.strokeStyle='#081a2a77';c.lineWidth=.7;c.beginPath();c.ellipse(x,0,3,16,0,0,TAU);c.stroke();for(let y=-9;y<=9;y+=6)circle(x-2,y,.65,'#b0c0b04a')}c.restore();
 c.strokeStyle='#b1c6b67a';c.lineWidth=.6;c.beginPath();c.moveTo(-35,-9);c.bezierCurveTo(-9,-14,27,-13,41,-7);c.stroke();
 path([[11,3],[24,10],[22,13],[5,6]],P[6],'#9db4a544',.6);
 c.font='5px Arial';c.fillStyle='#b1c3baaa';c.fillText(m.mark,-30,3);
 circle(45,0,2.3,'#e2f2d4');glow(47,0,12,'#b7f6df55');circle(mx,top+2,1.2,'#bf8b61');c.restore();
}
/* The boat in 3D: a lathed pressure hull, extruded sail and decks, cruciform (or X)
   stern planes, bow planes and propulsors, built once per class in the same model
   units as the side drawing, lit from above and painter-sorted each frame. */
const meshCache={},hexRgb=h=>[1,3,5].map(i=>parseInt(h.slice(i,i+2),16));
const STATIONS=[-50,-46,-42,-37,-31,-25,-20,-10,0,10,20,30,36,42,47,51,54,56,57],LIGHT=[.3,-1,-.45].map((v,_,a)=>v/Math.hypot(...a));
function hullR(x){return x>36?15.5*Math.sqrt(Math.max(0,1-((x-36)/21)**2)):x<-20?15.5*Math.sqrt(Math.max(0,1-((x+20)/30)**2*.93)):15.5}
function lathe(f,xs,rf,kind,two,N=18,oz=0){const ring=(x,a)=>{const r=rf(x);return [x,-r*Math.cos(a),r*Math.sin(a)+oz]};for(let i=0;i<xs.length-1;i++)for(let j=0;j<N;j++){const a0=j/N*TAU,a1=(j+1)/N*TAU;f.push({v:[ring(xs[i],a0),ring(xs[i+1],a0),ring(xs[i+1],a1),ring(xs[i],a1)],ref:[(xs[i]+xs[i+1])/2,0,oz],kind,two})}}
function extrude(f,pts,w,kind){const ref=[pts.reduce((s,p)=>s+p[0],0)/pts.length,pts.reduce((s,p)=>s+p[1],0)/pts.length,0];
 for(const z of [-w,w])f.push({v:pts.map(p=>[p[0],p[1],z]),ref,kind,bias:-2});
 for(let i=0;i<pts.length-1;i++){const a=pts[i],b=pts[i+1];f.push({v:[[a[0],a[1],-w],[b[0],b[1],-w],[b[0],b[1],w],[a[0],a[1],w]],ref,kind,bias:-2})}}
function buildMesh(m){
 const L=m.look,f=[],sw=['tower','long','aft'].includes(L.sail)?4.2:3.2,fin=(shape,a)=>f.push({v:shape.map(([x,r])=>[x,-r*Math.cos(a),r*Math.sin(a)]),kind:'fin',two:true});
 if(L.turtle){lathe(f,[-45,-40,-30,-15,0,15,30,40,45],x=>17*Math.sqrt(Math.max(0,1-(x/45)**2)),'hull',false);extrude(f,[[-12,-14],[-10,-23],[10,-23],[12,-14]],6,'sail');for(const x of [-23,23])lathe(f,[x-1.5,x+1.5],()=>15,'prop',false);return {faces:f,sw:6}}
 lathe(f,STATIONS,hullR,'hull',false);
 f.push({v:Array.from({length:18},(_,j)=>{const a=j/18*TAU,r=hullR(-50);return [-50,-r*Math.cos(a),r*Math.sin(a)]}),ref:[-40,0,0],kind:'dark'});
 // The sail's base is sunk just below the curved deck so no gap shows.
 const sp=SAILS[L.sail]||SAILS.std;extrude(f,sp.map(([x,y],i)=>[x,i&&i<sp.length-1?y:.8-Math.sqrt(Math.max(0,hullR(x)**2-sw*sw))]),sw,'sail');
 if(L.deck==='hump')extrude(f,[[-30,-12.5],[-26,-18],[2,-18],[6,-12.5]],7,'hull');
 if(L.deck==='fore')extrude(f,[[8,-12.5],[13,-20],[40,-19],[46,-12.5]],7,'hull');
 const x=L.stern==='x',stern=x?[[-34,5],[-49,20],[-55,19],[-47,3]]:[[-37,7],[-52,20],[-57,19],[-53,3]];
 for(let k=0;k<4;k++)fin(stern,(x?Math.PI/4:0)+k*Math.PI/2);
 for(const s of [1,-1])f.push({v:[[6,4,13*s],[22,4,13*s],[19,4,21*s],[11,4,21*s]],kind:'fin',two:true});
 if(L.sail==='planes')for(const s of [1,-1])f.push({v:[[8,-25,2.5*s],[24,-25,2.5*s],[21,-25,14*s],[12,-25,14*s]],kind:'fin',two:true});
 if(L.pod)extrude(f,Array.from({length:11},(_,i)=>{const a=i/10*TAU;return [-55+7*Math.cos(a),-22+3*Math.sin(a)]}),2.6,'fin');
 if(L.prop==='pump'){const PX=[-46,-50,-55,-59,-61],PR=[8.6,9.2,9,8.2,7.2];lathe(f,PX,x=>PR[PX.indexOf(x)],'sail',true,14);f.push({v:Array.from({length:14},(_,j)=>{const a=j/14*TAU;return [-60.5,-7*Math.cos(a),7*Math.sin(a)]}),kind:'dark',two:true})}
 else for(const oz of L.prop==='twin'?[-6,6]:[0])lathe(f,[-48,-60],()=>1.4,'dark',false,6,oz);
 return {faces:f,sw};
}
function propFaces(L,time){const out=[];if(L.prop==='pump')return out;const spin=time*14;
 for(const oz of L.prop==='twin'?[-6,6]:[0]){const R=oz?8:12;for(let k=0;k<4;k++){const a=spin+k*TAU/4,p=(r,da)=>[-60,-r*Math.cos(a+da),r*Math.sin(a+da)+oz];out.push({v:[p(1.5,-.12),p(R,-.3),p(R,.3),p(1.5,.12)],kind:'prop',two:true})}}
 return out}
function drawSub3D(angle,wk=null){
 const m=S,L=m.look,mesh=meshCache[m.id]||(meshCache[m.id]=buildMesh(m)),P=PALS[L.pal].map(hexRgb);
 const big=state==='menu'&&!wk?1.45:1,kx=m.hx/45*big,ky=m.hy/17*big,ca=Math.cos(angle),sa=Math.sin(angle),bob=surfaced&&!wk?Math.sin(ambient*2.3)*1.4:0,[bx,by]=wk?proj(wk.x,wk.y):proj(sub.x,sub.y);
 const ox=bx+shakeX*scale,oy=by+shakeY*scale,dn=Math.hypot(syw*cpt,cyw*cyw*spt,cyw*cpt),d=[-syw*cpt/dn,cyw*cyw*spt/dn,cyw*cpt/dn],hl=[LIGHT[0]-d[0],LIGHT[1]-d[1],LIGHT[2]-d[2]],hn=Math.hypot(...hl);
 const cr=Math.cos(wk?wk.roll:0),sr=Math.sin(wk?wk.roll:0),cb=Math.cos(wk?wk.bend:0),sb=Math.sin(wk?wk.bend:0);
 const world=v=>{let x=v[0]*kx,y=v[1]*ky,z=v[2]*ky;
  // A wreck's stern sags where the back broke, and the hull rolls onto its side.
  if(wk){if(v[0]<-6){const dx=x+6*kx;x=-6*kx+dx*cb-y*sb;y=dx*sb+y*cb}const ry=y*cr-z*sr;z=y*sr+z*cr;y=ry}
  return [x*ca-y*sa,x*sa+y*ca+bob,z]};
 const view=w=>[ox+scale*(w[0]*cyw+w[2]*syw),oy+scale*(w[1]*cpt-w[2]*cyw*spt),w[0]*d[0]+w[1]*d[1]+w[2]*d[2]];
 c.save();c.setTransform(dpr,0,0,dpr,0,0);if(state==='playing'&&t<invulnUntil&&!active('shield')&&Math.floor(t*14)%2)c.globalAlpha=.45;else if(state==='playing'&&active('silent'))c.globalAlpha=.42;
 // Headlamp beam; on a wreck it stutters out.
 const lampOn=!wk||(ambient-wk.born<1.8&&Math.random()<.45);
 const B=view(world([45,0,0])),E=view(world([270,0,0])),bl=Math.hypot(E[0]-B[0],E[1]-B[1])||1,nx=-(E[1]-B[1])/bl,ny=(E[0]-B[0])/bl,bw=46*ky*scale,b0=3*ky*scale;
 if(lampOn){c.globalCompositeOperation='screen';let g=c.createLinearGradient(B[0],B[1],E[0],E[1]);g.addColorStop(0,`rgba(172,226,212,${.12+night*.09})`);g.addColorStop(1,'#a2dfc600');path([[B[0]+nx*b0,B[1]+ny*b0],[E[0]+nx*bw,E[1]+ny*bw],[E[0]-nx*bw,E[1]-ny*bw],[B[0]-nx*b0,B[1]-ny*b0]],g);c.globalCompositeOperation='source-over'}
 const list=[];
 for(const f of mesh.faces.concat(propFaces(L,wk?wk.born:ambient))){
  const w=f.v.map(world),n=w.length;let nx=0,ny=0,nz=0,cx=0,cy=0,cz=0;
  for(let i=0;i<n;i++){const a=w[i],b=w[(i+1)%n];nx+=(a[1]-b[1])*(a[2]+b[2]);ny+=(a[2]-b[2])*(a[0]+b[0]);nz+=(a[0]-b[0])*(a[1]+b[1]);cx+=a[0];cy+=a[1];cz+=a[2]}
  const len=Math.hypot(nx,ny,nz);if(!len)continue;nx/=len;ny/=len;nz/=len;cx/=n;cy/=n;cz/=n;
  if(f.ref){const r=world(f.ref);if(nx*(cx-r[0])+ny*(cy-r[1])+nz*(cz-r[2])<0){nx=-nx;ny=-ny;nz=-nz}}
  if(nx*d[0]+ny*d[1]+nz*d[2]>0){if(!f.two)continue;nx=-nx;ny=-ny;nz=-nz}
  const s=.25+.75*Math.max(0,nx*LIGHT[0]+ny*LIGHT[1]+nz*LIGHT[2]),spec=Math.max(0,(nx*hl[0]+ny*hl[1]+nz*hl[2])/hn)**24*.3;let col;
  if(f.kind==='hull'||f.kind==='sail'){const q=clamp((1-s)*5,0,4.999),i=Math.floor(q);col=P[i].map((v,j)=>mix(v,P[i+1][j],q-i));if(L.pal==='ru'&&f.kind==='hull'&&f.v[0][1]>8)col=col.map((v,j)=>mix(v,[120,40,32][j],.45))}
  else if(f.kind==='dark')col=[10,22,28];
  else col=(f.kind==='prop'?[139,154,131]:P[6]).map(v=>v*(.45+.8*s));
  if(wk)col=col.map((v,j)=>mix(v*.55,[70,48,38][j],.18));
  const pts=w.map(view);list.push({pts,z:pts.reduce((a,p)=>a+p[2],0)/n+(f.bias||0),fill:`rgb(${col.map(v=>Math.round(clamp(mix(v,235,spec),0,255))).join(',')})`});
 }
 list.sort((a,b)=>b.z-a.z);c.lineWidth=.6;c.lineJoin='round';
 for(const f of list){c.beginPath();f.pts.forEach((p,i)=>i?c.lineTo(p[0],p[1]):c.moveTo(p[0],p[1]));c.closePath();c.fillStyle=f.fill;c.fill();c.strokeStyle=f.fill;c.stroke()}
 // Masts and lights.
 const sp=SAILS[L.sail]||SAILS.std,top=Math.min(...sp.map(p=>p[1])),mx=(sp[1][0]+sp[sp.length-2][0])/2;
 const line=(a,b,wd,col)=>{const p=view(world(a)),q=view(world(b));c.strokeStyle=col;c.lineWidth=wd*kx*scale;c.beginPath();c.moveTo(p[0],p[1]);c.lineTo(q[0],q[1]);c.stroke()};
 line([mx-3.7,top+1,0],[mx-3.7,top-12,0],2.6,'#293e49');line([mx+4.9,top+1,0],[mx+4.9,top-7,0],1.8,'#293e49');line([mx-5,top-10.8,0],[mx+2,top-10.8,0],2.5,'#9daf9f');
 const nose=view(world([56.5,0,0])),red=view(world([mx,top+2,-mesh.sw]));
 if(lampOn)glow(nose[0],nose[1],12*kx*scale,'#b7f6df55');if(lampOn){circle(nose[0],nose[1],2.3*kx*scale,'#e2f2d4');circle(red[0],red[1],1.2*kx*scale,'#bf8b61')}
 c.restore();
}
function drawAbilityFx(){
 if(state!=='playing'||t>=abilityUntil)return;const id=S.ability.id,fade=clamp((abilityUntil-t)*2,0,1);
 c.save();c.globalCompositeOperation='screen';
 if(id==='shield'){glow(sub.x,sub.y,S.hx*1.7,`rgba(140,200,255,${(.22+.08*Math.sin(ambient*9))*fade})`);c.beginPath();c.ellipse(sub.x,sub.y,S.hx*1.4,S.hy*2.5,0,0,TAU);c.strokeStyle=`rgba(185,230,255,${.6*fade})`;c.lineWidth=1.6;c.stroke()}
 else if(id==='flank'){c.strokeStyle=`rgba(200,240,232,${.35*fade})`;c.lineWidth=1.2;c.beginPath();for(let i=0;i<5;i++){const y=sub.y+(i-2)*S.hy*.5,x=sub.x-S.hx*(1.3+hash(i+Math.floor(ambient*20))*.6);c.moveTo(x,y);c.lineTo(x-60-hash(i*7)*60,y)}c.stroke()}
 else if(id==='silent'){glow(sub.x,sub.y,S.hx*1.5,`rgba(20,40,60,${.25*fade})`)}
 else if(id==='rapid'){glow(sub.x+S.hx,sub.y,24,`rgba(255,214,150,${.3*fade})`)}
 c.restore();
}
function drawSub(){const angle=clamp(sub.v/650,-.22,.22)+tilt+(surfaced?Math.sin(ambient*1.9)*.02:0);if(!flat()){drawSub3D(angle);return}c.save();c.translate(sub.x,sub.y+(surfaced?Math.sin(ambient*2.3)*1.4:0));c.rotate(angle);if(state==='menu')c.scale(1.45,1.45);if(state==='playing'&&t<invulnUntil&&!active('shield')&&Math.floor(t*14)%2)c.globalAlpha=.45;else if(state==='playing'&&active('silent'))c.globalAlpha=.42;drawSubModel(S,true);c.restore()}
function drawPreview(cv,m,w,h){const ctx=cv.getContext('2d');ctx.setTransform(cv.width/w,0,0,cv.height/h,0,0);ctx.clearRect(0,0,w,h);const saved=c;c=ctx;try{const k=Math.min(w/((m.hx/45)*128),h/((m.hy/17)*58));c.translate(w/2+2*k,h/2+12*k*(m.hy/17));c.scale(k,k);drawSubModel(m,false)}finally{c=saved}}
function drawSurfaceFx(){
 for(const r of ripples){const k=(ambient-r.born)/1.6;c.strokeStyle=`rgba(225,245,240,${(1-k)*.5})`;c.lineWidth=1.4;c.beginPath();c.ellipse(r.x,SURFACE+2,r.w*(.6+k*1.6),5+k*7,0,0,TAU);c.stroke()}
 if(surfaced){c.strokeStyle='rgba(230,248,242,.55)';c.lineWidth=2;c.beginPath();c.moveTo(sub.x+S.hx*1.05,SURFACE+1);c.quadraticCurveTo(sub.x+S.hx*1.25,SURFACE-3,sub.x+S.hx*1.35,SURFACE+2);c.stroke();
  for(let i=0;i<3;i++){c.strokeStyle=`rgba(225,245,240,${.32-i*.09})`;c.lineWidth=1.6-i*.4;c.beginPath();c.moveTo(sub.x-S.hx*.9,SURFACE+2+i*2);c.quadraticCurveTo(sub.x-S.hx*2.4,SURFACE+4+i*5,sub.x-S.hx*(4+i*1.5),SURFACE+3+i*9);c.stroke()}}
 for(const p of spray){c.globalAlpha=clamp(p.life*1.4,0,1)*.8;circle(p.x,p.y,p.r,'#e4f6f2')}c.globalAlpha=1;
}
function drawParticles(){for(const b of bubbles){if(b.smoke){c.globalAlpha=clamp(b.life,0,1)*.35;circle(b.x,b.y,b.r*1.6,'#c9d2d0')}else{c.globalAlpha=clamp(b.life/2,0,1)*.3;circle(b.x,b.y,b.r,null,'#b2dacf',.7)}}c.globalAlpha=1;for(const p of debris){c.globalAlpha=clamp(p.life,0,1);circle(p.x,p.y,p.r,p.hot?'#efc191':'#647e7e');if(p.hot)glow(p.x,p.y,p.r*4,'#ffb26828')}c.globalAlpha=1}
function drawBooms(){c.save();c.globalCompositeOperation='screen';for(const b of booms){const k=(ambient-b.born)/.9;glow(b.x,b.y,b.size*(1.2+k*2),`rgba(255,${Math.round(190-k*80)},120,${(1-k)*.55})`);circle(b.x,b.y,b.size*(.4+k*1.6),null,`rgba(255,230,190,${(1-k)*.6})`,2)}c.restore()}
function drawInstruments(){
 // Restrained depth ruler on the right edge, in screen pixels.
 c.save();c.globalAlpha=.42;c.strokeStyle='#b3d4cc';c.fillStyle='#c4dcd5';c.lineWidth=.5;c.font='8px ui-monospace,monospace';let step=100;for(let y=Math.ceil((camY+120/scale)/step)*step;y<camY+vh-120/scale;y+=step){let yy=scrY(y);c.beginPath();c.moveTo(W-22,yy);c.lineTo(W-34,yy);c.stroke();if(W>700)c.fillText(String(Math.max(0,Math.round((y-68)*.1))).padStart(3,'0'),W-57,yy+3)}c.restore();
 if(state==='menu'){let x=(sub.x-camX)*scale,y=(sub.y-camY)*scale;c.strokeStyle='#afd6ce3a';c.lineWidth=.6;c.beginPath();c.moveTo(x+61*scale,y-19*scale);c.lineTo(x+130*scale,y-80*scale);c.lineTo(x+210*scale,y-80*scale);c.stroke();c.fillStyle='#9cbbbba0';c.font='9px ui-monospace,monospace';c.fillText(S.name.toUpperCase()+' CLASS / '+S.mark,x+134*scale,y-89*scale);c.font='8px ui-monospace,monospace';c.fillStyle='#719496';c.fillText(S.origin.toUpperCase(),x+134*scale,y-65*scale);return}
 // Off-screen warnings: incoming missiles and warships above the view.
 const edge=W<700?118:92;c.save();c.font='8px ui-monospace,monospace';
 for(const m of enemyMissiles){const [sx,sy]=proj(m.x,m.y);if(sx<10||sx>W-10||sy>4)continue;c.globalAlpha=.6+.4*Math.sin(ambient*14);c.fillStyle='#e3785f';c.beginPath();c.moveTo(sx-7,edge);c.lineTo(sx+7,edge);c.lineTo(sx,edge+10);c.fill();c.fillText('INBOUND',sx-17,edge+22)}
 for(const s of ships){if(s.sinking)continue;const [sx,sy]=proj(s.x,SURFACE);if(sx<10||sx>W-10||sy>0)continue;c.globalAlpha=.75;c.strokeStyle='#ecc69b';c.lineWidth=1.2;c.strokeRect(sx-9,edge-2,18,9);c.fillStyle='#ecc69b';c.fillText('SURFACE CONTACT',sx-36,edge-8)}
 c.restore();
}
/* ---- Distress effects -------------------------------------------------------
   Running out of air frosts the view in from the edges, drains the colour and
   narrows the view with each laboured breath. A failing hull drives a heartbeat:
   the frame throbs and zooms, the edges flush red, and the last hull section
   cracks the viewport. Hits and both states warp the picture with a strip pass. */
let airFx=0,hullFx=0,crackFx=0,critFx=0,wasCritical=false,beatPhase=0,fxBuf=null,fxCtx=null,frostTex=null,crackTex=null,maskBuf=null,maskCtx=null,fxW=0,fxH=0;
// Lub-dub envelope, 0..1.
function heartbeat(){const p=beatPhase%1;return Math.min(1,Math.exp(-((p/.045)**2))+Math.exp(-(((p-1)/.045)**2))+.6*Math.exp(-(((p-.2)/.05)**2)))}
const hitFx=()=>state==='playing'||state==='dying'?clamp(1-(t-lastHitAt)/.8,0,1):0;
function updateDistress(dt){
 const live=(state==='playing'||state==='dying'||state==='paused')&&!practice;
 const air=live?clamp(1-o2/(S.o2*.35),0,1):0,hurt=live?(hull<=1?1:clamp(1-(hull-1)/Math.max(1,S.hull-2),0,1)*.45):0;
 const k=1-Math.exp(-dt*1.5);airFx=mix(airFx,air,k);hullFx=mix(hullFx,hurt,k);crackFx=mix(crackFx,live&&hull<=1?1:0,1-Math.exp(-dt*6));critFx=mix(critFx,live&&hull<=1?1:0,1-Math.exp(-dt*3));
 if(critical()&&!wasCritical)toast('MISSION CRITICAL','One more hit and the boat is lost. Steer clear of everything.',3,true);wasCritical=critical();
 if(state==='paused')return;
 const stress=Math.max(hullFx,airFx*.7),prev=beatPhase;beatPhase+=dt*mix(66,150,stress)/60;
 if(stress>.15){const k=critical()?1:stress*.45;if(Math.floor(beatPhase)>Math.floor(prev))sfx.heart(k,false);else if(prev%1<.2&&beatPhase%1>=.2)sfx.heart(k,true)}
}
const edgeness=(px,py,w,h)=>clamp((Math.hypot((px/w-.5)*2,(py/h-.5)*2)-.5)/.6,0,1);
function buildFrost(w,h){
 const cv=document.createElement('canvas');cv.width=w;cv.height=h;const x=cv.getContext('2d');
 // Haze, thickest at the rim.
 x.save();x.translate(w/2,h/2);x.scale(1,h/w);let g=x.createRadialGradient(0,0,w*.25,0,0,w*.72);g.addColorStop(0,'rgba(215,238,250,0)');g.addColorStop(.7,'rgba(215,238,250,.22)');g.addColorStop(1,'rgba(232,246,255,.62)');x.fillStyle=g;x.fillRect(-w,-w,2*w,2*w);x.restore();
 for(let i=0;i<3200;i++){const px=Math.random()*w,py=Math.random()*h;if(Math.random()>edgeness(px,py,w,h))continue;x.fillStyle=`rgba(240,250,255,${.1+Math.random()*.35})`;x.fillRect(px,py,1+Math.random()*2,1+Math.random()*2)}
 // Fern-like dendrites grow inward from the rim.
 x.lineCap='round';x.strokeStyle='#eef8ff';
 const grow=(px,py,a,len,wd,d)=>{if(d>3||len<4)return;const ex=px+Math.cos(a)*len,ey=py+Math.sin(a)*len;x.globalAlpha=.18+.3*Math.random();x.lineWidth=wd;x.beginPath();x.moveTo(px,py);x.lineTo(ex,ey);x.stroke();
  const n=2+(Math.random()*3|0);for(let i=1;i<=n;i++){const f=i/(n+1);grow(px+(ex-px)*f,py+(ey-py)*f,a+(Math.random()<.5?-1:1)*(1.05+(Math.random()-.5)*.25),len*(.5-.25*f),wd*.7,d+1)}
  grow(ex,ey,a+(Math.random()-.5)*.5,len*.75,wd*.85,d+1)};
 for(let i=0,n=Math.round((w+h)/20);i<n;i++){const u=Math.random()*2*(w+h);let px,py;if(u<w){px=u;py=0}else if(u<2*w){px=u-w;py=h}else if(u<2*w+h){px=0;py=u-2*w}else{px=w;py=u-2*w-h}
  grow(px,py,Math.atan2(h/2-py,w/2-px)+(Math.random()-.5)*1.1,30+Math.random()*80,1.7,0)}
 // Six-armed crystals near the rim.
 for(let i=0;i<160;i++){const px=Math.random()*w,py=Math.random()*h;if(Math.random()>edgeness(px,py,w,h)*1.4)continue;const r=3+Math.random()*11,r0=Math.random()*TAU;x.globalAlpha=.35+.4*Math.random();x.lineWidth=.9;
  for(let k=0;k<6;k++){const a=r0+k*TAU/6,ax=px+Math.cos(a)*r,ay=py+Math.sin(a)*r;x.beginPath();x.moveTo(px,py);x.lineTo(ax,ay);for(const s of [-1,1]){const mx=px+Math.cos(a)*r*.55,my=py+Math.sin(a)*r*.55;x.moveTo(mx,my);x.lineTo(mx+Math.cos(a+s*.9)*r*.35,my+Math.sin(a+s*.9)*r*.35)}x.stroke()}}
 return cv;
}
function buildCracks(w,h){
 const cv=document.createElement('canvas');cv.width=w;cv.height=h;const x=cv.getContext('2d');x.lineCap='round';x.lineJoin='round';
 const crack=(px,py,a,len,d)=>{const pts=[[px,py]],segs=6+(Math.random()*6|0);let cx=px,cy=py;
  for(let i=0;i<segs;i++){a+=(Math.random()-.5)*.7;const l=len/segs*(.6+Math.random()*.8);cx+=Math.cos(a)*l;cy+=Math.sin(a)*l;pts.push([cx,cy]);if(d<2&&Math.random()<.3)crack(cx,cy,a+(Math.random()<.5?-1:1)*(.5+Math.random()*.6),len*.45,d+1)}
  const line=(col,wd,o)=>{x.strokeStyle=col;x.lineWidth=wd;x.beginPath();pts.forEach(([a,b],i)=>i?x.lineTo(a+o,b+o):x.moveTo(a+o,b+o));x.stroke()};
  line('rgba(0,0,0,.55)',2.4-d*.6,1);line('rgba(236,246,250,.8)',1.2-d*.3,0)};
 // Spider-web rings around an impact point.
 const web=(ix,iy,spokes,reach)=>{const ang=Array.from({length:spokes},(_,k)=>k/spokes*TAU+Math.random()*.35);for(const a of ang)crack(ix,iy,a,reach*(.5+Math.random()*.7),0);
  for(const r of [14,32,58]){x.strokeStyle='rgba(236,246,250,.55)';x.lineWidth=.8;x.beginPath();ang.forEach((a,i)=>{const rr=r*(.8+Math.random()*.4),px=ix+Math.cos(a)*rr,py=iy+Math.sin(a)*rr;i?x.lineTo(px,py):x.moveTo(px,py)});x.closePath();x.stroke()}
  const g=x.createRadialGradient(ix,iy,0,ix,iy,22);g.addColorStop(0,'rgba(240,250,255,.7)');g.addColorStop(1,'rgba(240,250,255,0)');x.fillStyle=g;x.fillRect(ix-22,iy-22,44,44)};
 web(w*(.8+Math.random()*.1),h*(.62+Math.random()*.2),10,Math.max(w,h)*.26);web(w*(.06+Math.random()*.1),h*(.12+Math.random()*.15),6,Math.max(w,h)*.14);
 // Fade the cracks out toward the centre so the boat stays clear.
 x.globalCompositeOperation='destination-in';x.save();x.translate(w/2,h/2);x.scale(1,h/w);const fade=x.createRadialGradient(0,0,0,0,0,w/2*Math.SQRT2);fade.addColorStop(0,'rgba(0,0,0,0)');fade.addColorStop(.5,'rgba(0,0,0,0)');fade.addColorStop(.85,'#000');fade.addColorStop(1,'#000');x.fillStyle=fade;x.fillRect(-w,-w,2*w,2*w);x.restore();
 return cv;
}
function ensureFx(){const w=Math.round(Math.min(W,1600)),h=Math.round(w*H/W);if(frostTex&&Math.abs(fxW-w)<w*.2&&Math.abs(fxH-h)<h*.2)return;fxW=w;fxH=h;frostTex=buildFrost(w,h);crackTex=buildCracks(w,h);maskBuf=document.createElement('canvas');maskBuf.width=w;maskBuf.height=h;maskCtx=maskBuf.getContext('2d')}
// Frost revealed from the rim inward through an elliptical mask that breathes.
function drawFrost(a,breath){
 ensureFx();const w=fxW,h=fxH,R=w/2*Math.SQRT2,reach=mix(1.02,.78,a)-(reduced?0:.02*breath*a),s0=clamp(reach-.1,0,1),s1=clamp(reach+.12,s0,1);
 maskCtx.globalCompositeOperation='copy';maskCtx.drawImage(frostTex,0,0);maskCtx.globalCompositeOperation='destination-in';
 maskCtx.save();maskCtx.translate(w/2,h/2);maskCtx.scale(1,h/w);const g=maskCtx.createRadialGradient(0,0,0,0,0,R);g.addColorStop(0,'rgba(0,0,0,0)');g.addColorStop(s0,'rgba(0,0,0,0)');g.addColorStop(s1,'#000');g.addColorStop(1,'#000');maskCtx.fillStyle=g;maskCtx.fillRect(-w,-w,2*w,2*w);maskCtx.restore();
 c.save();c.globalAlpha=Math.min(.9,a*1.3);c.drawImage(maskBuf,0,0,W,H);c.globalCompositeOperation='screen';const m=Math.min(W,H),tint=c.createRadialGradient(W/2,H/2,m*.6,W/2,H/2,Math.max(W,H)*.75);tint.addColorStop(0,'rgba(150,200,230,0)');tint.addColorStop(1,`rgba(150,200,230,${a*.22})`);c.globalAlpha=1;c.fillStyle=tint;c.fillRect(0,0,W,H);c.restore();
}
// Post pass: re-draw the frame in horizontal strips with a travelling sine shift, a slight roll, and a ghost copy.
function distort(beat){
 if(reduced)return;const hitK=hitFx(),amt=clamp(airFx*.35+hullFx*beat*.4+hitK*.8,0,1.2);if(amt<.02)return;
 if(!fxBuf||fxBuf.width!==canvas.width||fxBuf.height!==canvas.height){fxBuf=document.createElement('canvas');fxBuf.width=canvas.width;fxBuf.height=canvas.height;fxCtx=fxBuf.getContext('2d')}
 fxCtx.drawImage(canvas,0,0);
 const cw=canvas.width,ch=canvas.height,n=20,sh=Math.ceil(ch/n),roll=airFx*.002*Math.sin(ambient*.7)+hitK*.008*Math.sin(ambient*40),over=1+amt*.05+Math.abs(roll)*1.3;
 c.setTransform(1,0,0,1,0,0);c.globalAlpha=1;c.globalCompositeOperation='source-over';c.save();c.translate(cw/2,ch/2);c.rotate(roll);c.scale(over,over);c.translate(-cw/2,-ch/2);
 for(let i=0;i<n;i++){const y=i*sh,edge=Math.max(0,(Math.abs((i+.5)/n*2-1)-.35)/.65)**1.5,off=(Math.sin(i*.5+ambient*2.6)*10+Math.sin(i*1.9-ambient*6.3)*4)*amt*edge*dpr;c.drawImage(fxBuf,0,y,cw,sh+1,off,y,cw,sh+1)}
 const ghost=clamp(hullFx*beat*.03+hitK*.22,0,.2);if(ghost>.02){c.globalAlpha=ghost;c.drawImage(fxBuf,(6*beat*hullFx+9*hitK+5*airFx*Math.sin(ambient*1.1))*dpr,0)}
 c.restore();
}
function drawDistress(beat){
 const hitK=hitFx(),hud=$('hud');
 if(airFx<.01&&hullFx<.01&&crackFx<.01&&critFx<.01&&hitK<.01){if(hud.style.transform)hud.style.transform='';return}
 const m=Math.min(W,H),M=Math.max(W,H),breath=.5+.5*Math.sin(ambient*1.4);
 if(airFx>.01){
  c.save();c.globalCompositeOperation='saturation';let sg=c.createRadialGradient(W/2,H/2,m*.4,W/2,H/2,M*.72);sg.addColorStop(0,'rgba(128,128,128,0)');sg.addColorStop(1,`rgba(128,128,128,${airFx*.8})`);c.fillStyle=sg;c.fillRect(0,0,W,H);c.restore();
  const g=c.createRadialGradient(W/2,H/2,m*mix(.62,.5,airFx)*(1+breath*.04*airFx),W/2,H/2,M*.74);g.addColorStop(0,'rgba(0,4,10,0)');g.addColorStop(1,`rgba(0,4,10,${airFx*.7})`);c.fillStyle=g;c.fillRect(0,0,W,H);
  drawFrost(airFx,breath);
 }
 const red=hullFx*(.15+.55*beat)+hitK*.5;
 if(red>.01){
  const k=clamp(hullFx*beat*.5+hitK*.35,0,1);c.save();c.globalCompositeOperation='multiply';let mg=c.createRadialGradient(W/2,H/2,m*.48,W/2,H/2,M*.72);mg.addColorStop(0,'#fff');mg.addColorStop(1,`rgb(255,${Math.round(255-130*k)},${Math.round(255-140*k)})`);c.fillStyle=mg;c.fillRect(0,0,W,H);c.restore();
  const g=c.createRadialGradient(W/2,H/2,m*mix(.62,.52,hullFx*beat),W/2,H/2,M*.75);g.addColorStop(0,'rgba(150,15,10,0)');g.addColorStop(.6,`rgba(150,15,10,${red*.18})`);g.addColorStop(1,`rgba(110,0,0,${Math.min(.9,red)})`);c.fillStyle=g;c.fillRect(0,0,W,H);
 }
 // Mission critical: a hard red frame along every edge that throbs with the heartbeat.
 if(critFx>.01){const a=critFx*(.45+.4*beat),w=m*mix(.07,.1,beat);c.save();c.globalCompositeOperation='screen';
  for(const [x0,y0,x1,y1,rx,ry,rw,rh] of [[0,0,0,w,0,0,W,w],[0,H,0,H-w,0,H-w,W,w],[0,0,w,0,0,0,w,H],[W,0,W-w,0,W-w,0,w,H]]){
   const g=c.createLinearGradient(x0,y0,x1,y1);g.addColorStop(0,`rgba(255,40,25,${a})`);g.addColorStop(.25,`rgba(220,20,10,${a*.45})`);g.addColorStop(1,'rgba(200,0,0,0)');c.fillStyle=g;c.fillRect(rx,ry,rw,rh)}
  c.restore()}
 if(crackFx>.01){ensureFx();c.save();c.globalAlpha=crackFx*(.6+.2*beat);c.drawImage(crackTex,0,0,W,H);c.restore()}
 hud.style.transform=reduced?'':`scale(${1+beat*.006*hullFx})`;
}
function draw(){
 rackButton();
 c.setTransform(dpr,0,0,dpr,0,0);c.globalAlpha=1;c.globalCompositeOperation='source-over';
 if(cm&&cr&&cr.expedition){expeditionDraw();$('expedition').hidden=state!=='playing';return}
 if(state==='menu'){sub.x=350+ambient*13;sub.y=390+Math.sin(ambient*.55)*9;sub.v=Math.cos(ambient*.55)*5;camX=sub.x-vw*.63;camY=Math.max(-130,400-vh*.52);night=.12;}else camX=sub.x-vw*camLead;
 fX=sub.x;fY=sub.y;if(cm&&state!=='menu')campFocus();
 camSetup();const baseScale=scale,beat=heartbeat();
 // The view throbs with the heartbeat and swells with each laboured breath.
 if(!reduced)scale*=1+beat*.004*Math.max(hullFx,airFx*.7)+airFx*.003*(1+Math.sin(ambient*1.4));
 drawSky();drawWater();
 const unwiden=widenView();worldTransform();
 shakeX=shakeY=0;if(shake&&!reduced){shakeX=(Math.random()-.5)*shake;shakeY=(Math.random()-.5)*shake;c.translate(shakeX,shakeY)}
 drawSurface();drawTerrainDepth();if(state!=='menu')drawShips();drawTerrain();if(cm)campDrawBack();
 if(state!=='menu'){drawPickups();drawMines();drawMissiles();if(cm)campDrawFront();else drawPatrolContacts()}
 drawSonar();drawParticles();
 if((state!=='dying'&&state!=='over')||(cm&&!wreck)){drawSub();drawAbilityFx()}else if(wreck)drawSub3D(wreck.angle,wreck);
 if(state!=='menu')drawSurfaceFx();drawBooms();unwiden();distort(beat);
 c.setTransform(dpr,0,0,dpr,0,0);drawInstruments();if(cm)campDrawScreen();drawScreenBomb();
 if(night>0){let gg=c.createRadialGradient(W*.38,H*.47,Math.min(W,H)*.1,W*.4,H*.5,Math.max(W,H)*.7);gg.addColorStop(0,'#00000000');gg.addColorStop(1,`rgba(0,4,12,${night*.32})`);c.fillStyle=gg;c.fillRect(0,0,W,H)}
 drawDistress(beat);scale=baseScale;
 $('flash').style.opacity=String(flash);
}
let last=performance.now(),acc=0,slowFor=0,lastDraw=0;
const fps={el:$('fps'),gate:$('sfGate'),draws:0,since:last,worst:0};
// Draws per second, the slowest frame and the render resolution, twice a second in a corner.
function fpsTick(now,dt,covered){fps.worst=Math.max(fps.worst,dt);if(now-fps.since<500)return;
 fps.el.textContent=Math.round(fps.draws*1000/(now-fps.since))+' FPS / '+Math.round(fps.worst*1000)+' MS'+(quality<1?' / RES '+Math.round(quality*100)+'%':'')+(covered?' / PANEL':'');
 fps.draws=0;fps.since=now;fps.worst=0}
// A frame can carry a timestamp from before `last` was reset by an input handler; never step backwards.
function frame(now){let dt=clamp((now-last)/1000,0,.08);last=now;
 // A full-screen panel blurs the scene behind it, and re-blurring a moving scene every frame
 // is the costliest thing the game asks of a weak GPU, so behind a panel the ocean runs at 15 fps.
 const covered=!!panel||state==='paused'||!fps.gate.hidden;
 // On a machine that keeps missing 40 fps, draw at a lower resolution (down to 50%).
 if(!covered&&state!=='paused'){slowFor=dt>1/40?slowFor+dt:Math.max(0,slowFor-dt*.5);if(slowFor>1.5&&quality>.5){quality=Math.max(.5,quality*.8);slowFor=0;resize()}}
 if(state!=='paused'){ambient+=dt;}
 if(state==='playing'){acc+=dt;let steps=0;while(acc>=STEP&&steps<12&&state==='playing'){physics(STEP);acc-=STEP;steps++;}if(duel.run&&state==='playing')duelSample()}else acc=0;
 if(state==='watching')duelWatchStep(dt);
 if(state==='dying'||state==='over'){updateDebris(dt);updateWreck(dt)}
 if(state==='dying'&&((wreck&&wreck.settled&&ambient-wreck.settledAt>.6)||ambient-crashAt>5))finish();
 shake*=Math.exp(-dt*5);flash*=Math.exp(-dt*5);if(state!=='paused')updateCamera(dt);updateDistress(dt);
 updateMusic(dt);if(engineGain){let gain=soundOn&&state==='playing'?.024+(held?.008:0):0;engineGain.gain.setTargetAtTime(gain,audio.currentTime,.15);engine.frequency.setTargetAtTime(held?53:45,audio.currentTime,.2)}
 if(!covered||now-lastDraw>66){draw();lastDraw=now;fps.draws++}fpsTick(now,dt,covered);requestAnimationFrame(frame);
}
