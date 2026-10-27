'use strict';
/* ---- Menu, hangar ---- */
function updateMenu(){
 if(state==='menu')ensureFleetSelection();
 document.querySelectorAll('#diffRow button').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.diff===diffId)));
 $('vesselName').textContent=S.name.toUpperCase()+' CLASS';$('vesselOrigin').textContent=S.origin.toUpperCase()+' / HULL '+S.hull+' / E: '+S.ability.name;$('footVessel').textContent=S.name.toUpperCase()+' / '+S.mark;$('best').textContent=best.toLocaleString();
 const th=$('thumb');th.width=Math.round(112*dpr);th.height=Math.round(38*dpr);drawPreview(th,S,112,38);renderChip();renderRank();campTile();
}
function selectSub(id){if(!fleetOpen(id))return;subId=id;S=SUB_BY_ID[id];store.set('undertow.sub',id);profDirty(true);if(state==='menu')reset();updateMenu();document.querySelectorAll('.sub-card').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.sub===id)))}
function statRows(m){return [['SPEED',(m.speed-.88)/.26],['AGILITY',(m.agility-.68)/.56],['HULL',m.hull/6],['AIR',m.o2/125],['FIRE RATE',(6.6-m.reload)/4.2],['SONAR',(1.25-m.sonar)/.65]]}
function renderHangar(){
 const list=$('subList');list.textContent='';
 for(const m of SUBS){
  const b=document.createElement('button');b.className='sub-card';b.dataset.sub=m.id;b.setAttribute('aria-pressed',String(m.id===subId));b.disabled=!fleetOpen(m.id);b.classList.toggle('locked',b.disabled);
  const cv=document.createElement('canvas');cv.className='mini';cv.width=Math.round(240*dpr);cv.height=Math.round(64*dpr);
  const nm=document.createElement('b');nm.textContent=m.name.toUpperCase()+' CLASS';const ns=document.createElementNS('http://www.w3.org/2000/svg','svg'),nu=document.createElementNS('http://www.w3.org/2000/svg','use');ns.setAttribute('class','ic');nu.setAttribute('href','#i-check');ns.append(nu);nm.append(ns);
  const og=document.createElement('small');og.textContent='LEVEL '+FLEET_LEVELS[m.id]+' / '+(fleetOpen(m.id)?'UNLOCKED':'LOCKED')+' / '+m.origin.toUpperCase();const p=document.createElement('p');p.textContent=m.desc;
  const ab=document.createElement('div'),an=document.createElement('b');ab.className='ab';an.textContent='E / '+m.ability.name;ab.append(an,m.ability.desc+' Recharge '+m.ability.cd+' s.');
  b.append(cv,nm,og,p,ab);
  for(const [label,v] of statRows(m)){const row=document.createElement('div'),l=document.createElement('label'),bar=document.createElement('span'),fill=document.createElement('i');row.className='stat';l.textContent=label;fill.style.width=Math.round(clamp(v,.08,1)*100)+'%';bar.append(fill);row.append(l,bar);b.append(row)}
  b.onclick=()=>selectSub(m.id);list.append(b);drawPreview(cv,m,240,64);
 }
}
document.querySelectorAll('#diffRow button').forEach(b=>b.onclick=()=>{diffId=b.dataset.diff;store.set('undertow.diff',diffId);D=DIFFS[diffId];profDirty(true);updateMenu()});
