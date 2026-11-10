import test from 'node:test';
import assert from 'node:assert/strict';
import {evaluateOffer} from '../lib-offer-policy.js';

test('three inputs, 10% buffer, and two thresholds drive the payout checker',()=>{
 const a=evaluateOffer({payout:13,miles:3,uberMinutes:20});
 assert.equal(a.verdict,'TAKE');assert.equal(a.tier,'STRONG ACCEPT');
 assert.equal(a.hourlyGross,35.45);assert.equal(a.dollarsPerMile,4.33);
 assert.equal(a.adjustedMinutes,22);assert.equal(a.minimumPayout,8.8);
});
test('a very quick $6 order is accepted; no hard $8 floor',()=>{
 const a=evaluateOffer({payout:6,miles:1.2,uberMinutes:10});
 assert.equal(a.verdict,'TAKE');
});
test('a long underpaying order is declined',()=>{
 const a=evaluateOffer({payout:8,miles:4,uberMinutes:35});
 assert.equal(a.verdict,'SKIP');
});
test('insufficient pay per mile is borderline even when hourly is high',()=>{
 const a=evaluateOffer({payout:10,miles:7,uberMinutes:23,cruiseMph:22});
 assert.equal(a.verdict,'CHECK');
 assert.equal(a.tier,'BORDERLINE');
});
test('must provide all three Uber fields',()=>{
 for(const args of [
  {payout:10,miles:2},{payout:10,uberMinutes:12},{miles:2,uberMinutes:12},
  {payout:0,miles:2,uberMinutes:12},{payout:10,miles:0,uberMinutes:12}
 ]) assert.equal(evaluateOffer(args).verdict,'CHECK');
});
test('the rider speed is only an ETA sanity check, not additional time',()=>{
 assert.equal(evaluateOffer({payout:10,miles:5,uberMinutes:8}).verdict,'CHECK');
 const a=evaluateOffer({payout:13,miles:3,uberMinutes:20,cruiseMph:20});
 assert.equal(a.adjustedMinutes,22);
});
test('unknown battery does not prevent a decision, known insufficient miles checks',()=>{
 assert.equal(evaluateOffer({payout:13,miles:3,uberMinutes:20,batteryMiles:null}).verdict,'TAKE');
 assert.equal(evaluateOffer({payout:13,miles:3,uberMinutes:20,batteryMiles:4}).verdict,'CHECK');
});
test('a busy shop-and-pay or an add-on is not auto accepted',()=>{
 assert.equal(evaluateOffer({payout:20,miles:2,uberMinutes:25,isShop:true}).verdict,'CHECK');
 assert.equal(evaluateOffer({payout:20,miles:2,uberMinutes:25,offerKind:'addon'}).verdict,'CHECK');
});
test('buffer is optional and never double counts pickup or drop-off',()=>{
 const a=evaluateOffer({payout:8,miles:2,uberMinutes:20,bufferPercent:0});
 assert.equal(a.adjustedMinutes,20);
 assert.equal(a.hourlyGross,24);
});
