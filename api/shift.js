import { cors, requireToken, dbConfigured, insert, select, patch, bodyOf } from './_shared.js';
export default async function handler(req,res){
 cors(res); if(req.method==='OPTIONS')return res.status(204).end();
 const driverId=requireToken(req,res); if(!driverId)return;
 if(!dbConfigured())return res.status(503).json({error:'Supabase is not configured'});
 try{
  if(req.method==='GET'){
   const rows=await select(`shifts?driver_id=eq.${driverId}&order=started_at.desc&limit=10&select=*`);
   return res.status(200).json({shifts:rows||[],active:(rows||[]).find(x=>!x.ended_at)||null});
  }
  if(req.method!=='POST')return res.status(405).json({error:'GET/POST only'});
  const body=await bodyOf(req), action=String(body.action||'start');
  if(action==='start'){
   const open=await select(`shifts?driver_id=eq.${driverId}&ended_at=is.null&order=started_at.desc&limit=1&select=*`);
   if(open?.[0])return res.status(200).json({ok:true,shift:open[0],resumed:true});
   const out=await insert('shifts',{driver_id:driverId,vehicle:body.vehicle||'ebike',started_at:new Date().toISOString()});
   return res.status(200).json({ok:true,shift:out?.[0]});
  }
  if(action==='end'){
   const open=await select(`shifts?driver_id=eq.${driverId}&ended_at=is.null&order=started_at.desc&limit=1&select=*`);
   if(!open?.[0])return res.status(409).json({error:'No active shift'});
   const out=await patch(`shifts?id=eq.${open[0].id}&driver_id=eq.${driverId}`,{ended_at:new Date().toISOString()});
   return res.status(200).json({ok:true,shift:out?.[0]});
  }
  return res.status(400).json({error:'Unknown action'});
 }catch(error){return res.status(500).json({error:error.message})}
}