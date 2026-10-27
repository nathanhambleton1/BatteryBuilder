'use strict';
/* ---- Campaign data: Operation Deep Meridian ------------------------------------
   Story, cast, chapters and the 24 missions. Everything here is plain data read by
   campaign.js. Positions are world units along the course (10 units = 1 m). Each
   mission's course is seeded from its id, so every sailor dives the same campaign.

   Mission fields:
    diff     base level (DIFFS key); speed and gaps ramp over the mission's length
    L        finish line (missions without a boss)
    cps      checkpoint positions; a lost boat restarts from the last one passed
    biomes   scripted seabed: [kind,length] pairs from x=0, random beyond the end
    night    x where dusk begins (0 = dark from the start, absent = daylight)
    ships    x where warships start hunting (absent = none); shipHp overrides
    mines    minefield density (1 = normal), gapK widens or narrows the gaps
    air      chance of an air pocket per minefield; drift where mines start drifting
    wrecks   [x,kind] on the seabed for the salvage drone
    recon    surface zones for the spotter drone: {x0,x1,clues:[[x,height]],relic,flak}
    obj      {salv:n} salvage loads, {sub:n} loads from sunken submarines,
             {clues:n} beacons found from the air, need:'core' a wreck that must be raised
    boss     {k,at}: from `at` the arena replaces the finish line
    foes     [x,kind]: enemies met on the way (hunter subs, destroyers, cave octopods,
             Kraken ambushes); they harass the boat for a while and can be sunk
    race     {rv,rival}: a rival boat to beat to the finish (rv is its speed)
    chase    {from,to}: the Kraken hunts you between these positions
    relic    the hidden journal page: {t:'float',x,d} (d 0 = ceiling, 1 = seabed),
             {t:'wreck',i} inside wreck i, or the spotter drone's relic in a recon zone
    start    {hull:-1,tubes:false}: the boat begins damaged (sabotage)
    msgs     [x,who,text] radio traffic; cuts {cpIndex:[[who,text]]} pause for a scene
    pre/post cutscene ids; reward [scrap,alloy,circuits] first time; unlock a boat */

const CAST={
 HALE:{name:'ADM. RUTH HALE',role:'FLEET COMMAND',c:'#ecc69b',i:'RH'},
 JUNO:{name:'LT. JUNO PARK',role:'CHIEF ENGINEER',c:'#a6ead5',i:'JP'},
 RIGGS:{name:'PO TOMMY RIGGS',role:'SONAR',c:'#9fdcf0',i:'TR'},
 VANCE:{name:'DR. ELIAS VANCE',role:'RECOVERED LOG',c:'#d8c3f0',i:'EV'},
 VOLKOV:{name:'CAPT. ANATOLY VOLKOV',role:'SOVIET NAVY / VEPR',c:'#e3785f',i:'AV'},
 YOU:{name:'',role:'COMMANDING OFFICER',c:'#e8f4ee',i:''},
 NARR:{name:'',role:'',c:'#91b0b5',i:''},
};

const CHAPTERS=[
 {n:'I',name:'SHAKEDOWN',line:'An old boat, a new captain, and a ship that should not be there.'},
 {n:'II',name:'THE DROWNED COAST',line:'Beacons, wrecks and the thing that lives in the sea caves.'},
 {n:'III',name:'THE RACE',line:'Captain Volkov wants the Core. So do you.'},
 {n:'IV',name:'NORTHERN LIGHTS',line:'A prize, a minefield, and a gate into the deep.'},
 {n:'V',name:'THE KRAKEN’S TRENCH',line:'Where the Meridian went down, and what pulled her there.'},
 {n:'VI',name:'MERIDIAN',line:'The Core comes home, or nobody does.'},
];

/* Workshop upgrades apply to every boat in the campaign. cost[level] = [scrap,alloy,circuits]. */
const UPGRADES=[
 {id:'hull',name:'Hull plating',desc:'Bolt on another hull section.',per:'+1 HULL',max:2,cost:[[12,2,0],[26,6,2]]},
 {id:'air',name:'CO2 scrubbers',desc:'Stretch every breath of air further.',per:'+15% AIR',max:3,cost:[[8,1,0],[16,3,1],[28,6,3]]},
 {id:'reload',name:'Torpedo room',desc:'A faster crew and a better loading rail.',per:'-10% RELOAD',max:3,cost:[[10,2,0],[18,4,1],[30,7,3]]},
 {id:'sonar',name:'Sonar array',desc:'A wider array pings more often.',per:'+12% PING RATE',max:2,cost:[[8,2,1],[18,5,3]]},
 {id:'drone',name:'Drone winch',desc:'Stronger ROV thrusters and longer batteries: +8 seconds underwater, +5 seconds airborne.',per:'+15% ROV THRUST / MORE BATTERY',max:2,cost:[[6,1,1],[14,4,2]]},
 {id:'ballast',name:'Ballast pumps',desc:'The boat answers the helm sooner.',per:'+6% AGILITY',max:2,cost:[[10,3,0],[20,6,2]]},
];
const PARTS=[['scrap','SCRAP'],['alloy','ALLOY'],['circ','CIRCUITS']];

/* Dr. Vance's journal: one hidden page per mission. */
const JOURNAL=[
 'Day 1. The Core held 94% charge after the bench test. Admiralty wants a sea trial. I want another year. They are paying, so we sail.',
 'Day 3. Captain Moreau calls the Core “the kettle”. It runs warm, always warm, even switched off. The galley crew keep their coffee on the casing.',
 'Day 6. Something followed us for an hour today. Not a submarine. Sonar called it a whale. Whales do not change course when you do.',
 'Day 8. A Soviet trawler with too many antennas is shadowing the Meridian. Moreau has stopped pretending not to see it.',
 'Day 9. Thermal plumes off the Drowned Coast. Every vent we pass, the Core’s output climbs. It is not drawing power. It is answering.',
 'Day 10. I dropped two emergency buoys on the old route. If anyone reads this, follow them.',
 'Day 11. The caves are full of life that should not exist this far north. Octopus the size of a tram. It watched the hull for a long time.',
 'Day 12. The big one in the caves is a mother. The small ones fled when the Core passed. They know it. Everything down here knows it.',
 'Day 13. Moscow has sent a captain named Volkov. Moreau knew him at a conference once. “Honest,” he said. “That is what makes him dangerous.”',
 'Day 14. Sabotage? A valve failed that cannot fail. I trust this crew. I do not trust whoever loaded our stores.',
 'Day 15. The Core spikes whenever the current runs north. The ocean has a pulse down here, and the Core keeps time with it.',
 'Day 16. Volkov signalled us by light: “Turn back. This is bigger than flags.” I almost agree with him.',
 'Day 17. Found a Soviet hull on the bottom, years old, crushed like a can. Something held it. Something squeezed.',
 'Day 18. We released the spotter drone over the islands. Old radar towers. Someone has been watching this sea for a very long time.',
 'Day 19. Mines everywhere, old and new. Somebody wants this stretch of water left alone. Somebody else keeps adding more.',
 'Day 20. There is a gate. That is the only word for it: two walls of rock and a darkness between them that sonar will not cross.',
 'Day 21. We are in the trench. The Core is at 140% and rising. Moreau ordered it shut down. It will not shut down.',
 'Day 21, later. The Kraken is real. It is old, older than the trench maybe. It is not hunting us. It is hunting the heat.',
 'Day 22. Hull breach aft. We are settling on a ledge at four hundred metres. The crew are in the escape trunk. I am staying with the Core.',
 'Day 22, later. If it wants the heat, I can give it the heat. I am venting the Core’s casing. The creature is turning away. It is working.',
 'Day 23. The crew got out. I watched their buoy light go up. I am cold and I am very happy.',
 'Day 24. The Core is dormant now. It needs a cold hand and a fast boat to carry it out. I hope whoever reads this has both.',
 'Day 25. Volkov, if it is you: the Core is not a weapon. It is a battery. It could light a city. Please let it.',
 'Last page. Tell my daughter the kettle worked. — E. Vance',
];

const CLUE_TEXT=['The buoy is still transmitting the Meridian’s course.','A flare canister wedged in the rocks. Its log points north.','Fresh paint on an old radar mast: a Meridian crew mark.','A life raft, empty, tied to the cliff. Someone made it ashore.','A survey stake with Vance’s initials and a depth: 400 m.','Tyre tracks on the beach. Soviet landing craft.','A radio mast still humming on battery. It is beaming the Core’s signal.','Scorch marks on the cliff top. Something very hot passed here.'];

/* Cutscenes. A line is [who,text,scene] (the scene carries on until changed) or a
   title card {title,sub,scene}. Scenes are painted in campaign-draw.js. */
const CINES={
 prologue:[
  {title:'OPERATION DEEP MERIDIAN',sub:'NORTH ATLANTIC / 1986',scene:'title'},
  ['NARR','Eleven days ago the research submarine Meridian went silent beyond the continental shelf. Her last signal was a distress strobe, going down.','meridian_last'],
  ['NARR','Aboard her: Dr. Elias Vance, and the Thermal Core, a prototype battery that could light a city for a year.','core'],
  ['HALE','Captain. Every attack boat we have is shadowing the Northern Fleet. What I can give you is the Remora.','pier_night'],
  ['HALE','She is a Gato-class fleet boat, older than both of us. She floats, she dives, and as of tonight she is yours.','hale'],
  ['JUNO','Lieutenant Juno Park, chief engineer. Two salvage drones on her belly, a spotter drone on her deck. Please don’t ask about the paperwork.','drydock'],
  ['RIGGS','Petty Officer Riggs, sonar. If it makes a sound down there, Captain, I will hear it first.','riggs'],
  ['HALE','Find the Meridian. Bring home the Core, and Vance if he is alive. And Captain: Moscow is listening.','map'],
  ['YOU','Take her out. All ahead full.','you'],
  {title:'CHAPTER I',sub:'SHAKEDOWN',scene:'sea'},
 ],
 m1_post:[
  ['HALE','Not bad for a museum piece. The tender says you came in hard and straight.','tender'],
  ['JUNO','She leaks a little. Mostly in the good way.','juno'],
  ['HALE','We found debris from the Meridian’s escort on the shelf. Juno, show the Captain what your drones can do.','map'],
 ],
 m2_post:[
  ['RIGGS','Captain, the drone brought up the escort’s recorder. It is still blinking.','recorder'],
  ['RIGGS','Last entry: Meridian altered course for the Drowned Coast. Then nothing.','logtape'],
  ['HALE','And something else. A cruiser with no flag has been sitting on the strait for three days.','periscope'],
 ],
 m3_post:[
  ['HALE','Those ships were crewed by contractors. Somebody paid them to keep the strait closed.','hale'],
  ['RIGGS','Intercepting radio traffic, Captain. Russian. It is addressed to the cruiser.','radio'],
  ['VOLKOV','Grozny, this is Vepr. Hold the strait. No American boat passes until I have it.','volkov_bridge'],
  ['JUNO','Grozny. That is a cruiser. That is a very large cruiser.','juno'],
 ],
 m4_pre:[
  ['RIGGS','Heavy screws ahead. One big contact, sitting right across the channel.','periscope'],
  ['HALE','That is the Grozny. Nothing gets through while she is on station. Make her move, Captain.','map'],
  ['JUNO','She rolls depth charges off her stern. Watch for the red rings and do not be at that depth when they go off.','warden'],
 ],
 m4_post:[
  ['RIGGS','Breaking-up noises. The Grozny is going down in two pieces.','grozny_sink'],
  ['HALE','The strait is open. Admiralty is impressed, which they hate.','hale'],
  ['HALE','Kiel has lent us a Type 212A. Small, quiet and long-legged. She is in the dry dock when you want her.','drydock_type212'],
  {title:'CHAPTER II',sub:'THE DROWNED COAST',scene:'island'},
 ],
 m5_pre:[
  ['JUNO','The Meridian dropped emergency buoys along the coast. They are up on the islands, out of reach of a boat.','island'],
  ['JUNO','So we fly. Surface at a recon point, press Q, and the spotter is yours. Climb with the rise control.','drone_launch'],
  ['JUNO','The beacons are logged on the drone, not on the boat. Turn it around with Q and land it on our deck, or we lose what it found.','juno'],
  ['RIGGS','And mind the gulls. They do not respect aircraft.','gulls'],
 ],
 m5_post:[
  ['RIGGS','Three beacons. Triangulating... their course runs through the wreck shoals and into the sea caves.','map'],
  ['VANCE','“I dropped two emergency buoys on the old route. If anyone reads this, follow them.”','logtape'],
  ['YOU','Then we follow them.','you'],
 ],
 m6_post:[
  ['JUNO','A graveyard. Half these hulls went down in the last twenty years, and nobody reported any of them.','graveyard'],
  ['RIGGS','Something big is moving in the caves ahead. Sonar keeps losing it. It keeps finding us.','sonar_big'],
 ],
 m7_post:[
  ['RIGGS','Contact. Massive. It is coming out of the rock.','sonar_big'],
  ['JUNO','Captain, those are arms. Those are a lot of arms.','tentacles'],
 ],
 m8_pre:[
  ['VANCE','“The big one in the caves is a mother. It watched the hull for a long time.”','logtape'],
  ['JUNO','Its eye is the only soft target. Everything else is muscle and spite.','octopus'],
  ['JUNO','The arms come out of the ceiling and the floor. Watch for the glow and thread between them.','tentacles'],
 ],
 m8_post:[
  ['RIGGS','She is retreating into the deep caves. We are clear.','octo_retreat'],
  ['JUNO','She was guarding something. A dive helmet, Captain. Meridian issue.','divesuit'],
  ['VANCE','“Everything down here knows the Core. The big one lives in the trench.”','logtape'],
  ['HALE','Admiralty has released a Virginia-class boat to you. You will want speed for what comes next.','drydock_virginia'],
  {title:'CHAPTER III',sub:'THE RACE',scene:'stream'},
 ],
 m9_pre:[
  ['RIGGS','Contact, Captain. Akula class, making thirty knots, same heading as us.','sonar'],
  ['VOLKOV','American captain. I am Volkov, of the Vepr. You are following the same lights I am.','volkov_bridge'],
  ['VOLKOV','Let us make it honest. First boat to the last beacon. The loser goes home.','volkov'],
  ['JUNO','Ride the bright currents for speed and grab the orange vents. Every hit we take slows us down.','stream'],
 ],
 m9_post:[
  ['VOLKOV','Hm. A good boat. A better captain than I was told. I will remember this.','volkov_bridge'],
  ['RIGGS','Captain, the Vepr just dropped something behind her. Small. Metallic. Drifting toward us.','limpet'],
  ['JUNO','Oh no.','alarm'],
 ],
 m10_pre:[
  {title:'SABOTAGE',sub:'THE TORPEDO ROOM IS FLOODING',scene:'alarm'},
  ['JUNO','Limpet charge. The torpedo room is under water and we lost a hull section. Tubes are dead.','flood'],
  ['JUNO','There are sunken submarines on this stretch. Send the drone down and pull parts off them. Four loads and I can fix this.','sunken_subs'],
  ['HALE','Repair tender is waiting at the far end. Get there, Captain, and keep your head down.','hale'],
 ],
 m10_post:[
  ['JUNO','Tubes are dry and loaded. The plating is ugly but it will hold. Don’t tell the Admiral what I welded it to.','weld'],
  ['HALE','Volkov has the next beacon’s bearing. The current runs north tonight, and so does he.','map'],
 ],
 m11_post:[
  ['VOLKOV','Again you beat me. Very well. Then we stop racing.','volkov_bridge'],
  ['RIGGS','The Vepr is turning around. She is flooding tubes. All of them.','tubes'],
 ],
 m12_pre:[
  ['VOLKOV','No hard feelings, Captain. The Core is too important to leave to the fast.','volkov'],
  ['JUNO','He fires stern torpedoes and drops mines in his wake. Shoot the mines if you need a gap.','juno'],
 ],
 m12_post:[
  ['RIGGS','Vepr is blowing ballast. She is surfacing, trailing oil.','vepr_surface'],
  ['VOLKOV','This is not finished. The Core belongs to whoever is still afloat at the end.','volkov_bridge'],
  ['HALE','A Seawolf-class boat is yours, Captain. Fastest hull in the fleet. Do not scratch it.','drydock_seawolf'],
  {title:'CHAPTER IV',sub:'NORTHERN LIGHTS',scene:'radar_island'},
 ],
 m13_pre:[
  ['RIGGS','Old Soviet hull on the bottom. Akula class. Her crew abandoned her years ago.','akula_wreck'],
  ['JUNO','Her reactor might still be good. Bring me parts and her codebook and I can get her running.','juno'],
 ],
 m13_post:[
  ['JUNO','Captain, I may have accidentally refitted an entire Akula. She is in the dry dock.','drydock_akula'],
  ['HALE','I did not hear that. I especially did not hear it from Moscow.','hale'],
 ],
 m14_pre:[
  ['JUNO','The northern islands have old radar towers on them. Someone is still running the flak guns.','radar_island'],
  ['JUNO','The black bursts flicker red before they pop. And the wind up there is nasty, so expect gusts.','gulls'],
 ],
 m14_post:[
  ['RIGGS','Four markers. They all point at one place: a gap in the seabed the old charts call the Gate.','map'],
  ['VANCE','“There is a gate. Two walls of rock and a darkness between them that sonar will not cross.”','gate'],
 ],
 m15_post:[
  ['RIGGS','We are through. Captain, my hands are shaking.','riggs'],
  ['HALE','The Gate is ahead. Whatever is past it pulled the Meridian down. Go carefully.','gate'],
 ],
 m16_pre:[
  ['RIGGS','Sonar is... the whole seabed is moving.','sonar_big'],
  ['JUNO','That is not seabed.','kraken_shadow'],
  ['HALE','Do not fight it. You cannot fight it. Run, Captain. Run for the far side of the Gate.','kraken_chase'],
 ],
 m16_post:[
  ['RIGGS','It let us go. I don’t know why it let us go.','kraken_eye'],
  ['VANCE','“It is not hunting us. It is hunting the heat.”','logtape'],
  ['HALE','The Astute is yours. Quietest boat ever built. You are going to need quiet.','drydock_astute'],
  {title:'CHAPTER V',sub:'THE KRAKEN’S TRENCH',scene:'kraken'},
 ],
 m17_pre:[
  ['RIGGS','Debris field. This is her, Captain. This is the Meridian, in pieces.','meridian_debris'],
  ['JUNO','Pull everything you can. Somewhere in there is the trail to the Core.','sunken_subs'],
 ],
 m17_post:[
  ['VANCE','“Hull breach aft. We are settling on a ledge at four hundred metres. I am staying with the Core.”','logtape'],
  ['RIGGS','The Core is not in the debris. It is deeper. In the lair.','kraken_lair'],
 ],
 m18_pre:[
  ['VOLKOV','Captain. I have friends now. Moscow sent me a wolfpack.','volkov_bridge'],
  ['HALE','Warships above and the Vepr below. Win the race to the lair and you win the Core.','wolfpack'],
 ],
 m18_post:[
  ['VOLKOV','You are a stubborn people.','volkov'],
  ['RIGGS','Lair entrance is ahead. We will need eyes on the islands above it.','island'],
 ],
 m19_post:[
  ['RIGGS','The markers ring one cave. The Core’s signal is coming from inside it.','kraken_lair'],
  ['JUNO','And the Kraken is lying on top of it like a cat on a radiator.','kraken'],
 ],
 m20_pre:[
  ['HALE','There is no going around it, Captain. Make it let go of the Core.','hale'],
  ['JUNO','Its eye only opens after it attacks. The rest of the time that lid is armour. Wait for the glow.','kraken_eye'],
  ['RIGGS','When it lines up a sweep, the band lights up red. Do not be in that band.','sweep'],
 ],
 m20_post:[
  ['RIGGS','It is sinking. It is going back into the dark.','kraken_sink'],
  ['JUNO','Captain. The Core. I can see the casing from here.','core_found'],
  ['HALE','The Ohio is yours. Bring that thing home.','drydock_ohio'],
  {title:'CHAPTER VI',sub:'MERIDIAN',scene:'core'},
 ],
 m21_pre:[
  ['JUNO','The Core is in the old Meridian hull. Raise it with the drone, plus every spare part you can carry.','core_found'],
  ['RIGGS','Once it is aboard the whole ocean will hear the heat. Expect company.','sonar'],
 ],
 m21_post:[
  ['JUNO','The Core is aboard. It is warm. It is so warm.','core'],
  ['VOLKOV','Captain. I have a Typhoon now. You have something of mine. Let us race one last time.','typhoon_turn'],
 ],
 m22_post:[
  ['VOLKOV','No. No more races.','volkov_bridge'],
  ['RIGGS','The Typhoon is coming about. She is bigger than anything I have ever heard.','typhoon_turn'],
 ],
 m23_pre:[
  ['VOLKOV','I am sorry, Captain. Truly. Moscow does not accept second place.','volkov_bridge'],
  ['JUNO','The Typhoon is shielded. When she opens her hatches to fire, the shield drops. Hit her then.','typhoon_shield'],
  ['JUNO','When she glows red she is about to ram. Get out of her line.','ram'],
 ],
 m23_post:[
  ['RIGGS','Typhoon is surfacing. Her crew are on deck. Volkov is signalling by lamp.','typhoon_surface'],
  ['VOLKOV','“Vance was right. It is a battery. Light a city with it, Captain. One of ours, one day.”','volkov_bridge'],
  ['HALE','Then bring it home. All the way home.','map'],
 ],
 m24_pre:[
  ['RIGGS','Captain... the Kraken. It is awake again, and it smells the Core.','kraken_eye'],
  ['HALE','Home port is beyond the trench. Everything we have is waiting for you there.','hale'],
  ['JUNO','Full speed. Don’t look back. Actually, look back a little. It helps with the arms.','kraken_chase'],
 ],
 m24_post:[
  {title:'HOME PORT',sub:'0612 HOURS',scene:'port'},
  ['HALE','Remora, you are cleared to come alongside. Welcome home.','port_pier'],
  ['JUNO','The Core is cool to the touch for the first time in months. I think it knows it is home.','core'],
  ['VANCE','“Tell my daughter the kettle worked.”','logtape'],
  ['NARR','The Thermal Core lit a hospital, then a town, then a city. Nobody ever told the Kraken.','city_lights'],
  {title:'OPERATION DEEP MERIDIAN',sub:'COMPLETE / THE TYPHOON IS YOURS',scene:'title'},
 ],
};

const MISSIONS=[
 // ---- Chapter I: Shakedown ----
 {id:'m1',foes:[[5200,'hunter'],[9000,'hunter']],ships:7800,ch:0,name:'Old Iron',diff:'admiral',L:11000,cps:[3800,7600],
  brief:'Take the Remora out past the harbour shoals. Learn how she answers the helm, recover the recorders and meet the tender at the rendezvous.',
  biomes:[['open',2800],['shoal',2600],['open',3400],['basin',8000]],mines:.75,gapK:1.12,air:.45,
  relic:{t:'float',x:6400,d:.82},pre:'prologue',post:'m1_post',reward:[6,1,0],
  msgs:[[300,'JUNO','Hold Space, W or the rise button to climb. Let go to sink. She is heavy, so think ahead.'],[1900,'JUNO','Air pockets glow blue. Steer through them to refill the tanks.'],[3900,'JUNO','That light curtain was a checkpoint. If we get into trouble, we start again from the last one we passed.'],[5100,'RIGGS','Mines ahead, paired top and bottom. Thread the gap and mind the cables.'],[6000,'JUNO','Something glinting near the seabed. Vance’s crew sealed their notes in capsules. Grab it if you can.'],[9400,'HALE','Remora, the tender is on station. Bring her in.']]},
 {id:'m2',foes:[[2600,'hunter'],[7000,'destroyer'],[11500,'hunter']],ch:0,name:'First Salvage',diff:'admiral',L:14000,cps:[4600,9400],obj:{salv:3},
  brief:'Debris from the Meridian’s escort lies across the shelf. When a wreck is in range, launch the salvage drone with Q (or the DRONE button) and recover three loads.',
  biomes:[['open',3000],['basin',4000],['shoal',2400],['open',9000]],mines:.8,gapK:1.08,air:.45,
  wrecks:[[1800,'ship'],[3600,'plane'],[6200,'ship'],[8200,'sub'],[11000,'ship'],[12600,'plane']],
  relic:{t:'wreck',i:3},post:'m2_post',reward:[8,1,0],
  msgs:[[700,'JUNO','Wreck on sonar. When the SALVAGE marker lights up, press Q. Pilot with WASD. Space rises; C descends. Q scans; hold F to grab. Bring the payload back to the green dock.'],[4700,'JUNO','Watch vent warnings and your battery. Optional scrap is worth a detour if you have time.'],[8000,'RIGGS','Sunken submarine below. Those carry alloy.']]},
 {id:'m3',foes:[[6500,'destroyer'],[12500,'hunter'],[14800,'destroyer']],ch:0,name:'Picket Line',diff:'admiral',L:17000,cps:[5200,10800],ships:2600,
  brief:'Contract warships patrol the approaches to the strait. Fire missiles with F or right-click, shoot down their seekers, and reach the end of the picket line.',
  biomes:[['open',4000],['shoal',2500],['open',3500],['basin',4000],['open',9000]],mines:.9,air:.4,night:9000,
  relic:{t:'float',x:8200,d:.86},post:'m3_post',reward:[8,2,0],
  msgs:[[2700,'RIGGS','Surface contact! Warship, bearing zero-four-five.'],[3100,'HALE','Weapons free, Captain. F or right-click.'],[7000,'JUNO','Your boat has a special ability on E. The Remora’s crew can reload double-time.'],[9200,'RIGGS','Light is going. Sonar will paint the mines for us now.']]},
 {id:'m4',foes:[[1800,'hunter'],[4400,'destroyer']],ch:0,name:'The Iron Warden',diff:'admiral',cps:[3200,6400],boss:{k:'warden',at:6400},
  brief:'The cruiser Grozny holds the strait. Close in under her, survive her depth charges and seekers, and sink her.',
  biomes:[['open',4200],['basin',40000]],mines:.7,air:.4,relic:{t:'float',x:2600,d:.1},
  pre:'m4_pre',post:'m4_post',reward:[12,3,1],unlock:'type212',
  msgs:[[600,'RIGGS','Big screws on the horizon. Very big.'],[3300,'JUNO','Arena ahead. Red rings show where her charges will burst.']],
  cuts:{2:[['VOLKOV','American captain. You are in Soviet water now. Grozny, sink it.'],['YOU','Battle stations.']]}},
 // ---- Chapter II: The Drowned Coast ----
 {id:'m5',foes:[[2600,'hunter'],[8400,'octopod'],[16200,'octopod']],ch:1,name:'Breadcrumbs',diff:'admiral',L:19500,cps:[4200,11400],obj:{clues:3},
  brief:'Find three of the Meridian’s emergency beacons on the islands. Surface at each RECON POINT and fly the spotter drone (Q) over the cliffs.',
  biomes:[['open',2600],['shoal',2000],['open',2600],['cave',4000],['open',3100],['cave',4500],['open',8000]],mines:.85,air:.45,
  recon:[{x0:5100,x1:6900,clues:[[8100,95],[9700,160]]},{x0:12600,x1:14000,clues:[[15700,125]],relic:[17300,250]}],
  relic:{t:'sky'},pre:'m5_pre',post:'m5_post',reward:[8,2,1],
  msgs:[[4700,'JUNO','Recon point ahead. Ride the surface, then launch the spotter with Q.'],[11800,'JUNO','Second recon point. One more beacon.']]},
 {id:'m6',foes:[[3000,'hunter'],[7600,'destroyer'],[12500,'hunter'],[17800,'destroyer']],ch:1,name:'Graveyard of Ships',diff:'admiral',L:20500,cps:[5000,10500,15400],obj:{salv:5},
  brief:'The Meridian’s trail runs through a field of unreported wrecks. Recover five salvage loads before night falls on the shoals.',
  biomes:[['open',2400],['shoal',3000],['basin',5000],['shoal',2500],['basin',5000],['open',8000]],mines:1,air:.38,night:7000,
  wrecks:[[1600,'ship'],[3400,'sub'],[5900,'ship'],[7400,'plane'],[9200,'ship'],[11700,'sub'],[13800,'ship'],[16800,'sub'],[18500,'ship']],
  relic:{t:'wreck',i:6},post:'m6_post',reward:[10,3,1],
  msgs:[[600,'RIGGS','Multiple wrecks on the bottom. Dozens.'],[7200,'JUNO','Sun is down. Use the sonar echoes.'],[15600,'RIGGS','I keep hearing something in the rock. Like breathing.']]},
 {id:'m7',foes:[[4200,'octopod'],[9000,'ambush'],[14000,'octopod'],[20000,'ambush']],ch:1,name:'The Cathedral',diff:'admiral',L:24000,cps:[6000,12000,18000],
  brief:'The trail runs through the sea caves. No ships can follow you in, but the mines drift, the dark is total and the air is thin.',
  biomes:[['open',2200],['cave',8000],['open',1800],['cave',9000],['basin',1800],['cave',9000]],mines:1,air:.4,drift:.2,night:0,
  relic:{t:'float',x:14600,d:.5},post:'m7_post',reward:[10,3,1],
  msgs:[[2600,'RIGGS','Entering the caves. Ceiling above, rock below.'],[9000,'RIGGS','Movement in the rock. Big movement.'],[19500,'JUNO','Captain, the temperature outside just jumped four degrees.']],
  cuts:{2:[['RIGGS','Captain... something just touched the hull.'],['YOU','Steady. Keep her moving.']]}},
 {id:'m8',foes:[[2600,'hunter'],[5600,'octopod']],ch:1,name:'Old Mother',diff:'admiral',cps:[4400,8800],boss:{k:'mother',at:8800},
  brief:'A giant octopus guards the deep caves. Thread between her arms, keep clear of the ink, and put missiles into her eye.',
  biomes:[['open',2400],['cave',50000]],mines:.9,air:.42,night:0,relic:{t:'float',x:6200,d:.2},
  pre:'m8_pre',post:'m8_post',reward:[14,4,2],unlock:'virginia',
  cuts:{2:[['RIGGS','She is here. She is right in front of us.'],['JUNO','Eye, Captain. Aim for the eye.']]}},
 // ---- Chapter III: The Race ----
 {id:'m9',foes:[[5000,'hunter'],[11000,'destroyer'],[15500,'hunter']],ch:2,name:'Red Contact',diff:'admiral',L:21000,cps:[6800,13600],race:{rv:1.16,rival:'akula'},
  brief:'Volkov’s Akula is racing you to the next beacon. Ride the bright slipstream currents, grab orange thermal vents for a burst, and get there first.',
  biomes:[['open',3000],['basin',5000],['open',4000],['shoal',2500],['basin',12000]],mines:.75,gapK:1.06,air:.42,
  relic:{t:'float',x:11200,d:.9},pre:'m9_pre',post:'m9_post',reward:[10,3,1],
  msgs:[[800,'JUNO','Bright current band ahead. Inside it we run thirty percent faster.'],[4000,'RIGGS','Thermal vent! Orange glow, grab it.'],[10000,'HALE','You are neck and neck. Do not let him have this.']]},
 {id:'m10',foes:[[3000,'hunter'],[13000,'destroyer'],[18500,'hunter']],ch:2,name:'Sabotage',diff:'admiral',L:22500,cps:[5600,11200,16800],obj:{sub:4},start:{hull:-1,tubes:false},ships:9500,
  brief:'A limpet charge flooded the torpedo room and cost you a hull section. Salvage four loads from sunken submarines to repair the boat, then reach the tender.',
  biomes:[['shoal',2500],['basin',6000],['open',4000],['basin',6000],['open',9000]],mines:.9,air:.4,night:12000,
  wrecks:[[1900,'sub'],[3800,'ship'],[5100,'sub'],[7500,'sub'],[9800,'plane'],[12100,'sub'],[14500,'sub'],[17600,'ship'],[19900,'sub']],
  relic:{t:'wreck',i:7},pre:'m10_pre',post:'m10_post',reward:[12,4,2],
  msgs:[[600,'JUNO','Tubes are dead until we pull parts off a sunken boat. Only submarine wrecks have what we need.'],[9600,'RIGGS','Warships moving in. If the tubes are still down, dodge their seekers.']]},
 {id:'m11',foes:[[4500,'octopod'],[11000,'hunter'],[18500,'octopod'],[25000,'destroyer']],ch:2,name:'Slipstream',diff:'admiral',L:30000,cps:[7500,15000,22500],race:{rv:1.22,rival:'akula'},
  brief:'The north current runs tonight and Volkov rides it. A long race through open water and caves, in the dark. Win it.',
  biomes:[['open',3000],['cave',5000],['open',3000],['basin',6000],['cave',5000],['open',14000]],mines:.85,air:.4,drift:.3,night:0,
  relic:{t:'float',x:18200,d:.15},post:'m11_post',reward:[12,4,2],
  msgs:[[2500,'RIGGS','Vepr is ahead and riding the current. We need every vent.'],[16000,'JUNO','Halfway. Engines are hot but happy.']]},
 {id:'m12',foes:[[2000,'hunter'],[5200,'destroyer']],ch:2,name:'Vepr',diff:'admiral',cps:[4000,8200],boss:{k:'vepr',at:8200},ships:1800,
  brief:'Volkov has stopped racing. Duel the Vepr: dodge her stern torpedoes, shoot down the mines she drops and break her hull.',
  biomes:[['open',3000],['basin',50000]],mines:.9,air:.42,relic:{t:'float',x:5800,d:.86},
  pre:'m12_pre',post:'m12_post',reward:[16,5,3],unlock:'seawolf',
  cuts:{2:[['VOLKOV','Here, Captain. Just you and me.'],['YOU','Tubes one through four. Make ready.']]}},
 // ---- Chapter IV: Northern Lights ----
 {id:'m13',foes:[[3000,'destroyer'],[9500,'hunter'],[14000,'destroyer'],[19000,'hunter']],ch:3,name:'Prize Crew',diff:'admiral',L:22500,cps:[5600,11200,16800],obj:{salv:5},ships:4200,
  brief:'An abandoned Soviet Akula lies in the northern basin. Strip five loads of parts from the wrecks around her, and find her codebook.',
  biomes:[['open',3000],['shoal',2500],['basin',7000],['open',3000],['basin',12000]],mines:1,air:.38,night:10000,
  wrecks:[[2000,'ship'],[4200,'sub'],[6700,'plane'],[8500,'akula'],[10700,'sub'],[13100,'ship'],[15300,'sub'],[17500,'plane'],[19500,'sub']],
  relic:{t:'wreck',i:3},pre:'m13_pre',post:'m13_post',reward:[14,5,2],unlock:'akula',
  msgs:[[8000,'RIGGS','There she is. Akula hull, lying on her side.']]},
 {id:'m14',foes:[[2500,'destroyer'],[10000,'octopod'],[17000,'octopod'],[21000,'hunter']],ch:3,name:'Eyes in the Sky',diff:'admiral',L:24500,cps:[4800,12900,19200],obj:{clues:4},ships:1500,
  brief:'Old radar islands overlook the route to the Gate. Fly the spotter drone through their flak and find four survey markers.',
  biomes:[['open',2600],['shoal',2400],['open',2600],['cave',5200],['open',2900],['cave',5000],['open',9000]],mines:1,air:.4,
  recon:[{x0:5500,x1:7300,clues:[[8800,100],[10300,175]],flak:1},{x0:14200,x1:15500,clues:[[16900,140],[18400,90]],relic:[17700,280],flak:1}],
  relic:{t:'sky'},pre:'m14_pre',post:'m14_post',reward:[12,4,3]},
 {id:'m15',foes:[[4000,'hunter'],[15000,'octopod'],[18500,'hunter'],[24000,'destroyer']],ch:3,name:'Minefield Alley',diff:'admiral',L:28000,cps:[7000,14000,21000],ships:3200,
  brief:'Every navy that ever sailed here left mines behind. Thread the densest field on the charts, with warships hunting from above.',
  biomes:[['open',3000],['shoal',3000],['basin',5000],['cave',4000],['basin',4000],['shoal',3000],['open',12000]],mines:1.35,gapK:.96,air:.42,drift:.05,night:14000,
  relic:{t:'float',x:12600,d:.5},post:'m15_post',reward:[14,5,2],
  msgs:[[1500,'RIGGS','Mine count is... I stopped counting.'],[14500,'JUNO','Halfway. Night is coming. Watch the echoes.']]},
 {id:'m16',foes:[[6000,'ambush'],[11500,'hunter'],[17000,'ambush']],ch:3,name:'The Deep Gate',diff:'admiral',L:21000,cps:[3000,9000,15000],chase:{from:3200,to:21000},
  brief:'Something vast lives beyond the Gate. You cannot fight it. Outrun its arms through the trench and reach the far side.',
  biomes:[['open',2200],['trench',40000]],mines:.55,air:.42,night:0,relic:{t:'float',x:12200,d:.9},
  pre:'m16_pre',post:'m16_post',reward:[16,5,3],unlock:'astute',
  cuts:{1:[['RIGGS','Contact behind us. It is... everywhere.'],['HALE','Run, Captain!']]}},
 // ---- Chapter V: The Kraken's Trench ----
 {id:'m17',foes:[[4000,'hunter'],[10500,'ambush'],[16000,'hunter'],[22000,'ambush']],ch:4,name:'Into the Trench',diff:'admiral',L:26000,cps:[6500,13000,19500],obj:{salv:5},
  brief:'The Meridian broke apart on the trench walls. Recover five loads from her debris and follow the trail deeper.',
  biomes:[['open',2000],['trench',9000],['basin',4000],['trench',20000]],mines:1.05,air:.4,night:0,
  wrecks:[[2400,'ship'],[4800,'meridian'],[7200,'sub'],[9700,'meridian'],[12100,'plane'],[14700,'meridian'],[17300,'sub'],[19900,'meridian'],[22900,'ship']],
  relic:{t:'wreck',i:5},pre:'m17_pre',post:'m17_post',reward:[14,5,3],
  msgs:[[4500,'RIGGS','Meridian hull section below. Her name is still on it.']]},
 {id:'m18',foes:[[5000,'destroyer'],[11000,'hunter'],[16000,'hunter'],[24000,'destroyer']],ch:4,name:'Wolfpack',diff:'admiral',L:28000,cps:[7000,14000,21000],race:{rv:1.22,rival:'akula'},ships:2500,shipHp:2,
  brief:'Volkov brought friends. Race the Vepr to the lair entrance while a wolfpack of warships hunts you from the surface.',
  biomes:[['open',3000],['basin',6000],['open',4000],['shoal',3000],['open',14000]],mines:.8,gapK:1.04,air:.42,night:16000,
  relic:{t:'float',x:20200,d:.12},pre:'m18_pre',post:'m18_post',reward:[16,5,3]},
 {id:'m19',foes:[[3500,'hunter'],[10000,'octopod'],[19000,'octopod'],[23000,'hunter']],ch:4,name:'The Lair',diff:'admiral',L:26000,cps:[5000,13600,20000],obj:{clues:3},
  brief:'The Kraken’s lair lies under the northern islands. Fly the spotter over them, find three markers and pin down the Core’s signal.',
  biomes:[['shoal',2600],['open',5400],['cave',5000],['open',3200],['cave',6000],['open',8000]],mines:1,air:.4,night:20000,
  wrecks:[[3000,'ship'],[12000,'sub'],[21500,'meridian']],
  recon:[{x0:5600,x1:7700,clues:[[9100,120],[10700,85]]},{x0:14400,x1:16000,clues:[[17100,160]],relic:[18500,240],flak:1}],
  relic:{t:'sky'},post:'m19_post',reward:[14,5,3]},
 {id:'m20',foes:[[3000,'ambush'],[6500,'hunter']],ch:4,name:'The Kraken',diff:'admiral',cps:[4500,9000],boss:{k:'kraken',at:9000},
  brief:'The Kraken coils over the Core. Weave through its arms, stay out of the red sweep bands, and hit its eye whenever the lid opens.',
  biomes:[['open',2000],['trench',60000]],mines:.8,air:.42,night:0,relic:{t:'float',x:6600,d:.9},
  pre:'m20_pre',post:'m20_post',reward:[22,7,4],unlock:'ohio',
  cuts:{2:[['RIGGS','It is opening its eye.'],['JUNO','Now we see who blinks first.']]}},
 // ---- Chapter VI: Meridian ----
 {id:'m21',foes:[[4000,'hunter'],[10000,'ambush'],[16500,'destroyer'],[21500,'hunter']],ch:5,name:'Heat Signature',diff:'admiral',L:26000,cps:[6500,13000,19500],obj:{salv:4,need:'core'},ships:15000,shipHp:2,
  brief:'Raise the Thermal Core from the Meridian’s hull with the salvage drone, plus three loads of spares. Once the Core is aboard, everything will come for it.',
  biomes:[['open',2600],['trench',8000],['basin',6000],['open',14000]],mines:1.05,air:.4,night:0,
  wrecks:[[2200,'ship'],[5200,'sub'],[8000,'meridian'],[11000,'plane'],[14300,'core'],[17000,'sub'],[20200,'ship'],[23000,'meridian']],
  relic:{t:'wreck',i:6},pre:'m21_pre',post:'m21_post',reward:[16,6,4],
  msgs:[[13600,'JUNO','The Core is just ahead. Gently with the drone. Gently.'],[16000,'RIGGS','Warships converging. They can hear the Core.']]},
 {id:'m22',foes:[[5000,'hunter'],[11000,'destroyer'],[17500,'octopod'],[25000,'destroyer']],ch:5,name:'Last Race',diff:'admiral',L:30000,cps:[7500,15000,22500],race:{rv:1.26,rival:'typhoon'},ships:12000,
  brief:'Volkov’s Typhoon is racing you to the extraction point. The biggest submarine ever built against the Core. Win.',
  biomes:[['open',3000],['basin',6000],['shoal',3000],['open',4000],['cave',4000],['open',14000]],mines:.8,gapK:1.05,air:.42,night:18000,
  relic:{t:'float',x:16200,d:.3},post:'m22_post',reward:[16,6,4]},
 {id:'m23',foes:[[2000,'destroyer'],[5500,'hunter']],ch:5,name:'Leviathan',diff:'admiral',cps:[4000,8000],boss:{k:'leviathan',at:8000},
  brief:'The Typhoon will not let you leave. Wait for her shield to drop when she fires, hit her hard, and stay out of her ramming line.',
  biomes:[['open',3000],['basin',60000]],mines:.9,air:.42,relic:{t:'float',x:6000,d:.82},
  pre:'m23_pre',post:'m23_post',reward:[24,8,5],
  cuts:{2:[['VOLKOV','Last chance, Captain. Surface and hand it over.'],['YOU','Not today, Anatoly.']]}},
 {id:'m24',foes:[[3000,'hunter'],[12000,'ambush'],[20500,'destroyer'],[24500,'hunter'],[28000,'destroyer']],ch:5,name:'Homeward',diff:'admiral',L:32000,cps:[6000,12000,18000,25000],chase:{from:6200,to:18000},ships:18500,shipHp:2,
  brief:'The Kraken wants the Core back and the wolfpack wants revenge. Run the trench, then the gauntlet, and bring the Core home.',
  biomes:[['open',2200],['trench',16000],['basin',4000],['open',16000]],mines:.85,air:.42,
  relic:{t:'float',x:22400,d:.2},pre:'m24_pre',post:'m24_post',reward:[30,10,6],unlock:'typhoon',
  msgs:[[18200,'RIGGS','We are out of the trench! It is falling back!'],[18800,'HALE','Wolfpack on the surface between you and home. Last push, Remora.'],[30000,'HALE','I can see your wake from the pier.']]},
];
/* Keep authored distances: operations now add hands-on play rather than stretching
   transit by 45%. Checkpoint indices remain compatible with existing saves.
   Beacon offsets stay battery-safe if a future course scale is used. */
const COURSE_SCALE=1;
function scaleMission(m,k){
 const X=x=>Math.round(x*k);
 if(m.L)m.L=X(m.L);m.cps=m.cps.map(X);m.biomes=m.biomes.map(([b,len])=>[b,X(len)]);
 if(m.night>0)m.night=X(m.night);if(m.ships)m.ships=X(m.ships);
 if(m.wrecks)m.wrecks=m.wrecks.map(([x,w])=>[X(x),w]);if(m.foes)m.foes=m.foes.map(([x,f])=>[X(x),f]);if(m.msgs)m.msgs=m.msgs.map(([x,w,txt])=>[X(x),w,txt]);
 if(m.recon)m.recon=m.recon.map(z=>{const x1=X(z.x1),off=x=>x1+(x-z.x1);return {...z,x0:X(z.x0),x1,clues:z.clues.map(([x,h])=>[off(x),h]),relic:z.relic&&[off(z.relic[0]),z.relic[1]]}});
 if(m.relic&&m.relic.t==='float')m.relic={...m.relic,x:X(m.relic.x)};
 if(m.boss)m.boss={...m.boss,at:X(m.boss.at)};if(m.chase)m.chase={from:X(m.chase.from),to:X(m.chase.to)};
}
// Replace transit-only patrols with authored recovery operations.
const OPERATIONS={
 m1:{name:'Harbour blackout',wrecks:[[2300,'relay'],[6300,'relay']],brief:'Recover two navigation recorders with the ROV, then break through the hunter patrol. Fly the 3D ROV with WASD, rise with Space, descend with C, scan with Q, and hold F to secure the recorder.'},
 m3:{name:'Picket telemetry',wrecks:[[3800,'relay'],[9000,'relay']],brief:'Recover the picket fleet’s acoustic codes between destroyer patrols. Each recorder requires a drone sortie; bring it back to the dock.'},
 m7:{name:'Cathedral survey',wrecks:[[4300,'relay'],[10300,'relay'],[16300,'relay']],brief:'Recover three acoustic recorders inside the Cathedral. Dodge vent plumes during each drone dive, then survive the creatures drawn to the signal.'},
 m15:{name:'Mine network',wrecks:[[4500,'mineRig'],[11000,'mineRig'],[18500,'mineRig']],brief:'Disable three mine controllers with the ROV. Scan each controller, hold the tool steady, and return its circuit board to the boat.'}
};
for(const m of MISSIONS){
 const op=OPERATIONS[m.id];if(op){m.wrecks=op.wrecks;m.obj={salv:op.wrecks.length};m.brief=op.brief;m.operation=op.name}
 // Mines are local hazards around encounters, not an endless corridor.
 if(m.race)m.foes.unshift([1400,'hunter']);
 m.mineZones=(m.foes||[]).map(([x])=>[x-650,x+600]);
 if(m.id==='m15')m.mineZones=[[1800,3200],[7600,9000],[14500,16000],[22500,24000]];
 m.mines=Math.min(m.mines||1,.6);m.gapK=Math.max(m.gapK||1,1.12);

 if(m.id==='m1'||m.id==='m2')m.diff='captain';
 // Explicit encounters supply combat; avoid additional random warship stacks.
 delete m.ships;
}
MISSIONS.forEach(m=>scaleMission(m,COURSE_SCALE));
const MISSION_BY_ID=Object.fromEntries(MISSIONS.map((m,i)=>[m.id,Object.assign(m,{i})]));
/* Wreck loot by kind: [scrap min, scrap spread, alloy chance, circuit chance]. */
const LOOT={ship:[3,3,.3,.05],sub:[2,2,1,.35],plane:[1,2,0,.6],akula:[4,2,1,.8],meridian:[2,3,.6,.5],core:[2,0,1,1]};
