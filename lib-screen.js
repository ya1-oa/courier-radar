// OCR-only state detection for user-initiated iOS Shortcuts screenshots.
// Never infer acceptance from a disappearing offer or a new Uber notification.
import { parseOfferText } from './lib-parser.js';
const has=(s,re)=>re.test(s);
export function inspectUberScreen(text){
 const raw=String(text||'').replace(/\r/g,'').trim();
 if(!raw)return {kind:'unknown',confidence:0,reason:'No readable text'};
 const offer=parseOfferText(raw);
 const hasOfferControls=has(raw,/\b(?:accept(?:\s+request)?|decline|reject|exclusive|match(?:\s+request)?|includes? expected tip|delivery\s*\(\s*\d+\s*\))\b/i);
 if(Number(offer.payout)>0&&Number(offer.miles)>0&&Number(offer.etaMinutes)>0&&(hasOfferControls||offer.confidence>=.82))return {kind:'offer',confidence:offer.confidence,parsed:offer};
 const complete=has(raw,/\b(?:delivery\s+(?:completed|complete|finished)|trip\s+completed|order\s+delivered|delivered\s+successfully|you\s+(?:have\s+)?completed\s+(?:the|this|your)\s+delivery)\b/i)
   &&!has(raw,/\b(?:mark\s+as\s+delivered|confirm\s+delivery|slide\s+to\s+complete|complete\s+delivery|how\s+to\s+complete)\b/i);
 if(complete)return {kind:'lifecycle',stage:'delivered',confidence:.96,reason:'Explicit Uber completion confirmation'};
 if(has(raw,/\b(?:head\s+to\s+(?:the\s+)?(?:drop.?off|customer)|navigate\s+to\s+(?:the\s+)?(?:drop.?off|customer)|en\s+route\s+to\s+(?:the\s+)?customer|leave\s+at\s+door|meet\s+at\s+door|start\s+delivery|drop.?off\s+instructions)\b/i))
   return {kind:'lifecycle',stage:'picked_up',confidence:.84,reason:'Drop-off/navigation screen'};
 if(has(raw,/\b(?:confirm\s+pickup|verify\s+order|ready\s+for\s+pickup|swipe\s+to\s+pick.?up|pickup\s+code|pick.?up\s+instructions)\b/i))
   return {kind:'lifecycle',stage:'arrived',confidence:.82,reason:'Pickup confirmation screen'};
 if(has(raw,/\b(?:navigate\s+to\s+pickup|head\s+to\s+(?:the\s+)?(?:pickup|restaurant)|on\s+(?:your|the)\s+way\s+to\s+pickup|proceed\s+to\s+pickup)\b/i))
   return {kind:'lifecycle',stage:'accepted',confidence:.85,reason:'Pickup navigation screen'};
 return {kind:'unknown',confidence:0,reason:'No trustworthy offer or lifecycle evidence'};
}
// Monotonic states. Screenshots cannot skip prerequisite phases or change closed orders.
export function screenTransition(current,observed){
 const rank={observed:0,accepted:1,arrived:2,picked_up:3,delivered:4};
 if(!(current in rank)||!(observed in rank))return null;
 if(rank[observed]!==rank[current]+1)return null;
 return observed;
}
