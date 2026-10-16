const root = document.documentElement;
const systemReduce = matchMedia('(prefers-reduced-motion: reduce)');
const reduced = () => systemReduce.matches || root.classList.contains('reduce-motion');
const wait = ms => new Promise(r => setTimeout(r, reduced() ? 0 : ms));

// ------------------------------------------------------------------ header
const header = document.querySelector('.header');
const darks = [...document.querySelectorAll('.anatomy, .closing')];
const onScroll = () => {
  header.classList.toggle('is-scrolled', scrollY > 8);
  const y = header.offsetHeight / 2;
  header.classList.toggle('is-dark', darks.some(d => { const r = d.getBoundingClientRect(); return r.top <= y && r.bottom >= y; }));
};
addEventListener('scroll', onScroll, { passive: true });
onScroll();

// ------------------------------------------------------------------ motion toggle
const toggle = document.querySelector('[data-motion-toggle]');
const syncToggle = () => toggle?.setAttribute('aria-pressed', String(reduced()));
toggle?.addEventListener('click', () => {
  const on = !root.classList.contains('reduce-motion');
  root.classList.toggle('reduce-motion', on);
  try { localStorage.setItem('unpaged-reduce-motion', on ? '1' : '0'); } catch {}
  syncToggle();
});
systemReduce.addEventListener('change', syncToggle);
syncToggle();

// ------------------------------------------------------------------ reveals
const revealTargets = document.querySelectorAll('main > section:not(.hero) .section-head, .library-art, .moments-art, .habit, .playback-art, .plan, .features li, .points div, .details-grid article, .closing-inner > *, .plus-art');
if ('IntersectionObserver' in window) {
  const seen = new IntersectionObserver(entries => {
    for (const en of entries) if (en.isIntersecting) { en.target.classList.add('is-in'); seen.unobserve(en.target); }
  }, { rootMargin: '0px 0px -8% 0px' });
  revealTargets.forEach(el => {
    const sibs = [...el.parentElement.children].filter(c => c.matches(el.tagName));
    el.style.setProperty('--d', `${Math.min(sibs.indexOf(el), 5) * 70}ms`);
    el.classList.add('reveal');
    seen.observe(el);
  });
}

// ------------------------------------------------------------------ library tabs
const tabs = [...document.querySelectorAll('[role=tab]')];
const phones = [...document.querySelectorAll('.lib-phone')];
function selectTab(i, focus = false) {
  tabs.forEach((t, j) => {
    const on = i === j;
    t.setAttribute('aria-selected', String(on));
    t.tabIndex = on ? 0 : -1;
    const panel = document.getElementById(t.getAttribute('aria-controls'));
    if (on && panel.hidden) { panel.hidden = false; panel.classList.remove('is-entering'); void panel.offsetWidth; panel.classList.add('is-entering'); }
    else if (!on) panel.hidden = true;
    phones[j]?.classList.toggle('is-active', on);
    phones[j]?.setAttribute('aria-hidden', String(!on));
  });
  if (focus) tabs[i].focus();
}
tabs.forEach((t, i) => {
  t.addEventListener('click', () => selectTab(i));
  t.addEventListener('keydown', ev => {
    const n = tabs.length;
    const next = { ArrowRight: (i + 1) % n, ArrowLeft: (i - 1 + n) % n, Home: 0, End: n - 1 }[ev.key];
    if (next !== undefined) { ev.preventDefault(); selectTab(next, true); }
  });
});

// ------------------------------------------------------------------ anatomy of a moment
const body = document.querySelector('.anatomy-body');
if (body) {
  const stage = body.querySelector('.stage');
  const steps = [...body.querySelectorAll('.step')];
  const nav = [...body.querySelectorAll('[data-go]')];
  const now = body.querySelector('.stage-now');
  const marks = [...body.querySelectorAll('.m')];
  const fields = [...body.querySelectorAll('.field')];
  const wires = body.querySelector('.wires');
  const text = body.querySelector('.t-text');
  const typed = [...body.querySelectorAll('[data-type]')];
  typed.forEach(el => { el.dataset.full = el.textContent; });
  const labels = steps.map(s => s.querySelector('.step-label').lastChild.textContent);

  // Split transcript text into words once, keeping the marks intact, for the transcription pass.
  const walker = document.createTreeWalker(text, NodeFilter.SHOW_TEXT);
  const nodes = []; while (walker.nextNode()) nodes.push(walker.currentNode);
  for (const node of nodes) {
    const frag = document.createDocumentFragment();
    for (const part of node.textContent.split(/(\s+)/)) {
      if (!part) continue;
      if (/^\s+$/.test(part)) { frag.append(part); continue; }
      const w = document.createElement('span'); w.className = 'word'; w.textContent = part; frag.append(w);
    }
    node.replaceWith(frag);
  }
  const words = [...text.querySelectorAll('.word')];

  let current = 0, token = 0, lock = 0;

  async function typeOut(el, t, speed) {
    const full = el.dataset.full;
    if (reduced()) { el.textContent = full; return; }
    el.textContent = ''; el.classList.add('caret');
    for (let i = 1; i <= full.length; i += 2) {
      if (t !== token) return;
      el.textContent = full.slice(0, i);
      await wait(speed);
    }
    el.textContent = full; el.classList.remove('caret');
  }

  function anchor(el, side) {
    const s = stage.getBoundingClientRect();
    const rects = [...el.getClientRects()];
    const r = side === 'end' ? rects.at(-1) : rects[0] || el.getBoundingClientRect();
    return { l: r.left - s.left, r: r.right - s.left, t: r.top - s.top, b: r.bottom - s.top, cx: r.left + r.width / 2 - s.left, cy: r.top + r.height / 2 - s.top };
  }
  const tbox = body.querySelector('.transcript');
  const box = () => anchor(tbox, 'start');
  // On phones the transcript is a window; bring the words in play into view.
  function frame(n) {
    if (text.scrollHeight <= text.clientHeight + 1) return;
    const hot = marks.filter(m => +m.dataset.at === n && m.offsetParent !== null);
    let top = 0;
    if (hot.length) {
      const base = text.getBoundingClientRect().top - text.scrollTop;
      const ys = hot.flatMap(m => [...m.getClientRects()].map(r => [r.top - base, r.bottom - base]));
      const lo = Math.min(...ys.map(y => y[0])), hi = Math.max(...ys.map(y => y[1]));
      top = hi - lo > text.clientHeight - 24 ? lo - 12 : (lo + hi) / 2 - text.clientHeight / 2;
    } else if (n !== 2) top = text.scrollTop;
    text.scrollTop = Math.max(0, Math.min(top, text.scrollHeight - text.clientHeight));
  }
  const visibleIn = (el, box) => { const r = el.getClientRects()[0]; return r && r.bottom > box.top + 4 && r.top < box.bottom - 4; };

  function drawWires(n, animate) {
    wires.innerHTML = '';
    const s = stage.getBoundingClientRect();
    wires.setAttribute('viewBox', `0 0 ${s.width} ${s.height}`);
    let i = 0;
    const view = text.getBoundingClientRect();
    for (const m of marks) {
      if (+m.dataset.at !== n || m.offsetParent === null) continue;
      const target = document.getElementById(m.dataset.to);
      if (!target || target.offsetParent === null) continue;
      const field = target.closest('.field');
      if (!visibleIn(m, view)) {
        // Its words are scrolled out of the window: no cable, but the label still lands.
        if (target !== field) {
          if (animate && !reduced()) { const t = token; setTimeout(() => { if (t === token) target.classList.add('on'); }, i * 260 + 650); }
          else target.classList.add('on');
        }
        i++; continue;
      }
      const tgt = field.querySelector('.f-label');
      const a = anchor(m, 'end'), b = anchor(tgt, 'start');
      let d, sx, sy, ex, ey;
      if (b.l > a.r + 16) {
        // Leave from the transcript's edge on the mark's line, so cables never cross the prose.
        sx = box().r + 3; sy = a.cy; ex = b.l - 9; ey = b.cy;
        const dx = Math.max(30, (ex - sx) * .5);
        d = `M${sx},${sy} C${sx + dx},${sy} ${ex - dx},${ey} ${ex},${ey}`;
      } else {
        // Stacked layout: a cable would cut across the prose and the finished fields, so the
        // highlighted words and the lit chip carry the link.
        if (target !== field) {
          if (animate && !reduced()) { const t = token; setTimeout(() => { if (t === token) target.classList.add('on'); }, i * 260 + 650); }
          else target.classList.add('on');
        }
        i++; continue;
      }
      // A label lights up when its cable lands.
      const chip = target === field ? null : target;
      const g = document.createElementNS('http://www.w3.org/2000/svg', 'g');
      const path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
      path.setAttribute('d', d);
      const dot = document.createElementNS('http://www.w3.org/2000/svg', 'circle');
      dot.setAttribute('cx', ex); dot.setAttribute('cy', ey); dot.setAttribute('r', 3.2);
      const start = document.createElementNS('http://www.w3.org/2000/svg', 'circle');
      start.setAttribute('cx', sx); start.setAttribute('cy', sy); start.setAttribute('r', 2.2);
      g.append(path, start, dot);
      wires.append(g);
      if (animate && !reduced()) {
        const len = path.getTotalLength();
        path.style.setProperty('--len', len);
        path.classList.add('draw'); dot.classList.add('pop');
        path.style.animationDelay = `${i * 260}ms`; dot.style.animationDelay = `${i * 260 + 550}ms`;
        if (chip) { const t = token; setTimeout(() => { if (t === token) chip.classList.add('on'); }, i * 260 + 650); }
      } else if (chip) chip.classList.add('on');
      i++;
    }
  }

  async function setStep(n, animate = true) {
    if (n === current) return;
    current = n; const t = ++token;
    body.dataset.step = n;
    steps.forEach((s, i) => s.classList.toggle('is-active', i + 1 === n));
    nav.forEach((b, i) => { b.toggleAttribute('aria-current', false); if (i + 1 === n) b.setAttribute('aria-current', 'step'); b.classList.toggle('is-done', i + 1 < n); });
    now.innerHTML = `<span class="now-n">${n} ${now.dataset.of} ${steps.length} · </span>${labels[n - 1]}`;
    marks.forEach(m => { const at = +m.dataset.at; m.classList.toggle('is-active', at === n); m.classList.toggle('is-used', at < n); });
    fields.forEach(f => { const at = +f.dataset.at; f.dataset.state = at < n ? 'done' : at === n ? 'now' : 'todo'; });
    body.querySelectorAll('.lab.on, .verified.on').forEach(el => el.classList.remove('on'));
    typed.forEach(el => { el.classList.remove('caret'); const f = el.closest('.field'); el.textContent = f.dataset.state === 'todo' ? '' : el.dataset.full; });
    text.classList.remove('is-typing');
    words.forEach(w => w.classList.remove('on'));
    frame(n);
    drawWires(n, animate);

    if (!animate) return;
    if (n === 2 && !reduced()) {
      text.classList.add('is-typing');
      const live = words.filter(w => w.offsetParent !== null);
      for (let i = 0; i < live.length; i += 2) {
        if (t !== token) return;
        live[i].classList.add('on'); live[i + 1]?.classList.add('on');
        const r = live[i].offsetTop + live[i].offsetHeight - text.offsetTop;
        if (r > text.scrollTop + text.clientHeight - 20) text.scrollTop = r - text.clientHeight + 20;
        await wait(22);
      }
      text.classList.remove('is-typing');
    }
    const active = fields.filter(f => f.dataset.state === 'now');
    for (const f of active) {
      const typer = f.querySelector('[data-type]');
      if (typer) await typeOut(typer, t, f.id === 'f-note' ? 14 : f.id === 'f-quote' ? 22 : 40);
      if (t !== token) return;
      if (f.id === 'f-quote') { await wait(250); f.querySelector('.verified')?.classList.add('on'); }
    }
  }

  // Scroll drives the walkthrough. The reading line sits mid-screen, or just under the pinned stage on phones.
  const narrow = matchMedia('(max-width: 1100px)');
  const line = () => {
    if (!narrow.matches) return innerHeight / 2;
    const bottom = stage.getBoundingClientRect().bottom;
    return bottom + Math.min(130, Math.max(28, (innerHeight - bottom) * .5));
  };
  let ticking = false;
  function pick() {
    ticking = false;
    if (Date.now() < lock) return;
    const bodyBox = body.getBoundingClientRect();
    if (bodyBox.bottom < 0 || bodyBox.top > innerHeight) return;
    const y = line();
    let n = 1;
    steps.forEach((s, i) => { if (s.getBoundingClientRect().top <= y) n = i + 1; });
    setStep(n);
  }
  addEventListener('scroll', () => { if (!ticking) { ticking = true; requestAnimationFrame(pick); } }, { passive: true });
  narrow.addEventListener('change', () => { drawWires(current, false); pick(); });

  nav.forEach(b => b.addEventListener('click', () => {
    const n = +b.dataset.go;
    lock = Date.now() + 900;
    setStep(n);
    requestAnimationFrame(() => {
      const s = steps[n - 1];
      const y = s.getBoundingClientRect().top + scrollY - (narrow.matches ? line() - 4 : innerHeight / 2 - s.offsetHeight / 2);
      scrollTo({ top: y, behavior: reduced() ? 'auto' : 'smooth' });
    });
  }));

  new ResizeObserver(() => drawWires(current, false)).observe(stage);
  current = 0;
  setStep(1, false);
  pick();
}
