const workspaceData = {
  library: {number:'01 / Library',title:'Good taste.<br>Great company.',description:'Bring your font collection into focus. Browse, compare, and shortlist the faces that feel right for your next idea.',image:'library.png',alt:'Typefield Library showing a font collection, live type previews, and font details',features:'Collections & tags / Live previews / Font comparison',actions:['Preview your own words across a shortlist of fonts.','Compare details side by side before you choose.','Save favorites, tags, and collections for later.'],name:'Library'},
  spaces: {number:'02 / Spaces',title:'Room for<br>your next idea.',description:'Take type out of the dropdown and put it in context. Build typeboards, explore pairings, and see how your ideas hold together.',image:'spaces.png',alt:'Typefield Spaces showing an editorial typeboard, font roles, and a website layout',features:'Typeboards / Font pairings / Design & code handoffs',actions:['Put live text and shapes into website, poster, or editorial layouts.','Try font pairings and compare directions in context.','Export a PDF, editable design handoff, or developer tokens.'],name:'Spaces'},
  editor: {number:'03 / Letterforms',title:'Make your<br>own mark.',description:'Start with a drawing. Bring in your artwork, shape editable outlines, fine-tune the spacing, and export a font that is yours.',image:'editor.png',alt:'Typefield Letterform Editor showing an editable letter n with Bézier nodes and metrics',features:'Artwork import / Editable Bézier curves / TrueType export',actions:['Draw letters or import original artwork to start.','Move Bézier points and handles, then adjust spacing and kerning.','Proof your letters and export a static TrueType font.'],name:'Letterforms'}
};
const tabs = [...document.querySelectorAll('[data-workspace]')];
function selectWorkspace(key) {
  const d = workspaceData[key];
  animateWorkspace();
  tabs.forEach(tab => { const active = tab.dataset.workspace === key; tab.setAttribute('aria-selected',String(active)); tab.tabIndex = active ? 0 : -1; });
  document.querySelector('#workspace-number').textContent=d.number;
  document.querySelector('#workspace-title').innerHTML=d.title;
  document.querySelector('#workspace-description').textContent=d.description;
  const img=document.querySelector('#workspace-image'); img.src='assets/'+d.image; img.alt=d.alt;
  document.querySelector('#workspace-features').textContent=d.features;
  document.querySelector('#workspace-actions').replaceChildren(...d.actions.map(action => { const item=document.createElement('li'); item.textContent=action; return item; }));
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

// Spring-like, interaction-led motion. Every effect respects reduced motion.
const motionPreference = matchMedia('(prefers-reduced-motion: reduce)');
const motionAllowed = () => !motionPreference.matches;
const springEase = 'cubic-bezier(.2,.85,.25,1.2)';
function animateWorkspace() {
  if (!motionAllowed()) return;
  const panel = document.querySelector('#workspace-view');
  panel.getAnimations().forEach(a => a.cancel());
  panel.animate([{opacity:.2,transform:'translateY(16px) scale(.985)'},{opacity:1,transform:'none'}],{duration:480,easing:'cubic-bezier(.16,1,.3,1)'});
}
const specimens = [...document.querySelectorAll('.specimen-letter')];
function springSpecimen(button, direction = 1) {
  if (!motionAllowed()) return;
  button.getAnimations().forEach(a => a.cancel());
  button.animate([
    {transform:'translateY(0) rotate(0) scale(1)'},
    {transform:`translateY(-18px) rotate(${direction*9}deg) scale(1.07)`,offset:.36},
    {transform:`translateY(4px) rotate(${-direction*3}deg) scale(.98)`,offset:.7},
    {transform:'none'}
  ],{duration:650,easing:'cubic-bezier(.22,.8,.3,1)'});
}
specimens.forEach((button,i) => {
  button.addEventListener('pointerenter', () => springSpecimen(button,i%2?1:-1));
  button.addEventListener('click', () => {
    const span = button.querySelector('span');
    const useAlternative = button.dataset.alternate !== 'true';
    button.dataset.alternate = String(useAlternative);
    span.style.fontFamily = useAlternative ? (i%2 ? 'Georgia,serif' : '"Helvetica Neue",Arial,sans-serif') : '';
    springSpecimen(button,i%2?1:-1);
  });
});
if (motionAllowed()) {
  document.querySelector('.hero h1').animate([{opacity:0,transform:'translateY(22px)'},{opacity:1,transform:'none'}],{duration:800,easing:'cubic-bezier(.16,1,.3,1)'});
  specimens.forEach((button,i) => button.animate([{opacity:0,transform:'translateY(35px) rotate(-8deg)'},{opacity:1,transform:'none'}],{duration:700,delay:160+i*60,easing:springEase,fill:'backwards'}));
}
// Give every section a rhythm of its own instead of moving whole panels as one.
const revealGroups = [
  ['.intro h2','.intro p'],
  ['.workspace .section-head > div','.workspace .app-frame','.workspace-caption','.workspace-actions li'],
  ['.play-heading h2','.type-stage','.type-controls'],
  ['.detail-card h2','.collection-demo','.pairing-demo','.detail-card > p'],
  ['.handoffs-intro h2','.handoffs-intro p','.handoff-list article'],
  ['.principles article'],
  ['.faq h2','.faq details'],
  ['.closing h2','.closing .pill'],
  ['footer .wordmark','footer button']
];
const revealObserver = new IntersectionObserver(entries => {
  entries.forEach(entry => {
    if (!entry.isIntersecting) return;
    if (motionAllowed()) {
      const elements = revealGroups[Number(entry.target.dataset.motionGroup)].flatMap(selector => [...entry.target.querySelectorAll(selector)]);
      elements.forEach((element,index) => element.animate([
        {opacity:0,transform:'translateY(24px)'},
        {opacity:1,transform:'translateY(0)'}
      ],{duration:650,delay:Math.min(index,7)*75,easing:'cubic-bezier(.16,1,.3,1)',fill:'backwards'}));
      const image = entry.target.querySelector('.app-frame img');
      if (image) image.animate([{transform:'scale(1.035)'},{transform:'scale(1)'}],{duration:1100,easing:'cubic-bezier(.16,1,.3,1)'});
    }
    revealObserver.unobserve(entry.target);
  });
},{threshold:.08});
['.intro','.workspace','.playground','.details-grid','.handoffs','.principles','.faq','.closing','footer'].forEach((selector,index) => {
  const section = document.querySelector(selector);
  if (section) { section.dataset.motionGroup=String(index); revealObserver.observe(section); }
});
motionPreference.addEventListener('change', () => {
  if (motionPreference.matches) document.getAnimations().forEach(a=>a.cancel());
});

// Compact player chrome, with native controls as the no-JavaScript fallback.
const filmDialog = document.querySelector('#film-dialog');
const filmStage = filmDialog.querySelector('.film-stage');
const film = filmStage.querySelector('video');
const filmControls = filmStage.querySelector('.film-controls');
const filmToggle = document.querySelector('#film-toggle');
const filmSeek = document.querySelector('#film-seek');
const filmMute = document.querySelector('#film-mute');
const filmFullscreen = document.querySelector('#film-fullscreen');
film.controls = false;
filmControls.hidden = false;
film.volume = .75;
const timeLabel = seconds => `${Math.floor(seconds/60)}:${String(Math.floor(seconds%60)).padStart(2,'0')}`;
function updateFilm() {
  const duration = Number.isFinite(film.duration) ? film.duration : 60;
  filmSeek.value = String(duration ? film.currentTime/duration*1000 : 0);
  filmSeek.setAttribute('aria-valuetext',`${timeLabel(film.currentTime)} of ${timeLabel(duration)}`);
  document.querySelector('#film-time').textContent = `${timeLabel(film.currentTime)} / ${timeLabel(duration)}`;
  filmStage.classList.toggle('is-paused',film.paused);
  filmToggle.setAttribute('aria-label',film.paused?'Play film':'Pause film');
  filmMute.setAttribute('aria-label',film.muted?'Unmute film':'Mute film');
  filmStage.classList.toggle('is-muted',film.muted);
}
function toggleFilm() { if (film.paused) film.play().catch(()=>{}); else film.pause(); }
filmToggle.addEventListener('click',toggleFilm);
film.addEventListener('click',toggleFilm);
filmSeek.addEventListener('input',()=>{if(Number.isFinite(film.duration))film.currentTime=Number(filmSeek.value)/1000*film.duration;updateFilm();});
filmMute.addEventListener('click',()=>{film.muted=!film.muted;updateFilm();});
filmFullscreen.addEventListener('click',async()=>{
  try {
    if(document.fullscreenElement) await document.exitFullscreen();
    else if(filmStage.requestFullscreen) await filmStage.requestFullscreen();
    else if(film.webkitEnterFullscreen) film.webkitEnterFullscreen();
  } catch {}
});
document.addEventListener('fullscreenchange',()=>filmFullscreen.setAttribute('aria-label',document.fullscreenElement?'Exit fullscreen':'Enter fullscreen'));
if(!document.fullscreenEnabled && !film.webkitEnterFullscreen)filmFullscreen.hidden=true;
['timeupdate','loadedmetadata','play','pause','ended','volumechange'].forEach(event=>film.addEventListener(event,updateFilm));
filmStage.addEventListener('keydown',e=>{if((e.target===filmStage||e.target===film)&&e.code==='Space'){e.preventDefault();toggleFilm();}});
filmDialog.addEventListener('close',()=>{if(document.fullscreenElement)document.exitFullscreen().catch(()=>{});});
updateFilm();
let filmControlsTimer;
function showFilmControls() {
  filmStage.classList.add('controls-active');
  clearTimeout(filmControlsTimer);
  if (!film.paused) filmControlsTimer = setTimeout(()=>filmStage.classList.remove('controls-active'),2200);
}
filmStage.addEventListener('pointermove',showFilmControls);
filmStage.addEventListener('pointerdown',showFilmControls);
filmStage.addEventListener('focusin',showFilmControls);
film.addEventListener('play',showFilmControls);
film.addEventListener('pause',showFilmControls);
filmDialog.addEventListener('close',()=>clearTimeout(filmControlsTimer));
