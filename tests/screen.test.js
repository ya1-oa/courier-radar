import test from 'node:test';
import assert from 'node:assert/strict';
import {inspectUberScreen,screenTransition} from '../lib-screen.js';

test('offer screenshot is an offer, not lifecycle',()=>{
 const text='$10.02\n34 min (3.1 mi) total\nMendocino Farms\nDelivery (2)\nAccept';
 const result=inspectUberScreen(text);
 assert.equal(result.kind,'offer');
 assert.equal(result.parsed.payout,10.02);
 assert.equal(result.parsed.stackCount,2);
});
test('duplicate offer screenshot remains offer signal',()=>{
 const screen='$7.64\n31 min (3.9 mi) total\nWingstop\nAccept request';
 assert.equal(inspectUberScreen(screen).kind,'offer');
});
test('pickup screen containing an old payout is classified as lifecycle',()=>{
 const text='Confirm pickup\n$10.02\n34 min\n3.1 mi\nMendocino Farms';
 const screen=inspectUberScreen(text);
 assert.equal(screen.kind,'lifecycle');
 assert.equal(screen.stage,'arrived');
});
test('stage screenshots recognize accepted, pickup, dropoff and completed',()=>{
 const texts=[['Navigate to pickup location','accepted'],['Confirm pickup at restaurant','arrived'],['Meet at door\nNavigate to customer','picked_up'],['Delivery completed!','delivered']];
 for(const [text,stage] of texts){const r=inspectUberScreen(text);assert.equal(r.kind,'lifecycle');assert.equal(r.stage,stage)}
});
test('imperative delivery button is NOT a completion confirmation',()=>{
 assert.notEqual(inspectUberScreen('Mark as delivered\nConfirm delivery').stage,'delivered');
});
test('unknown screenshot has no side effects',()=>{
 assert.equal(inspectUberScreen('iPhone 5G battery 72% 9:41').kind,'unknown');
});
test('screens cannot skip or regress lifecycle states',()=>{
 assert.equal(screenTransition('observed','accepted'),'accepted');
 assert.equal(screenTransition('accepted','arrived'),'arrived');
 assert.equal(screenTransition('arrived','picked_up'),'picked_up');
 assert.equal(screenTransition('picked_up','delivered'),'delivered');
 assert.equal(screenTransition('observed','delivered'),null);
 assert.equal(screenTransition('delivered','accepted'),null);
 assert.equal(screenTransition('observed','picked_up'),null);
});
