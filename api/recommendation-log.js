import { cors,requireToken,dbConfigured,insert,select,bodyOf } from './_shared.js';
export default async function handler(req,res){
 cors(res);if(req.method==='OPTIONS')return res.status(204).end();
 const driverId=requireToken(req,res);if(!driverId)return;
 if(!dbConfigured())return res.status(503).json({error:'Supabase is not configured'});
 if(req.method==='GET'){try{const rows=await select(`recommendation_logs?driver_id=eq.${driverId}&order=created_at.desc&limit=100&select=*`);return res.status(200).json({recommendations:rows||[]})}catch(e){return res.status(500).json({error:e.message})}}
 if(req.method!=='POST')return res.status(405).json({error:'GET/POST only'});
 const b=await bodyOf(req),n=v=>{const x=Number(v);return Number.isFinite(x)?x:null};
 const row={driver_id:driverId,context:String(b.context||'live').slice(0,32),action:String(b.action||'').slice(0,80)||null,zone_type:String(b.zoneType||'').slice(0,40)||null,target_label:String(b.targetLabel||'').slice(0,180)||null,target_lat:n(b.targetLat),target_lng:n(b.targetLng),origin_lat:n(b.originLat),origin_lng:n(b.originLng),distance_miles:n(b.distanceMiles),confidence:n(b.confidence),score:n(b.score),reason:String(b.reason||'').slice(0,800)||null,idle_minutes:n(b.idleMinutes),time_block:String(b.timeBlock||'').slice(0,40)||null,source:String(b.source||'').slice(0,180)||null,evidence:b.evidence&&typeof b.evidence==='object'?b.evidence:{}};
 try{const saved=await insert('recommendation_logs',row);return res.status(200).json({ok:true,id:saved?.[0]?.id||null})}catch(e){return res.status(500).json({error:e.message})}
}