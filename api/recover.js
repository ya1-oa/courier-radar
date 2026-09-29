import { cors, requireToken, dbConfigured, select, insert, bodyOf } from './_shared.js';
import { zoneFor } from './_shared.js';
import { marketCellFor, timeBlockForDate } from '../lib-network.js';

// Explicitly user-reported recovery. Never turns a missed offer into verified dispatch exposure.
const stages = new Set(['accepted','arrived','picked_up','delivered','observed']);
const dateWithin = (x, now, days) => {
 const t = Date.parse(x);
 return Number.isFinite(t) && t >= now-days*86400000 && t <= now+120000 ? t : null;
};
const coord = x => x===undefined||x===null||x===''?null:Number(x);
export default async function handler(req,res) {
 cors(res);
 if(req.method==='OPTIONS') return res.status(204).end();
 if(req.method!=='POST') return res.status(405).json({error:'POST only'});
 const driverId=requireToken(req,res);
 if(!driverId)return;
 if(!dbConfigured())return res.status(503).json({error:'Database not configured'});
 const b=await bodyOf(req),now=Date.now();
 const stage=String(b.state||'').toLowerCase(),merchant=String(b.merchant||'').trim().slice(0,160);
 const payout=Number(b.payout),miles=b.miles==null||b.miles===''?null:Number(b.miles),eta=b.etaMinutes==null||b.etaMinutes===''?null:Number(b.etaMinutes);
 const acceptedAt=dateWithin(b.acceptedAt,now,14),finishedAt=b.finishedAt?dateWithin(b.finishedAt,now,14):null;
 const lat=coord(b.lat),lng=coord(b.lng),gps=Number.isFinite(lat)&&Number.isFinite(lng)&&Math.abs(lat)>1&&Math.abs(lng)>1;
 const clientId=String(b.clientId||'').trim();
 if(!/^[a-zA-Z0-9-]{16,80}$/.test(clientId))return res.status(400).json({error:'Provide a unique recovery ID'});
 if(!stages.has(stage)||!merchant||!Number.isFinite(payout)||payout<=0||payout>2000)
   return res.status(400).json({error:'Merchant, positive payout and valid delivery stage are required'});
 if((miles!==null&&(!Number.isFinite(miles)||miles<0||miles>250))||(eta!==null&&(!Number.isFinite(eta)||eta<1||eta>360)))
   return res.status(400).json({error:'Distance or duration invalid'});
 if(acceptedAt===null)return res.status(400).json({error:'Choose the approximate time the order started, within 14 days'});
 if(stage==='delivered'&&(finishedAt===null||finishedAt<acceptedAt))
   return res.status(400).json({error:'Completed orders need their actual or approximate completion time'});
 if(finishedAt!==null&&finishedAt<acceptedAt)return res.status(400).json({error:'Completion cannot precede start'});
 const raw='MANUAL_RECOVERY:'+clientId;
 try {
  // Same retry key produces one row even if the user double-taps.
  const old=await select('offers?driver_id=eq.'+driverId+'&source=eq.manual_recovery&raw_text=eq.'+encodeURIComponent(raw)+'&limit=1&select=id,state');
  if(old?.length)return res.status(200).json({ok:true,id:old[0].id,state:old[0].state,duplicate:true,manual:true});
  const row={
   driver_id:driverId,source:'manual_recovery',raw_text:raw,
   captured_at:new Date(acceptedAt).toISOString(),
   merchant,payout,miles,eta_minutes:eta,
   final_payout:stage==='delivered'?payout:null,
   state:stage,vehicle:'ebike',parser_confidence:null,
   lat:gps?lat:null,lng:gps?lng:null,
   zone:gps?zoneFor(lat,lng):null,
   time_block:timeBlockForDate(new Date(acceptedAt)),
   market_cell:gps?marketCellFor(lat,lng,'ebike'):null
  };
  const saved=await insert('offers',row),offer=saved?.[0];
  if(!offer?.id)return res.status(502).json({error:'Recovery could not be saved'});
  // User-supplied timestamps are explicitly manual and can be corrected later.
  // Only a known start and known end justify a modeled busy-time interval.
  if(stage!=='observed'){
   await insert('offer_events',{offer_id:offer.id,driver_id:driverId,event:'accepted',captured_at:new Date(acceptedAt).toISOString(),
         lat:gps?lat:null,lng:gps?lng:null,zone:gps?zoneFor(lat,lng):null,
         market_cell:gps?marketCellFor(lat,lng,'ebike'):null});
   if(stage==='delivered'){
     await insert('offer_events',{offer_id:offer.id,driver_id:driverId,event:'delivered',
       captured_at:new Date(finishedAt).toISOString(),
       lat:null,lng:null,zone:null,market_cell:null});
   }
  }
  return res.status(201).json({ok:true,manual:true,duplicate:false,id:offer.id,state:stage,merchant,payout,capturedAt:row.captured_at});
 }catch(error){return res.status(500).json({error:error.message})}
}