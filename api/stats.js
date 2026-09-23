import { cors, requireToken, dbConfigured, select } from './_shared.js';
const mins=(a,b)=>Math.max(0,(new Date(b)-new Date(a))/60000);
export default async function handler(req,res){
 cors(res); if(req.method==='OPTIONS')return res.status(204).end(); if(req.method!=='GET')return res.status(405).json({error:'GET only'});
 const driverId=requireToken(req,res);if(!driverId)return;if(!dbConfigured())return res.status(503).json({error:'Supabase is not configured'});
 const since=new Date(Date.now()-30*86400000).toISOString();
 try{
  const [offers,events,presence,shifts,earnings,goals]=await Promise.all([
   select(`offers?driver_id=eq.${driverId}&captured_at=gte.${encodeURIComponent(since)}&order=captured_at.asc&limit=2000&select=*`),
   select(`offer_events?driver_id=eq.${driverId}&captured_at=gte.${encodeURIComponent(since)}&order=captured_at.asc&limit=5000&select=*`),
   select(`presence?driver_id=eq.${driverId}&captured_at=gte.${encodeURIComponent(since)}&order=captured_at.asc&limit=10000&select=*`),
   select(`shifts?driver_id=eq.${driverId}&started_at=gte.${encodeURIComponent(since)}&order=started_at.desc&limit=100&select=*`),
   select(`earnings_imports?driver_id=eq.${driverId}&occurred_at=gte.${encodeURIComponent(since)}&order=occurred_at.asc&limit=5000&select=*`),
   select(`driver_goals?driver_id=eq.${driverId}&limit=1&select=*`)
  ]);
  const isSignal=o=>Number(o?.payout)>0||Number(o?.miles)>0||Number(o?.eta_minutes)>0||/(guaranteed|incl\. tip|includes expected tip|shop & deliver|add a delivery|accept request|\bdelivery\b|\baccept\b)/i.test(String(o?.raw_text||''));
  const signalOffers=(offers||[]).filter(isSignal);
  const byOffer=new Map(); for(const e of events||[]){if(!byOffer.has(e.offer_id))byOffer.set(e.offer_id,[]);byOffer.get(e.offer_id).push(e)}
  const completed=signalOffers.filter(o=>['delivered','completed'].includes(o.state));
  const offerPayout=completed.reduce((s,o)=>s+Number(o.final_payout??o.payout??0),0);
  const imported=(earnings||[]).reduce((s,e)=>s+Number(e.amount||0),0);
  const totalEarnings=imported||offerPayout;
  const active=(shifts||[]).find(s=>!s.ended_at)||null;
  const onlineMinutes=(shifts||[]).reduce((s,x)=>s+mins(x.started_at,x.ended_at||new Date().toISOString()),0);
  const lastOffer=signalOffers.at(-1)||null;
  const idleMinutes=active?mins(lastOffer?.captured_at||active.started_at,new Date().toISOString()):0;
  const merchants={}; for(const o of signalOffers){const k=o.merchant||'Unknown';const ev=byOffer.get(o.id)||[],arr=ev.find(e=>e.event==='arrived'),pick=ev.find(e=>e.event==='picked_up');const m=merchants[k]||={merchant:k,offers:0,completed:0,payout:0,waits:[]};m.offers++;if(['delivered','completed'].includes(o.state)){m.completed++;m.payout+=Number(o.final_payout??o.payout??0)}if(arr&&pick)m.waits.push(mins(arr.captured_at,pick.captured_at));merchants[k]=m}
  const merchantStats=Object.values(merchants).map(m=>({...m,avgWaitMinutes:m.waits.length?Number((m.waits.reduce((a,b)=>a+b,0)/m.waits.length).toFixed(1)):null})).sort((a,b)=>b.offers-a.offers).slice(0,20);
  const zones={};for(const e of events||[]){if(!e.zone||e.zone==='Unknown')continue;const z=zones[e.zone]||={zone:e.zone,events:0,delivered:0};z.events++;if(e.event==='delivered')z.delivered++;zones[e.zone]=z}
  return res.status(200).json({activeShift:active,onlineMinutes:Number(onlineMinutes.toFixed(1)),idleMinutes:Number(idleMinutes.toFixed(1)),offers:signalOffers.length,completed:completed.length,totalEarnings:Number(totalEarnings.toFixed(2)),offerPayout:Number(offerPayout.toFixed(2)),importedEarnings:Number(imported.toFixed(2)),onlineDph:onlineMinutes?Number((totalEarnings/(onlineMinutes/60)).toFixed(2)):0,monthlyGoal:Number(goals?.[0]?.monthly_goal||4000),merchantStats,zones:Object.values(zones),recentEvents:(events||[]).slice(-100)});
 }catch(error){return res.status(500).json({error:error.message})}
}