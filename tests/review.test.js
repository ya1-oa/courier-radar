import test from 'node:test';
import assert from 'node:assert/strict';
import {buildReview,mathNudges,mergeNudges,learnedMultipliers,marketZone,tierFor,aiCritique,laDay} from '../lib-review.js';

// Tuesday 2026-10-27, 12:00-14:00 LA (19:00-21:00 UTC): a LUNCH session.
const T=m=>new Date(Date.UTC(2026,9,27,19,0)+m*60000).toISOString();
const CULVER={lat:34.0211,lng:-118.3965},FOX={lat:33.990,lng:-118.391};
const shift={id:'s1',started_at:T(0),ended_at:T(120)};
function fixture(){
 const offers=[
  // Good take: $12 for ~13 min cycle.
  {id:'o1',captured_at:T(5),payout:12,miles:1,eta_minutes:10,merchant:'Philz Coffee',state:'delivered',...CULVER},
  // Weak take: $4 for a 30 min cycle.
  {id:'o2',captured_at:T(40),payout:4,miles:3,eta_minutes:27,merchant:'Erewhon',state:'delivered',...CULVER},
  // Costly skip: $15 for 13 min, nothing taken afterwards.
  {id:'o3',captured_at:T(80),payout:15,miles:1,eta_minutes:10,merchant:'Tender Greens',state:'rejected',...CULVER}
 ];
 const events=[
  {offer_id:'o1',event:'accepted',captured_at:T(5)},{offer_id:'o1',event:'arrived',captured_at:T(8)},
  {offer_id:'o1',event:'picked_up',captured_at:T(20)},{offer_id:'o1',event:'delivered',captured_at:T(28)},
  {offer_id:'o2',event:'accepted',captured_at:T(40)},{offer_id:'o2',event:'delivered',captured_at:T(70)},
  {offer_id:'o3',event:'rejected',captured_at:T(80)}
 ];
 // GPS every 5 min; the last 40 minutes idle in Fox Hills.
 const presence=[];for(let m=0;m<=120;m+=5)presence.push({captured_at:T(m),...(m>=80?FOX:CULVER)});
 // 30-day history: Culver lunch busy, Fox Hills lunch quiet (1 offer in 3 hours).
 const hp=[],ho=[];
 for(let d=1;d<=3;d++){for(let m=0;m<=60;m+=5){hp.push({captured_at:new Date(Date.parse(T(m))-d*86400000).toISOString(),...CULVER});hp.push({captured_at:new Date(Date.parse(T(m))-(d+3)*86400000).toISOString(),...FOX})}}
 for(let d=1;d<=3;d++)for(let k=0;k<6;k++)ho.push({captured_at:new Date(Date.parse(T(k*9))-d*86400000).toISOString(),payout:9,...CULVER});
 ho.push({captured_at:new Date(Date.parse(T(30))-4*86400000).toISOString(),payout:9,...FOX});
 const logs=[{action:'TAKE',evidence:{offerId:'o1'}},{action:'SKIP',evidence:{offerId:'o2'}},{action:'TAKE',evidence:{offerId:'o3'}}];
 return {offers,events,presence,logs,history:{presence:hp,offers:ho}};
}

test('zone keys match the native MarketZone names',()=>{
 assert.equal(marketZone(CULVER.lat,CULVER.lng),'Culver City');
 assert.equal(marketZone(FOX.lat,FOX.lng),'Fox Hills');
 assert.equal(marketZone(NaN,1),null);
 assert.match(marketZone(34.4,-118.9),/^Area /);
});
test('workday rolls over at 04:00 Los Angeles time',()=>{
 assert.equal(laDay('2026-10-28T10:30:00Z'),'2026-10-27'); // 03:30 LA
 assert.equal(laDay('2026-10-28T11:30:00Z'),'2026-10-28'); // 04:30 LA
});
test('session review measures decisions, grades them and prices mistakes',()=>{
 const r=buildReview({...fixture(),shifts:[shift],scope:'session',plannedHours:8});
 assert.equal(r.metrics.orders,2);assert.equal(r.metrics.earnings,16);
 assert.equal(r.metrics.onlineMinutes,120);assert.equal(r.metrics.dph,8);
 assert.equal(r.metrics.acceptance,round(2/3));
 const grade=Object.fromEntries(r.decisions.map(d=>[d.merchant,d.grade]));
 assert.equal(grade['Philz Coffee'],'good take');
 assert.equal(grade['Erewhon'],'weak take');
 assert.equal(grade['Tender Greens'],'costly skip');
 // Radar said SKIP on Erewhon and TAKE on Tender Greens: both overridden.
 assert.equal(r.metrics.followedRadar,1);assert.equal(r.metrics.overrodeRadar,2);
 const kinds=r.mistakes.map(m=>m.kind);
 assert.ok(kinds.includes('slow pickup'),'12 min restaurant wait is a mistake');
 assert.ok(kinds.includes('costly skip'));
 assert.ok(kinds.includes('dead zone'),'40 idle minutes in a historically quiet zone');
 assert.ok(r.estimate.upside>0);assert.equal(r.estimate.potentialEarnings,round(16+r.estimate.upside));
 assert.ok(['D','F'].includes(r.tier),`a $8/h session should grade low, got ${r.tier} ${r.score}`);
 assert.ok(r.segments.some(s=>s.zone==='Fox Hills'&&s.idleMinutes>=30));
});
test('day review prefers the Uber daily total over captured payouts',()=>{
 const r=buildReview({...fixture(),shifts:[shift],scope:'day',snapshotTotal:30});
 assert.equal(r.metrics.earnings,30);assert.equal(r.metrics.earningsSource,'uber_daily_total');
 assert.equal(r.rubric.targets.grossTarget,270);
});
test('tier thresholds',()=>{
 assert.equal(tierFor(95),'S');assert.equal(tierFor(80),'A');assert.equal(tierFor(67),'C');assert.equal(tierFor(5),'F');
});
test('tuning is bounded per day, limited to observed zone/blocks, and bounded overall',()=>{
 const r=buildReview({...fixture(),shifts:[shift],scope:'day'});
 const math=mathNudges(r);
 for(const v of Object.values(math))assert.ok(v>=.95&&v<=1.05);
 const allowed=new Set(r.zoneBlocks.map(z=>z.key));
 const merged=mergeNudges(math,[{key:'Fox Hills|LUNCH',multiplier:.5},{key:'Mars|LUNCH',multiplier:.9}],allowed);
 assert.ok(merged['Fox Hills|LUNCH']>=.9&&merged['Fox Hills|LUNCH']<1);
 assert.equal(merged['Mars|LUNCH'],undefined);
 const days=Array.from({length:10},()=>({adjustments:{'Fox Hills|LUNCH':.9}}));
 assert.equal(learnedMultipliers(days)['Fox Hills|LUNCH'],.7);
 assert.equal(learnedMultipliers([{adjustments:{'X|LUNCH':2}}])['X|LUNCH'],1.1);
});
test('AI critique is optional, schema-bounded and never throws',async()=>{
 const r=buildReview({...fixture(),shifts:[shift],scope:'day'});
 assert.deepEqual(await aiCritique({session:r,day:r,learned:{}},{key:''}),{configured:false});
 const failed=await aiCritique({session:r,day:r,learned:{}},{key:'k',fetcher:async()=>{throw Error('down')}});
 assert.equal(failed.configured,true);assert.ok(failed.error);
 let sent=null;
 const ok=await aiCritique({session:r,day:r,learned:{}},{key:'k',fetcher:async(_,init)=>{sent=JSON.parse(init.body);return {ok:true,json:async()=>({status:'completed',output:[{type:'message',content:[{type:'output_text',text:JSON.stringify({headline:'x'.repeat(200),summary:'s',mistakes:[{title:'t',detail:'d',estimatedCost:-4}],improvements:[],tomorrow:['a'],adjustments:[{key:'Fox Hills|LUNCH',multiplier:.92,reason:'quiet'}]})}]}]})}}});
 assert.equal(ok.headline.length,90);assert.equal(ok.mistakes[0].estimatedCost,0);
 assert.equal(sent.store,false);assert.equal(sent.text.format.strict,true);
 assert.ok(!JSON.stringify(sent).includes('dropoff_text'));
});
function round(v){return Number(v.toFixed(3))}
