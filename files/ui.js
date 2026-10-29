'use strict';
/* ---- Menu, hangar ---- */
function updateMenu(){
 if(state==='menu')ensureFleetSelection();
 document.querySelectorAll('#diffRow button').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.diff===diffId)));
 $('vesselName').textContent=S.name.toUpperCase()+' CLASS';$('vesselOrigin').textContent=S.origin.toUpperCase()+' / HULL '+S.hull+' / E: '+S.ability.name;$('footVessel').textContent=S.name.toUpperCase()+' / '+S.mark;$('best').textContent=best.toLocaleString();
 const th=$('thumb');th.width=Math.round(112*dpr);th.height=Math.round(38*dpr);drawPreview(th,S,112,38);renderChip();renderRank();campTile();
}
function selectSub(id){if(!fleetOpen(id))return;subId=id;S=SUB_BY_ID[id];store.set('undertow.sub',id);profDirty(true);if(state==='menu')reset();updateMenu();document.querySelectorAll('.sub-card').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.sub===id)))}
function statRows(m){return [['SPEED',(m.speed-.88)/.26],['AGILITY',(m.agility-.68)/.56],['HULL',m.hull/6],['AIR',m.o2/125],['FIRE RATE',(6.6-m.reload)/4.2],[m.id==='turtle'?'LANTERN':'SONAR',m.id==='turtle'?1:(1.25-m.sonar)/.65]]}
function vesselCard(base,boat,selected,onSelect){
 const ok=fleetOpen(base.id),card=el('button','sub-card'),cv=el('canvas','mini');card.type='button';card.dataset.sub=base.id;card.disabled=!ok;card.classList.toggle('locked',!ok);card.setAttribute('aria-pressed',String(ok&&selected));
 cv.width=Math.round(240*dpr);cv.height=Math.round(64*dpr);const name=el('b','vessel-title',base.name.toUpperCase()+' CLASS');name.append(icon('i-check'));
 const status=el('span','vessel-status',selected?'SELECTED':'AVAILABLE');
 const ability=el('div','ab');ability.append(el('small','ability-label','SPECIAL ABILITY · E'),el('b',null,base.ability.name),el('p',null,base.ability.desc),el('span','ability-recharge','RECHARGE · '+base.ability.cd+' SECONDS'));
 const stats=el('div','vessel-stats');for(const [label,v] of statRows(boat)){const row=el('div','stat'),bar=el('span'),fill=el('i');fill.style.width=Math.round(clamp(v,.08,1)*100)+'%';bar.append(fill);row.append(el('label',null,label),bar);stats.append(row)}
 card.append(cv,name,el('small','vessel-origin',base.origin+' / '+base.mark),status,el('p','vessel-description',base.desc),ability,stats);card.onclick=()=>{if(ok)onSelect()};drawPreview(cv,base,240,64);return card;
}
function renderHangar(){const list=$('subList');list.textContent='';for(const m of fleetOrdered())list.append(vesselCard(m,m,m.id===subId,()=>selectSub(m.id)))}
// Keep dismissal outside each panel's scrolling content.
function installPopupClose(view){const actions={help:'helpClose',hangar:'hangarClose',ach:'achClose',board:'boardClose',duel:'duelClose',camp:'campClose',statistics:'statsClose',paused:'resume',askBox:'askNo',campDone:'cdHome',sfGate:'sfOffline',secretAdmin:'adminClose'},id=actions[view.id],panelEl=view.querySelector('.panel');if(!id||!panelEl||panelEl.classList.contains('has-popup-close'))return;
 const scroll=el('div','popup-scroll');while(panelEl.firstChild)scroll.append(panelEl.firstChild);const close=el('button','popup-close','×');close.type='button';close.setAttribute('aria-label','Close '+(view.getAttribute('aria-label')||view.id));close.onclick=()=>$(id).click();panelEl.classList.add('has-popup-close');panelEl.append(scroll,close);
}
document.querySelectorAll('#diffRow button').forEach(b=>b.onclick=()=>{diffId=b.dataset.diff;store.set('undertow.diff',diffId);D=DIFFS[diffId];profDirty(true);updateMenu()});
