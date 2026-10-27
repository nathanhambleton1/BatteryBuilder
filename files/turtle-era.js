'use strict';
// A gameplay lantern, styled after early submersibles rather than modern sonar.
const turtleEra=()=>S.id==='turtle';
function turtleLamp(){return {x:sub.x+S.hx*.5,y:sub.y-3,angle:Math.sin(t*1.6)*.36,half:.64,range:Math.max(650,speed*2.4)}}
function turtleLightAt(x,y){
 const b=turtleLamp(),dx=x-b.x,dy=y-b.y,d=Math.hypot(dx,dy),angle=Math.abs(angDiff(Math.atan2(dy,dx),b.angle));
 if(d>b.range||angle>b.half)return 0;
 for(let i=1;i<=8;i++){const u=i/8,xx=mix(b.x,x,u),yy=mix(b.y,y,u),z=terrain(xx);if(yy<z.top||yy>z.bottom)return 0}
 return clamp((b.range-d)/90,0,1)*clamp((b.half-angle)/.12,0,1);
}
function turtleBeamPath(){const b=turtleLamp();c.beginPath();c.moveTo(b.x,b.y);c.arc(b.x,b.y,b.range,b.angle-b.half,b.angle+b.half);c.closePath()}
function drawTurtleLamp(){
 if(!turtleEra()||state==='menu')return;const b=turtleLamp();c.save();turtleBeamPath();c.clip();c.globalCompositeOperation='screen';
 const g=c.createRadialGradient(b.x,b.y,0,b.x,b.y,b.range);g.addColorStop(0,'#fff4bc88');g.addColorStop(.18,'#ffd77535');g.addColorStop(.72,'#efc56a13');g.addColorStop(1,'#efc56a00');c.fillStyle=g;c.fillRect(b.x-b.range,b.y-b.range,b.range*2,b.range*2);
 c.restore();glow(b.x,b.y,24,'#ffe6a680');circle(b.x,b.y,3,'#fff5c8');
}
function drawPowderMine(x,y,alpha){
 const lit=turtleLightAt(x,y);if(!lit)return;c.save();c.globalAlpha=Math.min(alpha,lit);c.translate(x,y);billboard();c.rotate(Math.sin(ambient*.7+x)*.06);
 const g=c.createLinearGradient(-18,0,18,0);g.addColorStop(0,'#4e301b');g.addColorStop(.4,'#ba8c4c');g.addColorStop(1,'#644326');
 c.fillStyle=g;c.strokeStyle='#ddbd7e';c.lineWidth=1.2;c.beginPath();c.ellipse(0,0,18,21,0,0,TAU);c.fill();c.stroke();
 c.save();c.clip();for(let xx=-15;xx<18;xx+=6){c.strokeStyle='#4d321e';c.beginPath();c.moveTo(xx,-22);c.quadraticCurveTo(xx+3,0,xx,22);c.stroke()}for(const yy of [-13,10]){c.fillStyle='#665e48';c.fillRect(-20,yy,40,4)}c.restore();
 c.strokeStyle='#d0b67b';c.lineWidth=2;c.beginPath();c.moveTo(0,-20);c.quadraticCurveTo(5,-28,10,-23);c.stroke();circle(0,0,5,'#694522','#c8a669',1);c.restore();
}
function drawTurtleMines(){
 for(const g of gates){if(g.x<camX-80||g.x>camX+vw+80)continue;const z=terrain(g.x);for(let k=0;k<2;k++){
 if(g.dead[k])continue;const y=mineY(g,k),lit=turtleLightAt(g.x,y);if(!lit)continue;
 c.save();turtleBeamPath();c.clip();c.globalAlpha=lit;c.strokeStyle='#ad9567';c.lineWidth=1.7;c.beginPath();c.moveTo(g.x,k?z.bottom:z.top);c.lineTo(g.x,y);c.stroke();c.restore();drawPowderMine(g.x,y,lit);
 }}
}
function drawSailingWarship(s){
 const sink=s.sinking?t-s.sinking:0;c.save();c.translate(s.x,SURFACE+2+sink*22+Math.sin(ambient*1.4+s.x)*1.2);c.rotate(s.sinking?Math.min(.32,sink*.09):Math.sin(ambient*.9+s.x)*.012);c.globalAlpha=s.sinking?clamp(1-(sink-2.5)/2.2,0,1):1;
 const wood=rgb([123,77,40],[65,44,31],night),sail=rgb([235,219,173],[120,125,116],night);
 path([[-100,-20],[-77,-12],[80,-12],[108,-28],[97,3],[72,12],[-80,12]],wood,'#d4a767',1.3);
 for(const yy of [-5,2,8]){c.strokeStyle='#241c17';c.lineWidth=1;c.beginPath();c.moveTo(-86,yy);c.lineTo(89,yy);c.stroke()}
 for(let x=-70;x<80;x+=23){c.fillStyle='#241e19';c.fillRect(x,-9,8,6);c.strokeStyle='#686252';c.lineWidth=3;c.beginPath();c.moveTo(x+4,-6);c.lineTo(x+14,-6);c.stroke()}
 for(const [x,h]of [[-48,94],[8,126],[58,86]]){
 c.strokeStyle='#8a663c';c.lineWidth=3;c.beginPath();c.moveTo(x,-12);c.lineTo(x,-h);c.stroke();
 for(const frac of [.35,.68]){const y=-h*frac-12,w=h*.25,belly=Math.sin(ambient*1.6+x)*3;c.fillStyle=sail;c.strokeStyle='#998965';c.lineWidth=.8;c.beginPath();c.moveTo(x-w,y);c.quadraticCurveTo(x,y+8+belly,x+w,y);c.lineTo(x+w*.78,y+25);c.quadraticCurveTo(x,y+34+belly,x-w*.78,y+25);c.closePath();c.fill();c.stroke();c.strokeStyle='#b9a580';c.beginPath();c.moveTo(x,y);c.lineTo(x,y+28);c.stroke()}
 c.strokeStyle='#aa98705e';c.lineWidth=.8;for(const end of [x-28,x+28]){c.beginPath();c.moveTo(x,-h);c.lineTo(end,-13);c.stroke()}
 }
 path([[8,-126],[32,-122],[10,-115]],'#a9563a');c.strokeStyle='#d8c5a2';c.lineWidth=2;c.beginPath();c.moveTo(91,-20);c.lineTo(127,-40);c.stroke();
 if(s.hp<s.max||s.sinking)glow(-20,-15,32,'#ff993d66');c.restore();
 if(!s.sinking){c.save();c.font='8px ui-monospace,monospace';c.fillStyle='#e8bd81';c.fillText('HOSTILE FRIGATE',s.x-36,SURFACE-146);for(let i=0;i<s.max;i++){c.fillStyle=i<s.hp?'#e8bd81':'#e8bd8133';c.fillRect(s.x-s.max*5+i*10+1,SURFACE-137,8,3)}c.restore()}
}
