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

  function cardHTML(p) {
    const thumbSrc = p.thumbnail
      ? p.thumbnail
      : (p.images && p.images.length > 0)
        ? (typeof p.images[0] === 'object' ? p.images[0].src : p.images[0])
        : null;

    const thumbHTML = thumbSrc
      ? `<img src="${thumbSrc}" class="card-thumb" alt="${p.title}">`
      : `<div class="card-image-box"><span class="img-placeholder">${p.id}</span></div>`;

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

  function render() {
    const filtered = getFiltered(getSorted(currentSort));
    projectList.innerHTML = filtered.length === 0
      ? '<p class="no-results">No projects match the current filters.</p>'
      : `<div class="row g-3 g-lg-4">${filtered.map(p => `<div class="col-12 col-sm-6">${cardHTML(p)}</div>`).join('')}</div>`;
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

  fetch('projects.json')
    .then(r => r.json())
    .then(projects => {
      allProjects = projects;
      populateYearDropdown();
      buildTagFilter();
      render();
    })
    .catch(err => console.warn('Could not load projects.json:', err));
}
