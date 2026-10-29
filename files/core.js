'use strict';
/* UNDERTOW — a Canvas 2D game. No network, fonts or assets required: players open
   undertow.html, which loads files/undertow.css and the files/*.js scripts in order.
   They are plain scripts (modules will not load from file://) sharing one global
   scope, so a file may use anything declared by a file loaded before it, and any
   function at all once the page has finished loading.
   World coordinates and collision geometry never change on resize. The camera
   reveals more world on wide screens; a bounded zoom preserves mobile lookahead.
   Physics: 120 Hz fixed steps, all velocities in world units per second. */
/* ---- Shared leaderboard ----------------------------------------------------
   Scores are shared through bin.dat in the same folder as this HTML file.
   Browsers never let a page write next to itself unasked, so in Microsoft Edge
   or Google Chrome each player picks that folder once (Leaderboard screen) and
   the browser remembers it. bin.dat is created automatically if it is missing;
   bin.dat.bak is a copy of the last good write. An older plain bin.json is
   imported once, when there is no bin.dat yet. */
// Shown in the footer and on the Duel screen, so players can tell which copy of the game they are running.
const BUILD='2026-10-26 / 12 · Campaign operations';
const BOARD_FILE='bin.dat', BACKUP_FILE='bin.dat.bak', LOCK_FILE='bin.dat.lock', LEGACY_FILE='bin.json';

/* ---- Seal ------------------------------------------------------------------
   Scores and achievements, on this computer and in the shared file, are saved
   scrambled and signed: the text is unreadable, and anything edited by hand no
   longer matches its signature and is thrown away. The key is in this page, so
   this stops casual edits, not someone willing to read the code. */
const SEAL_KEY='n9GekSKyVr_kwL6HkOCF5TuDMairIJL7', SEAL_TAG='UDT1:';
function sealHash(s,seed){let a=0xdeadbeef^seed,b=0x41c6ce57^seed;for(let i=0;i<s.length;i++){const ch=s.charCodeAt(i);a=Math.imul(a^ch,2654435761);b=Math.imul(b^ch,1597334677)}a=Math.imul(a^(a>>>16),2246822507)^Math.imul(b^(b>>>13),3266489909);b=Math.imul(b^(b>>>16),2246822507)^Math.imul(a^(a>>>13),3266489909);return [a>>>0,b>>>0]}
const sealSig=s=>[...sealHash(SEAL_KEY+s,1),...sealHash(s+SEAL_KEY,2)].map(n=>n.toString(16).padStart(8,'0')).join('');
function sealXor(bytes,nonce){let x=sealHash(SEAL_KEY,nonce)[0]||1;for(let i=0;i<bytes.length;i++){x^=x<<13;x^=x>>>17;x^=x<<5;bytes[i]^=x&255}return bytes}
function seal(text){const nonce=crypto.getRandomValues(new Uint32Array(1))[0],body=sealXor(new TextEncoder().encode(sealSig(text)+text),nonce);let bin=String.fromCharCode(nonce>>>24,nonce>>>16&255,nonce>>>8&255,nonce&255);for(let i=0;i<body.length;i+=8192)bin+=String.fromCharCode.apply(null,body.subarray(i,i+8192));return SEAL_TAG+btoa(bin)}
// The original text, or null if it is not sealed or has been altered.
function unseal(s){try{if(typeof s!=='string'||!s.startsWith(SEAL_TAG))return null;const bin=atob(s.slice(SEAL_TAG.length).trim());if(bin.length<36)return null;const nonce=((bin.charCodeAt(0)<<24)|(bin.charCodeAt(1)<<16)|(bin.charCodeAt(2)<<8)|bin.charCodeAt(3))>>>0,body=new Uint8Array(bin.length-4);for(let i=0;i<body.length;i++)body[i]=bin.charCodeAt(i+4);const t=new TextDecoder('utf-8',{fatal:true}).decode(sealXor(body,nonce)),text=t.slice(32);return t.slice(0,32)===sealSig(text)?text:null}catch(_){return null}}

const $=id=>document.getElementById(id), canvas=$('world');
let c=canvas.getContext('2d',{alpha:false});
const TAU=Math.PI*2, clamp=(x,a,b)=>Math.max(a,Math.min(b,x)), mix=(a,b,t)=>a+(b-a)*t;
const smooth=(a,b,x)=>{let t=clamp((x-a)/(b-a),0,1);return t*t*(3-2*t)};
const hash=n=>{let s=Math.sin(n*127.1+311.7)*43758.5453;return s-Math.floor(s)};
const rgb=(a,b,t)=>`rgb(${a.map((v,i)=>Math.round(mix(v,b[i],t))).join(',')})`;
const angDiff=(a,b)=>((a-b+Math.PI*3)%TAU)-Math.PI;
const STEP=1/120, R=24, SURFACE=68, SOUND_SPEED=1100, SONAR_RANGE=1180;
/* Levels scale forward speed, gap size, mine spacing (ramped over `ramp` world
   units), when warships arrive, how often they fire, and how fast air drains. */
const DIFFS={
 cadet:  {label:'Cadet',  speed:[180,265],gap:[255,188],space:[600,500],ramp:26000,drift:2,  ships:15000,shipGap:[13,9],fire:[4.4,3.2],mvel:110,turn:1.15,shipHp:1,twin:false,o2:1,   air:.3, score:.75},
 officer:{label:'Officer',speed:[210,305],gap:[240,170],space:[560,455],ramp:22000,drift:.6, ships:10000,shipGap:[11,7],fire:[3.6,2.5],mvel:140,turn:1.45,shipHp:2,twin:false,o2:1.35,air:.24,score:1},
 captain:{label:'Captain',speed:[240,345],gap:[226,156],space:[525,415],ramp:19000,drift:.3, ships:7000, shipGap:[9,6], fire:[3,2],    mvel:165,turn:1.75,shipHp:2,twin:true, o2:1.6, air:.2, score:1.35},
 admiral:{label:'Admiral',speed:[270,390],gap:[214,146],space:[495,385],ramp:16000,drift:.08,ships:4500, shipGap:[8,5], fire:[2.5,1.6],mvel:190,turn:2.05,shipHp:3,twin:true, o2:1.9, air:.17,score:1.8},
};
// Hull gradient stops (light to dark), then fin colour.
const PALS={us:['#91a6a0','#637f80','#375663','#263e4d','#152834','#071720','#324b54'],uk:['#8fa3ad','#5e7887','#33505f','#22394a','#132534','#06141e','#2f4655'],ru:['#7d8c87','#4e605e','#2b3b3f','#1d2a30','#111c22','#050d12','#26343a'],de:['#a9b6b2','#7e9191','#526972','#3c515c','#24353f','#0d1b23','#46606a'],gato:['#9ba8a5','#6f8685','#48616b','#344b56','#1e303b','#0b1921','#3c5560']};
/* Vessels are modelled on real classes. hx/hy are collision half-extents; speed and
   agility multiply the level's values; o2 is air in seconds; reload in seconds.
   ability is the class special (E): cd is its recharge and dur how long it lasts. */
const SUBS=[
 {id:'virginia',name:'Virginia',origin:'United States / 2004',mark:'SSN-774',desc:'Balanced multi-mission attack boat with a sharp sonar suite.',speed:1.04,agility:1.06,hull:3,o2:85,reload:4.5,sonar:.85,hx:45,hy:16,ability:{id:'salvo',name:'TORPEDO SALVO',desc:'Fires three missiles at once, each locked on a different target.',cd:10},look:{pal:'us',sail:'std',prop:'pump'}},
 {id:'seawolf',name:'Seawolf',origin:'United States / 1997',mark:'SSN-21',desc:'Built for speed. The fastest hull in the fleet, with eight torpedo tubes.',speed:1.12,agility:1,hull:3,o2:75,reload:3.6,sonar:.95,hx:47,hy:17,ability:{id:'flank',name:'FLANK SPEED',desc:'Reactor wide open: 50% faster for 4 seconds, leaving seekers in the wake.',cd:10,dur:4},look:{pal:'us',sail:'fillet',prop:'pump'}},
 {id:'astute',name:'Astute',origin:'United Kingdom / 2010',mark:'S119',desc:'Exceptionally quiet. The fastest sonar recharge and nimble dive planes.',speed:1.02,agility:1.1,hull:3,o2:90,reload:5,sonar:.62,hx:46,hy:16,ability:{id:'silent',name:'SILENT RUNNING',desc:'Goes acoustically dark for 6 seconds. Seekers lose lock and warships hold fire.',cd:13,dur:6},look:{pal:'uk',sail:'slope',prop:'pump'}},
 {id:'type212',name:'Type 212A',origin:'Germany / 2005',mark:'U 31',desc:'Compact air-independent boat. Tiny profile and long endurance, but a thin skin.',speed:.95,agility:1.22,hull:2,o2:115,reload:6,sonar:1.05,hx:36,hy:13,ability:{id:'air',name:'AIP RESERVE',desc:'The air-independent plant restores half your air and seals any leak.',cd:16},look:{pal:'de',sail:'small',stern:'x',prop:'screw'}},
 {id:'gato',name:'Gato',origin:'United States / 1941',mark:'SS-212',desc:'Second World War fleet boat. Quick reloads, but the air runs out fast.',speed:1,agility:1.12,hull:3,o2:62,reload:3.9,sonar:1.15,hx:46,hy:15,ability:{id:'rapid',name:'RAPID RELOAD',desc:'The torpedo room works double-time: half-second reloads for 6 seconds.',cd:12,dur:6},look:{pal:'gato',sail:'tower',prop:'twin',bow:'ship',deck:'fleet'}},
 {id:'akula',name:'Akula',origin:'Soviet Union / 1986',mark:'K-157',desc:'Double hull and heavy plating. Survives a hit that would sink others.',speed:1.03,agility:.95,hull:4,o2:75,reload:5,sonar:1,hx:48,hy:18,ability:{id:'repair',name:'DAMAGE CONTROL',desc:'Repairs one hull section and clears every system fault.',cd:24},look:{pal:'ru',sail:'long',prop:'screw',pod:true}},
 {id:'ohio',name:'Ohio',origin:'United States / 1981',mark:'SSBN-726',desc:'Ballistic missile carrier. Rapid launches, slow to answer the helm.',speed:.98,agility:.86,hull:5,o2:100,reload:2.6,sonar:1,hx:56,hy:18,ability:{id:'strike',name:'TRIDENT STRIKE',desc:'Vertical launch: enough missiles to sink each warship and intercept every seeker in range.',cd:18},look:{pal:'us',sail:'planes',prop:'screw',deck:'hump'}},
 {id:'typhoon',name:'Typhoon',origin:'Soviet Union / 1981',mark:'TK-208',desc:'The largest submarine ever built. Enormous, armoured and ponderous.',speed:.95,agility:.78,hull:6,o2:125,reload:3,sonar:1.1,hx:60,hy:22,ability:{id:'shield',name:'ICE-BREAKER HULL',desc:'Reinforced plating shrugs off all damage for 5 seconds. Rock is still fatal.',cd:15,dur:5},look:{pal:'ru',sail:'aft',prop:'twin',deck:'fore'}},
];
SUBS.push({id:'turtle',name:'Turtle',origin:'Wooden fleet / experimental',mark:'ONE MAN. BIG BOOM.',desc:'A tiny hand-cranked wooden menace. Slow, fragile, and carrying a deeply unreasonable bomb. No sonar: its sweeping lantern reveals only the mines it lights.',speed:.88,agility:1.15,hull:2,o2:55,reload:5.5,sonar:1.15,hx:20,hy:22,ability:{id:'wipe',name:'ABSOLUTELY EVERYONE',desc:'Detonates a screen-clearing bomb. Every visible hostile is destroyed.',cd:30},look:{pal:'wood',sail:'small',prop:'screw',turtle:true}});
PALS.wood=['#c8a36a','#ab834c','#88663b','#654c2d','#453520','#241e15','#a59361'];
const SUB_BY_ID=Object.fromEntries(SUBS.map(s=>[s.id,s]));
/* Achievements run from easy lessons to long-haul goals. Each has a value and a goal:
   run goals read the current dive (R), career goals read lifetime totals (L). */
const DIFF_RANK={cadet:0,officer:1,captain:2,admiral:3};
const TIERS=[['RECRUIT','Learn the boat'],['SEAMAN','First patrols'],['OFFICER','Command the depths'],['VETERAN','Long service'],['LEGEND','The deep remembers']];
const ACHS=[
 ['maiden',0,'Maiden Voyage','Complete your first dive.',1,(R,L)=>L.runs],
 ['breath',0,'Deep Breath','Steer through an air pocket.',1,R=>R.air],
 ['needle',0,'Thread the Needle','Clear 10 minefields in one dive.',10,R=>R.gates],
 ['fish',0,'Fish in the Water','Launch a missile.',1,(R,L)=>L.fired],
 ['orders',0,'Special Orders','Use your boat\'s special ability (E).',1,(R,L)=>L.ability],
 ['snorkel',0,'Snorkel Depth','Ride the surface to refill your air.',1,R=>R.surface],
 ['shakedown',0,'Shakedown Cruise','Travel 750 m in one dive.',750,R=>R.dist],
 ['firstsink',1,'Surface Kill','Sink a warship.',1,R=>R.ships],
 ['hardkill',1,'Hard Kill','Shoot down an incoming missile.',1,R=>R.ints],
 ['sweeper',1,'Minesweeper','Destroy 40 mines with missiles across your career.',40,(R,L)=>L.mines],
 ['dark',1,'Into the Dark','Dive until night falls on the shelf.',1,R=>R.night],
 ['cathedral',1,'The Cathedral','Navigate an undersea cavern.',1,R=>R.cave],
 ['patrol',1,'Patrol Complete','Travel 2,000 m in one dive.',2000,R=>R.dist],
 ['tour',1,'Shipyard Tour','Dive in 4 different classes.',4,(R,L)=>L.subs],
 ['rated',1,'Rated','Reach level 5.',5,(R,L)=>L.lvl],
 ['duelist',1,'Duelist','Win a 1v1 duel.',1,(R,L)=>L.wins],
 ['airman',1,'Air Hound','Collect 50 air pockets across your career.',50,(R,L)=>L.air],
 ['commission',2,'Commissioned','Score 5,000 in one dive on Officer or above.',5000,R=>R.diff>=1?R.score:0],
 ['wolfpack',2,'Wolfpack','Sink 5 warships in one dive.',5,R=>R.ships],
 ['lungs',2,'Iron Lungs','Collect 15 air pockets in one dive.',15,R=>R.air],
 ['crush',2,'Crush Depth','Reach a depth of 90 m.',90,R=>R.depth],
 ['threader',2,'Needle Threader','Clear 100 minefields in one dive.',100,R=>R.gates],
 ['clean',2,'Clean Hull','Travel 2,500 m without taking a hit.',2500,R=>R.hits?0:R.dist],
 ['drydock',2,'Full Dry Dock','Dive in every class of boat.',SUBS.length,(R,L)=>L.subs],
 ['wardroom',2,'Wardroom','Reach level 10.',10,(R,L)=>L.lvl],
 ['regular',2,'Regular','Dive on 3 different days.',3,(R,L)=>L.days],
 ['interceptor',2,'Interceptor','Shoot down 30 incoming missiles across your career.',30,(R,L)=>L.ints],
 ['rival',2,'Rivalry','Finish 5 duels.',5,(R,L)=>L.duels],
 ['longpatrol',3,'Long Patrol','Travel 6,000 m in one dive.',6000,R=>R.dist],
 ['arsenal',3,'Master of Arms','Use the special ability of every class.',SUBS.length,(R,L)=>L.abil],
 ['ace',3,'Ace of the Deep','Sink 15 warships in one dive.',15,R=>R.ships],
 ['captlog',3,'Captain\'s Log','Score 12,000 in one dive on Captain or above.',12000,R=>R.diff>=2?R.score:0],
 ['scourge',3,'Scourge of the Surface','Sink 250 warships across your career.',250,(R,L)=>L.ships],
 ['oldsalt',3,'Old Salt','Complete 150 dives.',150,(R,L)=>L.runs],
 ['leagues',3,'Twenty Thousand Leagues','Travel 250,000 m across your career.',250000,(R,L)=>L.dist],
 ['commander',3,'Commander','Reach level 20.',20,(R,L)=>L.lvl],
 ['devoted',3,'Devoted','Dive on 7 different days.',7,(R,L)=>L.days],
 ['marathon',3,'Marathon Watch','Spend 180 minutes submerged across your career.',180,(R,L)=>L.time],
 ['gladiator',3,'Gladiator','Win 10 duels.',10,(R,L)=>L.wins],
 ['admiralty',3,'The Admiralty','Complete 25 dives on Admiral.',25,(R,L)=>L.adm],
 ['demolition',3,'Demolition Crew','Destroy 200 mines with missiles across your career.',200,(R,L)=>L.mines],
 ['ghost',4,'Ghost','Travel 4,000 m in one dive without launching a missile.',4000,R=>R.fired?0:R.dist],
 ['irondome',4,'Iron Dome','Shoot down 20 incoming missiles in one dive.',20,R=>R.ints],
 ['admiral',4,'Fleet Admiral','Travel 6,000 m in one dive on Admiral.',6000,R=>R.diff>=3?R.dist:0],
 ['flawless',4,'Flawless','Travel 5,000 m on Captain or above without taking a hit.',5000,R=>R.diff>=2&&!R.hits?R.dist:0],
 ['legend',4,'Legend of the Deep','Score 40,000 in one dive.',40000,R=>R.score],
 ['flagofficer',4,'Flag Officer','Reach level 35.',35,(R,L)=>L.lvl],
 ['grandfleet',4,'Grand Fleet','Reach level 50.',50,(R,L)=>L.lvl],
 ['lifer',4,'Lifer','Dive on 20 different days.',20,(R,L)=>L.days],
 ['million',4,'Millionaire','Score 1,000,000 points across your career.',1000000,(R,L)=>L.score],
 ['fleetmaster',4,'Master of the Fleet','Travel 3,000 m in one dive with every class.',SUBS.length,(R,L)=>L.fleet],
 // Campaign (Operation Deep Meridian); L.c* come from campLife() in campaign.js.
 ['enlist',0,'Enlisted','Complete your first campaign mission.',1,(R,L)=>L.cmis],
 ['salvor',0,'Salvor','Recover a load of salvage with the drone.',1,(R,L)=>L.csalv],
 ['strait',1,'The Strait Is Open','Sink the cruiser Grozny in the campaign.',1,(R,L)=>L.cboss.warden],
 ['skyeyes',1,'Eyes in the Sky','Find 5 beacons with the spotter drone.',5,(R,L)=>L.cclues],
 ['shipwright',1,'Shipwright','Build 3 upgrades in the campaign workshop.',3,(R,L)=>L.cbuilt],
 ['calamari',2,'Calamari','Defeat Old Mother in the sea caves.',1,(R,L)=>L.cboss.mother],
 ['redtide',2,'Red Tide','Defeat Volkov’s Vepr.',1,(R,L)=>L.cboss.vepr],
 ['photo',2,'Photo Finish','Win a race against Volkov.',1,(R,L)=>L.craces],
 ['archivist',2,'Archivist','Recover 12 pages of Dr. Vance’s journal.',12,(R,L)=>L.crelic],
 ['kraken',3,'Release the Kraken','Defeat the Kraken.',1,(R,L)=>L.cboss.kraken],
 ['scrapper',3,'Scrapper','Recover 75 loads of salvage.',75,(R,L)=>L.csalv],
 ['decorated',3,'Decorated','Earn 50 campaign stars.',50,(R,L)=>L.cstars],
 ['meridian',4,'Meridian','Complete Operation Deep Meridian.',1,(R,L)=>L.cfin],
 ['perfect',4,'Perfect Record','Earn all 72 campaign stars.',72,(R,L)=>L.cstars],
 ['fitted',4,'Fully Fitted','Build every workshop upgrade to its last level.',14,(R,L)=>L.cbuilt],
].map(([id,tier,name,desc,goal,v])=>({id,tier,name,desc,goal,v}));
ACHS.push({id:'undertow',tier:4,name:'Undertow',desc:'Unlock every other achievement.',goal:ACHS.length,v:(R,L)=>L.count});
const ACH_BY_ID=Object.fromEntries(ACHS.map(a=>[a.id,a]));
// Records worth cheating on are sealed; settings stay plain. Unsealed records from
// before sealing existed are converted once, then never accepted again.
const SEALED=new Set(['undertow.ach.v1','undertow.best.v2','undertow.local.v1','undertow.mine.v1','undertow.pending.v1']);
const PROFILE_PREFIX='undertow.p.', sealedKey=k=>SEALED.has(k)||k.startsWith(PROFILE_PREFIX)||k.startsWith('undertow.score.v2.');
const store={get(k,f){try{const v=localStorage.getItem("offline."+k);if(v===null)return f;if(!sealedKey(k))return JSON.parse(v);const t=unseal(v);return t===null?f:JSON.parse(t)}catch(_){return f}},set(k,v){try{const t=JSON.stringify(v);localStorage.setItem("offline."+k,sealedKey(k)?seal(t):t);return true}catch(_){return false}}};
try{if(!localStorage.getItem('undertow.sealed')){for(const k of SEALED){const v=localStorage.getItem("offline."+k);if(v!==null&&unseal(v)===null)localStorage.setItem("offline."+k,seal(v))}localStorage.setItem('undertow.sealed','1')}}catch(_){}
let W=innerWidth,H=innerHeight,dpr=1,quality=1,scale=1,vw=1,vh=1,camX=0,camY=-10;
let state='menu', panel=null, practice=false, held=false, down=false, inputKeys=new Set(),pointerLift=false;
let diffId=store.get('undertow.diff','officer'), subId=store.get('undertow.sub','gato');
if(!DIFFS[diffId])diffId='officer';if(!SUB_BY_ID[subId])subId='virginia';
let D=DIFFS[diffId], S=SUB_BY_ID[subId];
let t=0, ambient=0, distance=0, speed=0, difficulty=0, night=0, sub={x:0,y:400,v:0}, gates=[],nextGate=900,lastCenter=null;
let pings=[],echoes=[],bubbles=[],debris=[],ships=[],enemyMissiles=[],missiles=[],booms=[],pickups=[],spray=[],ripples=[];
let surfaced=false,surfacedAt=-9,tilt=0,lastDrip=0;
let cleared=0,maxDepth=0,lastPing=-10,lastBubble=0,shake=0,flash=0,crashAt=0;
let hull=3,o2=80,invulnUntil=0,lastHitAt=-9,sonarDownUntil=0,leakUntil=0,ballastUntil=0,lastFire=-99,nextShipAt=0,shipsSunk=0,minesDestroyed=0,intercepts=0,airCollected=0,bonus=0,lastAlarm=0,lowO2Warned=false,abilityAt=-99,abilityUntil=0;
let firstShip=0,wreck=null,camLead=.24,overAt=0,toastUntil=0,announced={},practiceHit=-9,deathCause='',runSeed=Math.random()*1000,lastEntry=null;
let best=Number(store.get('undertow.best.v2',0))||0;
let reduced=matchMedia('(prefers-reduced-motion: reduce)').matches, soundOn=!!store.get('undertow.sound',false),musicOn=!!store.get('undertow.music',true),audio=null,engine=null,engineGain=null;
// cm is the campaign mission being flown and cr its live state (campaign.js); null outside the campaign.
let lastHud=-1,runX0=0,cm=null,cr=null;
$('motion').textContent='Motion effects: '+(reduced?'reduced':'on');
$('callsign').value=String(store.get('undertow.callsign','')).slice(0,16);
function resize(){W=innerWidth;H=innerHeight;dpr=Math.min(devicePixelRatio||1,1.5)*quality;canvas.width=Math.round(W*dpr);canvas.height=Math.round(H*dpr);scale=Math.min(clamp(H/820,.3,1.22),W/650);vw=W/scale;vh=H/scale;}
addEventListener('resize',()=>{resize();updateMenu()});resize();
/* Each run builds its own world: a random chain of biomes (open shelf, shoals,
   caverns, basins, trenches) blended with C1-continuous ramps so there are no
   vertical steps, plus run-specific ripples in the seabed and in the mine line. */
const rnd=(a,b)=>a+Math.random()*(b-a);
/* The course (terrain, minefields, air pockets) draws from two random streams of its
   own. In a duel both are seeded, so both players and anyone watching get the same
   course; one stream per part keeps them in step however far ahead a screen draws. */
const mulberry=a=>()=>{a=a+0x6D2B79F5|0;let x=Math.imul(a^a>>>15,1|a);x=x+Math.imul(x^x>>>7,61|x)^x;return((x^x>>>14)>>>0)/4294967296};
let courseSeed=null,worldRand=Math.random,gateRand=Math.random;
const wrnd=(a,b)=>a+worldRand()*(b-a), grnd=(a,b)=>a+gateRand()*(b-a);
const BIOMES={
 open:  {w:3,len:[2200,4200],v:()=>({cave:0,basin:0,lift:wrnd(-30,40),tight:0,rough:wrnd(.6,1.4)})},
 shoal: {w:2,len:[1800,3000],v:()=>({cave:0,basin:0,lift:wrnd(90,140),tight:0,rough:wrnd(1.2,1.8)})},
 cave:  {w:3,len:[2600,4800],v:()=>({cave:1,basin:0,lift:0,tight:wrnd(0,45),rough:wrnd(.6,1.2)})},
 basin: {w:2,len:[2400,4200],v:()=>({cave:0,basin:wrnd(.7,1.2),lift:0,tight:0,rough:wrnd(.7,1.3)})},
 trench:{w:1,len:[1600,2600],v:()=>({cave:0,basin:wrnd(1.3,1.7),lift:0,tight:0,rough:wrnd(1.6,2.2)})}
};
let SEG=[],TP={};
// terrain() runs thousands of times a frame, mostly at the same grid points, so
// whole-number positions are remembered until the next world is built.
const terrainCache=new Map();
function newWorld(){
 terrainCache.clear();
 TP={a1:wrnd(35,70),w1:wrnd(700,1100),p1:wrnd(0,TAU),a2:wrnd(15,40),w2:wrnd(300,500),p2:wrnd(0,TAU),p3:wrnd(0,TAU),p4:wrnd(0,TAU),
  r1:wrnd(30,60),rw1:wrnd(380,700),rp1:wrnd(0,TAU),r2:wrnd(10,25),rw2:wrnd(800,1300),rp2:wrnd(0,TAU),night:wrnd(2400,4200),sd:wrnd(0,999)};
 SEG=[{x0:0,len:wrnd(2400,3300),r:1,kind:'open',v:{cave:0,basin:0,lift:0,tight:0,rough:1}}];
 if(cm)campWorld();
}
function extendWorld(q){
 while(SEG[SEG.length-1].x0+SEG[SEG.length-1].len<=q){
  const prev=SEG[SEG.length-1],opts=Object.keys(BIOMES).filter(k=>k!==prev.kind);
  let pick=worldRand()*opts.reduce((n,k)=>n+BIOMES[k].w,0),kind=opts[0];
  for(const k of opts){pick-=BIOMES[k].w;if(pick<=0){kind=k;break}}
  const b=BIOMES[kind];SEG.push({x0:prev.x0+prev.len,len:wrnd(...b.len),r:wrnd(1000,1300),kind,v:b.v()});
 }
}
function feature(q){
 extendWorld(q);let lo=0,hi=SEG.length-1;
 while(lo<hi){const m=(lo+hi+1)>>1;if(SEG[m].x0<=q)lo=m;else hi=m-1}
 const s=SEG[lo];if(!lo)return s.v;
 const a=SEG[lo-1].v,b=s.v,k=smooth(s.x0,s.x0+s.r,q);
 return {cave:mix(a.cave,b.cave,k),basin:mix(a.basin,b.basin,k),lift:mix(a.lift,b.lift,k),tight:mix(a.tight,b.tight,k),rough:mix(a.rough,b.rough,k)};
}
newWorld();
function terrain(x){
 const hit=terrainCache.get(x);if(hit)return hit;
 const q=Math.max(0,x), f=feature(q), cave=f.cave, basin=f.basin;
 const centre=423+TP.a1*Math.sin(q/TP.w1+TP.p1)+TP.a2*Math.sin(q/TP.w2+TP.p2)+cave*270+basin*250-f.lift;
 const half=257-50*cave+f.tight*cave+14*Math.sin(q/650+TP.p3);
 const top=mix(68,centre-half,cave);
 const bottom=centre+half+f.rough*(13*Math.sin(q/137+TP.p4)+6*Math.sin(q/57));
 const z={top,bottom,cave,centre:(top+bottom)/2,basin,lift:f.lift,rough:f.rough};
 if(Number.isInteger(x)){if(terrainCache.size>40000)terrainCache.clear();terrainCache.set(x,z)}
 return z;
}
function caveNear(a,b){for(let x=a;x<=b+1;x+=Math.max(1,(b-a)/8))if(terrain(x).cave>=.01)return true;return false}
function route(x){const z=terrain(x);return z.centre+TP.r1*Math.sin(x/TP.rw1+TP.rp1)+TP.r2*Math.sin(x/TP.rw2+TP.rp2);}
function mineY(g,k){return (k?g.bottom:g.top)+(g.amp?g.amp*Math.sin(t*1.3+g.phase):0)}
function makeGate(x,space){
 const d=clamp(x/D.ramp,0,1), z=terrain(x), gap=mix(D.gap[0],D.gap[1],d)*grnd(.9,1.12);
 // The opening can only move as far as a boat can climb before it arrives.
 const shift=cm?clamp(space/(D.speed[1]*S.speed*1.5)*75*S.agility,18,90):clamp(space/mix(D.speed[0],D.speed[1],d)*125,60,104);
 let amp=d>D.drift&&gateRand()<.55?12+gateRand()*20:0;
 amp=Math.min(amp,Math.max(0,(z.bottom-z.top-gap-2*R-72)/2));
 const desired=route(x)+(gateRand()-.5)*gap*.9, reach=lastCenter===null?desired:clamp(desired,lastCenter-shift,lastCenter+shift);
 const centre=clamp(reach,z.top+R+gap/2+36+amp,z.bottom-R-gap/2-36-amp);
 gates.push({x,centre,gap,top:centre-gap/2-R,bottom:centre+gap/2+R,amp,phase:gateRand()*TAU,passed:false,echo:[-100,-100],dead:[false,false]});
 // Some minefields are one-sided: a lone moored mine on the seabed or one hanging from above.
 if(x>1800&&gateRand()<.18)gates[gates.length-1].dead[gateRand()<.5?0:1]=true;
 lastCenter=centre;
 // Air pockets sit midway between minefields, near the line a boat will take.
 if(x>1500&&gateRand()<D.air){const px=x+space*.5,pz=terrain(px),py=clamp(mix(centre,route(px),.5)+(gateRand()-.5)*gap*.8,pz.top+55,pz.bottom-55);pickups.push({x:px,y:py,cy:py,phase:gateRand()*TAU,taken:false});}
}
let burst=0;
function populate(){while(nextGate<(cm?campReach():sub.x)+Math.max(vw,2600)+900){let space=mix(D.space[0],D.space[1],clamp(nextGate/D.ramp,0,1));
 if(burst>0){burst--;space*=grnd(.5,.65)}else if(nextGate>2000&&gateRand()<.12){burst=1+Math.floor(gateRand()*3);space*=grnd(.5,.65)}else if(gateRand()<.1)space*=grnd(1.6,2.2);else space*=grnd(.75,1.35);
 if((nextGate<2000||gateRand()>.06)&&!(cm&&campCalm(nextGate)))makeGate(nextGate,space);nextGate+=space;}gates=gates.filter(g=>g.x>sub.x-700);pickups=pickups.filter(p=>p.x>sub.x-700&&!p.taken);}
/* Lifetime totals. Numbers only ever grow, and the maps (classes dived, abilities used,
   days dived, best distance per class) only gain keys, so two copies of a sailor's
   record merge by taking the larger of each. */
const ST_NUM=['runs','ships','dist','mines','fired','ability','ints','air','gates','time','score','duels','wins','adm'],ST_MAP=['subs','abil','days','subDist'];
function cleanSt(st){st=st&&typeof st==='object'?st:{};const o={};for(const k of ST_NUM)o[k]=Math.max(0,Math.floor(+st[k]||0));
 for(const k of ST_MAP){o[k]={};const m=st[k];if(m&&typeof m==='object')for(const [id,v] of Object.entries(m))o[k][String(id).slice(0,24)]=k==='subDist'?Math.max(0,Math.floor(+v||0)):1}return o}
const ach=(()=>{const a=store.get('undertow.ach.v1',{})||{};return {un:a.un||{},best:a.best||{},st:cleanSt(a.st)}})();
let run={hits:0,fired:0,ability:0,committed:false,earned:[],xp0:0};
const achSave=()=>profDirty(false);
// The sailor whose record is loaded (see Profiles). key is the callsign in file-name form.
const PROFILE_RUNS=25, prof={key:'',name:'Anonymous',pulled:false,scores:[],at:0,timer:0,chain:Promise.resolve(),note:''};
/* Levels come from everything a sailor has done: distance, minefields, kills, air,
   dives, time submerged, days played, duels, and achievements by tier. Each level
   needs more XP than the last. */
const LEVEL_MAX=99,TIER_XP=[100,250,500,1000,2000];
const xpFor=L=>Math.round(400*Math.pow(Math.max(0,L-1),1.7));
function levelOf(x){let L=1;while(L<LEVEL_MAX&&x>=xpFor(L+1))L++;return L}
const RANKS=[[1,'SEAMAN RECRUIT'],[3,'SEAMAN'],[6,'PETTY OFFICER'],[10,'CHIEF PETTY OFFICER'],[15,'ENSIGN'],[20,'LIEUTENANT'],[27,'LIEUTENANT COMMANDER'],[35,'COMMANDER'],[45,'CAPTAIN'],[55,'COMMODORE'],[65,'REAR ADMIRAL'],[78,'VICE ADMIRAL'],[90,'FLEET ADMIRAL']];
const rankTitle=L=>RANKS.filter(r=>L>=r[0]).pop()[1];
function profXp(st=ach.st,un=ach.un){
 let x=st.dist*.5+st.gates*2+st.ships*60+st.mines*15+st.ints*40+st.air*10+st.runs*25+st.time/4+st.duels*100+st.wins*250+Object.keys(st.days).length*150;
 for(const id of Object.keys(un))if(ACH_BY_ID[id])x+=TIER_XP[ACH_BY_ID[id].tier];
 return Math.floor(x+campXp());
}
const today=()=>new Date().toISOString().slice(0,10);
function achLife(){const st=ach.st,live=state==='playing'&&!run.committed&&!practice;
 const days={...st.days},subDist={...st.subDist};if(live){days[today()]=1;subDist[subId]=Math.max(subDist[subId]||0,Math.floor(distance))}
 return {runs:st.runs,fired:st.fired,ability:st.ability,ships:st.ships+(live?shipsSunk:0),dist:st.dist+(live?Math.floor(distance):0),mines:st.mines+(live?minesDestroyed:0),
  ints:st.ints+(live?intercepts:0),air:st.air+(live?airCollected:0),score:st.score+(live?score():0),time:Math.floor((st.time+(live?t:0))/60),duels:st.duels,wins:st.wins,adm:st.adm,
  days:Object.keys(days).length,fleet:SUBS.filter(s=>(subDist[s.id]||0)>=3000).length,lvl:levelOf(profXp()),
  subs:Object.keys(st.subs).length,abil:Object.keys(st.abil).length,count:ACHS.filter(a=>a.id!=='undertow'&&ach.un[a.id]).length,...campLife()}}
function achRun(){return {dist:Math.floor(distance),ships:shipsSunk,gates:cleared,air:airCollected,ints:intercepts,depth:Math.floor(maxDepth),score:score(),diff:DIFF_RANK[diffId],hits:run.hits,fired:run.fired,surface:announced.surface?1:0,night:announced.night?1:0,cave:announced.cave?1:0}}
// Checked a few times a second during a dive and once more when it ends. Practice never counts.
function achCheck(){
 if(practice)return;const R=achRun(),L=achLife(),day=today();let dirty=false;
 for(const a of ACHS){const v=Math.max(0,Math.floor(a.v(R,L)||0));if(v>(ach.best[a.id]||0)){ach.best[a.id]=v;dirty=true}
  if(!ach.un[a.id]&&v>=a.goal){ach.un[a.id]=day;run.earned.push(a.id);dirty=true;achPop(a);if(a.id!=='undertow')return achCheck()}}
 if(dirty)achSave();
}
let achPopUntil=0,achQueue=[];
function achPop(a){achQueue.push(a);if(achQueue.length===1)achShow()}
function achShow(){const a=achQueue[0];if(!a)return;$('achPopKind').textContent=a.kind||'ACHIEVEMENT UNLOCKED';$('achPopName').textContent=a.name.toUpperCase();$('achPop').classList.add('show');tone(660,.2,.05,990);setTimeout(()=>tone(990,.3,.05,1320),140);
 setTimeout(()=>{$('achPop').classList.remove('show');setTimeout(()=>{achQueue.shift();achShow()},500)},3200)}
function achCommit(){
 if(practice||run.committed)return;const st=ach.st;st.runs++;st.ships+=shipsSunk;st.dist+=Math.floor(distance);st.mines+=minesDestroyed;
 st.ints+=intercepts;st.air+=airCollected;st.gates+=cleared;st.time+=Math.floor(t);st.score+=score();st.days[today()]=1;if(diffId==='admiral')st.adm++;st.subDist[subId]=Math.max(st.subDist[subId]||0,Math.floor(distance));
 run.committed=true;achCheck();achSave();
}
function achCountText(){const n=ACHS.filter(a=>ach.un[a.id]).length;return 'Achievements '+n+'/'+ACHS.length}
function reset(){
 if(typeof analytics!=='undefined')analyticsEnd('abandoned');
 if(cm){if(cr&&cr.expedition)expeditionPanel(false);cr=null}
 D=cm?campDiff():DIFFS[diffId];S=cm?campSub():SUB_BY_ID[subId];runX0=0;
 t=0;distance=0;difficulty=0;speed=D.speed[0];night=0;runSeed=Math.random()*1000;if(courseSeed===null)worldRand=gateRand=Math.random;else{worldRand=mulberry(courseSeed);gateRand=mulberry(courseSeed^0x9E3779B9)}newWorld();burst=0;firstShip=D.ships*rnd(.7,1.3);sub={x:0,y:route(0),v:0};gates=[];nextGate=900;lastCenter=null;
 pings=[];echoes=[];bubbles=[];debris=[];ships=[];enemyMissiles=[];missiles=[];booms=[];pickups=[];spray=[];ripples=[];surfaced=false;surfacedAt=-9;tilt=0;lastDrip=0;
 cleared=0;maxDepth=0;lastPing=-10;lastBubble=0;shake=0;flash=0;airFx=hullFx=crackFx=0;wreck=null;camLead=.24;
 hull=S.hull;o2=S.o2;invulnUntil=0;lastHitAt=-9;sonarDownUntil=0;leakUntil=0;ballastUntil=0;lastFire=-99;nextShipAt=0;shipsSunk=0;minesDestroyed=0;intercepts=0;airCollected=0;bonus=0;lastAlarm=0;lowO2Warned=false;abilityAt=-99;abilityUntil=0;
 announced={};run={hits:0,fired:0,ability:0,committed:false,earned:[]};practiceHit=-9;lastHud=-1;toastUntil=0;camY=Math.max(-130,terrain(0).centre-vh*.53);clearInput();populate();buildPips();
 screenBombAt=-99;if(cm)campReset();
}
function score(){return Math.floor((distance+cleared*10+bonus)*D.score)}
function show(id,visible){$(id).hidden=!visible}
function callsign(){return $('callsign').value.replace(/[\u0000-\u001f]/g,'').trim().slice(0,16)||'Anonymous'}
// A dive from the home screen needs a callsign. BEGIN DESCENT looks disabled until one is typed; a press without
// one focuses the field and shows the inline message instead of starting.
function callsignSet(){return callsign().toLowerCase()!=='anonymous'}
function callsignState(){const ok=callsignSet(),l=$('launch');l.classList.toggle('locked',!ok);l.setAttribute('aria-disabled',String(!ok));if(ok){$('callsignMsg').hidden=true;$('callsign').classList.remove('err')}}
function launchDive(){if(callsignSet())return start();const i=$('callsign');i.classList.remove('err');void i.offsetWidth;i.classList.add('err');$('callsignMsg').hidden=false;i.focus();callsignState()}
function start(){initAudio();nextSong();store.set('undertow.callsign',$('callsign').value.trim().slice(0,16));profSwitch();ensureFleetSelection();if(cm){subId=campSubs().includes(camp.data.sub)?camp.data.sub:'gato';diffId=cm.diff;practice=false}if(!practice){ach.st.subs[subId]=1;achSave()}try{getSelection().removeAllRanges()}catch(_){}reset();run.xp0=profXp();state='playing';analyticsBegin();panel=null;duel.after=null;$('again').lastChild.textContent='DIVE AGAIN';show('restartPause',true);setTimeout(ensureFx,60);$('hud').classList.remove('ended');['menu','footer','paused','help','over','board','hangar','ach','duel','camp','campDone'].forEach(id=>show(id,false));show('hud',true);show('pause',true);$('hint').style.opacity='1';$('toast').classList.remove('show');toast(practice?'PRACTICE DIVE':'DIVE COMMENCING / '+D.label.toUpperCase(),practice?'Explore freely. Damage and air loss are disabled.':'Guard your air and your hull. The first minefield is ahead.',3);last=performance.now();acc=0;}
function home(){const wasCamp=campExit();state='menu';panel=null;duel.after=null;$('again').lastChild.textContent='DIVE AGAIN';clearInput();$('hud').classList.remove('ended');['paused','over','hud','pause','help','board','hangar','ach','duel'].forEach(id=>show(id,false));show('menu',true);show('footer',true);reset();updateMenu();if(wasCamp)openPanel('camp');}
function clearInput(){held=false;down=false;pointerLift=false;inputKeys.clear();$('thrust').classList.remove('on')}
function pause(){if(state!=='playing')return;state='paused';clearInput();show('paused',true);$('resume').focus()}
function resume(){if(state!=='paused')return;state='playing';show('paused',false);last=performance.now();acc=0;}
function toast(title,body,seconds=4,bad=false){$('toastTitle').textContent=title;$('toastBody').textContent=body;toastUntil=t+seconds;$('toast').classList.add('show');$('toast').classList.toggle('bad',bad);}
function openPanel(id){if(panel)show(panel,false);panel=id;if(state==='over')show('over',false);show(id,true);if(id==='board'){renderBoard();lbSync(false)}if(id==='hangar')renderHangar();if(id==='duel'){if(!duel.diffSet){duel.diff=diffId;duel.diffSet=true}renderDuel();duelTick()}if(id==='ach'){lb.achWho='';renderAch();lbSync(false)}if(id==='camp')renderCamp();if(id==='statistics')analyticsRender();const f=$(id).querySelector('.launch');if(f)f.focus({preventScroll:true})}
function closePanel(){if(!panel)return;show(panel,false);panel=null;if(state==='over'){show('over',true);$('again').focus()}}
