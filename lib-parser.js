import {evaluateOffer} from './lib-offer-policy.js';
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
  const isAddOn = /add a delivery|add-on|additional delivery|\+\s*\$[0-9]/i.test(text);
  const stackMatch = text.match(/\b(\d+)\s+(?:deliveries|orders|stops)\b/i) || text.match(/\bdelivery\s*\(\s*(\d+)\s*\)/i);
  const stackCount = stackMatch ? Math.max(1, Number(stackMatch[1])) : 1;
  const offerKind = isAddOn ? 'addon' : stackCount > 1 ? 'stack' : 'single';
  const isAddressLike = line => /\b\d{2,6}\s+[A-Za-z0-9.' -]+\b(?:st|street|ave|avenue|blvd|boulevard|rd|road|dr|drive|way|ln|lane|ct|court|pl|place|pkwy|parkway|hwy|highway)\b/i.test(line)
    || /\b(?:st|street|ave|avenue|blvd|boulevard|rd|road|dr|drive|way|ln|lane|ct|court|pl|place|pkwy|parkway|hwy|highway)\b.*&|&.*\b(?:st|street|ave|avenue|blvd|boulevard|rd|road|dr|drive|way|ln|lane|ct|court|pl|place|pkwy|parkway|hwy|highway)\b/i.test(line)
    || /\b[A-Za-z .'-]+,\s*(?:Los Angeles|Culver City|Santa Monica|Beverly Hills|West Hollywood)\b/i.test(line);
  const plausibleMerchant = line => line.length >= 2 && line.length <= 64 && !NOISE.some(re => re.test(line)) && !isAddressLike(line) && !/^\W+$/.test(line) && /[A-Za-z]/.test(line) && !/\b5g\b|°|^\d+%?$|^[A-Z]{1,3}\d?$/.test(line);
  const summaryIndex = lines.findIndex(line => /\b\d+\s*(?:min|mins|minutes?)\b.*\b\d+(?:\.\d+)?\s*(?:mi|miles?)\b.*\btotal\b/i.test(line));
  let merchantIndex = -1;
  if (summaryIndex >= 0) {
    for (let i = summaryIndex + 1; i < Math.min(lines.length, summaryIndex + 7); i++) {
      if (plausibleMerchant(lines[i])) { merchantIndex = i; break; }
    }
  }
  const candidateLines = lines.filter(plausibleMerchant);
  const merchant = merchantIndex >= 0 ? lines[merchantIndex] : (candidateLines[0] || null);
  const addressLines = lines.map((line,index)=>({line,index})).filter(({line,index})=>isAddressLike(line) && (merchantIndex < 0 || index > merchantIndex));
  const destinationText = addressLines.length ? addressLines[addressLines.length - 1].line : null;
  let confidence = 0;
  if (payout != null) confidence += 0.38;
  if (miles != null) confidence += 0.28;
  if (etaMinutes != null) confidence += 0.18;
  if (merchant) confidence += 0.16;
  return { payout, miles, etaMinutes, merchant, destinationText, isShop, itemCount, isAddOn, stackCount, offerKind, confidence: Number(Math.min(confidence, 1).toFixed(2)), rawText: text };
}

export function effectiveOfferRate({payout,miles,etaMinutes,isShop,itemCount,mode='normal'}){
 const assessment=evaluateOffer({payout,miles,uberMinutes:etaMinutes,isShop});
 if(assessment.hourlyGross==null)return null;
 return {effectiveMinutes:assessment.adjustedMinutes,
  dollarsPerHour:assessment.hourlyGross,dollarsPerMile:assessment.dollarsPerMile,
  verdict:assessment.verdict,bufferPercent:assessment.bufferPercent};
}

export function decisionForOffer({dollarsPerHour,dollarsPerMile}){
 const hour=Number(dollarsPerHour),mile=Number(dollarsPerMile);
 if(!Number.isFinite(hour)||!Number.isFinite(mile))return {verdict:'CHECK',reason:'missing_hour_or_mileage'};
 return {verdict:hour>=24&&mile>=1.5?'TAKE':hour>=20?'BORDERLINE':'SKIP',
  hourlyFloor:24,mileageFloor:1.5};
}
