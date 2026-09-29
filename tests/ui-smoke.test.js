import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const source=p=>readFileSync(new URL('../'+p,import.meta.url),'utf8');
const html=source('index.html'),app=source('app.js'),ui=source('ui.css'),sw=source('sw.js');
test('all four screens share the same final design stylesheet',()=>{
 assert.match(html,/href="\/ui\.css"/);
 for(const name of ['live','history','money','plan'])assert.match(html,new RegExp('data-view="'+name+'"'));
 assert.match(ui,/\.page-title/);
 assert.match(ui,/\.history-section/);
 assert.match(ui,/\.live-map-view/);
 assert.match(ui,/\.bottom-nav/);
 assert.match(ui,/\.onboard/);
});
test('all documented controls are actually wired and uniquely identified',()=>{
 for(const id of ['quickNext','captureEndpoint','copyCaptureEndpoint','homeGoalRemaining','activityRate','routeToTarget','startPlanRefresh']){
  const matches=[...html.matchAll(new RegExp('id="'+id+'"','g'))];
  assert.equal(matches.length,1,id+' must exist exactly once');
  assert.ok(app.includes("$('"+id+"')"),id+' must have code binding');
 }
});
test('new style and algorithm are refreshed in offline cache',()=>{
 assert.match(sw,/\/ui\.css/);
 assert.match(sw,/\/lib-screen\.js/);
});
test('screen lifecycle remains an inferred observation; unseen offers are not user declines',()=>{
 const cap=source('api/capture.js'),stats=source('api/stats.js');
 assert.match(cap,/inspectUberScreen/);
 assert.match(cap,/screenTransition/);
 assert.match(cap,/event:'expired'/);
 assert.match(cap,/event:'inferred_delivery'/);
 assert.match(stats,/o\.state!=='rejected'/);
});
