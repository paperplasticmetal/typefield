const workspaceData = {
  library: {number:'01 / Library',title:'Good taste.<br>Great company.',description:'Bring your font collection into focus. Browse, compare, and shortlist the faces that feel right for your next idea.',image:'library.png',alt:'Typefield Library showing a font collection, live type previews, and font details',features:'Collections & tags / Live previews / Font comparison',name:'Library'},
  spaces: {number:'02 / Spaces',title:'Room for<br>your next idea.',description:'Take type out of the dropdown and put it in context. Build typeboards, explore pairings, and see how your ideas hold together.',image:'spaces.png',alt:'Typefield Spaces showing an editorial typeboard, font roles, and a website layout',features:'Typeboards / Font pairings / Design & code handoffs',name:'Spaces'},
  editor: {number:'03 / Letterforms',title:'Make your<br>own mark.',description:'Start with a drawing. Bring in your artwork, shape editable outlines, fine-tune the spacing, and export a font that is yours.',image:'editor.png',alt:'Typefield Letterform Editor showing an editable letter n with Bézier nodes and metrics',features:'Artwork import / Editable Bézier curves / TrueType export',name:'Letterforms'}
};
const tabs = [...document.querySelectorAll('[data-workspace]')];
function selectWorkspace(key) {
  const d = workspaceData[key];
  tabs.forEach(tab => { const active = tab.dataset.workspace === key; tab.setAttribute('aria-selected',String(active)); tab.tabIndex = active ? 0 : -1; });
  document.querySelector('#workspace-number').textContent=d.number;
  document.querySelector('#workspace-title').innerHTML=d.title;
  document.querySelector('#workspace-description').textContent=d.description;
  const img=document.querySelector('#workspace-image'); img.src='assets/'+d.image; img.alt=d.alt;
  document.querySelector('#workspace-features').textContent=d.features;
  document.querySelector('.window-bar span').textContent='Typefield / '+d.name;
  document.querySelector('#workspace-view').setAttribute('aria-labelledby','tab-'+key);
}
tabs.forEach((tab,index)=>{
  tab.addEventListener('click',()=>selectWorkspace(tab.dataset.workspace));
  tab.addEventListener('keydown',e=>{let next;if(e.key==='ArrowRight')next=(index+1)%tabs.length;if(e.key==='ArrowLeft')next=(index+tabs.length-1)%tabs.length;if(e.key==='Home')next=0;if(e.key==='End')next=tabs.length-1;if(next!==undefined){e.preventDefault();tabs[next].focus();selectWorkspace(tabs[next].dataset.workspace);}});
});
document.querySelectorAll('[data-launch]').forEach(b=>b.addEventListener('click',()=>document.querySelector('#launch-dialog').showModal()));
document.querySelectorAll('[data-film]').forEach(b=>b.addEventListener('click',()=>{document.querySelector('#launch-dialog').close();const dialog=document.querySelector('#film-dialog');dialog.showModal();dialog.querySelector('video').play().catch(()=>{});}));
document.querySelectorAll('dialog').forEach(dialog=>{dialog.querySelector('.close-dialog').addEventListener('click',()=>dialog.close());dialog.addEventListener('click',e=>{if(e.target===dialog){const r=dialog.getBoundingClientRect();if(e.clientX<r.left||e.clientX>r.right||e.clientY<r.top||e.clientY>r.bottom)dialog.close();}});dialog.addEventListener('close',()=>dialog.querySelector('video')?.pause());});
const sample=document.querySelector('#type-sample');
const tracking=document.querySelector('#tracking');
const fonts={serif:'Georgia, serif',sans:'"Helvetica Neue", Helvetica, Arial, sans-serif',mono:'"Courier New", monospace'};
document.querySelectorAll('[name="face"]').forEach(radio=>radio.addEventListener('change',()=>{sample.style.fontFamily=fonts[radio.value];}));
tracking.addEventListener('input',()=>{sample.style.letterSpacing=(Number(tracking.value)/100)+'em';document.querySelector('#tracking-value').textContent=tracking.value.replace('-','−');});
document.querySelector('#reset-type').addEventListener('click',()=>{sample.value='Stay curious.';sample.style.fontFamily=fonts.serif;sample.style.letterSpacing='-.01em';document.querySelector('[name="face"][value="serif"]').checked=true;tracking.value='-1';document.querySelector('#tracking-value').textContent='−1';});

// Keep long specimens visible inside the type study at every viewport width.
function fitTypeSample() {
  sample.style.fontSize = '';
  const baseSize = parseFloat(getComputedStyle(sample).fontSize);
  let size = baseSize;
  while (sample.scrollHeight > sample.clientHeight + 1 && size > 24) {
    size -= 2;
    sample.style.fontSize = size + 'px';
  }
}
sample.addEventListener('input', fitTypeSample);
tracking.addEventListener('input', fitTypeSample);
document.querySelectorAll('[name="face"]').forEach(radio => radio.addEventListener('change', fitTypeSample));
document.querySelector('#reset-type').addEventListener('click', fitTypeSample);
window.addEventListener('resize', fitTypeSample);
fitTypeSample();
