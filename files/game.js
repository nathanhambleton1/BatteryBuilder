'use strict';
/* Sonar keeps pace with the boat: the faster it runs, the more often it pings and
   the further and faster each ping travels, so mines show up one to two seconds
   ahead at any level or boost. Echoes fade a little before the next ping lands. */
const sonarGap=()=>2.15*S.sonar*clamp(300/Math.max(speed,1),.6,1);
const sonarGlow=()=>Math.max(1.65,sonarGap()*.85);
function ping(){if((state!=='playing'&&state!=='watching')||t<sonarDownUntil||t-lastPing<sonarGap())return false;lastPing=t;pings.push({x:sub.x,y:sub.y,born:t,r:0,c:SOUND_SPEED+2.5*speed,range:SONAR_RANGE+1.6*speed,hit:new Set()});sfx.ping();return true;}
function updateSonar(dt){
 if(night>.06&&t-lastPing>=sonarGap())ping();
 for(const p of pings){p.r=(t-p.born)*p.c;for(const g of gates)for(let k=0;k<2;k++){if(g.dead[k])continue;const key=g.x+':'+k, my=mineY(g,k),dist=Math.hypot(g.x-p.x,my-p.y);if(dist<=p.range&&dist<=p.r&&!p.hit.has(key)){p.hit.add(key);echoes.push({x:g.x,y:my,ox:g.x,oy:my,g,k,c:p.c,born:t});}}}
 pings=pings.filter(p=>p.r<p.range);
 for(let i=echoes.length-1;i>=0;i--){let e=echoes[i],dx=sub.x-e.x,dy=sub.y-e.y,dist=Math.hypot(dx,dy);if(dist<e.c*dt+8){e.g.echo[e.k]=t;if(e.g.x>sub.x-100&&e.g.x<sub.x+700)sfx.echo();echoes.splice(i,1);}else {e.x+=dx/dist*e.c*dt;e.y+=dy/dist*e.c*dt;}}
}
/* Weapons. Player missiles lock onto the most urgent target at launch:
   an incoming missile, then a warship, then the nearest mine ahead. */
const reloadTime=()=>active('rapid')?.5:S.reload;
function launch(target,vy=0,life=4.2){run.fired++;missiles.push({x:sub.x+S.hx*.9,y:sub.y+3,vx:speed+150,vy:sub.v*.3+15+vy,target,life})}
function fire(){
 if(state!=='playing'||(cm&&!campCanFire()))return;
 if(t-lastFire<reloadTime()){if(t-lastFire>.25)tone(150,.07,.02,120);return}
 lastFire=t;launch(acquire());if(!practice)ach.st.fired++;
 sfx.launch();for(let i=0;i<10;i++)bubbles.push({x:sub.x+S.hx,y:sub.y+(Math.random()-.5)*8,r:1+Math.random()*2.5,life:1+Math.random(),vx:speed*.6+Math.random()*60,vy:-10-Math.random()*30});
}
// skip lists targets already claimed (missiles, ships, or 'x:k' mine keys).
function acquire(skip=[]){
 let found=null,bestD=Infinity;
 // Unguided torpedoes can be dodged, so they only take priority once they are close.
 for(const m of enemyMissiles){if(m.air||skip.includes(m))continue;const d=Math.hypot(m.x-sub.x,m.y-sub.y);if(d<(m.torp?240:420)&&d<bestD){bestD=d;found={missile:m}}}
 if(found)return found;
 if(cm){found=campAcquire(skip);if(found)return found}
 if(terrain(sub.x).cave<.3)for(const s of ships){if(s.sinking||skip.includes(s)||s.x<sub.x-120||s.x>sub.x+1500||terrain(s.x).cave>.15)continue;const d=Math.abs(s.x-sub.x);if(d<bestD){bestD=d;found={ship:s}}}
 if(found)return found;
 for(const g of gates){if(g.x<sub.x+S.hx+30||g.x>sub.x+950)continue;for(let k=0;k<2;k++){if(g.dead[k]||skip.includes(g.x+':'+k))continue;const d=(g.x-sub.x)+Math.abs(mineY(g,k)-sub.y)*2;if(d<bestD){bestD=d;found={gate:g,k}}}}
 return found;
}
/* Special abilities (E). Each class has one; timed ones run until abilityUntil.
   An ability that would do nothing right now is refused without spending the charge. */
const active=id=>S.ability.id===id&&t<abilityUntil;
function useAbility(){
 if(state!=='playing')return;
 const A=S.ability;
 if(t-abilityAt<A.cd){if(t-abilityAt>.25)tone(150,.07,.02,120);return}
 const refuse=(title,body)=>{toast(title,body,1.8);tone(150,.12,.03,110);return false};
 if(cm&&['salvo','strike','rapid'].includes(A.id)&&!campCanFire())return;
 let ok=true;
 if(A.id==='salvo'){const taken=[];for(let i=0;i<3;i++){const tg=acquire(taken);if(tg)taken.push(tg.missile||tg.ship||tg.gate.x+':'+tg.k);launch(tg,(i-1)*110)}
  for(let i=0;i<24;i++)bubbles.push({x:sub.x+S.hx,y:sub.y+(Math.random()-.5)*14,r:1+Math.random()*2.5,life:1+Math.random(),vx:speed*.6+Math.random()*60,vy:-10-Math.random()*30})}
 else if(A.id==='strike'){let n=0;
  if(terrain(sub.x).cave<.3)for(const s of ships){if(s.sinking||s.x<camX-100||s.x>camX+vw+200||terrain(s.x).cave>.15)continue;for(let i=0;i<s.hp;i++){launch({ship:s},-420-i*70,5.5);n++}}
  for(const m of enemyMissiles)if(Math.hypot(m.x-sub.x,m.y-sub.y)<700){launch({missile:m},-160);n++}
  if(cm)n+=campStrike();
  if(!n)ok=refuse('NO TARGETS','No warships or seekers in range. Charge held.')}
 else if(A.id==='air'){if(o2>=S.o2*.97&&t>=leakUntil)ok=refuse('AIR TANKS FULL','Charge held for when you need it.');else{o2=Math.min(S.o2,o2+S.o2*.5);leakUntil=0;lowO2Warned=false}}
 else if(A.id==='repair'){if(hull>=S.hull&&t>=sonarDownUntil&&t>=leakUntil&&t>=ballastUntil)ok=refuse('ALL SYSTEMS NOMINAL','Nothing to repair. Charge held.');else{hull=Math.min(S.hull,hull+1);sonarDownUntil=leakUntil=ballastUntil=0}}
 else if(A.id==='silent'){for(const m of enemyMissiles)m.seek=0}
 else if(A.id==='rapid'){lastFire=-99}
 if(!ok)return;
 abilityAt=t;abilityUntil=t+(A.dur||0);run.ability++;if(!practice){ach.st.ability++;ach.st.abil[S.id]=1}lastHud=-1;toast(A.name,A.desc,2.2);sfx.ability();
}
function targetPos(tg){
 if(!tg)return null;
 if(tg.camp)return campTargetPos(tg);
 if(tg.missile)return enemyMissiles.includes(tg.missile)?[tg.missile.x,tg.missile.y]:null;
 if(tg.ship)return !tg.ship.sinking&&ships.includes(tg.ship)?[tg.ship.x,SURFACE+2]:null;
 return !tg.gate.dead[tg.k]&&gates.includes(tg.gate)?[tg.gate.x,mineY(tg.gate,tg.k)]:null;
}
function boom(x,y,size){booms.push({x,y,size,born:ambient});for(let i=0;i<size*.7;i++){let a=Math.random()*TAU,s=20+Math.random()*size*5;debris.push({x,y,vx:Math.cos(a)*s,vy:Math.sin(a)*s,life:.4+Math.random()*.8,r:.8+Math.random()*2.6,hot:Math.random()<.55})}sfx.boom(size)}
function splash(x){for(let i=0;i<14;i++)bubbles.push({x:x+(Math.random()-.5)*16,y:SURFACE+4+Math.random()*10,r:1+Math.random()*3,life:.8+Math.random(),vx:(Math.random()-.5)*40,vy:-10-Math.random()*25})}
function detonateMine(g,k,byMissile){g.dead[k]=true;boom(g.x,mineY(g,k),34);if(byMissile){minesDestroyed++;bonus+=25}}
function hitShip(s,x,y){s.hp--;s.hitAt=t;boom(x,y,30);if(s.hp<=0){s.sinking=t;shipsSunk++;bonus+=250;boom(s.x,SURFACE-8,60);toast('WARSHIP SUNK','+250. More will follow.',2.2);sfx.sunk()}}
function updateMissiles(dt){
 for(let i=missiles.length-1;i>=0;i--){
  const m=missiles[i];m.life-=dt;const tp=targetPos(m.target);if(!tp)m.target=null;
  let a=Math.atan2(m.vy,m.vx);if(tp)a+=clamp(angDiff(Math.atan2(tp[1]-m.y,tp[0]-m.x),a),-4.2*dt,4.2*dt);
  const sp=Math.min(speed+620,Math.hypot(m.vx,m.vy)+700*dt);m.vx=Math.cos(a)*sp;m.vy=Math.sin(a)*sp;m.x+=m.vx*dt;m.y+=m.vy*dt;
  if(Math.random()<.6)bubbles.push({x:m.x-Math.cos(a)*12,y:m.y-Math.sin(a)*12,r:1+Math.random()*2,life:.6+Math.random()*.6,vx:0,vy:m.y<SURFACE?-4:-14,smoke:m.y<SURFACE});
  let done=false,silent=false;
  for(let j=0;j<enemyMissiles.length;j++){const e=enemyMissiles[j];if(Math.hypot(e.x-m.x,e.y-m.y)<22){boom(e.x,e.y,26);enemyMissiles.splice(j,1);intercepts++;bonus+=40;done=silent=true;break}}
  if(!done)for(const s of ships)if(!s.sinking&&Math.abs(m.x-s.x)<95&&m.y>SURFACE-34&&m.y<SURFACE+14){hitShip(s,m.x,m.y);done=silent=true;break}
  if(!done&&cm&&campMissile(m))done=silent=true;
  if(!done)for(const g of gates){if(Math.abs(g.x-m.x)>R+8)continue;for(let k=0;k<2;k++)if(!g.dead[k]&&Math.hypot(g.x-m.x,mineY(g,k)-m.y)<R+6){detonateMine(g,k,true);done=silent=true;break}if(done)break}
  const z=terrain(m.x);if(!done&&(m.y>z.bottom||(z.top>SURFACE+2&&m.y<z.top)||m.y<SURFACE-260||m.life<=0))done=true;
  if(done){if(!silent)boom(m.x,m.y,16);missiles.splice(i,1)}
 }
}
function updateShips(dt){
 const cap=D.twin&&difficulty>.6?2:1;
 if(sub.x>firstShip&&t>nextShipAt&&ships.filter(s=>!s.sinking).length<cap&&!(cm&&campQuiet())){
  const x=camX+vw+260;
  if(terrain(sub.x).cave<.05&&[0,.5,1].every(k=>terrain(mix(sub.x,x+700,k)).cave<.01)){
   ships.push({x,hp:D.shipHp,max:D.shipHp,fire:t+(announced.ship?rnd(.8,2.6):rnd(2.8,3.6)),sp:rnd(.35,.7),sinking:0,hitAt:-9,kind:Math.random()<.5?0:1});
   nextShipAt=t+mix(D.shipGap[0],D.shipGap[1],difficulty)*rnd(.55,1.5);
   if(!announced.ship){announced.ship=true;toast('SURFACE CONTACT','A hostile warship is hunting you. Dodge its missiles or fire back with F / right-click.',4.5,true)}
  }else nextShipAt=t+1.5;
 }
 for(let i=ships.length-1;i>=0;i--){const s=ships[i];
  if(s.sinking){s.x+=speed*.2*dt;if(t-s.sinking>5)ships.splice(i,1);continue}
  if(terrain(s.x+130).cave<.003)s.x+=speed*s.sp*dt;if(s.x<camX-320){ships.splice(i,1);continue}
  if(state==='playing'&&t>=invulnUntil&&sub.y-S.hy<SURFACE+12&&Math.abs(s.x-sub.x)<96+S.hx*.8){hitShip(s,sub.x+S.hx,SURFACE);damage(2,'The vessel rammed a warship and broke apart.','breach');if(state!=='playing')return}
  if(t>s.fire&&!active('silent')&&s.x>camX+60&&s.x<camX+vw-30&&terrain(s.x).cave<.15&&terrain(sub.x).cave<.35){
   // Seekers start crude and improve the farther the patrol runs: weaker turning,
   // shorter lock time, slower runs and a wider aim error early on.
   const acc=clamp((sub.x-firstShip)/(D.ramp*1.3),0,1);
   enemyMissiles.push({x:s.x+(s.kind?30:-20),y:SURFACE-22,vx:(sub.x-s.x)*.12+speed*.4,vy:-190-Math.random()*50,air:true,life:7,turn:D.turn*mix(.2,.55,acc),seek:mix(.6,1.6,acc),err:(Math.random()-.5)*2*mix(140,55,acc),sp:speed+D.mvel*mix(.22,.55,acc)});
   s.fire=t+mix(D.fire[0],D.fire[1],difficulty)*(.8+Math.random()*.4);sfx.enemyLaunch();
  }
 }
}
function updateEnemyMissiles(dt){
 for(let i=enemyMissiles.length-1;i>=0;i--){const m=enemyMissiles[i];m.life-=dt;
  if(m.air){m.vy+=430*dt;m.x+=m.vx*dt;m.y+=m.vy*dt;if(Math.random()<.7)bubbles.push({x:m.x,y:m.y,r:1.5+Math.random()*2,life:.7+Math.random()*.5,vx:0,vy:-6,smoke:true});
   if(m.y>SURFACE&&m.vy>0){m.air=false;const a=Math.atan2(m.vy,m.vx),sp=Math.hypot(m.vx,m.vy)*.5;m.vx=Math.cos(a)*sp;m.vy=Math.sin(a)*sp;splash(m.x);sfx.splash()}}
  else{let a=Math.atan2(m.vy,m.vx);
   // Once a seeker overshoots (it is moving away from the boat), it loses lock for good, so a late dodge sticks.
   if(m.seek>0&&(m.vx-speed)*(sub.x-m.x)+(m.vy-sub.v)*(sub.y-m.y)<0)m.seek=0;
   if(m.seek>0&&!active('silent')){m.seek-=dt;a+=clamp(angDiff(Math.atan2(sub.y+m.err-m.y,sub.x+speed*.25-m.x),a),-m.turn*dt,m.turn*dt)}const sp=Math.min(m.sp,Math.hypot(m.vx,m.vy)+260*dt);m.vx=Math.cos(a)*sp;m.vy=Math.sin(a)*sp;m.x+=m.vx*dt;m.y+=m.vy*dt;if(Math.random()<.5)bubbles.push({x:m.x-Math.cos(a)*10,y:m.y-Math.sin(a)*10,r:1+Math.random()*1.8,life:.6+Math.random()*.5,vx:0,vy:-12})}
  const z=terrain(m.x);let gone=m.life<=0||m.y>z.bottom||(!m.air&&z.top>SURFACE+2&&m.y<z.top);
  if(!gone&&state==='playing'){const dx=(m.x-sub.x)/(S.hx+4),dy=(m.y-sub.y)/(S.hy+5);if(dx*dx+dy*dy<1){gone=true;damage(1,'Enemy missiles tore the pressure hull apart.','random')}}
  if(gone){boom(m.x,m.y,22);enemyMissiles.splice(i,1)}
  // A fatal hit runs crash(), which clears enemyMissiles; stop iterating the stale indices.
  if(state!=='playing'&&!enemyMissiles.length)return;
 }
}
function damage(n,cause,effect){
 if(state!=='playing'||t<invulnUntil)return;
 if(active('shield')){invulnUntil=t+.4;shake=reduced?0:3;sfx.shield();return}
 invulnUntil=t+1.2;lastHitAt=t;shake=reduced?0:7;flash=reduced?.05:.25;sfx.impact();if(cam3d&&!reduced)yawKick+=(Math.random()<.5?-1:1)*.14;
 if(practice){toast('IMPACT / PRACTICE MODE','Damage is disabled in practice.',1.5);return}
 if(cm)campHit();run.hits++;hull-=n;if(hull<=0){hull=0;crash(cause);return}
 if(effect==='random')effect=['sonar','breach','ballast'][Math.floor(Math.random()*3)];
 if(effect==='sonar'){sonarDownUntil=t+7;toast('SONAR DAMAGED','The array is offline for 7 seconds. Navigate by sight.',2.5,true)}
 else if(effect==='breach'){o2=Math.max(0,o2-S.o2*.2);leakUntil=t+6;toast('HULL BREACH','Losing air fast. Find an air pocket.',2.5,true)}
 else {ballastUntil=t+5;toast('BALLAST DAMAGED','Dive planes are sluggish for 5 seconds.',2.5,true)}
}
function crash(reason){if(state!=='playing')return;if(practice){if(t-practiceHit>1.3){practiceHit=t;toast('CONTACT / PRACTICE MODE','Contact registered. Keep exploring.',1.5)}return;}state='dying';clearInput();deathCause=reason;crashAt=ambient;
 // The hull breaks its back, rolls and sinks to the seabed.
 wreck={x:sub.x,y:sub.y,vx:speed*.35,vy:Math.max(0,sub.v*.3)+10,angle:clamp(sub.v/650,-.22,.22)+tilt,rest:.22+Math.random()*.12,roll:0,rollTo:(Math.random()<.5?-1:1)*(.35+Math.random()*.25),bend:-(.18+Math.random()*.14),born:ambient,lastBubble:0,settled:false};
 enemyMissiles=[];missiles=[];tone(880,1.8,.025,870);shake=reduced?0:10;flash=reduced?.1:.6;show('pause',false);sfx.crash();for(let i=0;i<75;i++){let a=Math.random()*TAU,s=30+Math.random()*220;debris.push({x:sub.x,y:sub.y,vx:Math.cos(a)*s+speed*.25,vy:Math.sin(a)*s,life:1+Math.random()*1.4,r:1+Math.random()*4,hot:i<25})}}
function updateWreck(dt){
 const w=wreck;if(!w)return;
 if(!w.settled){w.vy=Math.min(w.vy+55*dt,90);w.y+=w.vy*dt;w.x+=w.vx*dt;w.vx*=Math.exp(-dt*.9);w.angle=mix(w.angle,w.rest,1-Math.exp(-dt*.8));w.roll=mix(w.roll,w.rollTo,1-Math.exp(-dt*.7));
  const floor=terrain(w.x).bottom-S.hy*.55;
  if(w.y>=floor){w.y=floor;w.settled=true;w.settledAt=ambient;shake=reduced?0:4;sfx.settle();for(let i=0;i<46;i++){const a=Math.PI+Math.random()*Math.PI;debris.push({x:w.x+(Math.random()-.5)*S.hx*2,y:floor+S.hy*.5,vx:Math.cos(a)*(20+Math.random()*70),vy:Math.sin(a)*(8+Math.random()*30),life:1.2+Math.random()*1.6,r:1.5+Math.random()*3.5})}}}
 else{w.angle=mix(w.angle,.06,1-Math.exp(-dt*1.5))}
 // Escaping air: a stream while sinking, then a slow trickle.
 if(ambient-w.lastBubble>(w.settled?.22:.04)){w.lastBubble=ambient;bubbles.push({x:w.x+(Math.random()-.5)*S.hx,y:w.y-S.hy*.4,r:1+Math.random()*3,life:2.5+Math.random()*2,vx:(Math.random()-.5)*12,vy:-28-Math.random()*30})}
 for(let i=bubbles.length-1;i>=0;i--){const b=bubbles[i];b.x+=b.vx*dt;b.y+=b.vy*dt;b.life-=dt;if(b.life<0||(!b.smoke&&b.y<SURFACE))bubbles.splice(i,1)}
 sub.x=w.x;sub.y=mix(sub.y,w.y,1-Math.exp(-dt*2));sub.v=0;camLead=mix(camLead,.56,1-Math.exp(-dt*1.2));
 camY=mix(camY,Math.max(-130,w.y-vh*.55),1-Math.exp(-dt*1.6));
}
function updateDebris(dt){for(const p of debris){p.x+=p.vx*dt;p.y+=p.vy*dt;p.vx*=Math.exp(-dt*1.8);p.vy*=Math.exp(-dt*.8);p.vy-=dt*10;p.life-=dt;}debris=debris.filter(p=>p.life>0);booms=booms.filter(b=>ambient-b.born<.9);
 for(const p of spray){p.x+=p.vx*dt;p.y+=p.vy*dt;p.vy+=620*dt;p.life-=dt}spray=spray.filter(p=>p.life>0&&!(p.vy>0&&p.y>SURFACE+2));ripples=ripples.filter(r=>ambient-r.born<1.6)}
/* Breaking the surface throws spray in proportion to the climb rate, pitches the
   bow up and leaves expanding rings; diving back under leaves a smaller splash. */
function breach(v){surfaced=true;surfacedAt=t;const k=clamp(v/170,.25,1);tilt=-.2*k;ripples.push({x:sub.x,born:ambient,w:S.hx*1.4});sfx.surface(k);for(let i=0;i<60*k+14;i++){const fx=(Math.random()-.3)*S.hx*2;spray.push({x:sub.x+fx,y:SURFACE-1,vx:speed*.8+(Math.random()-.5)*140,vy:-(70+Math.random()*260)*k-20,life:1.4,r:1+Math.random()*2.6})}for(let i=0;i<20;i++)bubbles.push({x:sub.x+(Math.random()-.5)*S.hx*2,y:SURFACE+6+Math.random()*16,r:1+Math.random()*3,life:.6+Math.random()*.6,vx:speed*.5,vy:-20})}
function dive(){ripples.push({x:sub.x,born:ambient,w:S.hx});sfx.dive();for(let i=0;i<18;i++)spray.push({x:sub.x+(Math.random()-.5)*S.hx*1.6,y:SURFACE-1,vx:speed*.8+(Math.random()-.5)*60,vy:-40-Math.random()*90,life:1,r:.8+Math.random()*1.8})}
async function finish(){
 if(cm)return campFinish();
 // What was actually dived. duelRoundOver() below restores the player's own menu level and
 // practice setting, so the score entry must use these, not the globals.
 const dived={diff:diffId,sub:S.id,practice};
 state='over';const final=score(),metres=Math.floor(distance),newBest=!practice&&final>best;
 if(newBest){best=final;store.set('undertow.best.v2',best)}
 $('overLabel').textContent=practice?'PRACTICE DIVE ENDED':newBest?'NEW PERSONAL BEST':'PATROL ENDED';$('cause').textContent=deathCause;
 $('endScore').textContent=final.toLocaleString();$('endMeta').textContent=S.name.toUpperCase()+' CLASS / '+D.label.toUpperCase()+' / '+D.score+'x';
 $('endDistance').textContent=metres+' m';$('endShips').textContent=shipsSunk;$('endGates').textContent=cleared;$('endDepth').textContent=Math.floor(maxDepth)+' m';$('endAir').textContent=airCollected;$('endBest').textContent=best.toLocaleString();
 achCommit();
 if(!practice){const x=profXp(),l0=levelOf(run.xp0),l1=levelOf(x);run.gain=x-run.xp0;run.promoted=l1>l0?l1:0;if(run.promoted)achPop({kind:'PROMOTED',name:'LEVEL '+l1+' / '+rankTitle(l1)})}
 renderEarned();$('place').hidden=true;
 show('over',true);overAt=performance.now();$('hud').classList.add('ended');$('again').focus({preventScroll:true});$('saveShared').hidden=true;
 if(duel.run)await duelRoundOver(final).catch(e=>{$('cause').textContent=deathCause+' The duel round could not be posted: '+(e&&e.message||e)});
 if(dived.practice){lastEntry=null;$('saveNote').textContent='Practice dives are not recorded.';return}
 const now=new Date();
 lastEntry={id:now.getTime().toString(36)+Math.random().toString(36).slice(2,8),name:callsign(),score:final,distance:metres,sub:dived.sub,diff:dived.diff,ships:shipsSunk,date:now.toISOString().slice(0,10),at:now.getTime()};
 $('saveNote').textContent='Saving score...';describeSave(await submitScore(lastEntry));
}
function physics(dt){
 t+=dt;difficulty=clamp(sub.x/D.ramp,0,1);
 speed=mix(D.speed[0],D.speed[1],difficulty)*(1+clamp((sub.x-D.ramp)/80000,0,.2))*S.speed*(practice?.85:1)*(active('flank')?1.5:1)*(cm?campSpeed():1);
 sub.x+=speed*dt;distance=(sub.x-runX0)*.1;night=smooth(TP.night,TP.night+3500,sub.x);camX=sub.x-vw*.24;
 held=pointerLift||inputKeys.has('Space')||inputKeys.has('ArrowUp')||inputKeys.has('KeyW');down=inputKeys.has('ArrowDown')||inputKeys.has('KeyS');
 if(cm&&campHold())held=down=false;
 const agi=S.agility*(t<ballastUntil?.55:1), accel=held?-470*agi:(down?660*agi:360*agi);
 sub.v=clamp(sub.v+(accel-2.6*sub.v)*dt,-185*agi,(down?235:150)*agi);sub.y+=sub.v*dt;
 const z=terrain(sub.x);maxDepth=Math.max(maxDepth,(sub.y-68)*.1);populate();
 // Open water lets the boat ride the surface: the sail and upper hull clear the
 // waterline. Under an island the rock ceiling is solid.
 const surfY=SURFACE+S.hy*.2;
 if(z.cave<.002&&sub.y<surfY){if(!surfaced)breach(-sub.v);sub.y=surfY;if(sub.v<0)sub.v=0}
 else if(surfaced&&sub.y>surfY+3){surfaced=false;dive()}
 tilt*=Math.exp(-dt*2.4);
 if(practice)sub.y=clamp(sub.y,z.cave>.002?z.top+S.hy+3:-1e9,z.bottom-S.hy-3);
 for(let xx=-S.hx;xx<=S.hx;xx+=15){let rock=terrain(sub.x+xx);let ry=S.hy*Math.sqrt(Math.max(0,1-(xx/S.hx)**2));if((rock.cave>.002&&sub.y-ry<rock.top)||sub.y+ry>rock.bottom){crash(sub.y+ry>rock.bottom?'The pressure hull struck the seabed.':sub.y<SURFACE+S.hy+6?'The vessel ran into the island cliffs.':'The sail struck the cavern ceiling.');break;}}
 if(state!=='playing')return;
 if(surfaced){if(!practice)o2=Math.min(S.o2,o2+S.o2*.12*dt);if(t-lastDrip>.05){lastDrip=t;for(let i=0;i<2;i++)spray.push({x:sub.x+(Math.random()-.4)*S.hx*1.6,y:sub.y-S.hy*.7,vx:speed*(.7+Math.random()*.2),vy:-20-Math.random()*40,life:.8,r:.8+Math.random()*1.4})}
  if(!announced.surface){announced.surface=true;toast('SURFACED','Snorkel open: air refills while you ride the surface. Mine cables reach the surface too, and warships can see you.',4)}}
 for(const g of gates){
  if(Math.abs(g.x-sub.x)<S.hx+R){
   const dx=Math.max(0,Math.abs(g.x-sub.x)-(S.hx-S.hy)), ty=mineY(g,0), by=mineY(g,1);
   for(let k=0;k<2;k++){if(!g.dead[k]&&Math.hypot(dx,(k?by:ty)-sub.y)<R+S.hy){detonateMine(g,k,false);damage(2,'A moored mine detonated against the hull.','breach')}}
   if(state==='playing'&&Math.abs(g.x-sub.x)<S.hx&&((!g.dead[0]&&sub.y-S.hy<ty)||(!g.dead[1]&&sub.y+S.hy>by)))damage(1,'The vessel fouled a mine tether and broke apart.','ballast');
  }
  if(!g.passed&&g.x+R+S.hx<sub.x){g.passed=true;cleared++;tone(360,.07,.018,480);}
  if(state!=='playing')return;
 }
 // Air: drains every second, faster through a breach; implosion at zero.
 if(!practice){o2=Math.max(0,o2-D.o2*(t<leakUntil?2.6:1)*dt);if(o2<=0){crash('Life support failed. The hull imploded under the crushing pressure.');return}}
 if(o2<S.o2*.25){if(t-lastAlarm>1.4){lastAlarm=t;sfx.alarm()}if(!lowO2Warned){lowO2Warned=true;toast('OXYGEN LOW','Steer through an air pocket before life support fails.',3,true)}}else if(o2>S.o2*.4)lowO2Warned=false;
 for(const p of pickups){if(p.taken)continue;p.cy=p.y+Math.sin(t*1.6+p.phase)*6;const dx=(p.x-sub.x)/(S.hx+18),dy=(p.cy-sub.y)/(S.hy+18);if(dx*dx+dy*dy<1){p.taken=true;o2=Math.min(S.o2,o2+S.o2*.3);airCollected++;bonus+=5;sfx.pickup();for(let i=0;i<16;i++)bubbles.push({x:p.x+(Math.random()-.5)*20,y:p.cy+(Math.random()-.5)*20,r:1+Math.random()*3,life:.8+Math.random(),vx:(Math.random()-.5)*60,vy:-20-Math.random()*40})}}
 updateShips(dt);updateEnemyMissiles(dt);if(state!=='playing')return;updateMissiles(dt);updateSonar(dt);updateDebris(dt);
 if(!announced.sunset&&sub.x>3000){announced.sunset=true;toast('LIGHT IS FADING','Automatic sonar coming online. Watch for returning echoes.',4)}
 if(!announced.cave&&z.cave>.5){announced.cave=true;toast('ENTERING THE CATHEDRAL','Rock above. Rock below. Ships cannot reach you here.',3.5)}
 if(!announced.night&&night>.97){announced.night=true;toast('RUNNING SILENT','Echoes reveal the mines. The cables are just as dangerous.',4)}
 if(!announced.drift&&gates.some(g=>g.amp&&g.x>sub.x&&g.x<camX+vw)){announced.drift=true;toast('DRIFTING MINES','Some mines now ride the current. Time your passage.',3.5,true)}
 if(t>toastUntil)$('toast').classList.remove('show');
 if(t>8)$('hint').style.opacity='0';
 if(t-lastBubble>(active('flank')?.012:.04)){lastBubble=t;bubbles.push({x:sub.x-S.hx*1.2,y:sub.y+(Math.random()-.5)*9,r:1+Math.random()*2.3,life:2+Math.random(),vx:-30-Math.random()*35,vy:-8-Math.random()*18});}
 for(let i=bubbles.length-1;i>=0;i--){let b=bubbles[i];b.x+=b.vx*dt;b.y+=b.vy*dt;b.life-=dt;if(b.life<0||(!b.smoke&&b.y<SURFACE))bubbles.splice(i,1)}
 camY=mix(camY,Math.max(-130,mix(z.centre,sub.y,.35)-vh*.53),1-Math.exp(-dt*2));
 if(cm){campStep(dt);if(state!=='playing')return}
 if(t-lastHud>.1){lastHud=t;updateHUD(z);if(Math.floor(t*4)!==Math.floor((t-.1)*4))achCheck()}
}
function buildPips(){const p=$('pips');p.textContent='';for(let i=0;i<S.hull;i++)p.append(document.createElement('i'))}
function setRing(el,p,off){el.style.background=off?'#3a1c1cb0':`conic-gradient(rgba(166,234,213,.36) ${Math.round(p*360)}deg, rgba(12,38,52,.72) 0)`;el.classList.toggle('ready',p>=1&&!off);el.classList.toggle('off',!!off)}
function effect(label,until){const s=document.createElement('span'),i=document.createElementNS('http://www.w3.org/2000/svg','svg'),u=document.createElementNS('http://www.w3.org/2000/svg','use');i.setAttribute('class','ic');u.setAttribute('href','#i-warn');i.append(u);s.append(i,label+' '+Math.ceil(until-t)+'s');return s}
function updateHUD(z){
 $('score').textContent=score().toLocaleString();$('distance').textContent=String(Math.floor(distance)).padStart(4,'0');$('depth').textContent=String(Math.max(0,Math.floor((sub.y-68)*.1))).padStart(3,'0');$('sunk').textContent=shipsSunk;
 $('sector').textContent=(practice?'PRACTICE / ':z.cave>.45?'02 / ':z.basin>.4?'03 / ':'01 / ')+(z.cave>.45?'THE CATHEDRAL':z.basin>1.25?'THE TRENCH':z.basin>.4?'HADAL BASIN':z.lift>70?'THE SHOALS':night>.9?'MIDNIGHT SHELF':'CONTINENTAL SHELF')+' / '+D.label.toUpperCase();
 const sonarDown=t<sonarDownUntil, A=S.ability, on=t<abilityUntil, ac=clamp((t-abilityAt)/A.cd,0,1);
 setRing($('ability'),on?(abilityUntil-t)/A.dur:ac);$('ability').classList.toggle('active',on);$('abilityCopy').classList.toggle('active',on);
 $('abilityState').textContent=on?A.name:ac<1?'RECHARGING':A.name;$('abilityHint').textContent=on?'ACTIVE '+Math.ceil(abilityUntil-t)+' s':ac<1?(A.cd*(1-ac)).toFixed(1)+' s':'E / TAP';
 const rl=reloadTime(),mc=clamp((t-lastFire)/rl,0,1);setRing($('fire'),mc);$('fireState').textContent=mc<1?'RELOADING':'MISSILE READY';$('fireHint').textContent=mc<1?(rl*(1-mc)).toFixed(1)+' s':'F / RIGHT-CLICK';
 [...$('pips').children].forEach((p,i)=>p.classList.toggle('lost',i>=hull));
 const pct=clamp(o2/S.o2,0,1);$('o2bar').style.width=pct*100+'%';$('o2val').textContent=Math.ceil(pct*100)+'%';$('airRow').classList.toggle('low',pct<.25);
 const fx=$('effects');fx.textContent='';if(sonarDown)fx.append(effect('SONAR OFFLINE',sonarDownUntil));if(t<leakUntil)fx.append(effect('AIR LEAK',leakUntil));if(t<ballastUntil)fx.append(effect('BALLAST FAULT',ballastUntil));if(surfaced){const sn=document.createElement('span');sn.className='good';sn.textContent='SURFACED / SNORKEL OPEN';fx.append(sn)}
 $('thrust').classList.toggle('on',held);
 if(cm)campHUD();
}
