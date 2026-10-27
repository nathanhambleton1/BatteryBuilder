'use strict';
/* ROV sorties use their own clock; campaign physics holds until recovery. */
function expeditionStart(w){
 if(!droneInit()){toast('3D DRONE UNAVAILABLE','Enable hardware acceleration or try a WebGL-capable browser.',6,true);return}
 const seed=campSeed(cm)+w.i*977,random=mulberry(seed),kind=w.k==='core'?'core':w.k==='relay'?'relay':w.k==='mineRig'?'disarm':'salvage',variant=w.i%3;
 const e={w,kind,seed,phase:'launch',phaseTime:0,x:0,y:14,z:24,vx:0,vy:0,vz:0,yaw:0,pitch:-.12,clock:0,battery:150+8*(camp.data.up.drone||0),hp:3,hit:-9,scan:0,pulse:-9,grip:0,cargo:false,extra:0,heat:0,toolWindow:true,notice:'',noticeUntil:12,dock:{x:0,y:14,z:24}};
 e.target={x:(variant===1?-1:1)*(12+variant*2),y:2.5+variant,z:-27};
 e.nodes=kind==='relay'?[{x:-15,y:8,z:3,done:false},{x:15,y:11,z:-13,done:false}]:[];
 if(cm.ch>=2&&kind==='relay')e.nodes.push({x:-4,y:5,z:-33,done:false});
 e.rocks=[];for(let i=0;i<24;i++){const x=(random()-.5)*95,z=(random()-.5)*105,r=1.5+random()*4;if(Math.abs(x)<20&&z>-40&&z<32)continue;e.rocks.push({x,y:droneFloor(x,z)+r*.35,z,r})}
 e.structure=[{x:-5,y:.1,z:-22,sx:6,sy:.4,sz:11},{x:-10.6,y:1.6,z:-22,sx:.4,sy:1.8,sz:11},{x:1,y:1.1,z:-22,sx:.4,sy:1.2,sz:8},{x:-5,y:2,z:-32.5,sx:5.5,sy:2,sz:.35},{x:-5,y:1,z:-12,sx:3.5,sy:.6,sz:.4}];
 e.vents=[{x:-19,z:-14,phase:random()*6},{x:23,z:5,phase:random()*6}];e.mines=[{x:8,y:7,z:-6,r:1},{x:-21,y:10,z:-23,r:1.2}];
 e.items=[{x:-13,y:3,z:-5,taken:false},{x:24,y:6,z:-21,taken:false}];
 e.notice=kind==='relay'?'Scan the numbered relays in order, recover the recorder, then dock.':kind==='core'?'Scan the Core. Use short tool bursts and release F to cool.':kind==='disarm'?'Scan the controller. Work during its green isolation window.':'Find the payload, scan with Q, hold F to secure it, then return to dock.';
 cr.expedition=e;w.busy=true;clearInput();expeditionPanel(true);csfx.drone();
}
function expeditionPanel(on){
 let box=$('expedition');if(!box){box=document.createElement('section');box.id='expedition';box.setAttribute('aria-label','3D drone flight controls');
 box.innerHTML='<div id="rovLook" aria-label="Drag to look around the wreck site"></div><div class="rov-top"><span>REMORA / ROV-03 · LIVE FEED</span><div class="rov-actions"><button id="rovSkip">Skip deployment</button><button id="rovRecall">Recall</button><button id="rovPause">Pause</button></div></div><div class="rov-flight-help">WASD fly · SPACE rise · C descend · ARROWS or drag to look · SHIFT boost</div><div class="rov-bottom"><div class="rov-steer"><button data-rov="KeyA" aria-label="Strafe left">←</button><button data-rov="KeyW" aria-label="Fly forward">↑</button><button data-rov="KeyS" aria-label="Fly backward">↓</button><button data-rov="KeyD" aria-label="Strafe right">→</button><button data-rov="Space" aria-label="Ascend">RISE</button><button data-rov="KeyC" aria-label="Descend">DIVE</button></div><div class="rov-actions"><button id="rovScan">Q · SONAR</button><button data-rov="KeyF" id="rovTool">HOLD F · TOOL</button></div></div>';
 document.body.append(box);box.querySelectorAll('[data-rov]').forEach(b=>{const key=b.dataset.rov;b.addEventListener('pointerdown',ev=>{ev.preventDefault();if(state!=='playing')return;inputKeys.add(key);b.setPointerCapture(ev.pointerId)});for(const event of ['pointerup','pointercancel','lostpointercapture'])b.addEventListener(event,()=>inputKeys.delete(key))});
 const look=$('rovLook');let drag=null;look.addEventListener('pointerdown',ev=>{if(state!=='playing')return;ev.preventDefault();drag={id:ev.pointerId,x:ev.clientX,y:ev.clientY};look.setPointerCapture(ev.pointerId)});
 look.addEventListener('pointermove',ev=>{const e=cr&&cr.expedition;if(!drag||ev.pointerId!==drag.id||!e||e.phase!=='pilot'||state!=='playing')return;e.yaw+=(ev.clientX-drag.x)*.005;e.pitch=clamp(e.pitch-(ev.clientY-drag.y)*.004,-1.25,1.25);drag.x=ev.clientX;drag.y=ev.clientY});
 for(const event of ['pointerup','pointercancel','lostpointercapture'])look.addEventListener(event,()=>drag=null);
 $('rovScan').onclick=expeditionScan;$('rovRecall').onclick=()=>expeditionEnd(false,'Recovery tether engaged. Relaunch from the same site.');$('rovPause').onclick=pause;
 $('rovSkip').onclick=()=>{const e=cr&&cr.expedition;if(e&&e.phase==='launch'&&state==='playing'){e.phase='pilot';e.phaseTime=0;clearInput()}};
 }box.hidden=!on;document.body.classList.toggle('rov-active',on);
}
function expeditionScan(){const e=cr&&cr.expedition;if(!e||state!=='playing'||e.phase!=='pilot'||e.clock-e.pulse<2)return;e.pulse=e.clock;e.scan=6;csfx.radio();const n=e.nodes.find(n=>!n.done);if(n&&droneDistance(e,n)<5){n.done=true;e.notice='Relay synchronized. '+(e.nodes.every(n=>n.done)?'Recover the recorder.':'Proceed to the next relay.');e.noticeUntil=e.clock+3}}
function expeditionEnd(success,msg){const e=cr&&cr.expedition;if(!e)return;e.w.busy=false;cr.expedition=null;expeditionPanel(false);clearInput();if(success){deliver(e.w);if(e.extra)addParts([e.extra,0,0]);o2=Math.min(S.o2,o2+S.o2*.18)}else toast('DRONE RECOVERED',msg,3,true);cr.droneCool=t+.25}
function expeditionStep(dt){
 const e=cr.expedition;if(!e||state!=='playing')return;e.clock+=dt;e.phaseTime+=dt;camp.run.time+=dt;
 if(e.hp<=0||e.battery<=0)return expeditionEnd(false,e.hp<=0?'Recovery tether saved the drone. Relaunch to try again.':'Battery exhausted. Relaunch from the recovery dock.');
 if(e.phase==='launch'){if(e.phaseTime>=3.2){e.phase='pilot';e.phaseTime=0;clearInput()}return}
 if(e.phase==='dock'){if(e.phaseTime>=1.6)expeditionEnd(true);return}if(DroneWorld.lost)return;
 e.battery-=dt;e.scan=Math.max(0,e.scan-dt);const axis=(a,b)=>(inputKeys.has(a)?1:0)-(inputKeys.has(b)?1:0);
 e.yaw+=axis('ArrowRight','ArrowLeft')*1.45*dt;e.pitch=clamp(e.pitch+axis('ArrowUp','ArrowDown')*1.15*dt,-1.25,1.25);
 const boost=inputKeys.has('ShiftLeft')||inputKeys.has('ShiftRight'),mass=(e.cargo?.78:1)*(1+.15*(camp.data.up.drone||0)),thrust=18*mass*(boost?1.65:1);
 let ax=axis('KeyD','KeyA'),az=axis('KeyW','KeyS'),ay=(inputKeys.has('Space')?1:0)-(inputKeys.has('KeyC')||inputKeys.has('ControlLeft')||inputKeys.has('ControlRight')?1:0);const norm=Math.max(1,Math.hypot(ax,ay,az));ax/=norm;ay/=norm;az/=norm;
 const co=Math.cos(e.yaw),si=Math.sin(e.yaw),flow=cm.ch>=2?Math.sin(e.clock*.4+e.z*.05)*.3:0;
 e.vx+=((ax*co+az*si)*thrust+flow-e.vx*2.7)*dt;e.vz+=((ax*si-az*co)*thrust-e.vz*2.7)*dt;e.vy+=(ay*thrust-e.vy*3)*dt;
 e.x+=e.vx*dt;e.y+=e.vy*dt;e.z+=e.vz*dt;if(boost)e.battery-=dt*.45;const velocity=Math.hypot(e.vx,e.vy,e.vz);
 const hit=msg=>{if(e.clock-e.hit<1.5)return;e.hit=e.clock;e.hp--;e.notice=msg;e.noticeUntil=e.clock+3;csfx.alarm()};
 const stop=()=>{if(velocity>3.5)hit('Hull contact. Release thrust and approach slowly.');e.vx*=.1;e.vy*=.1;e.vz*=.1};
 const floor=droneFloor(e.x,e.z)+.7;if(e.y<floor){e.y=floor;stop()}if(e.y>25){e.y=25;e.vy=Math.min(0,e.vy)}
 for(const a of ['x','z'])if(Math.abs(e[a])>49){e[a]=clamp(e[a],-49,49);e['v'+a]=0;e.notice='Tether limit. Turn toward the operation site.';e.noticeUntil=e.clock+2}
 for(const r of e.rocks){const dx=e.x-r.x,dy=(e.y-r.y)/.8,dz=e.z-r.z,d=Math.hypot(dx,dy,dz),lim=r.r+.65;if(d<lim){const n=d||1;e.x=r.x+(d?dx/n:1)*lim;e.y=r.y+dy/n*lim*.8;e.z=r.z+dz/n*lim;stop()}}
 for(const b of e.structure){const d=[e.x-b.x,e.y-b.y,e.z-b.z],p=[b.sx+.65-Math.abs(d[0]),b.sy+.65-Math.abs(d[1]),b.sz+.65-Math.abs(d[2])];if(p.every(v=>v>0)){const i=p.indexOf(Math.min(...p));e[['x','y','z'][i]]+=Math.sign(d[i]||1)*p[i];stop()}}
 // The mothership's hull is solid; the recovery cradle below it remains open.
 {const dx=e.x/12.65,dy=(e.y-24)/3.85,dz=(e.z-27)/4.65,d=Math.hypot(dx,dy,dz);if(d<1){e.x=dx/(d||1)*12.65;e.y=24+dy/(d||1)*3.85;e.z=27+dz/(d||1)*4.65;stop()}}
 for(const m of e.mines)if(droneDistance(e,m)<m.r+.65)hit('Live charge. Fly above or around it.');
 for(const v of e.vents){const phase=(e.clock+v.phase)%6;if(phase>3.3&&phase<5.2&&Math.hypot(e.x-v.x,e.z-v.z)<1.7&&e.y<8){hit('Thermal plume. Move away from the vent.');e.vy+=dt*8}}
 e.toolWindow=e.kind!=='disarm'||e.clock%4.8<2.4;
 const near=droneDistance(e,e.target)<2.8,tool=inputKeys.has('KeyF'),ready=e.nodes.every(n=>n.done),working=!e.cargo&&near&&tool&&e.scan>0&&ready&&e.toolWindow&&velocity<1.8;
 e.heat=clamp(e.heat+(working?.48:-.8)*dt,0,1);
 if(working&&!(e.kind==='core'&&e.heat>.88)){e.grip+=dt/(e.kind==='core'?3.2:e.kind==='disarm'?1.8:1.1);if(e.grip>=1){e.cargo=true;e.notice='Payload secured. Follow the green dock marker. Approach slowly to recover.';e.noticeUntil=e.clock+5;if(e.kind==='disarm')e.mines=[];csfx.salvage()}}
 else if(!e.cargo&&e.kind!=='disarm')e.grip=Math.max(0,e.grip-dt*.3);
 for(const item of e.items)if(!item.taken&&tool&&droneDistance(e,item)<2){item.taken=true;e.extra+=2;csfx.relic()}
 if(e.cargo&&droneDistance(e,e.dock)<2.8&&velocity<2){e.phase='dock';e.phaseTime=0;clearInput()}
}
function expeditionInstruction(e){
 if(e.phase==='launch')return 'CRADLE RELEASE · CAMERA HANDOVER';if(e.phase==='dock')return 'RECOVERY CLAMPS ENGAGED · PAYLOAD TRANSFER';if(e.clock<e.noticeUntil)return e.notice;
 if(e.cargo)return droneDistance(e,e.dock)<4?'Release thrust. Hold position inside the green cradle.':'Return to the green dock marker.';
 if(e.nodes.some(n=>!n.done))return 'Approach relay '+(e.nodes.findIndex(n=>!n.done)+1)+' within 5 m and press Q.';
 if(droneDistance(e,e.target)>2.8)return 'Follow the payload marker. WASD fly · Space rise · C descend.';
 if(e.scan<=0)return 'Press Q to scan the payload.';if(Math.hypot(e.vx,e.vy,e.vz)>=1.8)return 'Release thrust to stabilize before using the tool.';
 if(!e.toolWindow)return 'LIVE CIRCUIT · Wait for the green isolation window.';if(e.kind==='core'&&e.heat>.78)return 'TOOL HOT · Release F to cool.';return 'Hold F / TOOL to secure the payload.';
}
function expeditionDraw(){
 const e=cr&&cr.expedition;if(!e)return;c.save();if(droneRender(e,W,H))c.drawImage(DroneWorld.canvas,0,0,W,H);else{c.fillStyle='#04141d';c.fillRect(0,0,W,H);c.fillStyle='#ecc69b';c.font='16px monospace';c.fillText('3D feed interrupted. Recall the drone to relaunch.',20,H/2)}
 $('rovSkip').hidden=e.phase!=='launch';$('rovTool').disabled=$('rovScan').disabled=e.phase!=='pilot';const compact=W<700,margin=compact?16:34;
 if(e.phase==='pilot'){
  const v=c.createRadialGradient(W/2,H/2,H*.12,W/2,H/2,Math.max(W,H)*.6);v.addColorStop(0,'#00101800');v.addColorStop(1,'#000811bb');c.fillStyle=v;c.fillRect(0,0,W,H);
  c.strokeStyle='#74cbb977';c.lineWidth=1;c.beginPath();for(const [x,y,dx,dy] of [[-12,0,8,0],[4,0,8,0],[0,-12,0,8],[0,4,0,8]]){c.moveTo(W/2+x,H/2+y);c.lineTo(W/2+x+dx,H/2+y+dy)}c.stroke();
  for(const side of [-1,1]){const x=W/2+side*W*.3;path([[x,H],[x-side*28,H*.82],[x-side*70,H*.76],[x-side*78,H*.79],[x-side*45,H*.85],[x-side*18,H]],'#152b34','#456465',2)}
  const target=e.cargo?e.dock:e.nodes.find(n=>!n.done)||e.target,label=e.cargo?'RECOVERY DOCK':e.nodes.some(n=>!n.done)?'RELAY '+(e.nodes.findIndex(n=>!n.done)+1):'PAYLOAD',p=droneProject(target,W,H),dist=droneDistance(e,target);
  if(p){const x=p.behind?W/2:clamp(p.x,75,W-75),y=p.behind?H*.6:clamp(p.y,135,H-240);c.strokeStyle=e.cargo?'#8ff0c2':'#f1ce8c';c.fillStyle=c.strokeStyle;c.lineWidth=1.5;c.strokeRect(x-12,y-12,24,24);c.textAlign='center';c.font='11px monospace';c.fillText(label+' · '+dist.toFixed(1)+' m',x,y-23);if(p.behind)c.fillText('TURN AROUND',x,y+29)}
  c.textAlign='center';c.font='12px monospace';c.fillStyle='#bbddd6';c.fillText(String((Math.round(e.yaw*180/Math.PI)%360+360)%360).padStart(3,'0')+'°',W/2,compact?130:112);
  if(e.scan>0){c.strokeStyle='#9ce6cf55';c.beginPath();c.arc(W/2,H/2,(e.clock-e.pulse)*Math.min(W,H)*.3,0,TAU);c.stroke()}
 }
 c.textAlign='left';c.fillStyle='#d7ede7';c.font=(compact?'12':'14')+'px monospace';c.fillText(e.kind==='core'?'THERMAL CORE / EXTRACTION':e.kind==='relay'?'ACOUSTIC RELAY / RECOVERY':e.kind==='disarm'?'MINE NETWORK / ISOLATION':'WRECK SITE / SALVAGE',margin,90);
 c.font='11px monospace';c.fillStyle=e.battery<25?'#ff9b7c':'#a4d1c7';c.fillText('BAT '+Math.ceil(e.battery)+'s   HULL '+e.hp+'/3   ALT '+Math.max(0,e.y-droneFloor(e.x,e.z)).toFixed(1)+'m',margin,110);if(!compact)c.fillText('THRUST '+Math.hypot(e.vx,e.vy,e.vz).toFixed(1)+' m/s   CARGO '+(e.cargo?'SECURED':'EMPTY'),margin,132);
 const bottom=compact?H-215:H-145,width=Math.min(W-32,620),left=(W-width)/2;c.fillStyle='#03131de8';c.fillRect(left,bottom,width,76);c.fillStyle='#dfdfbd';c.font='12px monospace';c.textAlign='center';let line='',y=bottom+22;for(const word of expeditionInstruction(e).split(' ')){if(c.measureText(line+word).width>width-24){c.fillText(line,W/2,y);y+=17;line=''}line+=word+' '}c.fillText(line,W/2,y);
 if(!e.cargo&&e.grip>0){c.fillStyle='#5cddbb';c.fillRect(left+12,bottom+66,(width-24)*Math.min(1,e.grip),3)}if(e.kind==='core'&&!e.cargo){c.fillStyle=e.heat>.78?'#ff9b7c':'#e7bb77';c.fillRect(left+12,bottom+71,(width-24)*e.heat,3)}
 if(e.phase!=='pilot'){c.fillStyle='#000';c.fillRect(0,0,W,Math.min(48,H*.06));c.fillRect(0,H-45,W,45);c.fillStyle='#a6ead5';c.font='12px monospace';c.fillText(e.phase==='launch'?'ROV-03 / DEPLOYING':'ROV-03 / DOCKING',W/2,H*.22)}
 if(e.clock-e.hit<.35){c.fillStyle='#ff503322';c.fillRect(0,0,W,H)}c.restore();
}
addEventListener('keydown',ev=>{const e=cr&&cr.expedition;if(!e||state!=='playing')return;if(['KeyQ','KeyF','Space','ControlLeft','ControlRight','ShiftLeft','ShiftRight','KeyW','KeyA','KeyS','KeyD','ArrowUp','ArrowDown','ArrowLeft','ArrowRight','KeyE','KeyC','KeyX'].includes(ev.code)){ev.preventDefault();ev.stopImmediatePropagation();if(ev.code==='KeyQ'){if(!ev.repeat)expeditionScan()}else if(e.phase==='pilot')inputKeys.add(ev.code)}},true);
