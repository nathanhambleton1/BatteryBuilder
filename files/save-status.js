'use strict';
function saveStatus(){}
function renderSaveStatus(){
 if($('saveStatus'))return;
 const badge=document.createElement('span');badge.id='saveStatus';badge.textContent='OFFLINE VERSION';badge.setAttribute('role','status');badge.title='Single-player · No shared-drive connection';
 badge.style.cssText='font-size:11px;letter-spacing:.08em;color:#a6ead5;padding:8px;border:1px solid #a6ead555;border-radius:4px';
 document.querySelector('.tools').prepend(badge);
}
addEventListener('DOMContentLoaded',renderSaveStatus);
