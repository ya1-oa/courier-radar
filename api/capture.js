import { parseOfferText, effectiveOfferRate } from '../lib-parser.js';
import { cors, requireToken, dbConfigured, insert, bodyOf, zoneFor } from './_shared.js';
import { marketCellFor, normalizeVehicle, timeBlockForDate, DEFAULT_TIMEZONE } from '../lib-network.js';
export default async function handler(req,res){
  cors(res); if(req.method==='OPTIONS')return res.status(204).end(); if(req.method!=='POST')return res.status(405).json({error:'POST only'});
  const driverId=requireToken(req,res); if(!driverId)return;
  const body=bodyOf(req),parsed=parseOfferText(body.text||body.rawText||''),lat=Number(body.lat),lng=Number(body.lng),zone=body.zone||zoneFor(lat,lng),vehicle=normalizeVehicle(body.vehicle||'ebike'),timeZone=String(body.timeZone||body.tz||DEFAULT_TIMEZONE).slice(0,80),timeBlock=String(body.timeBlock||timeBlockForDate(new Date(),timeZone)).toUpperCase(),marketCell=marketCellFor(lat,lng,vehicle),idleMinutes=Number(body.idleMinutes||0),mode=idleMinutes>=15?'escape':idleMinutes>=8?'slow':'normal',rate=effectiveOfferRate({...parsed,mode});
  const row={driver_id:driverId,source:body.source||'uber_eats',captured_at:new Date().toISOString(),payout:parsed.payout,miles:parsed.miles,eta_minutes:parsed.etaMinutes,merchant:parsed.merchant,is_shop:parsed.isShop,item_count:parsed.itemCount,parser_confidence:parsed.confidence,raw_text:parsed.rawText,lat:Number.isFinite(lat)?lat:null,lng:Number.isFinite(lng)?lng:null,zone,vehicle,time_block:timeBlock,market_cell:marketCell,state:'observed'};
  let saved=null;if(dbConfigured()){try{saved=await insert('offers',row)}catch(error){return res.status(500).json({error:error.message,parsed,rate})}}
  const target=Number(process.env.TARGET_DPH||35),verdict=rate?.dollarsPerHour>=target?'TAKE':rate?.dollarsPerHour>=target*.82?'BORDERLINE':'SKIP';
  return res.status(200).json({ok:true,persisted:Boolean(saved),id:saved?.[0]?.id||null,parsed,rate,verdict,zone,vehicle,timeBlock,marketCell,mode});
}