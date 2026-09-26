import { cors, requireToken, dbConfigured, select, upsert, insert, bodyOf } from './_shared.js';

const defaults={vehicle:'ebike',target_dph:35,speed_low_mph:12,speed_mid_mph:16,speed_high_mph:20,active_speed_level:'high',service_overhead_minutes:4.5,acceptance_rate_current:null,acceptance_rate_floor:30};

function clean(body={}){
  const vehicle=['ebike','bike','car'].includes(body.vehicle)?body.vehicle:'ebike';
  const target=Math.max(10,Math.min(150,Number(body.target_dph ?? body.target ?? 35)));
  const low=Math.max(3,Math.min(40,Number(body.speed_low_mph ?? 12)));
  const mid=Math.max(3,Math.min(40,Number(body.speed_mid_mph ?? 16)));
  const high=Math.max(3,Math.min(40,Number(body.speed_high_mph ?? 20)));
  const level=['low','mid','high'].includes(body.active_speed_level)?body.active_speed_level:'high';
  const overhead=Math.max(0,Math.min(30,Number(body.service_overhead_minutes ?? 4.5)));
  const arRaw=body.acceptance_rate_current,arCurrent=arRaw==null||arRaw===''?null:Math.max(0,Math.min(100,Number(arRaw))),arFloor=Math.max(0,Math.min(100,Number(body.acceptance_rate_floor ?? 30)));return {vehicle,target_dph:target,speed_low_mph:low,speed_mid_mph:mid,speed_high_mph:high,active_speed_level:level,service_overhead_minutes:overhead,acceptance_rate_current:Number.isFinite(arCurrent)?arCurrent:null,acceptance_rate_floor:arFloor};
}

export default async function handler(req,res){
  cors(res); if(req.method==='OPTIONS')return res.status(204).end();
  const driverId=requireToken(req,res); if(!driverId)return;
  if(!dbConfigured())return res.status(503).json({error:'Supabase is not configured'});
  try{
    if(req.method==='GET' && String(req.query?.resource||'')==='recommendations'){const rows=await select(`recommendation_logs?driver_id=eq.${driverId}&order=created_at.desc&limit=100&select=*`);return res.status(200).json({recommendations:rows||[]})}
    if(req.method==='POST' && String(req.query?.resource||'')==='recommendation'){const b=await bodyOf(req),n=v=>{const x=Number(v);return Number.isFinite(x)?x:null},row={driver_id:driverId,context:String(b.context||'live').slice(0,32),action:String(b.action||'').slice(0,80)||null,zone_type:String(b.zoneType||'').slice(0,40)||null,target_label:String(b.targetLabel||'').slice(0,180)||null,target_lat:n(b.targetLat),target_lng:n(b.targetLng),origin_lat:n(b.originLat),origin_lng:n(b.originLng),distance_miles:n(b.distanceMiles),confidence:n(b.confidence),score:n(b.score),reason:String(b.reason||'').slice(0,800)||null,idle_minutes:n(b.idleMinutes),time_block:String(b.timeBlock||'').slice(0,40)||null,source:String(b.source||'').slice(0,180)||null,evidence:b.evidence&&typeof b.evidence==='object'?b.evidence:{}};const out=await insert('recommendation_logs',row);return res.status(200).json({ok:true,id:out?.[0]?.id||null})}
    if(req.method==='GET'){
      const rows=await select(`driver_settings?driver_id=eq.${driverId}&limit=1&select=*`);
      return res.status(200).json({settings:{...defaults,...(rows?.[0]||{})}});
    }
    if(req.method==='POST'){
      const body=await bodyOf(req),row={driver_id:driverId,...clean(body),updated_at:new Date().toISOString()};
      const out=await upsert('driver_settings',row,'driver_id');
      return res.status(200).json({ok:true,settings:out?.[0]||row});
    }
    return res.status(405).json({error:'GET/POST only'});
  }catch(error){return res.status(500).json({error:error.message})}
}
