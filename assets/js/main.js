/* ─────────────────────────────────────────────────────────
   main.js — enhanced background + project card renderer
   ───────────────────────────────────────────────────────── */

const canvas = document.getElementById('stars');
if (canvas) {
  const ctx = canvas.getContext('2d');

  let stars             = [];
  let shooters          = [];
  let nebulae           = [];
  let constellationPairs = [];
  let t                 = 0;
  let scrollY           = 0;
  let targetScrollY     = 0;

  window.addEventListener('scroll', () => { targetScrollY = window.scrollY; });

  function resize() {
    canvas.width  = window.innerWidth;
    canvas.height = window.innerHeight;
    initNebulae();
  }

  function initStars() {
    stars = [];
    const n = Math.floor((canvas.width * canvas.height) / 3800);
    for (let i = 0; i < n; i++) {
      stars.push({
        x:      Math.random() * canvas.width,
        y:      Math.random() * canvas.height,
        r:      Math.random() * 1.1 + 0.1,
        phase:  Math.random() * Math.PI * 2,
        speed:  Math.random() * 0.006 + 0.001,
        bright: Math.random() < 0.07,
        depth:  Math.random()
      });
    }
  }

  function drawStars() {
    for (const s of stars) {
      const parallaxOffset = scrollY * (0.02 + s.depth * 0.12);
      const drawY = s.y - (parallaxOffset % canvas.height);
      const base  = s.bright ? 0.5 : 0.08;
      const range = s.bright ? 0.45 : 0.28;
      const alpha = base + range * Math.sin(t * s.speed + s.phase);
      ctx.beginPath();
      ctx.arc(s.x, drawY, s.r, 0, Math.PI * 2);
      ctx.fillStyle = s.bright ? `rgba(200,225,255,${alpha})` : `rgba(216,220,232,${alpha})`;
      ctx.fill();
      if (s.bright && alpha > 0.55) {
        ctx.strokeStyle = `rgba(200,225,255,${alpha * 0.35})`;
        ctx.lineWidth = 0.5;
        ctx.beginPath();
        ctx.moveTo(s.x - s.r * 3, drawY); ctx.lineTo(s.x + s.r * 3, drawY);
        ctx.moveTo(s.x, drawY - s.r * 3); ctx.lineTo(s.x, drawY + s.r * 3);
        ctx.stroke();
      }
    }
  }

  function buildConstellations() {
    constellationPairs = [];
    const nodes   = stars.filter((s, i) => s.bright || i % 18 === 0);
    const maxDist = Math.min(canvas.width, canvas.height) * 0.18;
    for (let i = 0; i < nodes.length; i++) {
      let connections = 0;
      for (let j = i + 1; j < nodes.length; j++) {
        if (connections >= 2) break;
        const dx = nodes[i].x - nodes[j].x, dy = nodes[i].y - nodes[j].y;
        const dist = Math.sqrt(dx*dx + dy*dy);
        if (dist < maxDist) { constellationPairs.push({ a: nodes[i], b: nodes[j], dist, maxDist }); connections++; }
      }
    }
  }

  function drawConstellations() {
    for (const p of constellationPairs) {
      const alpha   = 0.14 * (1 - p.dist / p.maxDist);
      const aOffset = scrollY * (0.02 + p.a.depth * 0.12);
      const bOffset = scrollY * (0.02 + p.b.depth * 0.12);
      ctx.beginPath();
      ctx.moveTo(p.a.x, p.a.y - (aOffset % canvas.height));
      ctx.lineTo(p.b.x, p.b.y - (bOffset % canvas.height));
      ctx.strokeStyle = `rgba(126,200,227,${alpha})`;
      ctx.lineWidth = 0.8;
      ctx.stroke();
    }
  }

  function initNebulae() {
    nebulae = [
      { x: canvas.width*.15, y: canvas.height*.25, rx: canvas.width*.28, ry: canvas.height*.32, color:'80,60,160', alpha:0.1 },
      { x: canvas.width*.82, y: canvas.height*.65, rx: canvas.width*.30, ry: canvas.height*.28, color:'30,90,160', alpha:0.09 },
      { x: canvas.width*.55, y: canvas.height*.10, rx: canvas.width*.22, ry: canvas.height*.20, color:'20,110,140', alpha:0.07 }
    ];
  }

  function drawNebulae() {
    for (const n of nebulae) {
      const drawY = n.y - scrollY * 0.015;
      const pulse = 1 + 0.06 * Math.sin(t * 0.0008 + n.rx);
      const grad  = ctx.createRadialGradient(n.x, drawY, 0, n.x, drawY, n.rx * pulse);
      grad.addColorStop(0,   `rgba(${n.color},${n.alpha})`);
      grad.addColorStop(0.5, `rgba(${n.color},${n.alpha * 0.4})`);
      grad.addColorStop(1,   `rgba(${n.color},0)`);
      ctx.save();
      ctx.scale(1, n.ry / n.rx);
      ctx.beginPath();
      ctx.arc(n.x, drawY * (n.rx / n.ry), n.rx * pulse, 0, Math.PI * 2);
      ctx.fillStyle = grad;
      ctx.fill();
      ctx.restore();
    }
  }

  function drawGrid() {
    const size   = 48;
    const alpha  = 0.022;
    const offset = (scrollY * 0.05) % size;
    ctx.strokeStyle = `rgba(126,200,227,${alpha})`;
    ctx.lineWidth   = 0.5;
    for (let x = 0; x < canvas.width; x += size) { ctx.beginPath(); ctx.moveTo(x,0); ctx.lineTo(x,canvas.height); ctx.stroke(); }
    for (let y = -size+offset; y < canvas.height; y += size) { ctx.beginPath(); ctx.moveTo(0,y); ctx.lineTo(canvas.width,y); ctx.stroke(); }
    ctx.fillStyle = `rgba(126,200,227,${alpha*1.8})`;
    for (let x = 0; x < canvas.width; x += size)
      for (let y = -size+offset; y < canvas.height; y += size) { ctx.beginPath(); ctx.arc(x,y,0.8,0,Math.PI*2); ctx.fill(); }
  }

  function spawnShooter() {
    const angle = (Math.random()*30+15)*Math.PI/180, speed = Math.random()*6+5, length = Math.random()*180+80;
    shooters.push({ x: Math.random()*canvas.width, y: Math.random()*canvas.height*0.5, vx: Math.cos(angle)*speed, vy: Math.sin(angle)*speed, length, alpha:0, life:0, maxLife: Math.floor(length/speed)+20 });
  }

  function drawShooters() {
    if (Math.random() < 0.004 && shooters.length < 3) spawnShooter();
    shooters = shooters.filter(s => s.life < s.maxLife);
    for (const s of shooters) {
      s.life++; s.x += s.vx; s.y += s.vy;
      const progress = s.life / s.maxLife;
      s.alpha = progress < 0.2 ? progress/0.2 : progress > 0.7 ? (1-progress)/0.3 : 1;
      const mag = Math.hypot(s.vx, s.vy);
      const tailX = s.x - s.vx*(s.length/mag), tailY = s.y - s.vy*(s.length/mag);
      const grad = ctx.createLinearGradient(tailX,tailY,s.x,s.y);
      grad.addColorStop(0, `rgba(255,255,255,0)`);
      grad.addColorStop(0.7, `rgba(200,230,255,${s.alpha*0.4})`);
      grad.addColorStop(1, `rgba(255,255,255,${s.alpha*0.95})`);
      ctx.beginPath(); ctx.moveTo(tailX,tailY); ctx.lineTo(s.x,s.y);
      ctx.strokeStyle = grad; ctx.lineWidth = 1.5; ctx.stroke();
      ctx.beginPath(); ctx.arc(s.x,s.y,1.5,0,Math.PI*2);
      ctx.fillStyle = `rgba(255,255,255,${s.alpha})`; ctx.fill();
    }
  }

  function loop() {
    t++;
    scrollY += (targetScrollY - scrollY) * 0.08;
    ctx.clearRect(0,0,canvas.width,canvas.height);
    drawNebulae(); drawGrid(); drawConstellations(); drawStars(); drawShooters();
    requestAnimationFrame(loop);
  }

  resize(); initStars(); buildConstellations();
  window.addEventListener('resize', () => { resize(); initStars(); buildConstellations(); });
  requestAnimationFrame(loop);
}

// ── MOBILE NAV: push content down when menu opens ─────────────────
(function () {
  const navMenu = document.getElementById('navMenu');
  const navbar  = document.querySelector('.navbar');
  const mainEl  = document.querySelector('main');
  if (!navMenu || !navbar || !mainEl) return;

  const observer = new MutationObserver(() => {
    if (window.innerWidth > 576) return;
    if (navMenu.classList.contains('show')) {
      setTimeout(() => {
        mainEl.style.paddingTop = navbar.offsetHeight + 'px';
      }, 380);
    } else {
      mainEl.style.paddingTop = '';
    }
  });

  observer.observe(navMenu, { attributes: true, attributeFilter: ['class'] });

  window.addEventListener('resize', () => {
    if (window.innerWidth > 576) mainEl.style.paddingTop = '';
  });
})();

// ── SHARED HELPERS ────────────────────────────────────────────────
// Used by projects/project.html and projects/viewer.html, which both
// load this file. They previously each had their own copy — including
// two copies of the icon set that had to be kept identical by hand.

function escapeHtml(str) {
  return String(str).replace(/[&<>"']/g, c =>
    ({ '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;' }[c]));
}

// Lowercase, so it can be compared against the lists below directly.
// Uppercase it at the point of display.
function fileExt(src) {
  const m = String(src || '').split('?')[0].match(/\.([a-z0-9]+)$/i);
  return m ? m[1].toLowerCase() : '';
}

// Filename minus path and extension, percent-decoded.
function fileLabel(src) {
  try {
    return decodeURIComponent(String(src).split('/').pop().split('?')[0].replace(/\.[^.]+$/, ''));
  } catch { return 'Document'; }
}

function humanSize(bytes) {
  const n0 = Number(bytes);
  if (!n0 || !isFinite(n0)) return '';
  const units = ['B', 'KB', 'MB', 'GB'];
  let n = n0, u = 0;
  while (n >= 1024 && u < units.length - 1) { n /= 1024; u++; }
  return (u === 0 || n >= 10 ? Math.round(n) : n.toFixed(1)) + ' ' + units[u];
}

// Attachment icons — Lucide (MIT), drawn on a 24x24 grid and wrapped in
// a translate that puts each one's ink centre on (11, 13). They're
// wrapped rather than rewritten because several use arc commands that
// are easy to corrupt by hand, and Lucide balances the set against each
// other. Stroke weight is inherited from the <svg> root.
const FILE_KINDS = {
  doc: {
    ext: ['pdf', 'doc', 'docx', 'txt', 'md', 'markdown', 'rtf', 'pages'],
    color: '#16c1ff', dim: 'rgba(22,193,255,0.38)',
    glyph: `<g transform="translate(-1,1)" stroke-linecap="round">
              <path d="M6 22a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h8a2.4 2.4 0 0 1 1.704.706l3.588 3.588A2.4 2.4 0 0 1 20 8v12a2 2 0 0 1-2 2z"/>
              <path d="M14 2v5a1 1 0 0 0 1 1h5"/>
              <path d="M10 9H8"/><path d="M16 13H8"/><path d="M16 17H8"/>
            </g>`
  },
  code: {
    ext: ['ino', 'py', 'c', 'h', 'cpp', 'hpp', 'js', 'ts', 'java', 'cs',
          'm', 'rb', 'go', 'rs', 'sh', 'ipynb', 'json', 'xml', 'yml', 'yaml',
          'html', 'css', 'sql'],
    color: '#6ee7a8', dim: 'rgba(110,231,168,0.38)',
    glyph: `<g transform="translate(0,1)" stroke-linecap="round">
              <path d="M4 12.15V4a2 2 0 0 1 2-2h8a2.4 2.4 0 0 1 1.706.706l3.588 3.588A2.4 2.4 0 0 1 20 8v12a2 2 0 0 1-2 2h-3.35"/>
              <path d="M14 2v5a1 1 0 0 0 1 1h5"/>
              <path d="m5 16-3 3 3 3"/><path d="m9 22 3-3-3-3"/>
            </g>`
  },
  model: {
    ext: ['step', 'stp', 'stl', 'f3d', 'sldprt', 'sldasm', 'iges', 'igs',
          'obj', '3mf', 'dxf', 'dwg', 'ipt', 'iam', 'x_t', 'gltf'],
    color: '#f2b366', dim: 'rgba(242,179,102,0.38)',
    glyph: `<g transform="translate(0,1)" stroke-linecap="round">
              <path d="M14 2v5a1 1 0 0 0 1 1h5"/>
              <path d="M14.692 22H18a2 2 0 0 0 2-2V8a2.4 2.4 0 0 0-.706-1.706l-3.588-3.588A2.4 2.4 0 0 0 14 2H6a2 2 0 0 0-2 2v3.804"/>
              <path d="M2.264 13.752 7 16.5l4.737-2.748"/>
              <path d="M2.995 13.014A2 2 0 0 0 2 14.744v3.516a2 2 0 0 0 .996 1.73l3 1.74a2 2 0 0 0 2.008 0l3-1.74A2 2 0 0 0 12 18.26v-3.517a2 2 0 0 0-.995-1.73l-3-1.742a2 2 0 0 0-1.892-.064z"/>
              <path d="M7 16.5V22"/>
            </g>`
  },
  data: {
    ext: ['csv', 'tsv', 'xlsx', 'xls', 'xlsm', 'numbers', 'db', 'sqlite', 'mat'],
    color: '#b39dfa', dim: 'rgba(179,157,250,0.38)',
    glyph: `<g transform="translate(-1,1)" stroke-linecap="round">
              <path d="M6 22a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h8a2.4 2.4 0 0 1 1.704.706l3.588 3.588A2.4 2.4 0 0 1 20 8v12a2 2 0 0 1-2 2z"/>
              <path d="M14 2v5a1 1 0 0 0 1 1h5"/>
              <path d="M8 13h2"/><path d="M14 13h2"/>
              <path d="M8 17h2"/><path d="M14 17h2"/>
            </g>`
  },
  archive: {
    ext: ['zip', 'tar', 'gz', 'rar', '7z'],
    color: '#93a3b8', dim: 'rgba(147,163,184,0.38)',
    glyph: `<g transform="translate(-1,1)" stroke-linecap="round">
              <path d="M13.659 22H18a2 2 0 0 0 2-2V8a2.4 2.4 0 0 0-.706-1.706l-3.588-3.588A2.4 2.4 0 0 0 14 2H6a2 2 0 0 0-2 2v11.5"/>
              <path d="M14 2v5a1 1 0 0 0 1 1h5"/>
              <path d="M8 12v-1"/><path d="M8 18v-2"/><path d="M8 7V6"/>
              <circle cx="8" cy="20" r="2"/>
            </g>`
  }
};

// Unknown extensions fall back to `doc`, so a new file type still gets a
// working chip — just the generic page icon.
function kindOf(src) {
  const ext = fileExt(src);
  for (const [name, k] of Object.entries(FILE_KINDS)) {
    if (k.ext.includes(ext)) return name;
  }
  return 'doc';
}

function glyphFor(src, cls = 'doc-glyph') {
  const k = FILE_KINDS[kindOf(src)];
  return `<svg class="${cls}" viewBox="0 0 22 26" fill="none"
      stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"
      aria-hidden="true">${k.glyph}</svg>`;
}

// main-4.js has its own copy of this inside a block that only runs on the
// index page, so pages that need it outside that block use this one.
function fetchWithTimeout(url, options, ms) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), ms);
  return fetch(url, { ...options, signal: controller.signal })
    .finally(() => clearTimeout(timer));
}

// ── PROJECT CARD RENDERER ─────────────────────────────────────────
const projectList = document.getElementById('project-list');
if (projectList) {
  let allProjects = [];
  let currentSort = localStorage.getItem('projectSort') || 'custom';

  const MONTHS_FULL  = ['January','February','March','April','May','June','July','August','September','October','November','December'];

  function monthName(num) {
    return MONTHS_FULL[(num || 1) - 1] || '';
  }

  function getSeason(monthNum) {
    if (monthNum >= 3 && monthNum <= 5) return 'Spring';
    if (monthNum >= 6 && monthNum <= 8) return 'Summer';
    if (monthNum >= 9 && monthNum <= 11) return 'Fall';
    return 'Winter';
  }

  function buildDateBlock(p) {
    if (!p.date_start) return '';
    const [sy, sm] = p.date_start.split('-').map(Number);
    const end      = p.date_end || p.date_start;
    const [ey, em] = end.split('-').map(Number);

    const season = getSeason(em);

    let monthRange;
    if (sy === ey && sm === em) {
      monthRange = monthName(sm);
    } else if (sy === ey) {
      monthRange = monthName(sm) + ' \u2013 ' + monthName(em);
    } else {
      monthRange = monthName(sm) + ' ' + sy + ' \u2013 ' + monthName(em) + ' ' + ey;
    }

    const code = String(sm).padStart(2,'0') + '/' + sy +
      (sm !== em || sy !== ey ? ' \u2013 ' + String(em).padStart(2,'0') + '/' + ey : '');

    return `<div class="card-date-block">
        <div class="card-date-season">${season} ${ey}</div>
        <div class="card-date-months">${monthRange}</div>
        <div class="card-date-code">${code}</div>
      </div>`;
  }

  function getSorted(mode) {
    const arr = [...allProjects];
    if (mode === 'date-asc')  arr.sort((a, b) => (a.date_start || '').localeCompare(b.date_start || ''));
    if (mode === 'date-desc') arr.sort((a, b) => (b.date_start || '').localeCompare(a.date_start || ''));
    return arr;
  }

  function getFiltered(arr) {
    const yearVal    = (document.getElementById('filter-year')?.value || '').trim();
    const fromVal    = (document.getElementById('range-from')?.value  || '').trim();
    const toVal      = (document.getElementById('range-to')?.value    || '').trim();
    const activeTags = [...document.querySelectorAll('.tag-filter-btn.active')].map(b => b.dataset.tag);

    return arr.filter(p => {
      const ps = p.date_start || '';
      const pe = p.date_end   || ps;
      if (yearVal) {
        const sy = ps.split('-')[0];
        const ey = pe.split('-')[0];
        if (sy > yearVal || ey < yearVal) return false;
      }
      if (fromVal && pe < fromVal) return false;
      if (toVal   && ps > toVal)   return false;
      if (activeTags.length > 0) {
        if (!activeTags.some(t => (p.skills || []).includes(t))) return false;
      }
      return true;
    });
  }

  function isVideoSrc(src) {
    return /\.(mp4|mov|webm|ogg)$/i.test((src || '').split('?')[0]);
  }

  function cardHTML(p) {
    const thumbSrc = p.thumbnail
      ? p.thumbnail
      : (p.images && p.images.length > 0)
        ? (typeof p.images[0] === 'object' ? p.images[0].src : p.images[0])
        : null;

    // Optional clip that plays over the still on hover. Kept separate from
    // `images` so it never shows up in the gallery — the card's motion and
    // the project's photos are different things.
    const hoverSrc = isVideoSrc(p.thumbnail_hover) ? p.thumbnail_hover : null;

    let thumbHTML;
    if (!thumbSrc) {
      thumbHTML = `<div class="card-image-box"><span class="img-placeholder">${p.id}</span></div>`;
    } else if (isVideoSrc(thumbSrc)) {
      // The still itself is a video: show a frame from it, play on hover.
      // `#t=1` names the frame; wireCardVideos() forces the seek, because
      // the fragment alone doesn't make the browser decode and paint it.
      thumbHTML = `<video class="card-thumb card-thumb-video" muted loop playsinline
                          preload="metadata" tabindex="-1" aria-label="${p.title}">
                     <source src="${thumbSrc}#t=1">
                   </video>`;
    } else if (hoverSrc) {
      // Still image with a separate clip layered over it. preload="none"
      // means the clip isn't downloaded until someone actually hovers.
      thumbHTML = `<span class="card-thumb-wrap">
                     <img src="${thumbSrc}" class="card-thumb" alt="${p.title}">
                     <video class="card-thumb-hover" muted loop playsinline
                            preload="none" tabindex="-1" aria-hidden="true">
                       <source src="${hoverSrc}">
                     </video>
                   </span>`;
    } else {
      thumbHTML = `<img src="${thumbSrc}" class="card-thumb" alt="${p.title}">`;
    }

    return `
      <a class="project-card card h-100" href="projects/project.html?id=${p.id}">
        <div class="card-body">
          <div class="card-header-row">
            <div class="card-header-left">
              <div class="card-subtitle-label">${p.subtitle}</div>
            </div>
            ${buildDateBlock(p)}
          </div>
          <h2 class="card-title">${p.title}</h2>
          ${thumbHTML}
          <p class="card-blurb">${p.blurb}</p>
          <div class="card-skills">
            ${p.skills.map(s => `<span class="skill-tag">${s}</span>`).join('')}
          </div>
          <div class="card-cta">
            <span class="cta-text">View project</span>
            <span class="cta-arrow">\u2192</span>
          </div>
        </div>
      </a>`;
  }

  // Wire up both flavours of moving thumbnail. Re-run after every render,
  // because filtering and sorting rebuild the whole list.
  function wireCardVideos() {
    const stillOnly = window.matchMedia &&
      window.matchMedia('(prefers-reduced-motion: reduce)').matches;

    const play = v => { const r = v.play(); if (r && r.catch) r.catch(() => {}); };

    // (a) the thumbnail is itself a video — show a frame, play on hover
    projectList.querySelectorAll('.card-thumb-video').forEach(v => {
      const seek = () => { try { v.currentTime = 1; } catch (_) {} };
      if (v.readyState >= 1) seek();
      else v.addEventListener('loadedmetadata', seek, { once: true });

      if (stillOnly) return;   // asked for less motion: still frame only

      const card = v.closest('.project-card') || v;
      card.addEventListener('mouseenter', () => { v.currentTime = 0; play(v); });
      card.addEventListener('mouseleave', () => { v.pause(); seek(); });
    });

    // (b) a separate clip fading in over a still image
    projectList.querySelectorAll('.card-thumb-hover').forEach(v => {
      if (stillOnly) { v.remove(); return; }

      const card = v.closest('.project-card') || v;
      card.addEventListener('mouseenter', () => {
        v.currentTime = 0;
        play(v);
        v.classList.add('showing');
      });
      card.addEventListener('mouseleave', () => {
        v.classList.remove('showing');
        // Let the crossfade finish before pausing, so the last visible
        // frame isn't a frozen one.
        setTimeout(() => { if (!v.classList.contains('showing')) v.pause(); }, 260);
      });

      // If the file is missing or unplayable, drop it and leave the still.
      v.addEventListener('error', () => v.remove());
    });
  }

  function render() {
    const filtered = getFiltered(getSorted(currentSort));
    projectList.innerHTML = filtered.length === 0
      ? '<p class="no-results">No projects match the current filters.</p>'
      : `<div class="row g-3 g-lg-4">${filtered.map(p => `<div class="col-12 col-sm-6">${cardHTML(p)}</div>`).join('')}</div>`;
    wireCardVideos();
  }

  function setSort(mode) {
    currentSort = mode;
    localStorage.setItem('projectSort', mode);
    document.querySelectorAll('.sort-btn').forEach(b =>
      b.classList.toggle('active', b.dataset.sort === mode)
    );
    render();
  }

  function populateYearDropdown() {
    const years = new Set();
    allProjects.forEach(p => {
      if (p.date_start) years.add(p.date_start.split('-')[0]);
      if (p.date_end)   years.add(p.date_end.split('-')[0]);
    });
    const select = document.getElementById('filter-year');
    if (!select) return;
    [...years].sort().forEach(y => {
      const opt = document.createElement('option');
      opt.value = y;
      opt.textContent = y;
      select.appendChild(opt);
    });
  }

  function buildTagFilter() {
    const tags = [...new Set(allProjects.flatMap(p => p.skills || []))].sort();
    const container = document.getElementById('tag-filter');
    if (!container) return;
    container.innerHTML = tags.map(t =>
      `<button class="tag-filter-btn" data-tag="${t}">${t}</button>`
    ).join('');
    container.addEventListener('click', e => {
      const btn = e.target.closest('.tag-filter-btn');
      if (!btn) return;
      btn.classList.toggle('active');
      render();
    });
  }

  // wire up controls
  document.querySelectorAll('.sort-btn').forEach(btn =>
    btn.addEventListener('click', () => setSort(btn.dataset.sort))
  );
  document.querySelectorAll('.sort-btn').forEach(b =>
    b.classList.toggle('active', b.dataset.sort === currentSort)
  );
  document.getElementById('filter-year')?.addEventListener('change', render);
  document.getElementById('range-from')?.addEventListener('change', render);
  document.getElementById('range-to')?.addEventListener('change',   render);

  // filter panel toggle
  const filterToggle = document.getElementById('filter-toggle');
  const filterPanel  = document.getElementById('filter-panel');
  filterToggle?.addEventListener('click', e => {
    e.stopPropagation();
    const open = filterPanel.classList.toggle('open');
    filterToggle.classList.toggle('active', open);
  });
  document.addEventListener('click', e => {
    if (!e.target.closest('.filter-dropdown-wrap')) {
      filterPanel?.classList.remove('open');
      filterToggle?.classList.remove('active');
    }
  });

  // tag row toggle
  const tagToggle = document.getElementById('tag-toggle');
  const tagRow    = document.getElementById('tag-filter');
  tagToggle?.addEventListener('click', () => {
    const open = tagRow.classList.toggle('open');
    tagToggle.classList.toggle('active', open);
  });

  function loadError() {
    projectList.innerHTML = `
      <div class="load-error">
        <p class="load-error-text">Couldn't load projects. Try refreshing the page.</p>
        <button class="load-error-btn" onclick="location.reload()">Refresh</button>
      </div>`;
  }

  function handleProjects(projects) {
    allProjects = projects;
    populateYearDropdown();
    buildTagFilter();
    render();
  }

  // Try the cheap HEAD request first to version the cache by the file's
  // actual last-modified time (fast repeat loads, instant updates on edit).
  // If HEAD is blocked or fails for any reason (some browser extensions
  // flag chained fetches to .json endpoints), fall back to a plain
  // timestamped fetch instead of failing outright. Either path also has
  // a timeout so a silently-blocked request shows the error UI instead
  // of leaving the page blank forever.
  fetchWithTimeout('projects.json', { method: 'HEAD' }, 4000)
    .then(headRes => {
      const lastModified = headRes.headers.get('Last-Modified') || Date.now();
      return fetchWithTimeout(`projects.json?v=${encodeURIComponent(lastModified)}`, {}, 4000);
    })
    .catch(() => fetchWithTimeout(`projects.json?v=${Date.now()}`, {}, 4000))
    .then(r => {
      if (!r.ok) throw new Error('Bad response: ' + r.status);
      return r.json();
    })
    .then(handleProjects)
    .catch(err => {
      console.warn('Could not load projects.json:', err);
      loadError();
    });
}
