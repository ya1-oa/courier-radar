import test from 'node:test';
import assert from 'node:assert/strict';
import {buildDispatchModel,dispatchZone,dispatchBlock,decideDispatchOffer,decideDispatchWait} from '../lib-dispatch.js';
const now=Date.parse('2026-09-29T20:00:00Z'),iso=n=>new Date(n).toISOString(),westwood={lat:34.0627,lng:-118.4455},village={lat:34.027,lng:-118.444};
const st={started_at:iso(now-120*60000),ended_at:iso(now)};
function pings(count=60){return Array.from({length:count},(_,i)=>({captured_at:iso(now-(count-i)*120000),event:'heartbeat',vehicle:'ebike',...westwood}))}
const base=(over={})=>({version:4,zones:[],pooled:{rate:1/16,payout:7.5,duration:24},decline:{observedExcessMinutes:0},...over});
function z(zone,rate,amount,minutes=100,n=12,coords=westwood){return{zone,block:'LUNCH',rate,payout:amount,duration:16,confidence:0.95,availableMinutes:minutes,offers:n,sampled:true,...coords}}
test('invalid and missing GPS never becomes a geographic zone',()=>{
 assert.equal(dispatchZone(null,null),null);assert.equal(dispatchZone(undefined,undefined),null);assert.equal(dispatchZone(34.0627,-118.4455),'Westwood');
});
test('correct time-of-day block, localized to Los Angeles',()=>{
 assert.equal(dispatchBlock(now),'LUNCH');
});
test('background GPS gaps are censored; no synthetic hours counted',()=>{
 const ps=[{captured_at:iso(now-60*60000),...westwood,vehicle:'ebike'},{captured_at:iso(now-5*60000),...westwood,vehicle:'ebike'}];
 const m=buildDispatchModel({presence:ps,shifts:[st],now});
 assert.ok(m.verifiedAvailableMinutes<=5.1,m.verifiedAvailableMinutes);
 assert.equal(m.gpsSamples,2);
});
test('delivery lifecycles remove busy minutes from waiting exposure',()=>{
 const ps=pings(60),offer={id:'busy',captured_at:iso(now-78*60000),payout:10,miles:2,eta_minutes:28,merchant:'Test',...westwood};
 const events=[{offer_id:'busy',event:'accepted',captured_at:iso(now-76*60000)},{offer_id:'busy',event:'delivered',captured_at:iso(now-48*60000)}];
 const model=buildDispatchModel({offers:[offer],events,presence:ps,shifts:[st],now});
 assert.ok(model.verifiedAvailableMinutes>80&&model.verifiedAvailableMinutes<95,model.verifiedAvailableMinutes);
});
test('identical OCR copies do not inflate offer count',()=>{
 const offers=[{id:'a',merchant:'Demo',captured_at:iso(now-30*60000),payout:8,miles:1,eta_minutes:20,...westwood},{id:'b',merchant:'Demo',captured_at:iso(now-29*60000),payout:8,miles:1,eta_minutes:20,...westwood}];
 const m=buildDispatchModel({offers,presence:pings(),shifts:[st],now});
 assert.equal(m.offersCaptured,1);
});
test('low-data default accepts guaranteed feasible money',()=>{
 const a=decideDispatchOffer({model:base(),offer:{payout:10,miles:3.1,eta_minutes:34,...westwood},position:westwood,now});
 assert.equal(a.verdict,'TAKE');assert.equal(a.mode,'LOW DATA');
});
test('calibration collects offers without hour-rate rejection',()=>{
 const m=base({zones:[z('Westwood',.2,12)]});
 const a=decideDispatchOffer({model:m,offer:{payout:3,miles:1,eta_minutes:43,...westwood},position:westwood,now,calibration:true});
 assert.equal(a.verdict,'TAKE');assert.equal(a.mode,'CALIBRATION');
});
test('trained model may reject a weak order for real opportunity cost',()=>{
 const m=base({zones:[z('Westwood',.2,12)]});
 const a=decideDispatchOffer({model:m,offer:{payout:3,miles:2,eta_minutes:45,...westwood},position:westwood,now,remainingMinutes:120});
 assert.equal(a.verdict,'SKIP');assert.ok(a.skipValue>a.takeValue);
});
test('battery reserve check stops an unsafe order even during calibration',()=>{
 const a=decideDispatchOffer({model:base(),offer:{payout:20,miles:6,eta_minutes:30,...westwood},position:westwood,now,batteryMiles:7,calibration:true});
 assert.equal(a.verdict,'CHECK');
});
test('unknown battery and sparse nearby data never invent a move target',()=>{
 const a=decideDispatchWait({model:base(),position:westwood,now});
 assert.equal(a.advice,'WAIT');assert.ok(!a.target);
});
test('RETURN requires real comparative exposure, not restaurant density',()=>{
 const m=base({zones:[z('Westside Village',.018,6,100,10,village),z('Westwood',.17,11,150,18,westwood)]});
 const a=decideDispatchWait({model:m,position:village,now,remainingMinutes:130,lastOriginZone:'Westwood'});
 assert.equal(a.advice,'RETURN');assert.equal(a.target.zone,'Westwood');
 const sparse=base({zones:[z('Westside Village',.018,6,100,10,village),z('Westwood',.17,11,2,1,westwood)]});
 assert.equal(decideDispatchWait({model:sparse,position:village,now,lastOriginZone:'Westwood'}).advice,'WAIT');
});
test('low e-bike range requires charge, not merchant hopping',()=>{
 assert.equal(decideDispatchWait({model:base(),position:westwood,now,batteryMiles:3.5}).advice,'CHARGE');
});
