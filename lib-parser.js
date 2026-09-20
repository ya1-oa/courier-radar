const MONEY = /\$\s*([0-9]+(?:\.[0-9]{1,2})?)/gi;
const MILES = /([0-9]+(?:\.[0-9]+)?)\s*(?:mi|miles?)\b/i;
const MINUTES = /([0-9]+)\s*(?:min|mins|minutes?)\b/i;

const NOISE = [
  /uber\s*eats/i, /delivery/i, /exclusive/i, /accept/i, /decline/i,
  /includes? expected tip/i, /estimated/i, /total/i, /miles?\b/i,
  /minutes?\b/i, /customer/i, /pickup/i, /drop.?off/i, /you(?:'|’)re/i,
  /match/i, /radar/i, /shop\s*&?\s*pay/i, /items?\b/i,
  /^\s*\$?[0-9.,]+\s*$/, /^\s*\d{1,2}:\d{2}\s*(?:am|pm)?\s*$/i
];

export function parseOfferText(rawText = '') {
  const text = String(rawText || '').replace(/\r/g, '');
  const lines = text.split('\n').map(s => s.trim()).filter(Boolean);
  const payouts = [...text.matchAll(MONEY)].map(m => Number(m[1])).filter(n => Number.isFinite(n) && n > 0 && n < 500);
  const payout = payouts.length ? Math.max(...payouts) : null;
  const milesMatch = text.match(MILES);
  const miles = milesMatch ? Number(milesMatch[1]) : null;
  const minuteMatches = [...text.matchAll(new RegExp(MINUTES.source, 'gi'))].map(m => Number(m[1])).filter(n => Number.isFinite(n) && n > 0 && n < 240);
  const etaMinutes = minuteMatches.length ? Math.min(...minuteMatches) : null;
  const isShop = /shop\s*&?\s*pay|shopping|\b\d+\s+items?\b/i.test(text);
  const itemMatch = text.match(/\b(\d+)\s+items?\b/i);
  const itemCount = itemMatch ? Number(itemMatch[1]) : null;
  const candidateLines = lines.filter(line => line.length >= 2 && line.length <= 64 && !NOISE.some(re => re.test(line)) && !/^\W+$/.test(line) && /[A-Za-z]/.test(line));
  const merchant = candidateLines[0] || null;
  let confidence = 0;
  if (payout != null) confidence += 0.38;
  if (miles != null) confidence += 0.28;
  if (etaMinutes != null) confidence += 0.18;
  if (merchant) confidence += 0.16;
  return { payout, miles, etaMinutes, merchant, isShop, itemCount, confidence: Number(Math.min(confidence, 1).toFixed(2)), rawText: text };
}

export function effectiveOfferRate({ payout, miles, etaMinutes, isShop, itemCount, mode = 'normal' }) {
  if (!(payout > 0)) return null;
  const rideMinutes = etaMinutes ?? ((miles || 0) / 11.5) * 60 + 5;
  const shoppingPenalty = isShop ? Math.max(8, Math.min(25, (itemCount || 6) * 1.2)) : 0;
  const repositionPenalty = mode === 'escape' ? 2 : 5;
  const effectiveMinutes = Math.max(1, rideMinutes + shoppingPenalty + repositionPenalty);
  return { effectiveMinutes: Number(effectiveMinutes.toFixed(1)), dollarsPerHour: Number((payout / effectiveMinutes * 60).toFixed(2)) };
}


export function decisionForOffer({ dollarsPerHour, target = 35, mode = 'normal' }) {
  const rate = Number(dollarsPerHour);
  const goal = Math.max(1, Number(target) || 35);
  if (!Number.isFinite(rate)) return { verdict: 'SKIP', floor: null, borderlineFloor: null, reason: 'missing_rate' };

  // $35/hr is the rolling online-income goal, not a literal per-order minimum.
  // As the market slows, rejecting an offer carries a larger expected idle-time cost.
  const takeFactor = mode === 'escape' ? 0.62 : mode === 'slow' ? 0.72 : 0.80;
  const borderlineFactor = Math.max(0.50, takeFactor - 0.10);
  const floor = goal * takeFactor;
  const borderlineFloor = goal * borderlineFactor;

  const verdict = rate >= floor ? 'TAKE' : rate >= borderlineFloor ? 'BORDERLINE' : 'SKIP';
  return {
    verdict,
    floor: Number(floor.toFixed(2)),
    borderlineFloor: Number(borderlineFloor.toFixed(2)),
    target: goal,
    mode
  };
}
