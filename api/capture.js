import { parseOfferText, effectiveOfferRate } from '../lib-parser.js';
import { buildDispatchModel, decideDispatchOffer, remainingBatteryMiles } from '../lib-dispatch.js';
import { cors, requireToken, dbConfigured, insert, select, patch, bodyOf, zoneFor, zoneHintFromText } from './_shared.js';
import { marketCellFor, normalizeVehicle, timeBlockForDate, DEFAULT_TIMEZONE } from '../lib-network.js';
export default async function handler(req,res){
  cors(res); if(req.method==='OPTIONS')return res.status(204).end(); if(req.method!=='POST')return res.status(405).json({error:'POST only'});
  const driverId=requireToken(req,res); if(!driverId)return;
  const body=await bodyOf(req);
  const screen=inspectUberScreen(body.text||body.rawText||'');
  if(screen.kind==='unknown')return res.status(422).json({ok:false,error:'No readable Uber offer or lifecycle state',screen});
  if(screen.kind==='lifecycle'){
    if(!dbConfigured())return res.status(503).json({error:'Database unavailable'});
    const active=await select('offers?driver_id=eq.'+driverId+'&state=in.(observed,accepted,arrived,picked_up)&order=captured_at.desc&limit=12&select=*').catch(()=>[]);
    const latest=(active||[]).find(o=>['accepted','arrived','picked_up'].includes(o.state))||active?.[0];
    if(!latest)return res.status(200).json({ok:true,screen,updated:false,reason:'No active Radar order matched. Capture and mark the Uber offer first.'});
    const stage=screenTransition(latest.state,screen.stage);
    if(!stage)return res.status(200).json({ok:true,screen,updated:false,currentState:latest.state,reason:'Requires intervening lifecycle evidence or manual Next; no state changed.'});
    const receivedAt=new Date().toISOString(),lat=Number(body.lat),lng=Number(body.lng),validGps=Number.isFinite(lat)&&Number.isFinite(lng)&&Math.abs(lat)>1&&Math.abs(lng)>1,place=validGps?{lat,lng}:{lat:null,lng:null},zone=validGps?zoneFor(lat,lng):null;
    await patch('offers?id=eq.'+latest.id+'&driver_id=eq.'+driverId,stage==='delivered'?{state:stage,final_payout:latest.final_payout??latest.payout??null}:{state:stage});
    await insert('offer_events',{offer_id:latest.id,driver_id:driverId,event:stage,captured_at:receivedAt,...place,zone,market_cell:validGps?marketCellFor(lat,lng,latest.vehicle||'ebike'):null});
    if(latest.batch_id)await patch('batches?id=eq.'+latest.batch_id+'&driver_id=eq.'+driverId,stage==='delivered'?{state:'completed',completed_at:receivedAt}:{state:stage==='accepted'?'active':stage}).catch(()=>null);
    return res.status(200).json({ok:true,persisted:true,screen,updated:true,id:latest.id,state:stage,reason:'Lifecycle updated from screenshot OCR. This is inferred from on-screen text.'});
  }
  const coord=v=>{if(v==null||v==='')return NaN;let raw=String(v).trim();const matches=raw.match(/-?\d+(?:\.\d+)?/g)||[];if(matches.length===1){const n=Number(matches[0]);return Number.isFinite(n)?n:NaN}const n=Number(raw.replace(',','.'));return Number.isFinite(n)?n:NaN};
  const pairFrom=v=>{if(v==null)return null;const m=String(v).match(/(-?\d{1,3}(?:\.\d+)?)\s*[, ]\s*(-?\d{1,3}(?:\.\d+)?)/);if(!m)return null;const a=Number(m[1]),b=Number(m[2]);return Number.isFinite(a)&&Number.isFinite(b)?[a,b]:null};
  let settings={target_dph:Number(process.env.TARGET_DPH||35),speed_low_mph:12,speed_mid_mph:16,speed_high_mph:20,active_speed_level:'high',service_overhead_minutes:4.5}; if(dbConfigured()){try{const rows=await select(`driver_settings?driver_id=eq.${driverId}&limit=1&select=*`);if(rows?.[0])settings={...settings,...rows[0]}}catch{}} const parsed=parseOfferText(body.text||body.rawText||''),pair=pairFrom(body.location??body.coordinates??body.lat),lat0=coord(body.lat??body.latitude??body.Latitude),lng0=coord(body.lng??body.lon??body.longitude??body.Longitude),lat=Number.isFinite(lat0)?lat0:pair?.[0],lng=Number.isFinite(lng0)?lng0:pair?.[1],zone=body.zone||zoneFor(lat,lng),vehicle=normalizeVehicle(body.vehicle||'ebike'),timeZone=String(body.timeZone||body.tz||DEFAULT_TIMEZONE).slice(0,80),timeBlock=String(body.timeBlock||timeBlockForDate(new Date(),timeZone)).toUpperCase(),marketCell=marketCellFor(lat,lng,vehicle),idleMinutes=Number(body.idleMinutes||0),mode=idleMinutes>=15?'escape':idleMinutes>=8?'slow':'normal',rate=effectiveOfferRate({...parsed,mode}),dropoffText=String(body.dropoffText||body.destinationText||parsed.destinationText||'').trim()||null,dropoffLat0=coord(body.dropoffLat),dropoffLng0=coord(body.dropoffLng),geo=(!Number.isFinite(dropoffLat0)||!Number.isFinite(dropoffLng0))&&dropoffText?await fetch('https://nominatim.openstreetmap.org/search?'+new URLSearchParams({q:dropoffText+', Los Angeles, CA',format:'jsonv2',limit:'1'}),{headers:{'user-agent':'CourierRadar/1.0'},signal:AbortSignal.timeout(1800)}).then(r=>r.ok?r.json():[]).then(x=>x?.[0]||null).catch(()=>null):null,dropoffLat=Number.isFinite(dropoffLat0)?dropoffLat0:Number(geo?.lat),dropoffLng=Number.isFinite(dropoffLng0)?dropoffLng0:Number(geo?.lon),dropoffZone=body.dropoffZone||(Number.isFinite(dropoffLat)&&Number.isFinite(dropoffLng)?zoneFor(dropoffLat,dropoffLng):zoneHintFromText(dropoffText)),dropoffMarketCell=marketCellFor(dropoffLat,dropoffLng,vehicle),destinationSource=Number.isFinite(dropoffLat0)&&Number.isFinite(dropoffLng0)?'coordinates':geo?'ocr_geocoded':dropoffZone?'text_hint':'unknown',destinationConfidence=Number.isFinite(dropoffLat0)&&Number.isFinite(dropoffLng0)?.95:geo?.82:dropoffZone?.6:0,speedLevel=['low','mid','high'].includes(settings.active_speed_level)?settings.active_speed_level:'high',speedMph=Number(settings[`speed_${speedLevel}_mph`]||20),routeMiles=Number(parsed.miles),radarEtaMinutes=Number.isFinite(routeMiles)&&routeMiles>0?Math.max(1,(routeMiles/Math.max(3,speedMph))*60+Number(settings.service_overhead_minutes||0)):parsed.etaMinutes;
  const row={driver_id:driverId,source:body.source||'uber_eats',captured_at:new Date().toISOString(),payout:parsed.payout,miles:parsed.miles,eta_minutes:parsed.etaMinutes,merchant:parsed.merchant,is_shop:parsed.isShop,item_count:parsed.itemCount,parser_confidence:parsed.confidence,raw_text:parsed.rawText,lat:Number.isFinite(lat)?lat:null,lng:Number.isFinite(lng)?lng:null,zone,vehicle,time_block:timeBlock,market_cell:marketCell,dropoff_text:dropoffText,dropoff_lat:Number.isFinite(dropoffLat)?dropoffLat:null,dropoff_lng:Number.isFinite(dropoffLng)?dropoffLng:null,dropoff_zone:dropoffZone,dropoff_market_cell:dropoffMarketCell,destination_source:destinationSource,destination_confidence:destinationConfidence,radar_eta_minutes:Number.isFinite(radarEtaMinutes)?Number(radarEtaMinutes.toFixed(2)):null,speed_mph:speedMph,speed_level:speedLevel,target_dph:Number(settings.target_dph||35),offer_kind:parsed.offerKind||'single',stack_count:parsed.stackCount||1,state:'observed'};
  let saved=null,duplicate=false;
  if(dbConfigured()){
    try{
      const prior=await select(`offers?driver_id=eq.${driverId}&order=captured_at.desc&limit=1&select=id,state,batch_id,offer_kind,payout,final_payout,captured_at,merchant,miles,eta_minutes,stack_count`);
      const repeat=prior?.[0]&&Math.abs(Number(prior[0].payout)-Number(row.payout))<.02&&Math.abs(Number(prior[0].miles)-Number(row.miles))<.16&&Math.abs(Number(prior[0].eta_minutes)-Number(row.eta_minutes))<=2&&String(prior[0].merchant||'').toLowerCase()===String(row.merchant||'').toLowerCase()&&(Date.now()-new Date(prior[0].captured_at).getTime())<180000;
      if(repeat){saved=[prior[0]];duplicate=true;}
      else{
      // A newly observed offer while the previous order was already picked up is strong
      // evidence that Uber considers that trip complete. Close it automatically so
      // earnings never disappear just because the final Radar Next tap was missed.
      const priorAgeMin=prior?.[0]?.captured_at?(Date.now()-new Date(prior[0].captured_at).getTime())/60000:0;
      const incomingStack=parsed.isAddOn||parsed.stackCount>1;
      // A later standalone offer is also strong completion evidence after an ARRIVED
      // order has been active long enough. Never do this for Uber Delivery (N) stacks/add-ons.
      if(prior?.[0]?.state==='picked_up' && priorAgeMin>=5 && Number(prior[0].stack_count||1)===1 && !incomingStack){
        const completedAt=new Date().toISOString();
        await patch(`offers?id=eq.${prior[0].id}&driver_id=eq.${driverId}`,{state:'delivered',final_payout:prior[0].final_payout??prior[0].payout??null});
        await insert('offer_events',{offer_id:prior[0].id,driver_id:driverId,event:'inferred_delivery',captured_at:completedAt,lat:Number.isFinite(lat)?lat:null,lng:Number.isFinite(lng)?lng:null,zone,market_cell:marketCell});
        await insert('offer_events',{offer_id:prior[0].id,driver_id:driverId,event:'delivered',captured_at:completedAt,lat:Number.isFinite(lat)?lat:null,lng:Number.isFinite(lng)?lng:null,zone,market_cell:marketCell});
        if(prior[0].batch_id)await patch(`batches?id=eq.${prior[0].batch_id}&driver_id=eq.${driverId}`,{state:'completed',completed_at:completedAt,final_payout:prior[0].final_payout??prior[0].payout??null}).catch(()=>null);
      }
      if(prior?.[0]?.state==='observed' && !parsed.isAddOn){
        await patch(`offers?id=eq.${prior[0].id}&driver_id=eq.${driverId}`,{state:'passed'});
        await insert('offer_events',{offer_id:prior[0].id,driver_id:driverId,event:'expired',captured_at:new Date().toISOString(),lat:Number.isFinite(lat)?lat:null,lng:Number.isFinite(lng)?lng:null,zone,market_cell:marketCell});
      }
      let batchId=null;
      if(parsed.isAddOn && prior?.[0]?.batch_id && !['delivered','completed','passed','rejected'].includes(prior[0].state)) batchId=prior[0].batch_id;
      if(!batchId){
        const active=await select(`batches?driver_id=eq.${driverId}&state=neq.completed&order=started_at.desc&limit=1&select=id,state,order_count`);
        if(parsed.isAddOn && active?.[0]?.id) batchId=active[0].id;
      }
      if(batchId && parsed.isAddOn){const rows=await select(`offers?driver_id=eq.${driverId}&batch_id=eq.${batchId}&select=payout,miles,eta_minutes,stack_count`).catch(()=>[]),all=[...(rows||[]),row],offeredPayout=all.reduce((s,o)=>s+(Number(o.payout)||0),0),offeredMiles=all.reduce((s,o)=>s+(Number(o.miles)||0),0),orderCount=Math.max(all.length,all.reduce((s,o)=>s+Math.max(1,Number(o.stack_count||1)),0));await patch(`batches?id=eq.${batchId}&driver_id=eq.${driverId}`,{offered_payout:Number(offeredPayout.toFixed(2)),offered_miles:Number(offeredMiles.toFixed(2)),order_count:orderCount}).catch(()=>null)}
      if(!batchId){
        const b=await insert('batches',{driver_id:driverId,state:'observed',offered_payout:parsed.payout,offered_miles:parsed.miles,order_count:parsed.stackCount||1});
        batchId=b?.[0]?.id||null;
      }
      row.batch_id=batchId;
      saved=await insert('offers',row);
      if(saved?.[0]?.id)await insert('offer_events',{offer_id:saved[0].id,driver_id:driverId,event:'observed',captured_at:row.captured_at,lat:row.lat,lng:row.lng,zone:row.zone,market_cell:row.market_cell});
      }
    }catch(error){return res.status(500).json({error:error.message,parsed,rate})}
  }
  const target=Number(settings.target_dph||35),uberRate=parsed.payout>0&&Number(parsed.etaMinutes)>0?{effectiveMinutes:Number(parsed.etaMinutes),dollarsPerHour:Number((parsed.payout/parsed.etaMinutes*60).toFixed(2))}:null,radarRate=parsed.payout>0&&Number.isFinite(radarEtaMinutes)?{effectiveMinutes:Number(radarEtaMinutes.toFixed(1)),dollarsPerHour:Number((parsed.payout/radarEtaMinutes*60).toFixed(2))}:rate,decisionRate=uberRate?.dollarsPerHour??radarRate?.dollarsPerHour,dispatchRows=dbConfigured()?await Promise.all([
   select('offers?driver_id=eq.'+driverId+'&order=captured_at.desc&limit=1500&select=*'),
   select('offer_events?driver_id=eq.'+driverId+'&order=captured_at.desc&limit=4000&select=*'),
   select('presence?driver_id=eq.'+driverId+'&order=captured_at.desc&limit=8000&select=*'),
   select('shifts?driver_id=eq.'+driverId+'&order=started_at.desc&limit=100&select=*')
  ]).catch(()=>null):null,
  learned=dispatchRows?buildDispatchModel({offers:(dispatchRows[0]||[]).filter(x=>x.id!==saved?.[0]?.id),events:dispatchRows[1]||[],presence:dispatchRows[2]||[],shifts:dispatchRows[3]||[],vehicle,now:Date.now()}):null,
  laDate=new Intl.DateTimeFormat('en-CA',{timeZone:'America/Los_Angeles',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date(Date.now()-4*3600000)),
  policy=settings.dispatch_policy||{},
  clock=new Intl.DateTimeFormat('en-US',{timeZone:'America/Los_Angeles',hourCycle:'h23',hour:'2-digit',minute:'2-digit'}).formatToParts(new Date()),
  nowMinutes=Number(clock.find(x=>x.type==='hour')?.value||0)*60+Number(clock.find(x=>x.type==='minute')?.value||0),
  stopParts=String(body.stopTime||policy.stopTime||'01:00').split(':').map(Number),
  stopMinutes=(stopParts[0]||0)*60+(stopParts[1]||0),
  workHorizon=Math.max(10,(stopMinutes>nowMinutes?stopMinutes:stopMinutes+1440)-nowMinutes),
  effectiveBattery=body.batteryMiles??remainingBatteryMiles(policy,dispatchRows?.[0]||[]),
  decision=decideDispatchOffer({model:learned,offer:row,position:Number.isFinite(lat)&&Number.isFinite(lng)?{lat,lng}:null,now:Date.now(),remainingMinutes:Math.max(10,Math.min(180,Number(body.remainingMinutes)||workHorizon)),batteryMiles:effectiveBattery,dailyEarned:body.dailyEarned??null,dailyTarget:200,calibration:laDate===String(body.calibrationDay||policy.calibrationDay||'2026-09-29')}),
  verdict=decision.verdict;
  if(dbConfigured()&&saved?.[0]?.id){
   await insert('recommendation_logs',{
    driver_id:driverId,context:'offer_decision',action:verdict,
    zone_type:decision.zone||zone||null,confidence:decision.confidence??0,
    reason:String(decision.reason||'').slice(0,800),time_block:timeBlock,
    source:'dispatch_v4',origin_lat:Number.isFinite(lat)?lat:null,origin_lng:Number.isFinite(lng)?lng:null,
    evidence:{offerId:saved[0].id,payout:row.payout,etaMinutes:row.eta_minutes,miles:row.miles,
     takeValue:decision.takeValue??null,skipValue:decision.skipValue??null,
     confidence:decision.confidence??null,mode:decision.mode,
     afterDelivery:decision.afterDelivery||null,horizonMinutes:decision.horizonMinutes||null,
     capturedAt:row.captured_at}
   }).catch(()=>null);
  }
  return res.status(200).json({ok:true,screen,duplicate,persisted:Boolean(saved),locationReceived:Boolean(Number.isFinite(lat)&&Number.isFinite(lng)),receivedLocation:{lat:Number.isFinite(lat)?lat:null,lng:Number.isFinite(lng)?lng:null},offerKind:parsed.offerKind,stackCount:parsed.stackCount,id:saved?.[0]?.id||null,parsed,rate:uberRate||radarRate,uberRate,radarRate,uberEtaMinutes:parsed.etaMinutes,radarEtaMinutes:Number.isFinite(radarEtaMinutes)?Number(radarEtaMinutes.toFixed(1)):null,speedMph,speedLevel,decision,verdict,zone,vehicle,timeBlock,marketCell,mode,destination:{text:dropoffText,lat:Number.isFinite(dropoffLat)?dropoffLat:null,lng:Number.isFinite(dropoffLng)?dropoffLng:null,zone:dropoffZone,marketCell:dropoffMarketCell,source:destinationSource,confidence:destinationConfidence}});
}