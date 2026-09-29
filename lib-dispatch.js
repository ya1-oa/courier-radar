// Radar's dispatch model is a personal, observational approximation, NOT Uber's private algorithm.
// No merchant-density, fabricated hotspot or anonymous rider-supply data enters this model.
const DAY=86400000, MIN=60000;
const clamp=(v,lo,hi)=>Math.max(lo,Math.min(hi,v));
const ms=d=>{const t=new Date(d).getTime();return Number.isFinite(t)?t:NaN};
const val=(x,d=0)=>Number.isFinite(Number(x))?Number(x):d;
const usd=x=>'$'+Math.max(0,val(x)).toFixed(2);
const decay=(at,now)=>Math.exp(-Math.max(0,now-at)/(10*DAY));
const actualMinutes=(a,b)=>clamp((b-a)/MIN,0,180);
const BLOCKS=['BREAKFAST','LUNCH','AFTERNOON','DINNER','LATE','OFF-PEAK'];
export function dispatchBlock(date,timezone='America/Los_Angeles'){
 const parts=new Intl.DateTimeFormat('en-US',{timeZone:timezone,hourCycle:'h23',hour:'2-digit',minute:'2-digit'}).formatToParts(new Date(date));
 const h=Number(parts.find(p=>p.type==='hour')?.value||0)+Number(parts.find(p=>p.type==='minute')?.value||0)/60;
 return h>=6&&h<10.5?'BREAKFAST':h>=10.5&&h<14.5?'LUNCH':h>=14.5&&h<16.5?'AFTERNOON':h>=16.5&&h<21?'DINNER':h>=21||h<1?'LATE':'OFF-PEAK';
}
const anchors=[
 ['Westwood',34.0627,-118.4455],['Century City',34.0554,-118.4174],
 ['Culver City',34.0211,-118.3965],['Palms',34.026,-118.4212],
 ['Westside Village',34.027,-118.4440],['Mar Vista',34.006,-118.431],
 ['Santa Monica',34.018,-118.491],['Venice',33.991,-118.466],
 ['Fox Hills',33.990,-118.391],['USC',34.023,-118.285],
 ['Koreatown',34.063,-118.301],['DTLA',34.046,-118.250],
 ['Sawtelle',34.037,-118.449],['Brentwood',34.052,-118.474]
];
export function milesBetween(a,b,c,d){
 if([a,b,c,d].some(v=>v==null||v===''||!Number.isFinite(Number(v))))return Infinity;
 const r=Math.PI/180,p=(Number(c)-Number(a))*r,q=(Number(d)-Number(b))*r;
 return 3958.76*2*Math.asin(Math.sqrt(Math.sin(p/2)**2+Math.cos(Number(a)*r)*Math.cos(Number(c)*r)*Math.sin(q/2)**2));
}
export function dispatchZone(lat,lng){
 if(lat==null||lng==null||lat===''||lng==='')return null;
 const y=Number(lat),x=Number(lng);if(!Number.isFinite(y)||!Number.isFinite(x)||Math.abs(y)>90||Math.abs(x)>180||Math.abs(y)<1||Math.abs(x)<1)return null;
 let closest=null,dist=Infinity;
 for(const a of anchors){const d=milesBetween(y,x,a[1],a[2]);if(d<dist){dist=d;closest=a}}
 // Broad zone, not an individual restaurant or arbitrary sub-400m hex. Avoid moving for 1 block difference.
 if(closest&&dist<1.45)return closest[0];
 return 'Area '+(Math.round(y/.014)*.014).toFixed(3)+','+(Math.round(x/.017)*.017).toFixed(3);
}
const zoneFrom=o=>dispatchZone(o?.lat,o?.lng)||(String(o?.zone||'').trim()&&!/learning|unknown/i.test(String(o.zone))?String(o.zone):null);
const fingerprint=o=>[String(o?.merchant||'').toLowerCase().replace(/[^a-z0-9]/g,''),val(o?.payout).toFixed(2),val(o?.miles).toFixed(1),val(o?.eta_minutes)].join('|');
const isRealOffer=o=>val(o.payout)>0&&val(o.eta_minutes)>0&&val(o.payout)<200&&val(o.eta_minutes)<240;
const isBusy=s=>['accepted','arrived','picked_up'].includes(String(s));
const weighted=(rows,key,now)=>{let n=0,d=0;for(const r of rows){const v=val(key(r),NaN),w=decay(ms(r.captured_at),now);if(Number.isFinite(v)&&Number.isFinite(w)){n+=v*w;d+=w}}return d?n/d:null};
const signature=r=>String(r.zone||'')+'|'+String(r.block||'');
export function buildDispatchModel({offers=[],events=[],presence=[],shifts=[],now=Date.now(),vehicle='ebike'}={}){
 const t=now instanceof Date?now.getTime():Number(now),since=t-30*DAY,usableShifts=(shifts||[]).filter(s=>ms(s.started_at)<t&&ms(s.ended_at||new Date(t))>since).map(s=>({a:Math.max(since,ms(s.started_at)),b:Math.min(t,ms(s.ended_at||new Date(t)))}));
 const eventMap=new Map();
 for(const e of events||[]){if(!eventMap.has(e.offer_id))eventMap.set(e.offer_id,[]);eventMap.get(e.offer_id).push(e)}
 for(const group of eventMap.values())group.sort((a,b)=>ms(a.captured_at)-ms(b.captured_at));
 const raw=(offers||[]).filter(o=>isRealOffer(o)&&ms(o.captured_at)>=since&&ms(o.captured_at)<=t).sort((a,b)=>ms(a.captured_at)-ms(b.captured_at));
 const unique=[],duplicateIds=new Set();
 for(const o of raw){const previous=unique.at(-1);if(previous&&fingerprint(previous)===fingerprint(o)&&ms(o.captured_at)-ms(previous.captured_at)<150000){duplicateIds.add(o.id);continue}unique.push(o)}
 const busy=[];
 for(const o of raw){
  const e=eventMap.get(o.id)||[],accept=e.find(x=>x.event==='accepted'),end=e.find(x=>['delivered','completed','cancelled'].includes(x.event));
  if(!accept)continue;const a=ms(accept.captured_at),b=end?ms(end.captured_at):Math.min(t,a+Math.max(20,val(o.eta_minutes,30))*MIN);
  if(b>a&&b-a<=4*3600000)busy.push({a,b,id:o.id});
 }
 busy.sort((a,b)=>a.a-b.a);
 const busyAt=t=>busy.some(w=>t>=w.a&&t<w.b);
 const inShift=t=>usableShifts.some(w=>t>=w.a&&t<w.b);
 // Explicit parentheses matter: never silently treat foreign vehicle telemetry as personal exposure.
 const validPings=(presence||[]).filter(p=>ms(p.captured_at)>=since&&ms(p.captured_at)<=t&&zoneFrom(p)&&!/(shift_end|offline)/i.test(String(p.event||''))&&(!p.vehicle||p.vehicle===vehicle)).sort((a,b)=>ms(a.captured_at)-ms(b.captured_at));
 const exposures=[],byKey=new Map(),global=new Map();
 const record=(zone,block,at,minutes)=>{
  if(!(minutes>0)||!zone)return;const w=decay(at,t),key=zone+'|'+block;
  let g=byKey.get(key);if(!g){g={zone,block,minutes:0,offers:0,reward:0,rewardWeight:0,duration:0,durationWeight:0,last:at,latSum:0,lngSum:0,coordWeight:0};byKey.set(key,g)}
  g.minutes+=minutes*w;g.last=Math.max(g.last,at);
  let all=global.get(block);if(!all){all={minutes:0,offers:0,reward:0,rewardWeight:0,duration:0,durationWeight:0};global.set(block,all)}
  all.minutes+=minutes*w;
 };
 // A 2-minute ping earns no more than 2.5 verified minutes. Background iOS gaps are NOT assumed available.
 for(let i=0;i<validPings.length;i++){
  const p=validPings[i],at=ms(p.captured_at);if(!inShift(at))continue;
  const next=validPings[i+1],nextAt=next?ms(next.captured_at):Infinity;
  const end=Math.min(t,at+2.5*MIN,nextAt);
  // Slice into small pieces to remove accepted/delivering windows, shift edges and block edges.
  const zone=zoneFrom(p),block=dispatchBlock(at);
  for(let x=at;x<end;x+=0.5*MIN){const b=Math.min(end,x+0.5*MIN),mid=(x+b)/2;if(!inShift(mid)||busyAt(mid))continue;
   const duration=(b-x)/MIN;record(zone,dispatchBlock(mid),mid,duration);
   exposures.push({a:x,b,zone,block:dispatchBlock(mid)});
  }
  const g=byKey.get(zone+'|'+block);
  if(g&&Number.isFinite(Number(p.lat))&&Number.isFinite(Number(p.lng))){const w=decay(at,t);g.latSum+=Number(p.lat)*w;g.lngSum+=Number(p.lng)*w;g.coordWeight+=w}
 }
 const observed=unique.filter(o=>{
  const at=ms(o.captured_at);return !busyAt(at)&&inShift(at)&&exposures.some(x=>at>=x.a-15000&&at<=x.b+15000);
 });
 for(const o of observed){
  const zone=zoneFrom(o),block=dispatchBlock(o.captured_at),key=zone+'|'+block,g=byKey.get(key),all=global.get(block);
  if(!g||!all)continue;const w=decay(ms(o.captured_at),t);g.offers+=w;all.offers+=w;
  for(const z of [g,all]){z.reward+=w*val(o.payout);z.rewardWeight+=w;z.duration+=w*val(o.eta_minutes);z.durationWeight+=w}
 }
 const rates=[...global.values()].filter(g=>g.minutes>=15).map(g=>g.offers/g.minutes).filter(Number.isFinite);
 const globalRate=rates.length?clamp(rates.reduce((a,b)=>a+b,0)/rates.length,.005,.33):1/16;
 const observedPayout=weighted(observed,o=>o.payout,t)??weighted(unique,o=>o.payout,t)??7.5;
 const observedDuration=weighted(observed,o=>o.eta_minutes,t)??weighted(unique,o=>o.eta_minutes,t)??24;
 const zones=[...byKey.values()].map(g=>{
  const base=global.get(g.block),priorRate=base&&base.minutes>=30?clamp((base.offers+1)/(base.minutes+16),.005,.33):globalRate;
  const rate=clamp((g.offers+priorRate*60)/(g.minutes+60),.004,.33);
  const payout=(g.reward+observedPayout*4)/(g.rewardWeight+4);
  const duration=clamp((g.duration+observedDuration*4)/(g.durationWeight+4),8,85);
  const confidence=clamp(Math.min(g.minutes/120,g.offers/7),0,1);
  return {zone:g.zone,block:g.block,availableMinutes:+g.minutes.toFixed(1),offers:+g.offers.toFixed(1),offersPerHour:+(rate*60).toFixed(2),rate,payout:+payout.toFixed(2),duration:+duration.toFixed(1),confidence:+confidence.toFixed(3),sampled:g.offers>=4&&g.minutes>=45,lat:g.coordWeight?g.latSum/g.coordWeight:null,lng:g.coordWeight?g.lngSum/g.coordWeight:null,latest:new Date(g.last).toISOString()};
 });
 const eventsRejected=(events||[]).filter(e=>e.event==='rejected'&&ms(e.captured_at)>=since&&ms(e.captured_at)<=t);
 // These are observational comparisons, not a causal estimate of Uber punishing declines.
 const postGaps=[];
 for(const e of eventsRejected){if(duplicateIds.has(e.offer_id))continue;const at=ms(e.captured_at),o=raw.find(r=>r.id===e.offer_id),zone=zoneFrom(o||{}),block=dispatchBlock(at);const next=observed.find(x=>ms(x.captured_at)>at+2000&&zoneFrom(x)===zone&&dispatchBlock(x.captured_at)===block);if(!next)continue;const minutes=(ms(next.captured_at)-at)/MIN;if(minutes>0&&minutes<35&&exposures.some(x=>x.a<=at+3*MIN&&x.b>=at-3*MIN))postGaps.push(minutes)}
 const baselineGaps=[];
 for(let i=1;i<observed.length;i++){const a=observed[i-1],b=observed[i],gap=(ms(b.captured_at)-ms(a.captured_at))/MIN;if(gap>0&&gap<35&&zoneFrom(a)===zoneFrom(b)&&dispatchBlock(a.captured_at)===dispatchBlock(b.captured_at))baselineGaps.push(gap)}
 const mean=a=>a.length?a.reduce((sum,x)=>sum+x,0)/a.length:0;
 const penaltyEvidence=Math.min(1,postGaps.length/20);
 const declineExtraMinutes=postGaps.length>=10&&baselineGaps.length>=20?clamp((mean(postGaps)-mean(baselineGaps))*penaltyEvidence,0,8):0;
 return {version:4,trainedAt:new Date(t).toISOString(),windowDays:30,vehicle,offersCaptured:unique.length,offersObservedAvailable:observed.length,verifiedAvailableMinutes:+[...byKey.values()].reduce((s,x)=>s+x.minutes,0).toFixed(1),gpsSamples:validPings.length,completedWindows:busy.length,pooled:{rate:globalRate,payout:observedPayout,duration:observedDuration},zones,decline:{sampleSize:postGaps.length,baselineSize:baselineGaps.length,observedExcessMinutes:+declineExtraMinutes.toFixed(1),isCausal:false},limitations:['Only foreground/recent GPS pings count as availability','No access to Uber queue or other couriers','Offers captured incompletely bias learned arrival rates','Decline associations are observational']};
}
export function zoneEstimate(model,zone,block){
 const z=(model?.zones||[]).find(x=>x.zone===zone&&x.block===block),prior=model?.pooled||{rate:1/16,payout:7.5,duration:24};
 if(z)return z;
 return {zone,block,availableMinutes:0,offers:0,offersPerHour:+(prior.rate*60).toFixed(1),rate:clamp(prior.rate,.004,.33),payout:prior.payout,duration:prior.duration,confidence:0,sampled:false,lat:null,lng:null};
}
const cashRate=z=>val(z.payout)/(1/Math.max(.004,val(z.rate,.05))+Math.max(8,val(z.duration,24)));
const futureCash=(z,minutes)=>cashRate(z)*Math.max(0,Math.min(180,minutes)); // finite horizon baseline
const travelMinutes=(miles,speed=11)=>Math.max(0,miles)/clamp(speed,6,20)*60+2;
function destinations(model,offer,homeZone,block,eta,batteryMiles,lookahead){
 const remaining=Math.max(0,lookahead-eta),home=zoneEstimate(model,homeZone,block);
 const lat=Number(offer?.dropoff_lat),lng=Number(offer?.dropoff_lng),hasCoord=Number.isFinite(lat)&&Number.isFinite(lng)&&Math.abs(lat)>1&&Math.abs(lng)>1;
 const destZone=hasCoord?dispatchZone(lat,lng):null,dest=zoneEstimate(model,destZone||homeZone,block);
 // Unknown destinations do not inherit imaginary high-confidence demand.
 let best=futureCash(dest,remaining)*(destZone?1:.90),action='WAIT AFTER DROPOFF',returnTravel=0;
 const originLat=Number(offer?.lat),originLng=Number(offer?.lng);
 if(hasCoord&&Number.isFinite(originLat)&&Number.isFinite(originLng)){
  returnTravel=travelMinutes(milesBetween(lat,lng,originLat,originLng));
  if((batteryMiles==null||batteryMiles>val(offer?.miles)+returnTravel/60*11+2)&&returnTravel<remaining){
   const returning=futureCash(home,remaining-returnTravel)-.18*returnTravel/60*11;
   if(returning>best){best=returning;action='RETURN TO '+homeZone}
  }
 }
 return {continuation:best,afterAction:action,destinationZone:destZone,returnMinutes:returnTravel};
}
export function decideDispatchOffer({model,offer,position,now=Date.now(),remainingMinutes=120,batteryMiles=null,dailyEarned=0,dailyTarget=200,calibration=false}={}){
 const payout=val(offer?.payout),eta=val(offer?.eta_minutes||offer?.radar_eta_minutes),miles=val(offer?.miles),nowMs=now instanceof Date?now.getTime():Number(now);
 const zone=dispatchZone(position?.lat,position?.lng)||zoneFrom(offer)||null,block=dispatchBlock(nowMs),here=zoneEstimate(model,zone,block),h=clamp(val(remainingMinutes,120),10,180);
 if(!(payout>0&&eta>0&&miles>=0))return {verdict:'CHECK',reason:'Offer price or duration missing. Verify the Uber screen.',zone,mode:calibration?'CALIBRATION':'LEARNING'};
 if(batteryMiles!=null&&Number.isFinite(Number(batteryMiles))&&miles+2>Number(batteryMiles))return {verdict:'CHECK',reason:'Battery range could be insufficient for this trip plus a 2-mile reserve. Charge or verify range.',zone,mode:'BATTERY SAFETY'};
 const rate=cashRate(here),waitValue=futureCash(here,h),after=destinations(model,offer,zone,block,eta,batteryMiles,h);
 const takeValue=payout+after.continuation;
 // The refusal case is counterfactual and thus needs stronger evidence than guaranteed cash.
 const uncertainty=1-val(here.confidence),margin=2.5+Math.min(6,uncertainty*5);
 const declinePenalty=clamp(val(model?.decline?.observedExcessMinutes),0,8)*rate*.35;
 const skipValue=Math.max(0,waitValue-declinePenalty);
 const evidenceOk=val(here.availableMinutes)>=60&&val(here.offers)>=5;
 let verdict='TAKE',reason='';
 if(calibration){reason='Calibration day: bank feasible cash while collecting unbiased dispatch observations.'}
 else if(!evidenceOk){reason='TAKE: local availability evidence is insufficient for a justified SKIP.'}
 else if(skipValue>takeValue+margin){verdict='SKIP';reason='Observed future cash from staying available exceeds this offer plus estimated post-dropoff opportunity.'}
 else reason='TAKE: guaranteed payout plus post-dropoff opportunity beats, or is too close to, the uncertain SKIP alternative.';
 return {verdict,reason,zone,block,mode:calibration?'CALIBRATION':evidenceOk?'LEARNED':'LOW DATA',payout,eta,miles,remainingToTarget:Math.max(0,dailyTarget-dailyEarned-payout),takeValue:+takeValue.toFixed(2),skipValue:+skipValue.toFixed(2),difference:+(takeValue-skipValue).toFixed(2),horizonMinutes:h,afterDelivery:after.afterAction,returnMinutes:+after.returnMinutes.toFixed(1),sampledMinutes:here.availableMinutes,offerSamples:here.offers,confidence:here.confidence,observationalDeclinePenalty:+declinePenalty.toFixed(2)};
}
export function decideDispatchWait({model,position,now=Date.now(),remainingMinutes=120,batteryMiles=null,active=false,calibration=false,lastOriginZone=null}={}){
 if(active)return {advice:'ON DELIVERY',reason:'Complete the delivery and capture the drop-off. Then re-evaluate your location.'};
 const zone=dispatchZone(position?.lat,position?.lng),block=dispatchBlock(now),h=clamp(val(remainingMinutes,120),10,180),here=zoneEstimate(model,zone,block);
 if(batteryMiles!=null&&Number(batteryMiles)<=4)return {advice:'CHARGE',reason:'Range is at or below 4 miles. Protect your ability to work the next delivery block.',zone};
 if(!position||zone==null)return {advice:'WAIT',reason:'Location unavailable. Do not travel to an unverified hotspot.',zone:null};
 if(calibration)return {advice:'WAIT',reason:'Calibration: hold a stable waiting area to measure actual offer arrivals.',zone};
 if(here.availableMinutes<40||here.offers<3)return {advice:'WAIT',reason:'No reliable local exposure comparison yet. Stay online; avoid speculative deadhead.',zone,confidence:here.confidence};
 const base=futureCash(here,h),choices=(model?.zones||[]).filter(z=>z.block===block&&z.zone!==zone&&z.sampled&&z.availableMinutes>=45&&z.offers>=4&&Number.isFinite(z.lat)&&Number.isFinite(z.lng));
 let winner=null;
 for(const dest of choices){
  const miles=milesBetween(position.lat,position.lng,dest.lat,dest.lng),travel=travelMinutes(miles);
  if(miles>4.5||travel>=Math.min(h*.4,35)||batteryMiles!=null&&miles+4>Number(batteryMiles))continue;
  // Conservative lower bound on new-zone advantage; insufficient history means no move.
  const destinationValue=futureCash(dest,h-travel),uncertainty=(1-Math.min(here.confidence,dest.confidence))*8;
  const advantage=destinationValue-base-uncertainty-.18*miles;
  if(advantage>7&&(!winner||advantage>winner.advantage))winner={zone:dest.zone,lat:dest.lat,lng:dest.lng,miles:+miles.toFixed(1),travelMinutes:+travel.toFixed(1),advantage:+advantage.toFixed(2),confidence:Math.min(here.confidence,dest.confidence)};
 }
 if(winner)return {advice:winner.zone===lastOriginZone?'RETURN':'MOVE',reason:'Personal available-time and offer evidence supports a net cash advantage after travel cost and uncertainty.',zone,target:winner,confidence:winner.confidence};
 return {advice:'WAIT',reason:'Staying has better evidence than paying battery/time to relocate. Review again after more available minutes.',zone,confidence:here.confidence,expectedWaitMinutes:+(1/Math.max(.004,here.rate)).toFixed(1),observedAvailableMinutes:here.availableMinutes};
}

// A conservative mileage budget, not a voltage-to-range measurement. Update after charging.
export function remainingBatteryMiles(policy,orders=[]){
 if(policy?.batteryMiles==null||policy?.batteryMiles==='')return null;
 const starting=Number(policy.batteryMiles);if(!Number.isFinite(starting))return null;
 const at=(policy.batteryRecordedAt?ms(policy.batteryRecordedAt):Date.now()),seen=new Map();let used=0;
 for(const o of orders){
  if(!['accepted','arrived','picked_up','delivered','completed'].includes(String(o.state||'')))continue;
  const time=ms(o.captured_at);if(Number.isFinite(at)&&time<at)continue;
  const key=fingerprint(o),prior=seen.get(key);
  if(prior!=null&&Math.abs(time-prior)<180000)continue;
  seen.set(key,time);
  used+=Math.max(0,val(o.miles));
 }
 return +Math.max(0,starting-used*1.2).toFixed(1);
}
