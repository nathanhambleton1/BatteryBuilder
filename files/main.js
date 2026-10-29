'use strict';
/* ---- Input ---- */
$('launch').onclick=launchDive;$('again').onclick=againOrDuel;$('restartPause').onclick=()=>cm?campRetry():start();$('home').onclick=home;
// Leaving a duel dive part-way ends the round with the score so far.
$('quit').onclick=()=>{if(duel.run){show('paused',false);state='playing';deathCause='The dive was abandoned.';finish()}else home()};
$('duelOpen').onclick=()=>openPanel('duel');$('duelChip').onclick=()=>openPanel('duel');$('duelClose').onclick=closePanel;$('duelConnect').onclick=()=>duelConnectionAction($('duelConnect'),async()=>{await lbPick();await duelTick()},'Connecting…');$('duelRefresh').onclick=()=>duelConnectionAction($('duelRefresh'),()=>duelTick(),'Refreshing…');$('watchLeave').onclick=duelLeaveWatch;
document.querySelectorAll('#duelRoundSeg button').forEach(b=>b.onclick=()=>{duel.rounds=+b.dataset.r;profDirty(true);renderDuel()});
document.querySelectorAll('#duelDiffSeg button').forEach(b=>b.onclick=()=>{duel.diff=b.dataset.diff;duel.diffSet=true;profDirty(true);renderDuel()});$('pause').onclick=pause;$('resume').onclick=resume;$('sound').onclick=toggleSound;$('music').onclick=toggleMusic;
function setMission(p){practice=p;$('standard').setAttribute('aria-pressed',String(!p));$('practice').setAttribute('aria-pressed',String(p))}
$('standard').onclick=()=>{setMission(false);profDirty(true)};
$('practice').onclick=()=>{setMission(true);profDirty(true)};
$('helpOpen').onclick=()=>{if(state==='playing')pause();openPanel('help')};$('helpClose').onclick=closePanel;$('hangarOpen').onclick=()=>openPanel('hangar');$('hangarClose').onclick=closePanel;
$('boardOpen').onclick=()=>openPanel('board');$('achOpen').onclick=()=>openPanel('ach');$('overAch').onclick=()=>openPanel('ach');$('achClose').onclick=closePanel;document.querySelectorAll('#achSeg button').forEach(b=>b.onclick=()=>{lb.achView=b.dataset.v;if(b.dataset.v==='path')lb.achWho='';renderAch()});$('lbChip').onclick=()=>openPanel('board');$('overBoard').onclick=()=>openPanel('board');$('boardClose').onclick=closePanel;
$('callsign').addEventListener('change',()=>{store.set('undertow.callsign',$('callsign').value.trim().slice(0,16));profSwitch()});
$('callsign').addEventListener('input',callsignState);callsignState();
$('motion').onclick=()=>{reduced=!reduced;$('motion').textContent='Motion effects: '+(reduced?'reduced':'on')};
$('camBtn').onclick=toggleCam;$('camBtn').textContent='Camera: '+(cam3d?'3D orbit':'flat');
$('fullscreen').onclick=async()=>{try{if(document.fullscreenElement)await document.exitFullscreen();else if(document.documentElement.requestFullscreen)await document.documentElement.requestFullscreen();else toast('FULLSCREEN UNAVAILABLE','Use your browser’s full-screen view.',3)}catch(_){} };
$('ability').onclick=()=>{initAudio();useAbility()};$('fire').onclick=()=>{initAudio();fire()};
function pointerStart(e){if(state==='over'&&!panel){if(performance.now()-overAt>700){e.preventDefault();againOrDuel()}return}if(state!=='playing')return;e.preventDefault();initAudio();if(e.button===2){fire();return}pointerLift=true;try{e.currentTarget.setPointerCapture(e.pointerId)}catch(_){} }
for(const el of [canvas,$('thrust')]){el.addEventListener('pointerdown',pointerStart);el.addEventListener('pointerup',e=>{if(e.button!==2)pointerLift=false});el.addEventListener('pointercancel',()=>pointerLift=false);el.addEventListener('lostpointercapture',()=>pointerLift=false)}
// A right press while the left button is already held arrives as a chorded pointermove.
canvas.addEventListener('pointermove',e=>{if(state==='playing'&&e.button===2&&(e.buttons&2))fire()});
addEventListener('contextmenu',e=>{if(state==='playing'||e.target===canvas)e.preventDefault()});
addEventListener('keydown',e=>{
 if(e.target instanceof HTMLInputElement){if(e.code==='Enter'||e.code==='Escape'){e.preventDefault();e.target.blur()}return}
 const controls=['Space','ArrowUp','ArrowDown','KeyW','KeyS','KeyE','KeyF','KeyX','Escape','KeyP','KeyM','KeyN','KeyR','KeyA','KeyD','ArrowLeft','ArrowRight','KeyC','Enter'];if(!controls.includes(e.code))return;
 if(e.code==='KeyM'&&!e.repeat){toggleSound();return}
 if(e.code==='KeyN'&&!e.repeat){toggleMusic();return}
 if(e.code==='KeyC'&&!e.repeat){toggleCam();return}
 if(['KeyA','KeyD','ArrowLeft','ArrowRight'].includes(e.code)){if(!panel&&state!=='paused'){e.preventDefault();inputKeys.add(e.code)}return}
 if((e.code==='KeyP'||e.code==='Escape')&&!e.repeat){e.preventDefault();if(askDone)askDone(false);else if(panel)closePanel();else if(state==='playing')pause();else if(state==='paused')resume();else if(state==='watching')duelLeaveWatch();return}
 if(state==='playing'){e.preventDefault();if(e.code==='KeyE'&&!e.repeat)useAbility();if((e.code==='KeyF'||e.code==='KeyX')&&!e.repeat)fire();inputKeys.add(e.code)}
 // After a wreck, any dive key starts again (a short delay ignores keys still held from the crash).
 else if(state==='over'&&!panel&&!e.repeat&&['KeyR','Space','KeyW','ArrowUp','Enter'].includes(e.code)&&!(e.target instanceof HTMLButtonElement&&e.target.id!=='again')&&performance.now()-overAt>700){e.preventDefault();againOrDuel()}
});addEventListener('keyup',e=>inputKeys.delete(e.code));
addEventListener('blur',()=>{clearInput();if(state==='playing')pause()});document.addEventListener('visibilitychange',()=>{if(document.hidden){clearInput();if(state==='playing')pause()}});
addEventListener('error',e=>{$('error').textContent='The dive was interrupted. Reload the file to restart. '+(e.message||'');show('error',true)});
$('fullscreen').hidden=!document.documentElement.requestFullscreen;$('build').textContent=BUILD;
// Browsers usually hold audio until a user gesture. Build the graph now (it may start straight away), and
// resume it on the first click, tap or key. A press of the sound/music button while it is still waiting
// only unlocks audio, so a saved "on" setting is never flipped off by that first click.
initAudio();['pointerdown','touchstart','keydown'].forEach(ev=>addEventListener(ev,()=>{if(soundOn)initAudio()},{capture:true,passive:true}));
profInit();initializeSharedScores();reset();updateSound();updateMenu();requestAnimationFrame(frame);

analyticsInit();

document.querySelectorAll('.view.overlay').forEach(installPopupClose);
