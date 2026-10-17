// Live sky: the visitor's current weather and time of day behind the hero (see site/README.md, "Live sky").
// No geolocation prompt and no IP lookup. The browser's time zone picks an approximate place, Open-Meteo
// returns its current conditions, and the answer is kept in sessionStorage for 30 minutes. Any failure
// falls back to a sky drawn from the local clock. `?sky=rain&daypart=dusk` overrides both for QA.
const root = document.documentElement;
const skies = [...document.querySelectorAll('.sky')];
const systemReduce = matchMedia('(prefers-reduced-motion: reduce)');
const reduced = () => systemReduce.matches || root.classList.contains('reduce-motion');

const DAYPARTS = ['dawn', 'day', 'dusk', 'night'];
const WEATHERS = ['clear', 'cloudy', 'fog', 'rain', 'snow', 'storm'];
const CACHE = 'unpaged-sky';          // the Open-Meteo answer, 30 minutes
const STATE = 'unpaged-sky-state';    // the last resolved sky, read by the head script before first paint
const FRESH = 30 * 60e3;
const TWILIGHT = 45 * 60e3;           // dawn and dusk run 45 minutes either side of sunrise and sunset

// ------------------------------------------------------------------ where (roughly)
// Representative coordinates for the most common IANA zones. Anything else falls back to the
// zone's region for latitude and the UTC offset for longitude (15 degrees per hour).
const ZONES = {
  'America/New_York': [40.7, -74], 'America/Detroit': [42.3, -83], 'America/Toronto': [43.7, -79.4], 'America/Chicago': [41.9, -87.6],
  'America/Winnipeg': [49.9, -97.1], 'America/Regina': [50.4, -104.6], 'America/Denver': [39.7, -105], 'America/Edmonton': [53.5, -113.5],
  'America/Phoenix': [33.4, -112.1], 'America/Boise': [43.6, -116.2], 'America/Los_Angeles': [34.1, -118.2], 'America/Vancouver': [49.3, -123.1],
  'America/Anchorage': [61.2, -149.9], 'Pacific/Honolulu': [21.3, -157.9], 'America/Halifax': [44.6, -63.6], 'America/St_Johns': [47.6, -52.7],
  'America/Indiana/Indianapolis': [39.8, -86.2], 'America/Mexico_City': [19.4, -99.1], 'America/Monterrey': [25.7, -100.3],
  'America/Tijuana': [32.5, -117], 'America/Cancun': [21.2, -86.8], 'America/Guatemala': [14.6, -90.5], 'America/El_Salvador': [13.7, -89.2],
  'America/Costa_Rica': [9.9, -84.1], 'America/Panama': [9, -79.5], 'America/Havana': [23.1, -82.4], 'America/Jamaica': [18, -76.8],
  'America/Santo_Domingo': [18.5, -69.9], 'America/Puerto_Rico': [18.5, -66.1], 'America/Bogota': [4.7, -74.1], 'America/Caracas': [10.5, -66.9],
  'America/Guayaquil': [-2.2, -79.9], 'America/Lima': [-12, -77], 'America/La_Paz': [-16.5, -68.1], 'America/Santiago': [-33.4, -70.7],
  'America/Argentina/Buenos_Aires': [-34.6, -58.4], 'America/Buenos_Aires': [-34.6, -58.4], 'America/Montevideo': [-34.9, -56.2],
  'America/Asuncion': [-25.3, -57.6], 'America/Sao_Paulo': [-23.5, -46.6], 'America/Bahia': [-13, -38.5], 'America/Recife': [-8.1, -34.9],
  'America/Fortaleza': [-3.7, -38.5], 'America/Manaus': [-3.1, -60],
  'Atlantic/Reykjavik': [64.1, -21.9], 'Atlantic/Azores': [37.7, -25.7], 'Atlantic/Canary': [28.1, -15.4], 'Europe/Lisbon': [38.7, -9.1],
  'Europe/Dublin': [53.3, -6.3], 'Europe/London': [51.5, -0.1], 'Europe/Madrid': [40.4, -3.7], 'Europe/Paris': [48.9, 2.4],
  'Europe/Brussels': [50.8, 4.4], 'Europe/Amsterdam': [52.4, 4.9], 'Europe/Luxembourg': [49.6, 6.1], 'Europe/Zurich': [47.4, 8.5],
  'Europe/Berlin': [52.5, 13.4], 'Europe/Copenhagen': [55.7, 12.6], 'Europe/Oslo': [59.9, 10.8], 'Europe/Stockholm': [59.3, 18.1],
  'Europe/Helsinki': [60.2, 24.9], 'Europe/Tallinn': [59.4, 24.7], 'Europe/Riga': [56.9, 24.1], 'Europe/Vilnius': [54.7, 25.3],
  'Europe/Warsaw': [52.2, 21], 'Europe/Prague': [50.1, 14.4], 'Europe/Vienna': [48.2, 16.4], 'Europe/Bratislava': [48.1, 17.1],
  'Europe/Budapest': [47.5, 19], 'Europe/Ljubljana': [46.1, 14.5], 'Europe/Zagreb': [45.8, 16], 'Europe/Belgrade': [44.8, 20.5],
  'Europe/Sarajevo': [43.9, 18.4], 'Europe/Rome': [41.9, 12.5], 'Europe/Malta': [35.9, 14.5], 'Europe/Athens': [38, 23.7],
  'Europe/Sofia': [42.7, 23.3], 'Europe/Bucharest': [44.4, 26.1], 'Europe/Chisinau': [47, 28.9], 'Europe/Kyiv': [50.5, 30.5],
  'Europe/Kiev': [50.5, 30.5], 'Europe/Minsk': [53.9, 27.6], 'Europe/Moscow': [55.8, 37.6], 'Europe/Istanbul': [41, 29], 'Asia/Istanbul': [41, 29],
  'Africa/Casablanca': [33.6, -7.6], 'Africa/Algiers': [36.8, 3.1], 'Africa/Tunis': [36.8, 10.2], 'Africa/Cairo': [30, 31.2],
  'Africa/Dakar': [14.7, -17.4], 'Africa/Abidjan': [5.3, -4], 'Africa/Accra': [5.6, -0.2], 'Africa/Lagos': [6.5, 3.4],
  'Africa/Kinshasa': [-4.3, 15.3], 'Africa/Luanda': [-8.8, 13.2], 'Africa/Addis_Ababa': [9, 38.7], 'Africa/Nairobi': [-1.3, 36.8],
  'Africa/Maputo': [-25.9, 32.6], 'Africa/Johannesburg': [-26.2, 28],
  'Asia/Jerusalem': [31.8, 35.2], 'Asia/Tel_Aviv': [32.1, 34.8], 'Asia/Beirut': [33.9, 35.5], 'Asia/Amman': [32, 35.9],
  'Asia/Baghdad': [33.3, 44.4], 'Asia/Riyadh': [24.7, 46.7], 'Asia/Qatar': [25.3, 51.5], 'Asia/Dubai': [25.2, 55.3],
  'Asia/Tehran': [35.7, 51.4], 'Asia/Tbilisi': [41.7, 44.8], 'Asia/Yerevan': [40.2, 44.5], 'Asia/Baku': [40.4, 49.9],
  'Asia/Karachi': [24.9, 67], 'Asia/Tashkent': [41.3, 69.3], 'Asia/Almaty': [43.2, 76.9], 'Asia/Kolkata': [28.6, 77.2],
  'Asia/Calcutta': [28.6, 77.2], 'Asia/Colombo': [6.9, 79.9], 'Asia/Kathmandu': [27.7, 85.3], 'Asia/Dhaka': [23.8, 90.4],
  'Asia/Yangon': [16.8, 96.2], 'Asia/Bangkok': [13.8, 100.5], 'Asia/Ho_Chi_Minh': [10.8, 106.7], 'Asia/Saigon': [10.8, 106.7],
  'Asia/Kuala_Lumpur': [3.1, 101.7], 'Asia/Singapore': [1.3, 103.8], 'Asia/Jakarta': [-6.2, 106.8], 'Asia/Manila': [14.6, 121],
  'Asia/Shanghai': [31.2, 121.5], 'Asia/Hong_Kong': [22.3, 114.2], 'Asia/Taipei': [25, 121.6], 'Asia/Seoul': [37.6, 127],
  'Asia/Tokyo': [35.7, 139.7], 'Asia/Yekaterinburg': [56.8, 60.6], 'Asia/Novosibirsk': [55, 82.9], 'Asia/Vladivostok': [43.1, 131.9],
  'Australia/Perth': [-32, 115.9], 'Australia/Darwin': [-12.5, 130.8], 'Australia/Adelaide': [-34.9, 138.6], 'Australia/Brisbane': [-27.5, 153],
  'Australia/Sydney': [-33.9, 151.2], 'Australia/Melbourne': [-37.8, 145], 'Australia/Hobart': [-42.9, 147.3],
  'Pacific/Guam': [13.5, 144.8], 'Pacific/Fiji': [-18.1, 178.4], 'Pacific/Auckland': [-36.8, 174.8]
};
const REGION_LAT = { America: 35, Europe: 50, Africa: 5, Asia: 30, Australia: -30, Pacific: -15, Atlantic: 35, Indian: -10, Antarctica: -75, Arctic: 78 };

function place() {
  let zone = '';
  try { zone = Intl.DateTimeFormat().resolvedOptions().timeZone || ''; } catch {}
  if (ZONES[zone]) return ZONES[zone];
  const lon = Math.max(-180, Math.min(180, -new Date().getTimezoneOffset() / 4));
  return [REGION_LAT[zone.split('/')[0]] ?? 45, Math.round(lon * 10) / 10];
}

// ------------------------------------------------------------------ what's outside
const weatherOf = (code, cover) =>
  code >= 95 ? 'storm'
  : (code >= 71 && code <= 77) || code === 85 || code === 86 ? 'snow'
  : (code >= 51 && code <= 67) || (code >= 80 && code <= 82) ? 'rain'
  : code === 45 || code === 48 ? 'fog'
  : code === 3 || (code === 2 && cover >= 50) ? 'cloudy'
  : 'clear';

async function conditions() {
  const [lat, lon] = place();
  try {
    const c = JSON.parse(sessionStorage.getItem(CACHE) || 'null');
    if (c && c.lat === lat && c.lon === lon && Date.now() - c.at < FRESH) return c.data;
  } catch {}
  const url = `https://api.open-meteo.com/v1/forecast?latitude=${lat}&longitude=${lon}`
    + '&current=weather_code,is_day,cloud_cover,precipitation,wind_speed_10m&daily=sunrise,sunset&timezone=auto&past_days=1&forecast_days=2';
  const abort = new AbortController();
  const timer = setTimeout(() => abort.abort(), 4000);
  try {
    const res = await fetch(url, { signal: abort.signal, credentials: 'omit', referrerPolicy: 'no-referrer' });
    if (!res.ok) throw new Error(`open-meteo ${res.status}`);
    const j = await res.json();
    const offset = j.utc_offset_seconds * 1000;
    const time = s => Date.parse(`${s}Z`) - offset; // local ISO times without a zone
    const cur = j.current;
    const data = {
      weather: weatherOf(cur.weather_code, cur.cloud_cover), cover: cur.cloud_cover, precip: cur.precipitation, wind: cur.wind_speed_10m,
      isDay: cur.is_day === 1, rises: j.daily.sunrise.map(time), sets: j.daily.sunset.map(time)
    };
    if (!data.rises.every(Number.isFinite) || !data.sets.every(Number.isFinite)) delete data.rises;
    try { sessionStorage.setItem(CACHE, JSON.stringify({ at: Date.now(), lat, lon, data })); } catch {}
    return data;
  } finally {
    clearTimeout(timer);
  }
}

// ------------------------------------------------------------------ when
// Without sunrise and sunset, assume 06:30 and 18:45 on the local clock.
function clockSuns(now) {
  const days = [-1, 0, 1].map(d => { const t = new Date(now); t.setDate(t.getDate() + d); return t; });
  const at = (t, h, m) => new Date(t.getFullYear(), t.getMonth(), t.getDate(), h, m).getTime();
  return { rises: days.map(t => at(t, 6, 30)), sets: days.map(t => at(t, 18, 45)) };
}

// Daypart, the sun's arc (0 at sunrise, 1 at sunset, a little past either end in twilight)
// and the moon's (0 at sunset, 1 at sunrise).
function timeOfDay(now, { rises, sets }) {
  const events = [...rises.map(t => [t, 'rise']), ...sets.map(t => [t, 'set'])].sort((a, b) => a[0] - b[0]);
  const i = clamp(events.findIndex(([t]) => t > now), 1, events.length - 1);
  const [from, kind] = events[i - 1], [to] = events[i];
  const span = (now - from) / (to - from);
  const length = sets[1] - rises[1];
  const near = list => Math.min(...list.map(t => Math.abs(now - t)));
  const daypart = near(rises) < TWILIGHT ? 'dawn' : near(sets) < TWILIGHT ? 'dusk' : kind === 'rise' ? 'day' : 'night';
  if (kind === 'rise') return { daypart, sunArc: span, moonArc: .5 };
  return { daypart, moonArc: clamp(span, 0, 1), sunArc: now - from < to - now ? 1 + (now - from) / length : -(to - now) / length };
}

// Fraction of the synodic month since a known new moon (0 new, .5 full).
const moonPhase = now => (((now - Date.UTC(2000, 0, 6, 18, 14)) / 864e5 / 29.530588853) % 1 + 1) % 1;
function moonSvg(phase, south) {
  const waxing = phase < .5, crescent = phase < .25 || phase > .75;
  const rx = Math.abs(Math.cos(phase * 2 * Math.PI)) * 50;
  const lit = `M50 0A50 50 0 0 ${waxing ? 1 : 0} 50 100A${rx.toFixed(2)} 50 0 0 ${waxing === crescent ? 0 : 1} 50 0Z`;
  return `<svg viewBox="0 0 100 100"${south ? ' style="scale:-1 1"' : ''}><circle class="moon-dark" cx="50" cy="50" r="50"/><path class="moon-lit" d="${lit}"/></svg>`;
}

// ------------------------------------------------------------------ drawing
const rng = seed => () => { seed = (seed + 0x6d2b79f5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
const dark = s => s.daypart === 'dusk' || s.daypart === 'night' || s.weather === 'storm';
const clamp = (v, a, b) => Math.max(a, Math.min(b, v));

const CLOUD = {
  day: ['#ffffff', '#e2e8ed'], dawn: ['#fff3ec', '#ecd3cf'], dusk: ['#7d6478', '#4a4560'], night: ['#2f3d52', '#223045']
};
const GREY = { day: ['#f6f7f8', '#c3cad1'], dawn: ['#efe9e9', '#cfc9cc'], dusk: ['#4a4a5a', '#363948'], night: ['#253244', '#1a2535'] };
const STORM = { day: ['#4d5765', '#353e4a'], dawn: ['#4d5765', '#353e4a'], dusk: ['#4a5160', '#2b323d'], night: ['#3a4452', '#1c232d'] };

// One cloud: a domed row of puffs on a flat base, shaded light to dark, then softened.
// Overcast weather draws long flat banks; clear and cloudy skies draw cumulus.
function cloudSprite(rand, [light, shade], bank) {
  const w = 560, h = 240, base = h * .7, left = w * .12, right = w * .88;
  const shape = document.createElement('canvas');
  shape.width = w; shape.height = h;
  const s = shape.getContext('2d');
  const fill = s.createLinearGradient(0, h * .2, 0, base);
  fill.addColorStop(0, light); fill.addColorStop(1, shade);
  s.fillStyle = fill;
  s.beginPath();
  s.rect(0, 0, w, base);
  s.clip();
  s.beginPath();
  const slab = h * .12;
  if (s.roundRect) s.roundRect(left + 30, base - slab, right - left - 60, slab * 2, slab); else s.rect(left + 30, base - slab, right - left - 60, slab);
  const n = bank ? 10 : 7 + Math.floor(rand() * 3);
  for (let i = 0; i < n; i++) {
    const u = (i + .5) / n, dome = 1 - Math.abs(u - .5) * (bank ? .6 : 1.3);
    const r = h * (bank ? .13 + .08 * rand() : .1 + .15 * rand()) * (.6 + .6 * dome);
    const x = left + (right - left) * u + (rand() - .5) * 24, y = base - r * .55 - rand() * h * (bank ? .02 : .06);
    s.moveTo(x + r, y); s.arc(x, y, r, 0, 6.2832);
  }
  s.fill();
  const c = document.createElement('canvas');
  c.width = w; c.height = h;
  const g = c.getContext('2d');
  if ('filter' in g) { g.filter = 'blur(9px)'; g.drawImage(shape, 0, 0); }
  else { g.shadowColor = light; g.shadowBlur = 18; g.shadowOffsetX = w; g.drawImage(shape, -w, 0); }
  return c;
}

class Layer {
  constructor(canvas, { echo = false } = {}) {
    this.canvas = canvas; this.ctx = canvas.getContext('2d'); this.echo = echo;
    this.visible = false; this.w = 0; this.h = 0; this.clouds = []; this.drops = []; this.flakes = [];
  }
  resize() {
    const r = this.canvas.getBoundingClientRect();
    const dpr = Math.min(devicePixelRatio || 1, 2);
    if (!r.width || !r.height) return;
    this.w = r.width; this.h = r.height;
    this.canvas.width = Math.round(r.width * dpr); this.canvas.height = Math.round(r.height * dpr);
    this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    if (this.state) this.configure(this.state);
  }
  configure(s) {
    this.state = s;
    if (!this.w) return;
    const rand = rng(7), { w, h } = this, area = w * Math.min(h, 1400);
    const wind = clamp(s.wind ?? 12, 0, 60);
    this.speed = 5 + wind * .45;
    this.slant = clamp(wind / 90, .06, .38);
    // Clouds: few on a clear day, a full deck for rain and storm. The echo draws weather only.
    const counts = { clear: Math.round((s.cover ?? 20) / 22), cloudy: 10, fog: 5, rain: 10, snow: 8, storm: 12 };
    const alpha = { clear: .7, cloudy: .85, fog: .35, rain: .6, snow: .65, storm: .7 }[s.weather];
    const palette = (s.weather === 'storm' ? STORM : s.weather === 'clear' ? CLOUD : GREY)[s.daypart];
    const bank = s.weather !== 'clear' && s.weather !== 'cloudy';
    const n = this.echo ? 0 : Math.round(counts[s.weather] * clamp(w / 1440, .55, 1.3));
    const sprites = Array.from({ length: Math.min(n, 4) }, () => cloudSprite(rand, palette, bank));
    this.clouds = Array.from({ length: n }, (_, i) => {
      const depth = .55 + rand() * .7, scale = (bank ? .6 + rand() * .6 : .8 + rand() * .7) * clamp(w / 1200, .7, 1.2) * depth;
      return { img: sprites[i % sprites.length], x: rand() * (w + 400) - 200, y: -60 + rand() * Math.min(h * .5, 520), scale, stretch: bank ? 1.5 + rand() * .6 : 1, depth, a: alpha * (.55 + .45 * depth) };
    }).sort((a, b) => a.depth - b.depth);
    // Precipitation, sized to the area and capped so a phone and a 5K screen cost about the same.
    const heavy = clamp(.7 + (s.precip ?? 1) / 3, .7, 1.4) * (s.weather === 'storm' ? 1.35 : 1) * (this.echo ? .7 : 1);
    const raining = s.weather === 'rain' || s.weather === 'storm';
    this.drops = raining ? Array.from({ length: Math.round(clamp(area / 7000, 40, 150) * heavy) }, () => ({
      x: rand() * w, y: rand() * h, len: 10 + rand() * 12, v: 560 + rand() * 300, near: rand() < .35
    })) : [];
    this.flakes = s.weather === 'snow' ? Array.from({ length: Math.round(clamp(area / 9000, 30, 120) * (this.echo ? .7 : 1)) }, () => ({
      x: rand() * w, y: rand() * h, r: .8 + rand() * 1.8, v: 16 + rand() * 30, sway: 8 + rand() * 18, f: .3 + rand() * .7, p: rand() * 6.3
    })) : [];
    this.rain = dark(s) || this.echo ? ['rgba(205,218,232,.16)', 'rgba(215,226,238,.3)'] : ['rgba(64,84,104,.16)', 'rgba(58,78,98,.3)'];
    this.snow = dark(s) || this.echo ? 'rgba(244,240,232,.85)' : 'rgba(255,255,255,.95)';
    this.snowShade = dark(s) || this.echo ? null : 'rgba(90,108,124,.25)';
    this.t = 0;
    this.animated = this.clouds.length + this.drops.length + this.flakes.length > 0;
    this.draw();
  }
  step(dt) {
    const { w, h } = this;
    this.t += dt;
    for (const c of this.clouds) {
      c.x += this.speed * c.depth * dt;
      if (c.x > w + 40) c.x = -c.img.width * c.scale * c.stretch - 40;
    }
    for (const d of this.drops) {
      d.y += d.v * dt * (d.near ? 1.15 : 1); d.x += d.v * this.slant * dt;
      if (d.y > h) { d.y = -d.len; d.x = Math.random() * (w + 200) - 200; }
      if (d.x > w) d.x -= w + 100;
    }
    for (const f of this.flakes) {
      f.y += f.v * dt; f.x += Math.sin(this.t * f.f + f.p) * f.sway * dt + this.speed * .2 * dt;
      if (f.y > h + 4) { f.y = -4; f.x = Math.random() * w; }
      if (f.x > w + 4) f.x = -4;
    }
  }
  draw() {
    const { ctx, w, h } = this;
    ctx.clearRect(0, 0, w, h);
    for (const c of this.clouds) {
      ctx.globalAlpha = c.a;
      ctx.drawImage(c.img, c.x, c.y, c.img.width * c.scale * c.stretch, c.img.height * c.scale);
    }
    ctx.globalAlpha = 1;
    if (this.drops.length) {
      ctx.lineWidth = 1; ctx.lineCap = 'round';
      for (const near of [false, true]) {
        ctx.strokeStyle = this.rain[near ? 1 : 0];
        ctx.beginPath();
        for (const d of this.drops) if (d.near === near) { ctx.moveTo(d.x, d.y); ctx.lineTo(d.x + d.len * this.slant, d.y + d.len); }
        ctx.stroke();
      }
    }
    if (this.flakes.length) {
      for (const [color, dy] of [[this.snowShade, .8], [this.snow, 0]]) {
        if (!color) continue;
        ctx.fillStyle = color;
        ctx.beginPath();
        for (const f of this.flakes) { ctx.moveTo(f.x + f.r, f.y + dy); ctx.arc(f.x, f.y + dy, f.r, 0, 6.2832); }
        ctx.fill();
      }
    }
  }
}

// ------------------------------------------------------------------ one clock for every layer
const layers = [];
let raf = 0, last = 0, nextFlash = 0;
const running = () => !document.hidden && !reduced() && layers.some(l => l.visible && l.animated);
function frame(t) {
  const dt = Math.min(.05, (t - last) / 1000);
  last = t;
  for (const l of layers) if (l.visible && l.animated) { l.step(dt); l.draw(); }
  if (current?.weather === 'storm' && t > nextFlash) flash(t);
  raf = running() ? requestAnimationFrame(frame) : 0;
}
function kick() {
  if (running()) { if (!raf) { last = performance.now(); raf = requestAnimationFrame(frame); } }
  else { cancelAnimationFrame(raf); raf = 0; }
}
// A soft double flicker every 7 to 16 seconds: well under the three-flashes-a-second limit.
function flash(t) {
  nextFlash = t + 7000 + Math.random() * 9000;
  if (t < 2500) return; // never on arrival
  for (const el of document.querySelectorAll('.sky-flash')) {
    el.animate([{ opacity: 0 }, { opacity: .3, offset: .06 }, { opacity: .04, offset: .18 }, { opacity: .2, offset: .28 }, { opacity: 0 }], { duration: 1100, easing: 'ease-out' });
  }
}

// ------------------------------------------------------------------ wiring
let current = null;
const override = (() => {
  const q = new URLSearchParams(location.search);
  const sky = q.get('sky'), daypart = q.get('daypart');
  return { weather: WEATHERS.includes(sky) ? sky : null, daypart: DAYPARTS.includes(daypart) ? daypart : null, offline: sky === 'offline' };
})();

function resolve(data) {
  const now = Date.now();
  const tod = timeOfDay(now, data?.rises ? data : clockSuns(now));
  // A forced daypart parks the sun or moon where that daypart would have it.
  const forced = { dawn: { sunArc: .02 }, day: { sunArc: .4 }, dusk: { sunArc: .98 }, night: { moonArc: .35 } }[override.daypart];
  return {
    sunArc: .5, moonArc: .5, ...(forced ? {} : tod), ...forced,
    daypart: override.daypart || tod.daypart,
    weather: override.weather || data?.weather || 'clear',
    cover: data?.cover, precip: data?.precip, wind: data?.wind, live: !!data
  };
}

function apply(s) {
  const changed = !current || current.daypart !== s.daypart || current.weather !== s.weather || current.cover !== s.cover;
  current = s;
  root.dataset.daypart = s.daypart;
  root.dataset.weather = s.weather;
  // Light travels from the sun's (or moon's) side: 100deg low in the east, 180deg overhead, 260deg low in the west.
  const night = s.daypart === 'night', sun = clamp(s.sunArc, -.07, 1.07);
  root.style.setProperty('--sun-angle', `${Math.round(100 + 160 * clamp(night ? s.moonArc : s.sunArc, 0, 1))}deg`);
  for (const sky of skies) {
    sky.style.setProperty('--sun-p', clamp(sun, 0, 1).toFixed(3));
    sky.style.setProperty('--sun-lift', Math.sin(Math.PI * sun).toFixed(3));
    sky.style.setProperty('--moon-q', s.moonArc.toFixed(3));
    sky.style.setProperty('--moon-lift', Math.sin(Math.PI * s.moonArc).toFixed(3));
  }
  echo();
  if (changed) for (const l of layers) l.configure(s);
  if (s.live && !override.daypart && !override.weather) {
    try { sessionStorage.setItem(STATE, JSON.stringify({ at: Date.now(), daypart: s.daypart, weather: s.weather })); } catch {}
  }
  kick();
}

// The closing section repeats the weather faintly: rain, snow, fog, a storm's flicker, or the night's stars.
let echoEl = null;
function echo() {
  const closing = document.querySelector('.closing');
  if (!closing) return;
  const wanted = current.weather !== 'clear' && current.weather !== 'cloudy' || current.daypart === 'night';
  if (!wanted) { echoEl?.remove(); echoEl = null; const i = layers.findIndex(l => l.echo); if (i >= 0) layers.splice(i, 1); return; }
  if (echoEl) return;
  echoEl = document.createElement('div');
  echoEl.className = 'sky-echo';
  echoEl.setAttribute('aria-hidden', 'true');
  echoEl.innerHTML = '<div class="sky-echo-stars"></div><canvas></canvas><div class="sky-flash"></div>';
  closing.prepend(echoEl);
  watch(echoEl.querySelector('canvas'), { echo: true });
}

const seen = 'IntersectionObserver' in window ? new IntersectionObserver(entries => {
  for (const en of entries) { const l = layers.find(x => x.canvas === en.target); if (l) l.visible = en.isIntersecting; }
  kick();
}) : null;
const sized = 'ResizeObserver' in window ? new ResizeObserver(entries => {
  for (const en of entries) layers.find(x => x.canvas === en.target)?.resize();
}) : null;
function watch(canvas, opts) {
  const l = new Layer(canvas, opts);
  layers.push(l);
  l.resize();
  if (current) l.configure(current);
  if (seen) seen.observe(canvas); else l.visible = true;
  sized?.observe(canvas);
}

function start() {
  const south = place()[0] < 0, phase = moonPhase(Date.now());
  for (const sky of skies) {
    const moon = sky.querySelector('.sky-moon');
    if (moon) moon.innerHTML = moonSvg(phase, south);
    const canvas = sky.querySelector('.sky-canvas');
    if (canvas) watch(canvas);
  }
  // The header turns to dark glass while it scrolls over a dark sky.
  const end = document.querySelector('.sky-end');
  if (end && seen) {
    const header = document.querySelector('.header');
    new IntersectionObserver(([en]) => {
      root.classList.toggle('sky-behind-header', en.boundingClientRect.top > (header?.offsetHeight ?? 76) / 2);
    }).observe(end);
  }
  document.addEventListener('visibilitychange', kick);
  const redraw = () => { for (const l of layers) l.draw(); kick(); };
  systemReduce.addEventListener('change', redraw);
  new MutationObserver(redraw).observe(root, { attributes: true, attributeFilter: ['class'] });

  apply(resolve(null));
  let data = null;
  const refresh = () => apply(resolve(data));
  if (!override.offline && !(override.weather && override.daypart)) {
    conditions().then(d => { data = d; refresh(); }).catch(() => {});
  }
  setInterval(refresh, 5 * 60e3); // keep the sun moving on a page left open
}

if (skies.length) start();
