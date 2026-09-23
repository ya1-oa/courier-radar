import { cors, requireToken, dbConfigured, select, patch, insert, bodyOf, zoneFor } from './_shared.js';
import { marketCellFor, normalizeVehicle } from '../lib-network.js';

const NEXT={observed:'accepted',accepted:'arrived',arrived:'picked_up',picked_up:'delivered'};
const VALID=new Set(['accepted','arrived','picked_up','delivered','passed','rejected']);

export default async function handler(req,res){
  cors(res);
  if(req.method==='OPTIONS')return res.status(204).end();
  if(req.method!=='POST')return res.status(405).json({error:'POST only'});
  const driverId=requireToken(req,res); if(!driverId)return;
  if(!dbConfigured())return res.status(503).json({error:'Supabase is not configured'});
  const body=await bodyOf(req);
  try{
    const recent=await select(`offers?driver_id=eq.${driverId}&order=captured_at.desc&limit=1&select=id,captured_at,state,vehicle,batch_id,offer_kind,stack_count,payout,final_payout`);
    if(!recent?.length)return res.status(404).json({error:'No recent offer'});
    const offer=recent[0],requested=String(body.state||body.event||'next').toLowerCase();
    const state=requested==='next'?(NEXT[offer.state]||null):(VALID.has(requested)?requested:null);
    if(!state){
      return res.status(409).json({error:offer.state==='delivered'?'Latest order is already delivered. Capture the next offer first.':`Cannot advance from ${offer.state||'unknown'}`,currentState:offer.state});
    }
    const coord=v=>{if(v==null||v==='')return NaN;const m=String(v).match(/-?\d+(?:\.\d+)?/);return m?Number(m[0]):NaN};const lat=coord(body.lat??body.latitude??body.Latitude),lng=coord(body.lng??body.lon??body.longitude??body.Longitude),vehicle=normalizeVehicle(body.vehicle||offer.vehicle||'ebike');
    const zone=Number.isFinite(lat)&&Number.isFinite(lng)?zoneFor(lat,lng):null;
    const marketCell=marketCellFor(lat,lng,vehicle);
    const capturedAt=new Date().toISOString();
    const offerPatch={state};if(state==='delivered')offerPatch.final_payout=offer.final_payout??offer.payout??null;const updated=await patch(`offers?id=eq.${offer.id}&driver_id=eq.${driverId}`,offerPatch);
    if(offer.batch_id){
      const batchPatch=state==='delivered'?{state:'completed',completed_at:capturedAt}:{state:state==='accepted'?'active':state};
      await patch(`batches?id=eq.${offer.batch_id}&driver_id=eq.${driverId}`,batchPatch).catch(()=>null);
    }
    await insert('offer_events',{offer_id:offer.id,driver_id:driverId,event:state,captured_at:capturedAt,lat:Number.isFinite(lat)?lat:null,lng:Number.isFinite(lng)?lng:null,zone,market_cell:marketCell});
    return res.status(200).json({ok:true,id:offer.id,previousState:offer.state,state,label:state.replace('_',' ').toUpperCase(),capturedAt,batchId:offer.batch_id||null,offerKind:offer.offer_kind||'single',stackCount:offer.stack_count||1,locationRecorded:Boolean(Number.isFinite(lat)&&Number.isFinite(lng)),zone,marketCell,updated});
  }catch(error){return res.status(500).json({error:error.message})}
}