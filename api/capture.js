import { parseOfferText, effectiveOfferRate, decisionForOffer } from '../lib-parser.js';
import { cors, requireToken, dbConfigured, insert, select, patch, bodyOf, zoneFor, zoneHintFromText } from './_shared.js';
import { marketCellFor, normalizeVehicle, timeBlockForDate, DEFAULT_TIMEZONE } from '../lib-network.js';
export default async function handler(req,res){
  cors(res); if(req.method==='OPTIONS')return res.status(204).end(); if(req.method!=='POST')return res.status(405).json({error:'POST only'});
  const driverId=requireToken(req,res); if(!driverId)return;
  const body=await bodyOf(req);
  const coord=v=>{if(v==null||v==='')return NaN;let raw=String(v).trim();const matches=raw.match(/-?\d+(?:\.\d+)?/g)||[];if(matches.length===1){const n=Number(matches[0]);return Number.isFinite(n)?n:NaN}const n=Number(raw.replace(',','.'));return Number.isFinite(n)?n:NaN};
  const pairFrom=v=>{if(v==null)return null;const m=String(v).match(/(-?\d{1,3}(?:\.\d+)?)\s*[, ]\s*(-?\d{1,3}(?:\.\d+)?)/);if(!m)return null;const a=Number(m[1]),b=Number(m[2]);return Number.isFinite(a)&&Number.isFinite(b)?[a,b]:null};
  let settings={target_dph:Number(process.env.TARGET_DPH||35),speed_low_mph:12,speed_mid_mph:16,speed_high_mph:20,active_speed_level:'high',service_overhead_minutes:4.5}; if(dbConfigured()){try{const rows=await select(`driver_settings?driver_id=eq.${driverId}&limit=1&select=*`);if(rows?.[0])settings={...settings,...rows[0]}}catch{}} const parsed=parseOfferText(body.text||body.rawText||''),pair=pairFrom(body.location??body.coordinates??body.lat),lat0=coord(body.lat??body.latitude??body.Latitude),lng0=coord(body.lng??body.lon??body.longitude??body.Longitude),lat=Number.isFinite(lat0)?lat0:pair?.[0],lng=Number.isFinite(lng0)?lng0:pair?.[1],zone=body.zone||zoneFor(lat,lng),vehicle=normalizeVehicle(body.vehicle||'ebike'),timeZone=String(body.timeZone||body.tz||DEFAULT_TIMEZONE).slice(0,80),timeBlock=String(body.timeBlock||timeBlockForDate(new Date(),timeZone)).toUpperCase(),marketCell=marketCellFor(lat,lng,vehicle),idleMinutes=Number(body.idleMinutes||0),mode=idleMinutes>=15?'escape':idleMinutes>=8?'slow':'normal',rate=effectiveOfferRate({...parsed,mode}),dropoffText=String(body.dropoffText||body.destinationText||parsed.destinationText||'').trim()||null,dropoffLat=coord(body.dropoffLat),dropoffLng=coord(body.dropoffLng),dropoffZone=body.dropoffZone||(Number.isFinite(dropoffLat)&&Number.isFinite(dropoffLng)?zoneFor(dropoffLat,dropoffLng):zoneHintFromText(dropoffText)),dropoffMarketCell=marketCellFor(dropoffLat,dropoffLng,vehicle),destinationSource=dropoffMarketCell?'coordinates':dropoffZone?'text_hint':'unknown',destinationConfidence=dropoffMarketCell?.95:dropoffZone?.6:0,speedLevel=['low','mid','high'].includes(settings.active_speed_level)?settings.active_speed_level:'high',speedMph=Number(settings[`speed_${speedLevel}_mph`]||20),routeMiles=Number(parsed.miles),radarEtaMinutes=Number.isFinite(routeMiles)&&routeMiles>0?Math.max(1,(routeMiles/Math.max(3,speedMph))*60+Number(settings.service_overhead_minutes||0)):parsed.etaMinutes;
  const row={driver_id:driverId,source:body.source||'uber_eats',captured_at:new Date().toISOString(),payout:parsed.payout,miles:parsed.miles,eta_minutes:parsed.etaMinutes,merchant:parsed.merchant,is_shop:parsed.isShop,item_count:parsed.itemCount,parser_confidence:parsed.confidence,raw_text:parsed.rawText,lat:Number.isFinite(lat)?lat:null,lng:Number.isFinite(lng)?lng:null,zone,vehicle,time_block:timeBlock,market_cell:marketCell,dropoff_text:dropoffText,dropoff_lat:Number.isFinite(dropoffLat)?dropoffLat:null,dropoff_lng:Number.isFinite(dropoffLng)?dropoffLng:null,dropoff_zone:dropoffZone,dropoff_market_cell:dropoffMarketCell,destination_source:destinationSource,destination_confidence:destinationConfidence,radar_eta_minutes:Number.isFinite(radarEtaMinutes)?Number(radarEtaMinutes.toFixed(2)):null,speed_mph:speedMph,speed_level:speedLevel,target_dph:Number(settings.target_dph||35),offer_kind:parsed.offerKind||'single',stack_count:parsed.stackCount||1,state:'observed'};
  let saved=null;
  if(dbConfigured()){
    try{
      const prior=await select(`offers?driver_id=eq.${driverId}&order=captured_at.desc&limit=1&select=id,state,batch_id,offer_kind,payout,final_payout,captured_at,merchant,miles`);
      // A newly observed offer while the previous order was already picked up is strong
      // evidence that Uber considers that trip complete. Close it automatically so
      // earnings never disappear just because the final Radar Next tap was missed.
      const priorAgeMin=prior?.[0]?.captured_at?(Date.now()-new Date(prior[0].captured_at).getTime())/60000:0;
      const incomingStack=parsed.isAddOn||parsed.stackCount>1;
      // A later standalone offer is also strong completion evidence after an ARRIVED
      // order has been active long enough. Never do this for Uber Delivery (N) stacks/add-ons.
      if(['picked_up','arrived'].includes(prior?.[0]?.state) && !incomingStack && (prior[0].state==='picked_up'||priorAgeMin>=10)){
        const completedAt=new Date().toISOString();
        await patch(`offers?id=eq.${prior[0].id}&driver_id=eq.${driverId}`,{state:'delivered',final_payout:prior[0].final_payout??prior[0].payout??null});
        await insert('offer_events',{offer_id:prior[0].id,driver_id:driverId,event:'delivered',captured_at:completedAt,lat:Number.isFinite(lat)?lat:null,lng:Number.isFinite(lng)?lng:null,zone,market_cell:marketCell});
        if(prior[0].batch_id)await patch(`batches?id=eq.${prior[0].batch_id}&driver_id=eq.${driverId}`,{state:'completed',completed_at:completedAt,final_payout:prior[0].final_payout??prior[0].payout??null}).catch(()=>null);
      }
      if(prior?.[0]?.state==='observed' && !parsed.isAddOn){
        await patch(`offers?id=eq.${prior[0].id}&driver_id=eq.${driverId}`,{state:'passed'});
        await insert('offer_events',{offer_id:prior[0].id,driver_id:driverId,event:'passed',captured_at:new Date().toISOString(),lat:Number.isFinite(lat)?lat:null,lng:Number.isFinite(lng)?lng:null,zone,market_cell:marketCell});
      }
      let batchId=null;
      if(parsed.isAddOn && prior?.[0]?.batch_id && !['delivered','completed','passed','rejected'].includes(prior[0].state)) batchId=prior[0].batch_id;
      if(!batchId){
        const active=await select(`batches?driver_id=eq.${driverId}&state=neq.completed&order=started_at.desc&limit=1&select=id,state,order_count`);
        if(parsed.isAddOn && active?.[0]?.id) batchId=active[0].id;
      }
      if(!batchId){
        const b=await insert('batches',{driver_id:driverId,state:'observed',offered_payout:parsed.payout,offered_miles:parsed.miles,order_count:parsed.stackCount||1});
        batchId=b?.[0]?.id||null;
      }
      row.batch_id=batchId;
      saved=await insert('offers',row);
      if(saved?.[0]?.id)await insert('offer_events',{offer_id:saved[0].id,driver_id:driverId,event:'observed',captured_at:row.captured_at,lat:row.lat,lng:row.lng,zone:row.zone,market_cell:row.market_cell});
    }catch(error){return res.status(500).json({error:error.message,parsed,rate})}
  }
  const target=Number(settings.target_dph||35),uberRate=parsed.payout>0&&Number(parsed.etaMinutes)>0?{effectiveMinutes:Number(parsed.etaMinutes),dollarsPerHour:Number((parsed.payout/parsed.etaMinutes*60).toFixed(2))}:null,radarRate=parsed.payout>0&&Number.isFinite(radarEtaMinutes)?{effectiveMinutes:Number(radarEtaMinutes.toFixed(1)),dollarsPerHour:Number((parsed.payout/radarEtaMinutes*60).toFixed(2))}:rate,decisionRate=uberRate?.dollarsPerHour??radarRate?.dollarsPerHour,decision=decisionForOffer({dollarsPerHour:decisionRate,target,mode}),verdict=decision.verdict;
  return res.status(200).json({ok:true,persisted:Boolean(saved),locationReceived:Boolean(Number.isFinite(lat)&&Number.isFinite(lng)),receivedLocation:{lat:Number.isFinite(lat)?lat:null,lng:Number.isFinite(lng)?lng:null},offerKind:parsed.offerKind,stackCount:parsed.stackCount,id:saved?.[0]?.id||null,parsed,rate:uberRate||radarRate,uberRate,radarRate,uberEtaMinutes:parsed.etaMinutes,radarEtaMinutes:Number.isFinite(radarEtaMinutes)?Number(radarEtaMinutes.toFixed(1)):null,speedMph,speedLevel,decision,verdict,zone,vehicle,timeBlock,marketCell,mode,destination:{text:dropoffText,lat:Number.isFinite(dropoffLat)?dropoffLat:null,lng:Number.isFinite(dropoffLng)?dropoffLng:null,zone:dropoffZone,marketCell:dropoffMarketCell,source:destinationSource,confidence:destinationConfidence}});
}