'use strict';
/* Optional field operations occupy transit, never the compulsory recovery docks.
   No invisible walls or forced damage: precision earns supplies and workshop parts. */
const FIELD_BRIEFS=[
 ['relay','Harbour calibration'],['rescue','Escort survivors'],['silent','Picket blind spot'],['relay','Grozny firing solution'],
 ['survey','Coastal triangulation'],['rescue','Lifeboat trail'],['survey','Cathedral resonance'],['silent','Do not wake the mother'],
 ['relay','Current slalom'],['rescue','Emergency stores'],['survey','Map the north current'],['silent','Vepr listening net'],
 ['rescue','Prize crew evacuation'],['survey','Radar shadow'],['relay','Minefield safe lane'],['silent','Through the Gate'],
 ['survey','Debris tomography'],['silent','Wolfpack evasion'],['relay','Locate the lair'],['survey','Eye of the storm'],
 ['coolant','Core cooling run'],['coolant','Thermal sprint'],['silent','Leviathan blind spot'],['coolant','Bring the kettle home']
];
const FIELD_HELP={relay:'Pass through the numbered sonar rings in order.',rescue:'Intercept the drifting survival pods. Each recovered pod restores air.',survey:'Hold inside the blue survey band until the recorder is full.',silent:'Stay in the acoustic shadow. Firing a missile breaks the recording.',coolant:'Stay in the cold current to drain heat before extraction.'};
MISSIONS.forEach((m,i)=>m.field={kind:FIELD_BRIEFS[i][0],name:FIELD_BRIEFS[i][1]});
function fieldBuild(){
 const m=cm,end=(m.boss?m.boss.at:m.L)-650,blocked=[];
 for(const w of cr.wrecks)if(w.required)blocked.push([w.x-1050,w.x+600]);
 for(const z of m.recon||[])blocked.push([z.x0-650,z.x1+500]);
 // Dedicated arms and bosses already demand the helm's full attention.
 if(m.chase)blocked.push([m.chase.from-500,m.chase.to+350]);
 for(const x of m.cps)blocked.push([x-300,x+400]);
 const zones=[],length=m.field.kind==='rescue'?900:1500;let x=650;
 while(x+length<end){
  const block=blocked.find(([a,b])=>x<b&&x+length>a);
  if(block){x=block[1]+150;continue}
  const id=zones.length,kind=m.field.kind;
  zones.push({id,x0:x,x1:x+length,kind,name:m.field.name,done:x+length<sub.x,progress:0,total:0,heat:1,hits:0,started:false,nodes:[.23,.53,.83].map((d,j)=>({x:x+d*length,j,hit:false,passed:false}))});
  x+=2200;
 }
 // A few distinct beats per level, with breathing room for its headline encounters.
 cr.fields=zones.length<=3?zones:[zones[0],zones[Math.floor(zones.length/2)],zones[zones.length-1]];cr.field=null;
}
function fieldY(z,x){
 const u=(x-z.x0)/(z.x1-z.x0),offset=(z.kind==='relay'?Math.sin(u*TAU):z.kind==='rescue'?Math.sin(u*Math.PI):0)*65;
 return safeY(x,(cm.race?streamY(x):terrain(x).centre)+offset,75);
}
function fieldActive(){return cr&&cr.fields&&cr.fields.find(z=>!z.done&&sub.x>=z.x0-450&&sub.x<=z.x1)}
function fieldSpeed(v){
 const z=fieldActive();if(!z||cr.boss||campStation())return v;
 // Reserve reaction and reversal time even for damaged heavy boats.
 return Math.min(v,(z.kind==='rescue'?190:260)*S.agility*(t<ballastUntil?.55:1));
}
function fieldStep(dt){
 cr.field=null;if(cr.air||cr.expedition||campStation()||cr.boss)return;
 for(const z of cr.fields||[]){
  if(z.done||sub.x<z.x0-450)continue;
  if(!z.started){z.started=true;z.fired=run.fired;toast(z.name.toUpperCase(),FIELD_HELP[z.kind]+' Bonus operation: +2 scrap.',4)}
  if(sub.x<z.x0){cr.field=z;break}
  if(sub.x<=z.x1){
   cr.field=z;const inside=Math.abs(sub.y-fieldY(z,sub.x))<70;
   z.total+=dt;if(inside)z.progress+=dt;
   if(z.kind==='coolant')z.heat=clamp(z.heat+(inside?-1.5:.8)*speed*dt/(z.x1-z.x0),0,1);
   for(const n of z.nodes){
    if(n.passed)continue;
    if(Math.abs(sub.x-n.x)<S.hx+25&&Math.abs(sub.y-fieldY(z,n.x))<70){n.hit=true;n.passed=true;z.hits++;csfx.radio();if(z.kind==='rescue'){o2=Math.min(S.o2,o2+S.o2*.12);airCollected++}}
    else if(sub.x>n.x+S.hx+25)n.passed=true;
   }
   break;
  }
  z.done=true;
  const ok=z.kind==='relay'||z.kind==='rescue'?z.hits===3:z.kind==='coolant'?z.heat<.15:z.progress/Math.max(.01,z.total)>=.65&&(z.kind!=='silent'||run.fired===z.fired);
  z.success=ok;
  if(ok){addParts([2,0,0]);o2=Math.min(S.o2,o2+S.o2*.12);toast('FIELD OPERATION COMPLETE',z.name+' / +2 scrap / air replenished',2.5);csfx.checkpoint()}
  else toast('FIELD OPERATION MISSED',z.name+' / Continue to the next objective.',2);
 }
}
function fieldDraw(){
 if(!cr||cr.air||cr.expedition||cr.boss)return;
 for(const z of cr.fields||[]){
  if(z.done||z.x1<camX||z.x0>camX+vw+400)continue;
  c.save();const col=z.kind==='coolant'?'#72d4f2':z.kind==='rescue'?'#f1ca88':'#9ce4d4';
  if(['survey','silent','coolant'].includes(z.kind)){
   c.beginPath();for(let x=z.x0;x<=z.x1;x+=30){const y=fieldY(z,x);x===z.x0?c.moveTo(x,y-70):c.lineTo(x,y-70)}
   for(let x=z.x1;x>=z.x0;x-=30)c.lineTo(x,fieldY(z,x)+70);c.closePath();c.fillStyle=col+'18';c.fill();c.strokeStyle=col+'65';c.setLineDash([12,10]);c.stroke();c.setLineDash([]);
   for(let x=z.x0+100;x<z.x1;x+=170){const y=fieldY(z,x),pulse=reduced?0:Math.sin(ambient*2+x)*5;path([[x-8,y-8+pulse],[x,y+pulse],[x-8,y+8+pulse]],null,col+'99',2)}
  }else for(const n of z.nodes){
   const y=fieldY(z,n.x);c.globalAlpha=n.passed?(n.hit?.3:.15):.9;
   circle(n.x,y,70,null,col,2);circle(n.x,y,75,null,col+'44',1);
   if(z.kind==='rescue'){c.fillStyle='#344c56';c.fillRect(n.x-14,y-12,28,24);c.fillStyle=col;c.fillRect(n.x-3,y-8,6,16);c.fillRect(n.x-8,y-3,16,6)}
   tag(n.x,y-88,(n.hit?'RECOVERED ':z.kind==='rescue'?'SURVIVOR ':'RELAY ')+(n.j+1),col);
  }
  c.globalAlpha=1;tag(z.x0+60,fieldY(z,z.x0)-100,z.name.toUpperCase(),col);c.restore();
 }
}
function fieldDrawHUD(){
 const z=cr&&cr.field;if(!z||cr.air||cr.expedition||cr.boss)return;
 const progress=z.kind==='relay'||z.kind==='rescue'?z.hits/3:z.kind==='coolant'?1-z.heat:z.progress/Math.max(.01,z.total);
 const text=z.kind==='relay'||z.kind==='rescue'?z.hits+'/3 RECOVERED':z.kind==='coolant'?'HEAT '+Math.round(z.heat*100)+'%':z.kind==='silent'&&run.fired!==z.fired?'SIGNATURE DETECTED':Math.round(progress*100)+'% LOCK / NEED 65%';
 c.save();const width=Math.min(300,W-32),x=(W-width)/2,y=H-(W<700?198:100);
 c.fillStyle='#03131ee8';c.fillRect(x,y,width,52);c.fillStyle='#bcece1';c.font='11px monospace';c.textAlign='center';c.fillText(z.name.toUpperCase(),W/2,y+17);c.fillText(text,W/2,y+33);c.fillStyle='#29434c';c.fillRect(x+12,y+42,width-24,3);c.fillStyle='#8cdece';c.fillRect(x+12,y+42,(width-24)*clamp(progress,0,1),3);c.restore();
}
