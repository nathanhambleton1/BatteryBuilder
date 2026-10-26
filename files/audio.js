'use strict';
/* ---- Audio: everything is synthesized at runtime, so the file stays self-contained ----
   Buses: sfx and music feed a master gain and a compressor; a generated dark reverb is shared. */
let master=null,sfxBus=null,musicBus=null,musicTone=null,verbSend=null,noiseBuf=null;
const mus={next:0,step:0,int:0,bpm:100,key:0,echo:0,song:Math.random()*4|0,pending:null,phrase:0,sec:'main'};
function initAudio(){if(!soundOn)return;try{if(!audio){audio=new (window.AudioContext||window.webkitAudioContext)();
  const comp=audio.createDynamicsCompressor();comp.threshold.value=-14;comp.knee.value=12;comp.ratio.value=4;comp.attack.value=.004;comp.release.value=.25;comp.connect(audio.destination);
  master=audio.createGain();master.gain.value=.9;master.connect(comp);sfxBus=audio.createGain();sfxBus.connect(master);
  musicTone=audio.createBiquadFilter();musicTone.type='lowpass';musicTone.frequency.value=18000;musicBus=audio.createGain();musicBus.gain.value=0;musicBus.connect(musicTone).connect(master);
  const len=audio.sampleRate*2.8|0,ir=audio.createBuffer(2,len,audio.sampleRate);
  for(let ch=0;ch<2;ch++){const d=ir.getChannelData(ch);let lp=0;for(let i=0;i<len;i++){lp+=(Math.random()*2-1-lp)*.35;d[i]=lp*Math.pow(1-i/len,2.6)}}
  const verb=audio.createConvolver();verb.buffer=ir;verbSend=audio.createGain();verbSend.gain.value=.55;verbSend.connect(verb).connect(master);
  noiseBuf=audio.createBuffer(1,audio.sampleRate*2,audio.sampleRate);const nd=noiseBuf.getChannelData(0);for(let i=0;i<nd.length;i++)nd[i]=Math.random()*2-1;
  // Engine: a filtered sawtooth hum plus low noise for prop wash.
  engine=audio.createOscillator();engine.type='sawtooth';engine.frequency.value=47;const ef=audio.createBiquadFilter();ef.type='lowpass';ef.frequency.value=170;
  engineGain=audio.createGain();engineGain.gain.value=0;engine.connect(ef).connect(engineGain);
  const wash=audio.createBufferSource();wash.buffer=noiseBuf;wash.loop=true;const wf=audio.createBiquadFilter();wf.type='lowpass';wf.frequency.value=300;const wg=audio.createGain();wg.gain.value=.7;wash.connect(wf).connect(wg).connect(engineGain);
  engineGain.connect(sfxBus);engine.start();wash.start();setInterval(musicTick,25);
 }if(audio.state==='suspended')audio.resume().catch(()=>{});}catch(_){soundOn=false;updateSound()}}
const audible=()=>soundOn&&audio&&audio.state==='running';
function env(g,at,a,peak,dur,rel=0){peak=Math.max(peak,.0002);g.gain.setValueAtTime(.0001,at);g.gain.exponentialRampToValueAtTime(peak,at+a);if(rel)g.gain.setValueAtTime(peak,at+Math.max(a,dur-rel));g.gain.exponentialRampToValueAtTime(.0001,at+dur)}
function send(g,amt){if(!amt)return;const s=audio.createGain();s.gain.value=amt;g.connect(s).connect(verbSend)}
function osc(type,f,end,at,dur,vol,out=sfxBus,{a=.012,verb=0,cut=0,cutEnd=cut,detune=0,rel=0}={}){
 const o=audio.createOscillator(),g=audio.createGain();o.type=type;o.detune.value=detune;o.frequency.setValueAtTime(f,at);if(end!==f)o.frequency.exponentialRampToValueAtTime(end,at+dur);
 let n=o;if(cut){const fl=audio.createBiquadFilter();fl.type='lowpass';fl.frequency.setValueAtTime(cut,at);if(cutEnd!==cut)fl.frequency.exponentialRampToValueAtTime(cutEnd,at+dur);n=n.connect(fl)}
 env(g,at,a,vol,dur,rel);n.connect(g).connect(out);send(g,verb);o.start(at);o.stop(at+dur+.05);o.onended=()=>{o.disconnect();g.disconnect()}}
function noise(at,dur,vol,out=sfxBus,{type='lowpass',f=1200,end=f,q=.7,a=.005,verb=0}={}){
 const s=audio.createBufferSource(),fl=audio.createBiquadFilter(),g=audio.createGain();s.buffer=noiseBuf;s.loop=true;fl.type=type;fl.Q.value=q;fl.frequency.setValueAtTime(f,at);if(end!==f)fl.frequency.exponentialRampToValueAtTime(end,at+dur);
 env(g,at,a,vol,dur);s.connect(fl).connect(g).connect(out);send(g,verb);s.start(at,Math.random()*1.8);s.stop(at+dur+.05);s.onended=()=>{s.disconnect();g.disconnect()}}
function tone(f,dur,vol=.08,end=f,type='sine'){if(!audible())return;osc(type,f,end,audio.currentTime,dur,vol)}
const sfx={
 boom(size){if(!audible())return;const at=audio.currentTime,k=clamp(size/40,.3,1.6);osc('sine',110,28,at,.5+k*.4,Math.min(.32,.1*k+.06));noise(at,.4+k*.6,Math.min(.4,.13*k+.05),sfxBus,{f:2400,end:90,verb:.5});noise(at,.07,.1*k,sfxBus,{type:'highpass',f:2500})},
 launch(){if(!audible())return;const at=audio.currentTime;osc('sine',230,55,at,.35,.2);noise(at,.5,.16,sfxBus,{type:'bandpass',f:300,end:2600,q:1.4,a:.03,verb:.3});noise(at+.05,.7,.06,sfxBus,{type:'bandpass',f:700,end:1800,q:3})},
 enemyLaunch(){if(!audible())return;const at=audio.currentTime;noise(at,.8,.05,sfxBus,{type:'highpass',f:3200,end:1100,a:.04,verb:.4});osc('sawtooth',330,560,at,.3,.018,sfxBus,{cut:1600})},
 splash(){if(!audible())return;noise(audio.currentTime,.45,.09,sfxBus,{type:'bandpass',f:1700,end:300,q:.8,verb:.3})},
 impact(){if(!audible())return;const at=audio.currentTime;[173,271,389,557,812].forEach((f,i)=>osc('triangle',f,f*.97,at,1.3-i*.16,.055,sfxBus,{a:.003,verb:.6}));noise(at,.35,.28,sfxBus,{f:1400,end:80});osc('sine',120,38,at,.5,.2)},
 shield(){if(!audible())return;const at=audio.currentTime;[1320,1980,2640].forEach((f,i)=>osc('sine',f,f*1.02,at+i*.02,.55,.028,sfxBus,{a:.003,verb:.7}))},
 // With music on, sonar sounds land on the beat grid and take their pitch from the current chord.
 // Only the sound is delayed (at most an eighth note); pings and echoes still happen on time in the game.
 ping(){if(!audible())return;const g=musicGrid(2),at=g?g.at:audio.currentTime,f=g?mtof(g.ch[0]+36):1180;osc('sine',f,f*.97,at,1.5,.085,sfxBus,{a:.004,verb:1});osc('sine',f*2,f*1.95,at,.25,.012,sfxBus,{a:.004})},
 echo(){if(!audible())return;const g=musicGrid(1),at=g?g.at:audio.currentTime,f=g?mtof(g.ch[mus.echo++%3]+36+(mus.echo%6>2?12:0)):1180;osc('sine',f,f*.94,at,.35,g?.024:.018,sfxBus,{a:.006,verb:.8})},
 pickup(){if(!audible())return;const at=audio.currentTime;[523,659,784,1047].forEach((f,i)=>osc('sine',f,f*1.04,at+i*.05,.22,.035,sfxBus,{verb:.4}));noise(at,.35,.04,sfxBus,{type:'bandpass',f:900,end:2600,q:4})},
 ability(){if(!audible())return;const at=audio.currentTime;osc('sawtooth',110,440,at,.6,.05,sfxBus,{a:.05,cut:400,cutEnd:3000,verb:.5});osc('sine',520,980,at+.1,.4,.05,sfxBus,{verb:.4})},
 alarm(){if(!audible())return;const at=audio.currentTime;osc('square',880,880,at,.13,.022,sfxBus,{cut:2400});osc('square',660,660,at+.15,.13,.022,sfxBus,{cut:2400})},
 sunk(){if(!audible())return;const at=audio.currentTime;osc('sawtooth',70,24,at,2.4,.1,sfxBus,{cut:320,a:.2,verb:.6});noise(at+.3,2.2,.08,sfxBus,{f:600,end:70,a:.4})},
 crash(){if(!audible())return;const at=audio.currentTime;this.boom(70);this.impact();osc('sawtooth',92,22,at+.15,2.8,.12,sfxBus,{cut:420,a:.25,verb:.6});noise(at+.2,3,.18,sfxBus,{f:520,end:60,a:.3,verb:.4})},
 settle(){if(!audible())return;const at=audio.currentTime;osc('sine',62,28,at,.9,.22);noise(at,1.3,.15,sfxBus,{f:420,end:60,verb:.4})},
 surface(k){if(!audible())return;noise(audio.currentTime,.7,.06+.08*k,sfxBus,{type:'bandpass',f:1100,end:380,q:.7,verb:.3})},
 // Heartbeat: a deep chest thump plus a muffled thud; the second ("dub") beat is softer and lower.
 heart(k,dub){if(!audible())return;const at=audio.currentTime,f=dub?52:64;osc('sine',f,f*.6,at,.22,(dub?.16:.24)*k,sfxBus,{a:.004});osc('triangle',f*2,f,at,.06,(dub?.03:.05)*k,sfxBus,{a:.002});noise(at,.12,(dub?.05:.08)*k,sfxBus,{f:260,end:80,a:.003})},
 dive(){if(!audible())return;noise(audio.currentTime,.55,.06,sfxBus,{f:1400,end:180,a:.02})}
};
/* Battle score: a step sequencer playing one of several original EDM tracks, picked fresh each dive.
   Each track is 8 bars of chords (scale degrees in natural minor) plus a lead line written as one
   16-step string per bar: 0-9/a-e are scale degrees above the lead's tonic, '-' holds, '.' rests.
   Progress builds intensity and tempo slowly; the last hull section (critical) takes both all-out: layers stack up
   (pad, arp, kick, bass, hats, plucked lead, full supersaw lead, stabs, harmony), and the key lifts a
   step at each new phrase once you are deep enough. Combat (ships, incoming missiles, low hull) adds
   on top. Synths sit on a sidechained bus that pumps against every kick. Once the music is running hot,
   every fourth phrase is a breakdown: four bars without drums, then a snare-roll build into the drop. */
const SCALE=[0,2,3,5,7,8,10];
const SONGS=[
 {name:'Pressure Drop',tonic:50,bpm:[128,150],prog:[0,0,5,5,2,2,6,6],bass:'offbeat',drums:'four',voice:'saw',arp:'0121012101210121',stab:[2,6,10,14],
  lead:['7..7..8.9-.8.7..','7..7..8.b---9-8-','c..c..b.9-.b.c..','c..c..e.d---b-9-','9..9..b.d-.b.9..','9..9..b.d---e-d-','a..a..8.6-.8.a..','d..d..b.a-8-6-4-']},
 {name:'Deep Current',tonic:52,bpm:[136,160],prog:[0,3,5,6,0,3,5,6],bass:'roll',drums:'four',voice:'chip',arp:'0120201201202012',stab:[0,3,6,10,12],
  lead:['b.9.7.9.b..e.d.b','a.9.7.5.7..a.9.7','9.7.5.7.9..c.b.9','8.6.4.6.8.a.b.d.','b.9.7.9.b..e.d.e','e.d.c.a.c..e.d.c','c.b.9.7.9.b.c.9.','d---b---8---6.4.']},
 {name:'Ballast',tonic:48,bpm:[140,150],prog:[0,0,5,5,3,3,6,6],bass:'wobble',drums:'half',voice:'saw',arp:'0.1.2.1.0.1.2.1.',stab:[0,6,10],
  lead:['7-----4---6-7---','9-------8---7---','7-----5---4-5---','4-----------....','5-----7---8-9---','a-------9---7---','8-----6---8-9---','8-----------6-8-']},
 {name:'Hadal Light',tonic:45,bpm:[130,155],prog:[0,5,2,6,0,5,2,6],bass:'bounce',drums:'four',voice:'pluck',arp:'0122101202212010',stab:[2,6,10,14],
  lead:['9.9.b.9..7.9.b..','c.c.b.9..7.9.7..','b.b.9.b..d.b.9..','a.a.8.a..b-a-8--','9.9.b.9..7.9.e..','e.c.b.9..c.b.9..','b.d.e.d..b.9.b..','a---8---a---b---']}];
// Pre-parse each lead into per-step notes {d: scale degree, len: steps held}.
SONGS.forEach(so=>so.notes=so.lead.map(b=>[...b].map((c,i)=>{if(c==='.'||c==='-')return null;let len=1;while(b[i+len]==='-')len++;return {d:parseInt(c,36),len}})));
const mtof=n=>440*Math.pow(2,(n-69)/12);
const sdeg=d=>SCALE[d%7]+12*Math.floor(d/7);
// The bar's triad as MIDI notes; roots above the fifth are voiced an octave down to keep it near the tonic.
function chordAt(so,bar,key){const r=so.prog[bar];let c=[r,r+2,r+4].map(sdeg);if(c[0]>7)c=c.map(x=>x-12);return c.map(x=>x+so.tonic+key)}
function nextSong(){let i=Math.floor(Math.random()*(SONGS.length-1));if(i>=mus.song)i++;mus.pending=i;
 $('music').title='Music (N) / '+SONGS[i].name}
let musicDrive=null,synthBus=null,synthLP=null;
function musicProgress(){return state==='menu'?0:clamp(sub.x/(D.ramp*2.5),0,1)}
const critical=()=>state==='playing'&&!practice&&hull<=1;
function musicTarget(){if(state==='menu')return .14;if(state==='dying'||state==='over')return .04;
 const p=musicProgress();let i=.38+p*.3;if(practice)i=Math.min(i,.58);
 if(ships.some(s=>!s.sinking))i+=.1;if(enemyMissiles.length)i+=.06;if(critical())i=Math.max(i+.3,.92);return clamp(i,0,1)}
function musicBpm(){const b=SONGS[mus.song].bpm;if(state==='menu')return b[0]-16;if(state!=='playing'&&state!=='paused')return b[0]-24;
 return (critical()?b[1]:b[0]+(b[1]-b[0])*.4*Math.pow(musicProgress(),1.5))*(active('flank')?1.04:1)}
// Audio time and chord of the next free slot on the music's sixteenth-note grid, snapped to every
// `every` steps; null when the music is silent.
function musicGrid(every){if(!audible()||!musicOn||!mus.next)return null;const L=128,st=60/mus.bpm/4,now=audio.currentTime;let at=mus.next,i=mus.step;
 while(at-st>=now+.005){at-=st;i--}while(((i%every)+every)%every){at+=st;i++}i=((i%L)+L)%L;return {at,ch:chordAt(SONGS[mus.song],i>>4,mus.key||0)}}
function updateMusic(dt){if(!audio)return;const on=soundOn&&musicOn,now=audio.currentTime;
 // Mission critical muffles the score as if heard through the hull, so the heartbeat cuts through.
 const crit=critical();musicBus.gain.setTargetAtTime(on?(state==='paused'?.35:crit?.42:.5+mus.int*.2):0,now,.4);
 musicTone.frequency.setTargetAtTime(state==='paused'||state==='dying'||state==='over'?650:crit?800:18000,now,crit?.25:.5);
 const tg=musicTarget();mus.int=mix(mus.int,tg,1-Math.exp(-dt*(tg>mus.int?1.4:.35)));
 mus.bpm=mix(mus.bpm||100,musicBpm(),1-Math.exp(-dt*.8))}
function musicTick(){if(!audible()||!musicOn){mus.next=0;return}
 if(!musicDrive){synthLP=audio.createBiquadFilter();synthLP.type='lowpass';synthLP.frequency.value=18000;synthBus=audio.createGain();synthBus.connect(synthLP).connect(musicBus);
  musicDrive=audio.createWaveShaper();const c=new Float32Array(1024);for(let i=0;i<1024;i++){const x=i/511.5-1;c[i]=Math.tanh(x*4)}musicDrive.curve=c;const g=audio.createGain();g.gain.value=.5;musicDrive.connect(g).connect(synthBus)}
 const now=audio.currentTime;if(mus.next<now-.1){mus.next=now+.06}
 while(mus.next<now+.15){const st=60/(mus.bpm||100)/4;
  // A new track waits for the next bar line, then starts from its top.
  if(mus.pending!=null&&mus.step%16===0){mus.song=mus.pending;mus.pending=null;mus.step=0;mus.phrase=0}
  playStep(mus.step,mus.next,st);mus.step=(mus.step+1)%128;mus.next+=st}}
// Drums go straight to the music bus; everything tonal goes through the pumping synth bus.
function kick(at,v,st){const o=audio.createOscillator(),g=audio.createGain();o.frequency.setValueAtTime(190,at);o.frequency.exponentialRampToValueAtTime(48,at+.08);
 env(g,at,.002,v,.34);o.connect(g).connect(musicBus);o.start(at);o.stop(at+.4);o.onended=()=>{o.disconnect();g.disconnect()};
 noise(at,.015,v*.25,musicBus,{type:'highpass',f:2500});
 const p=synthBus.gain,d=.2+.55*mus.int;p.cancelScheduledValues(at);p.setValueAtTime(1-d,at);p.setTargetAtTime(1,at+.015,st*.9)}
function snare(at,v){noise(at,.17,v,musicBus,{type:'bandpass',f:1900,end:1500,q:.8,verb:.3});osc('triangle',230,160,at,.09,v*.45,musicBus,{a:.002})}
function saws(m,at,dur,v,o){[-14,0,14].forEach(d=>osc('sawtooth',mtof(m),mtof(m),at,dur,v,synthBus,{a:.006,rel:Math.min(.08,dur/3),detune:d,...o}))}
function playStep(n,at,st){const I=mus.int,s=n%16,bar=n>>4,so=SONGS[mus.song];
 if(n===0){mus.phrase=(mus.phrase||0)+1;const p=musicProgress();
  mus.key=state==='playing'?(p>.7?2:p>.4?1:0):0;
  mus.sec=state==='playing'&&I>.58&&mus.phrase%4===0?'break':'main';
  const f=synthLP.frequency;f.cancelScheduledValues(at);
  if(mus.sec==='break'){f.setValueAtTime(f.value,at);f.setTargetAtTime(900,at,st*4)}else f.setValueAtTime(18000,at)}
 const brk=mus.sec==='break',quiet=brk&&bar<4,build=brk&&bar>=4,fill=!brk&&bar===7&&I>.5,drop=!brk&&I>.68;
 if(build&&n===64){const f=synthLP.frequency;f.cancelScheduledValues(at);f.setValueAtTime(900,at);f.exponentialRampToValueAtTime(16000,at+st*64)}
 const key=mus.key||0,ch=chordAt(so,bar,key),root=ch[0];let bn=root-12;while(bn<36)bn+=12;const bf=mtof(bn);
 // Pad: always there, swelling in the breakdown and thinning out once the drop takes over.
 if(s===0)ch.forEach(m=>[-9,9].forEach(d=>osc('sawtooth',mtof(m),mtof(m),at,st*16+.4,quiet?.02:drop?.008:.012,synthBus,{a:.4,cut:500+I*1600,detune:d,verb:.5,rel:1})));
 // Arpeggio: eighths, then sixteenths, an octave up at full tilt.
 const ai=so.arp[s];if(ai!=='.'&&(s%2===0||I>.5)){const m=ch[+ai]+12+(I>.8&&s>=8?12:0);osc('square',mtof(m),mtof(m),at,st*.7,.009+.008*I,synthBus,{a:.003,cut:1400+2200*I,cutEnd:700,verb:.3})}
 // Drums.
 if(I>.25&&!quiet){
  let k;if(build)k=s%4===0&&(bar<7||s<12);
  else if(so.drums==='half'&&I>.62)k=s===0||s===10||(I>.82&&(s===3||s===14));
  else k=s===0||s===8||(I>.42&&s%4===0)||(I>.9&&s===14);
  if(fill&&s>=12)k=false;if(k)kick(at,I>.5?.36:.26,st);
  let sn=I>.4&&(so.drums==='half'&&I>.62?s===8:s===4||s===12);
  if(fill&&s>=8&&(s>=12||s%2===0))sn=true;
  if(sn&&!build)snare(at,fill&&s>=8?.06+.012*(s-8):.15);
  if(build){const u=(bar-4)*16+s,every=bar===4?4:bar===5?2:1;if(s%every===0){snare(at,.04+.1*u/64);if(bar===7)snare(at+st/2,.04+.1*u/64)}}
  if(I>.35&&!build&&s%4===2)noise(at,.12,.045,musicBus,{type:'highpass',f:7000});
  if(I>.6&&!build&&s%2===1)noise(at,.03,.018,musicBus,{type:'highpass',f:9000})}
 // The drop: a crash and a sub hit on the first downbeat of each hot phrase.
 if(n===0&&I>.5&&mus.phrase>1){noise(at,1.8,.09,musicBus,{type:'highpass',f:4500,end:2800,verb:.6});if(I>.68)osc('sine',90,30,at,1.1,.25,musicBus,{a:.003})}
 // Risers into each new phrase.
 if(fill&&s===0)noise(at,st*16,.06,musicBus,{type:'bandpass',f:400,end:6000,q:2,a:st*14});
 if(build&&n===64){noise(at,st*64,.08,musicBus,{type:'bandpass',f:300,end:8000,q:1.6,a:st*60,verb:.3});osc('sawtooth',110,1760,at,st*64,.02,synthBus,{a:st*58,cut:3000})}
 // Bass: long notes early, then each track's own groove.
 if(I>.15&&!quiet){
  if(build){if(s%2===0)osc('sawtooth',bf,bf,at,st*1.6,.05,synthBus,{a:.004,cut:300+1400*(n-64)/64,cutEnd:150})}
  else if(I<.42){if(s===0||s===8)osc('sawtooth',bf,bf,at,st*7.5,.06,synthBus,{a:.02,cut:200+I*800,rel:.2})}
  else{const b=so.bass,v=.075*(.7+I*.3),o={a:.004,cut:400+I*1800,cutEnd:150};
   if(b==='wobble'&&I>.62){if(s%2===0){const up=(s>>1)%2;osc('sawtooth',bf,bf,at,st*1.9,.11,musicDrive,{a:.004,cut:up?250:3200,cutEnd:up?2600:220});osc('sine',bf/2,bf/2,at,st*1.9,.09,synthBus,{a:.004})}}
   else if(b==='roll'){if(s%4!==0){osc('sawtooth',bf,bf,at,st*.85,v,synthBus,o);osc('sine',bf/2,bf/2,at,st*.85,v*.8,synthBus,{a:.004})}}
   else if(b==='bounce'){if(s%4===2||s%4===3){const f=s%4===3?bf*2:bf;osc('sawtooth',f,f,at,st*.9,v,synthBus,o);osc('sine',bf/2,bf/2,at,st*.9,v*.8,synthBus,{a:.004})}}
   else if(s%4===2){osc('sawtooth',bf,bf,at,st*1.7,v,synthBus,o);osc('sine',bf/2,bf/2,at,st*1.7,v*.9,synthBus,{a:.004})}
   if(I>.8&&b!=='wobble'&&s%4===0&&!fill){const f=bf/2;osc('sawtooth',f,f,at,st*1.6,.08,musicDrive,{a:.004,cut:900,cutEnd:200})}}}
 // Chord stabs in the drop.
 if(drop&&!build&&so.stab.includes(s)&&!(fill&&s>=12))ch.forEach(m=>saws(m+12,at,st*1.2,.011,{cut:4200,cutEnd:700,verb:.3}));
 // Lead: a soft pluck once things get moving, the track's full voice in the drop, and a
 // harmony a third up on alternate phrases when it is all-out.
 const nt=so.notes[bar][s];if(nt&&I>.45){const m=so.tonic+12+key+sdeg(nt.d),dur=nt.len*st*.95,f=mtof(m);
  if(!drop||quiet)osc('triangle',f,f,at,Math.min(dur,st*3),quiet?.05:.04,synthBus,{a:.003,verb:.5,rel:.05});
  else{if(so.voice==='saw')saws(m,at,dur,.02,{cut:4200,cutEnd:1800,verb:.4});
   else if(so.voice==='chip'){osc('square',f,f,at,dur,.026,synthBus,{a:.003,cut:5000,verb:.35,rel:.03});osc('square',f*2,f*2,at,dur,.009,synthBus,{a:.003,cut:6000,detune:7,rel:.03})}
   else{saws(m,at,Math.min(dur,st*2.5),.018,{a:.003,cut:5200,cutEnd:900,verb:.45});osc('triangle',f*2,f*2,at,Math.min(dur,st*2),.02,synthBus,{a:.003,rel:.04})}
   if(I>.88&&mus.phrase%2===0){const h=mtof(so.tonic+12+key+sdeg(nt.d+2));osc('square',h,h,at,dur,.01,synthBus,{a:.006,cut:3500,verb:.4})}}}}
function updateSound(){$('sound').setAttribute('aria-label',soundOn?'Mute sound':'Enable sound');$('sound').setAttribute('aria-pressed',String(soundOn));$('soundWaves').setAttribute('d',soundOn?'M17 8q5 4 0 8M20 5q8 7 0 14':'m17 9 5 6m0-6-5 6');
 $('music').setAttribute('aria-label',musicOn?'Mute music':'Play music');$('music').setAttribute('aria-pressed',String(musicOn&&soundOn));$('musicSlash').style.display=musicOn&&soundOn?'none':'';
 if(!soundOn&&engineGain)engineGain.gain.setTargetAtTime(0,audio.currentTime,.1)}
let unlockTried=false;
function toggleSound(){if(soundOn&&!audible()&&!unlockTried){unlockTried=true;initAudio();updateSound();return}soundOn=!soundOn;store.set('undertow.sound',soundOn);initAudio();updateSound();if(soundOn)tone(450,.12,.035,600)}
function toggleMusic(){if(musicOn&&soundOn&&!audible()&&!unlockTried){unlockTried=true;initAudio();updateSound();return}musicOn=!musicOn;store.set('undertow.music',musicOn);if(musicOn&&!soundOn){soundOn=true;store.set('undertow.sound',true);initAudio()}updateSound()}
