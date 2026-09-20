import crypto from 'node:crypto';

export function cors(res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Headers', 'content-type,x-capture-token');
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,OPTIONS');
}
export function tokenFrom(req) { return req.headers['x-capture-token'] || req.query?.token || null; }
export function requireToken(req, res) {
  const expected = process.env.CAPTURE_TOKEN, provided = tokenFrom(req);
  if (!expected) { res.status(500).json({ error: 'CAPTURE_TOKEN is not configured.' }); return null; }
  if (!provided || provided !== expected) { res.status(401).json({ error: 'Unauthorized' }); return null; }
  return crypto.createHash('sha256').update(provided).digest('hex').slice(0, 24);
}
function supabaseServerKey() {
  return process.env.SUPABASE_SECRET_KEY || process.env.SUPABASE_SERVICE_ROLE_KEY || '';
}
export function dbConfigured() { return Boolean(process.env.SUPABASE_URL && supabaseServerKey()); }

async function sbFetch(path, options = {}) {
  const base = process.env.SUPABASE_URL?.replace(/\/$/, ''), key = supabaseServerKey();
  if (!base || !key) throw new Error('Supabase is not configured');
  const authHeaders = key.startsWith('eyJ') ? { Authorization: `Bearer ${key}` } : {};
  const res = await fetch(`${base}/rest/v1/${path}`, {
    ...options,
    headers: {
      apikey: key,
      ...authHeaders,
      'Content-Type': 'application/json',
      Prefer: options.prefer || 'return=representation',
      ...(options.headers || {})
    }
  });
  if (!res.ok) throw new Error(`Supabase ${res.status}: ${await res.text()}`);
  const text = await res.text(); return text ? JSON.parse(text) : null;
}
export async function insert(table, row) { return sbFetch(table, { method: 'POST', body: JSON.stringify(row) }); }
export async function select(path) { return sbFetch(path, { method: 'GET', prefer: 'return=minimal' }); }
export async function patch(path, body) { return sbFetch(path, { method: 'PATCH', body: JSON.stringify(body) }); }
export async function upsert(table, row, onConflict) { return sbFetch(`${table}${onConflict?`?on_conflict=${encodeURIComponent(onConflict)}`:''}`, { method: 'POST', body: JSON.stringify(row), headers: { Prefer: 'resolution=merge-duplicates,return=representation' } }); }

export async function bodyOf(req) {
  const existing = req?.body;
  if (existing && typeof existing === 'object' && !Buffer.isBuffer(existing) && !(existing instanceof Uint8Array)) return existing;
  if (typeof existing === 'string') {
    try { return JSON.parse(existing); } catch { return {}; }
  }
  if (Buffer.isBuffer(existing) || existing instanceof Uint8Array) {
    try { return JSON.parse(Buffer.from(existing).toString('utf8')); } catch { return {}; }
  }
  if (!req || typeof req[Symbol.asyncIterator] !== 'function') return {};
  try {
    const chunks = [];
    for await (const chunk of req) chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
    if (!chunks.length) return {};
    return JSON.parse(Buffer.concat(chunks).toString('utf8'));
  } catch {
    return {};
  }
}

export function zoneHintFromText(text='') {
  const value=String(text||'').toLowerCase();
  const hints=[
    ['Downtown Culver',/(downtown\s+culver|culver\s+city)/i],
    ['Palms / Venice',/(\bpalms\b|\bvenice\b)/i],
    ['Fox Hills',/(fox\s+hills|westfield\s+culver)/i],
    ['Koreatown',/(koreatown|\bktown\b)/i],
    ['USC',/(\busc\b|university\s+park)/i],
    ['DTLA',/(\bdtla\b|downtown\s+los\s+angeles)/i]
  ];
  return hints.find(([,re])=>re.test(value))?.[0]||null;
}

export function zoneFor(lat, lng) {
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return 'Unknown';
  const zones = [['Downtown Culver',34.0211,-118.3965],['Palms / Venice',34.0228,-118.4200],['Fox Hills',33.9895,-118.3910],['Koreatown',34.0638,-118.3008],['USC',34.0224,-118.2851],['DTLA',34.0467,-118.2500]];
  let best=['Learning zone',Infinity];
  for (const [name,zlat,zlng] of zones) { const d=haversine(lat,lng,zlat,zlng); if (d<best[1]) best=[name,d]; }
  return best[1] <= 2.2 ? best[0] : 'Learning zone';
}
function haversine(lat1,lon1,lat2,lon2){const r=3958.8,p1=lat1*Math.PI/180,p2=lat2*Math.PI/180,dp=(lat2-lat1)*Math.PI/180,dl=(lon2-lon1)*Math.PI/180,a=Math.sin(dp/2)**2+Math.cos(p1)*Math.cos(p2)*Math.sin(dl/2)**2;return 2*r*Math.asin(Math.sqrt(a));}
