import Foundation

/// Offline LAN settings editor. Changes are staged and approved on the TV; completion waits for imports.
enum RemoteSetupWebPage {
    static let html = #"""
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="color-scheme" content="dark light">
<meta name="referrer" content="no-referrer">
<title>Nuvio · Remote Setup</title>
<style>
:root{--bg:#101113;--surface:#1b1c20;--text:#f5f5f7;--secondary:#a9a9b2;--line:#ffffff16;--accent:#89b8ff;--selected:#ffffff12;--danger:#ff8b8b;--success:#8edbb1;--glass:rgba(29,30,34,.94)}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font:16px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;-webkit-font-smoothing:antialiased}button,input{font:inherit}button{cursor:pointer;color:inherit;border:0;background:var(--selected);border-radius:999px;padding:10px 18px;min-height:44px;font-weight:550}button:hover{background:#ffffff22}button:disabled{opacity:.4;cursor:default}button:focus-visible,input:focus-visible,summary:focus-visible{outline:3px solid var(--accent);outline-offset:4px}button.primary{background:var(--text);color:var(--bg)}button.primary:hover{opacity:.86}button.quiet{background:transparent;color:var(--secondary)}.danger{color:var(--danger)}[hidden]{display:none!important}
.shell{max-width:1180px;margin:auto;padding:0 40px 150px}.topbar{display:flex;align-items:center;justify-content:space-between;padding:30px 0;border-bottom:1px solid var(--line);gap:20px}.brand{font-size:24px;letter-spacing:-.8px;font-weight:700}.brand small{font-size:14px;font-weight:400;letter-spacing:0;color:var(--secondary);margin-left:16px}.connection{font-size:13px;color:var(--secondary);text-align:right}.connection::before{content:"";display:inline-block;width:7px;height:7px;margin-right:8px;border-radius:50%;background:var(--secondary)}.connection.connected::before{background:var(--success)}.layout{display:grid;grid-template-columns:220px minmax(0,1fr);gap:56px;padding-top:32px}nav{display:flex;flex-direction:column;gap:8px;align-self:start;position:sticky;top:24px}nav button{text-align:left;border-radius:12px;background:transparent;color:var(--secondary);padding:13px 16px}nav button[aria-current="page"]{background:var(--selected);color:var(--text)}.nav-icon{display:inline-block;width:27px;font-size:18px}main{min-width:0}fieldset{margin:0;padding:0;border:0;min-width:0}h2{font-size:21px;letter-spacing:-.4px;font-weight:600;margin:0 0 4px}.hint{font-size:14px;color:var(--secondary);margin:0 0 20px;max-width:62ch}.group{padding:0 0 28px;margin-bottom:26px;border-bottom:1px solid var(--line)}details.group{padding-bottom:20px}summary{cursor:pointer;list-style:none;display:flex;justify-content:space-between;align-items:center;min-height:44px;font-size:18px;font-weight:600;border-radius:6px}summary::-webkit-details-marker{display:none}summary::after{content:"⌄";color:var(--secondary);font-size:24px}details[open]>summary{margin-bottom:20px}details[open]>summary::after{content:"⌃"}.row{display:flex;align-items:center;gap:14px;min-height:80px;padding:16px 0;border-bottom:1px solid var(--line)}.row:last-child{border-bottom:0}.info{flex:1;min-width:0}.name{font-weight:550;overflow-wrap:anywhere}.sub{font-size:13px;color:var(--secondary);overflow-wrap:anywhere;margin-top:3px}.disabled .name{color:var(--secondary)}.tag{display:inline-block;font-size:11px;color:var(--accent);margin-left:8px;font-weight:500}.actions{display:flex;gap:3px}.icon{width:44px;padding:0;background:transparent;font-size:19px}.switch{width:46px;height:28px;flex:none;appearance:none;-webkit-appearance:none;background:#59595e;border-radius:18px;position:relative;cursor:pointer;margin:0}.switch::after{content:"";position:absolute;top:3px;left:3px;width:22px;height:22px;border-radius:50%;background:white;transition:transform .15s}.switch:checked{background:#34a86d}.switch:checked::after{transform:translateX(18px)}.switch:disabled{cursor:default}.addbar{display:flex;gap:12px;align-items:center;margin-top:20px}input[type=text],input[type=password]{color:var(--text);background:transparent;border:0;border-bottom:1px solid var(--secondary);border-radius:0;padding:12px 0;min-width:0;width:100%;min-height:48px;outline-offset:2px}input::placeholder{color:var(--secondary);opacity:.8}.addbar input{flex:1}.keyrow{margin-top:20px}.keyrow label{display:block;font-size:15px;font-weight:550}.keyrow .sub{margin:4px 0}.keyinput{display:flex;gap:8px;align-items:center}.empty{color:var(--secondary);padding:20px 0;font-size:14px}.error{color:var(--danger);font-size:14px;margin:10px 0 0}.sr-only{position:absolute;width:1px;height:1px;padding:0;overflow:hidden;clip:rect(0,0,0,0);white-space:nowrap}.footer{position:fixed;bottom:0;left:0;right:0;background:var(--glass);backdrop-filter:blur(24px);-webkit-backdrop-filter:blur(24px);border-top:1px solid var(--line);padding:18px max(24px,env(safe-area-inset-right)) max(18px,env(safe-area-inset-bottom));z-index:5}.footer-inner{max-width:1100px;margin:auto;display:flex;align-items:center;gap:18px}.status-wrap{flex:1;min-width:0}#status{font-size:14px;overflow-wrap:anywhere}.ok{color:var(--success)}.err{color:var(--danger)}#change-count{font-size:12px;color:var(--secondary);margin-top:3px}.footer button{flex:none}#refresh{font-size:14px}.note{font-size:13px;color:var(--secondary);margin:20px 0}#issues{padding-left:20px;margin:0 0 24px;font-size:14px;color:var(--danger)}
dialog{border:1px solid var(--line);border-radius:22px;padding:26px;max-width:420px;width:calc(100% - 40px);background:var(--surface);color:var(--text);box-shadow:0 24px 100px #0008}dialog::backdrop{background:#0008;backdrop-filter:blur(5px)}dialog p{color:var(--secondary);font-size:14px}dialog .actions{justify-content:flex-end;gap:8px;margin-top:24px}
@media(prefers-color-scheme:light){:root{--bg:#fafafa;--surface:#fff;--text:#202124;--secondary:#686870;--line:#00000016;--accent:#005fcc;--selected:#00000008;--danger:#bb2525;--success:#217148;--glass:rgba(250,250,250,.96)}button:hover{background:#00000012}}
@media(max-width:760px){.shell{padding:0 22px 195px}.topbar{padding:22px 0;align-items:start}.brand small{display:block;margin:3px 0 0;font-size:12px}.connection{max-width:48%;font-size:12px;padding-top:7px}.layout{display:block;padding-top:0}nav{z-index:3;top:0;flex-direction:row;gap:2px;margin:0 -22px 28px;padding:12px 16px;background:var(--glass);backdrop-filter:blur(20px);overflow:auto}nav button{white-space:nowrap;font-size:13px;padding:10px}.nav-icon{display:none}.row{flex-wrap:wrap;column-gap:12px}.row .info{flex-basis:calc(100% - 66px)}.row .actions{margin-left:auto}.row:has(.actions) .actions{margin-top:-8px}.footer-inner{flex-wrap:wrap;gap:10px}.status-wrap{flex-basis:100%}.footer .primary{margin-left:auto}.hint{font-size:13px}h2{font-size:20px}}
@media(prefers-reduced-motion:reduce){*{transition:none!important;scroll-behavior:auto!important}}
</style>
</head>
<body>
<div class="shell">
<header class="topbar"><div class="brand">Nuvio<small>Remote Setup</small></div><div id="connection" class="connection">Connecting to your TV</div></header>
<div class="layout">
<nav aria-label="Settings categories">
<button type="button" data-panel="sources" id="nav-sources" aria-current="page"><span class="nav-icon" aria-hidden="true">⊞</span>Content Sources</button>
<button type="button" data-panel="home" id="nav-home"><span class="nav-icon" aria-hidden="true">⌂</span>Home Screen</button>
<button type="button" data-panel="appearance" id="nav-appearance"><span class="nav-icon" aria-hidden="true">◐</span>Appearance</button>
</nav>
<main>
<ul id="issues" hidden aria-live="polite"></ul>
<fieldset id="editor" disabled aria-label="TV settings">
<div id="panel-sources" role="region" aria-labelledby="nav-sources">
<section class="group" aria-labelledby="addons-heading">
<h2 id="addons-heading">Add-ons</h2><p class="hint">Choose your providers and their order on Home.</p>
<div id="addons"></div>
<form class="addbar" id="addon-form"><label class="sr-only" for="addon-url">Add-on manifest URL</label><input type="text" inputmode="url" id="addon-url" placeholder="Paste an add-on URL" autocapitalize="off" autocorrect="off" spellcheck="false" aria-describedby="addon-error"><button id="addon-add" type="submit" disabled>Add</button></form>
<p id="addon-error" class="error" role="alert" hidden></p>
</section>
<details class="group"><summary>Metadata &amp; Ratings</summary>
<p class="hint">Saved keys stay on your TV. Enter a key only to replace it.</p>
<div class="keyrow"><label for="tmdb-key">TMDB</label><p class="sub">Artwork, cast and title details</p><div class="keyinput"><input type="password" id="tmdb-key" placeholder="Enter API key" autocomplete="off" autocapitalize="off" spellcheck="false"><button type="button" data-show="tmdb-key" aria-label="Show TMDB key" aria-pressed="false">Show</button></div></div>
<div class="keyrow"><label for="mdblist-key">MDBList</label><p class="sub">IMDb, Rotten Tomatoes and Metacritic ratings</p><div class="keyinput"><input type="password" id="mdblist-key" placeholder="Enter API key" autocomplete="off" autocapitalize="off" spellcheck="false"><button type="button" data-show="mdblist-key" aria-label="Show MDBList key" aria-pressed="false">Show</button></div></div>
</details>
</div>
<div id="panel-home" role="region" aria-labelledby="nav-home" hidden><h2>Catalog Rows</h2><p class="hint">Choose which rows appear on Home and put them in your preferred order.</p><div id="rows"></div></div>
<div id="panel-appearance" role="region" aria-labelledby="nav-appearance" hidden><h2>Stream Badge Packs</h2><p class="hint">Add quality and format badges to stream results. Manage active packs or remove them in Settings on your TV.</p><div id="badges"></div><form class="addbar" id="badge-form"><label class="sr-only" for="badge-url">Badge pack JSON URL</label><input type="text" inputmode="url" id="badge-url" placeholder="Paste a badge pack URL" autocapitalize="off" autocorrect="off" spellcheck="false" aria-describedby="badge-error"><button id="badge-add" type="submit" disabled>Add</button></form><p id="badge-error" class="error" role="alert" hidden></p></div>
</fieldset>
<p class="note">Changes apply after you approve them on your Apple TV.</p>
</main></div></div>
<footer class="footer"><div class="footer-inner"><div class="status-wrap"><div id="status" role="status" aria-live="polite">Loading settings…</div><div id="change-count">No changes sent</div></div><button type="button" class="quiet" id="refresh">Reload</button><button type="button" id="check" hidden>Check status</button><button type="button" class="primary" id="apply" disabled>Send to TV</button></div></footer>
<dialog id="discard-dialog" aria-labelledby="discard-title"><h2 id="discard-title">Discard unsent changes?</h2><p>Your TV settings will stay as they are.</p><div class="actions"><button type="button" id="keep-editing" autofocus>Keep editing</button><button type="button" id="discard-confirm" class="danger">Discard</button></div></dialog>
<script>
'use strict';
let addons=[], rows=[], badgePacks=[], stagedBadgeUrls=[], baseline=null, busy=false, connected=false, pendingId=null;
const el=id=>document.getElementById(id);
const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const TOKEN=new URLSearchParams(location.search).get('t')||'';
const AUTH={'X-Setup-Token':TOKEN};
const addonValues=list=>list.map(a=>({url:a.url,enabled:a.enabled}));
const rowValues=list=>list.map(r=>({key:r.key,enabled:r.enabled}));
const same=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
function setStatus(text,cls=''){el('status').textContent=text;el('status').className=cls;}
function payload(){
  if(!baseline)return {};
  const p={baseRevision:baseline.revision};
  if(!same(addonValues(addons),addonValues(baseline.addons)))p.addons=addonValues(addons);
  if(!same(rowValues(rows),rowValues(baseline.rows))){p.rowOrder=rows.map(r=>r.key);p.disabledRowKeys=rows.filter(r=>!r.enabled).map(r=>r.key);}
  for(const [id,key] of [['tmdb-key','tmdbKey'],['mdblist-key','mdblistKey']])if(el(id).value.trim())p[key]=el(id).value.trim();
  if(stagedBadgeUrls.length)p.badgeUrls=stagedBadgeUrls.slice();
  return p;
}
function dirty(){return Object.keys(payload()).some(k=>k!=='baseRevision');}
function updateControls(){
  el('editor').disabled=busy||!connected;
  el('apply').disabled=busy||!connected||!dirty();
  el('refresh').disabled=busy;
  el('refresh').textContent=dirty()?'Discard changes':'Reload';
  el('addon-add').disabled=!el('addon-url').value.trim();el('badge-add').disabled=!el('badge-url').value.trim();
  const p=payload(),changes=[];
  if(p.addons)changes.push('Add-ons');if(p.rowOrder)changes.push('Home rows');if(p.tmdbKey)changes.push('TMDB');if(p.mdblistKey)changes.push('MDBList');if(p.badgeUrls)changes.push('Badge packs');
  el('change-count').textContent=changes.length?(pendingId?'Sent: ':'Unsaved: ')+changes.join(' · '):(baseline?'Up to date':'Waiting for settings');
}
async function api(path,options={}){
  const controller=new AbortController(),timeout=setTimeout(()=>controller.abort(),12000);
  try{
    const res=await fetch(path,{...options,headers:{...AUTH,...options.headers},signal:controller.signal,cache:'no-store'});
    if(res.status===403)throw new Error('This setup session expired. Scan the code on your TV again.');
    let data;try{data=await res.json();}catch{throw new Error('The TV returned an unreadable response. Try again.');}
    if(!res.ok)throw new Error(data.error||'The TV could not accept this request.');
    return data;
  }catch(error){if(error.name==='AbortError'||error instanceof TypeError)throw new Error('Could not reach the TV. Keep Remote Setup open and check your connection.');throw error;}
  finally{clearTimeout(timeout);}
}
function acceptState(state,preserve=false){
  if(!Array.isArray(state.addons)||!Array.isArray(state.rows)||!Array.isArray(state.badgePacks)||!state.revision)throw new Error('Settings are still loading on the TV. Try Reload in a moment.');
  const previous=baseline;baseline=state;badgePacks=state.badgePacks;
  if(!preserve){addons=state.addons.map(a=>({...a}));rows=state.rows.map(r=>({...r}));stagedBadgeUrls=[];el('tmdb-key').value='';el('mdblist-key').value='';for(const kind of ['addon','badge']){el(kind+'-url').value='';el(kind+'-error').hidden=true;el(kind+'-url').removeAttribute('aria-invalid');}}
  else{
    addons=addons.map(a=>({...a,name:state.addons.find(s=>s.url===a.url)?.name||a.name}));
    for(const a of state.addons)if(!previous?.addons.some(b=>b.url===a.url)&&!addons.some(b=>b.url===a.url))addons.push({...a});
    rows=rows.filter(r=>state.rows.some(s=>s.key===r.key));
    for(const row of state.rows)if(!rows.some(r=>r.key===row.key))rows.push({...row});
    stagedBadgeUrls=stagedBadgeUrls.filter(url=>!badgePacks.includes(url));
  }
  for(const [id,saved] of [['tmdb-key',state.tmdbKeySet],['mdblist-key',state.mdblistKeySet]])el(id).placeholder=saved?'Saved on TV — enter to replace':'Enter API key';
  el('connection').textContent=state.deviceName||'Apple TV';el('connection').className='connection connected';connected=true;render();
}
async function load(){
  busy=true;updateControls();setStatus('Loading settings…');
  try{acceptState(await api('/api/state'));el('issues').hidden=true;setStatus('Connected. Make your changes here.');}
  catch(error){connected=false;el('connection').className='connection';el('connection').textContent='Connection unavailable';setStatus(error.message,'err');}
  finally{busy=false;updateControls();}
}
function shortURL(value){try{const u=new URL(value);return u.hostname+u.pathname;}catch{return value;}}
function action(label,kind,list,index,symbol,disabled=false){return `<button type="button" class="icon ${kind==='remove'?'danger':''}" data-action="${kind}" data-list="${list}" data-index="${index}" data-focus="${esc(list+':'+index+':'+kind)}" aria-label="${esc(label)}" ${disabled?'disabled':''}>${symbol}</button>`;}
function render(){
  const focused=document.activeElement?.dataset.focus;
  el('addons').innerHTML=addons.length?addons.map((a,i)=>`<div class="row ${a.enabled?'':'disabled'}"><input class="switch" type="checkbox" role="switch" aria-label="Enable ${esc(a.name||shortURL(a.url))}" data-action="toggle" data-list="addons" data-index="${i}" data-focus="addons:${i}:toggle" ${a.enabled?'checked':''}><div class="info"><div class="name">${esc(a.name||'New add-on')}${baseline?.addons.some(b=>b.url===a.url)?'':'<span class="tag">Pending</span>'}</div><div class="sub">${esc(shortURL(a.url))}</div></div><div class="actions">${action('Move '+(a.name||'add-on')+' up','up','addons',i,'↑',i===0)}${action('Move '+(a.name||'add-on')+' down','down','addons',i,'↓',i===addons.length-1)}${action('Remove '+(a.name||'add-on'),'remove','addons',i,'×')}</div></div>`).join(''):'<div class="empty">No add-ons. Add a provider to get started.</div>';
  el('rows').innerHTML=rows.length?rows.map((r,i)=>`<div class="row ${r.enabled?'':'disabled'}"><input class="switch" type="checkbox" role="switch" aria-label="Show ${esc(r.title)}" data-action="toggle" data-list="rows" data-index="${i}" data-focus="rows:${i}:toggle" ${r.enabled?'checked':''}><div class="info"><div class="name">${esc(r.title)}</div><div class="sub">${r.isCollection?'Collection':'Catalog'}</div></div><div class="actions">${action('Move '+r.title+' up','up','rows',i,'↑',i===0)}${action('Move '+r.title+' down','down','rows',i,'↓',i===rows.length-1)}</div></div>`).join(''):'<div class="empty">Rows appear after your add-ons load. Install an add-on, then reload this page.</div>';
  el('badges').innerHTML=[...badgePacks.map(url=>`<div class="row"><div class="info"><div class="name">${esc(shortURL(url))}</div><div class="sub">Installed on TV</div></div></div>`),...stagedBadgeUrls.map((url,i)=>`<div class="row"><div class="info"><div class="name">${esc(shortURL(url))}</div><div class="sub">Pending import</div></div>${action('Remove pending badge pack','remove','badges',i,'×')}</div>`)].join('')||'<div class="empty">No badge packs installed.</div>';
  updateControls();
  if(focused){const controls=Array.from(document.querySelectorAll('[data-focus]'));const target=controls.find(e=>e.dataset.focus===focused&&!e.disabled)||controls.find(e=>e.dataset.focus.startsWith(focused.split(':').slice(0,2).join(':')+':')&&!e.disabled);target?.focus({preventScroll:true});}
}
function normalizeURL(value,addon=false){
  let raw=value.trim();if(addon){raw=raw.replace(/^stremio:\/\//i,'https://');if(!/^[a-z][a-z0-9+.-]*:/i.test(raw))raw='https://'+raw;}
  if(/\s/.test(raw))throw new Error('Enter a URL without spaces.');
  let u;try{u=new URL(raw);}catch{throw new Error('Enter a valid '+(addon?'add-on':'badge pack')+' URL.');}
  if(!['https:','http:'].includes(u.protocol)||!u.hostname)throw new Error('Use an HTTP or HTTPS URL.');
  u.hash='';if(addon){let path=u.pathname.replace(/\/+$/,'');if(!path.endsWith('/manifest.json'))path+='/manifest.json';u.pathname=path;}
  return u.href;
}
function addURL(kind){
  if(busy||!connected)return;
  const input=el(kind+'-url'),error=el(kind+'-error');
  try{
    const url=normalizeURL(input.value,kind==='addon');
    if(kind==='addon'){
      if(addons.some(a=>a.url===url))throw new Error('That add-on is already in the list.');
      addons.push({url,name:'',enabled:true});
    }else{
      if([...badgePacks,...stagedBadgeUrls].some(u=>u.toLowerCase()===url.toLowerCase()))throw new Error('That badge pack is already in the list.');
      if(badgePacks.length+stagedBadgeUrls.length>=3)throw new Error('You can keep three packs. Remove a pack on the TV before adding another.');
      stagedBadgeUrls.push(url);
    }
    input.value='';error.hidden=true;input.removeAttribute('aria-invalid');render();setStatus('Change added. Send to your TV when ready.');input.focus();
  }catch(e){error.textContent=e.message;error.hidden=false;input.setAttribute('aria-invalid','true');input.focus();}
}
async function apply(){
  if(busy||!connected||!dirty())return;
  const p=payload();busy=true;updateControls();el('issues').hidden=true;setStatus('Sending changes…');
  try{const result=await api('/api/apply',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(p)});if(!result.id)throw new Error('The TV did not acknowledge this request. Check Remote Setup on the TV.');pendingId=result.id;await poll();}
  catch(error){busy=false;setStatus(error.message,'err');updateControls();}
}
async function poll(){
  el('check').hidden=true;busy=true;updateControls();
  for(let attempt=0;attempt<180;attempt++){
    try{
      const result=await api('/api/status/'+encodeURIComponent(pendingId));
      if(result.status==='confirmed'||result.status==='failed'){
        const failed=result.status==='failed';
        const state=await api('/api/state');
        // Refresh only once application has finished. Keep failed edits available for retry.
        if(!failed||result.started){el('tmdb-key').value='';el('mdblist-key').value='';}
        acceptState(state,failed);
        const errors=result.errors||[];el('issues').innerHTML=errors.map(e=>'<li>'+esc(e)+'</li>').join('');el('issues').hidden=!errors.length;
        setStatus(failed?'Some changes could not be applied. Review the details above.':'Changes saved on your TV.',failed?'err':'ok');
        pendingId=null;busy=false;updateControls();return;
      }
      if(result.status==='rejected'||result.status==='not_found'){
        setStatus(result.status==='rejected'?'Declined on the TV. Your changes are still here.':'This request is no longer available. Reload to check the TV settings.','err');pendingId=null;busy=false;updateControls();return;
      }
      setStatus(result.status==='applying'?'Approved. Applying changes on your TV…':'Approve the changes on your Apple TV.');
    }catch(error){setStatus(error.message+' Checking again…','err');}
    await new Promise(resolve=>setTimeout(resolve,1000));
  }
  setStatus('The TV has not finished responding. Check its screen, then check status again.','err');el('check').hidden=false;
}
document.querySelector('nav').addEventListener('click',event=>{
  const button=event.target.closest('[data-panel]');if(!button)return;
  document.querySelectorAll('[data-panel]').forEach(b=>{if(b===button)b.setAttribute('aria-current','page');else b.removeAttribute('aria-current');el('panel-'+b.dataset.panel).hidden=b!==button;});
  window.scrollTo({top:0,behavior:'instant'});
});
el('editor').addEventListener('click',event=>{
  if(busy)return;const show=event.target.closest('[data-show]');if(show){const field=el(show.dataset.show),visible=field.type==='password';field.type=visible?'text':'password';show.textContent=visible?'Hide':'Show';show.setAttribute('aria-pressed',String(visible));show.setAttribute('aria-label',(visible?'Hide ':'Show ')+(show.dataset.show==='tmdb-key'?'TMDB':'MDBList')+' key');return;}
  const button=event.target.closest('button[data-action]');if(!button)return;
  const list=button.dataset.list==='addons'?addons:button.dataset.list==='rows'?rows:stagedBadgeUrls,i=Number(button.dataset.index),kind=button.dataset.action;
  if(kind==='remove')list.splice(i,1);else{const j=i+(kind==='up'?-1:1);if(j<0||j>=list.length)return;[list[i],list[j]]=[list[j],list[i]];button.dataset.focus=button.dataset.list+':'+j+':'+kind;}
  render();setStatus('Changes are ready to send.');
});
el('editor').addEventListener('change',event=>{const input=event.target;if(input.dataset.action!=='toggle'||busy)return;const list=input.dataset.list==='addons'?addons:rows;list[Number(input.dataset.index)].enabled=input.checked;render();setStatus('Changes are ready to send.');});
el('editor').addEventListener('input',event=>{for(const kind of ['addon','badge'])if(event.target.id===kind+'-url'){el(kind+'-error').hidden=true;event.target.removeAttribute('aria-invalid');}updateControls();});
el('addon-form').addEventListener('submit',e=>{e.preventDefault();addURL('addon');});el('badge-form').addEventListener('submit',e=>{e.preventDefault();addURL('badge');});
el('apply').addEventListener('click',apply);el('check').addEventListener('click',poll);
el('refresh').addEventListener('click',()=>{if(dirty())el('discard-dialog').showModal();else load();});
el('keep-editing').addEventListener('click',()=>el('discard-dialog').close());
el('discard-confirm').addEventListener('click',()=>{el('discard-dialog').close();load();});
window.addEventListener('beforeunload',e=>{if(dirty()||pendingId){e.preventDefault();e.returnValue='';}});
load();
</script>
</body></html>
"""#
}
