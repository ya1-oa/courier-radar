import test from 'node:test';
import assert from 'node:assert/strict';
import handler from '../api/coach.js';
function response(){return {code:200,payload:null,setHeader(){},status(c){this.code=c;return this;},json(p){this.payload=p;return this;},end(){return this;}};}
function request(state={algorithm:{action:'TAKE',cycleMinutes:20}}){return {method:'POST',headers:{'x-capture-token':process.env.CAPTURE_TOKEN},body:{offerId:'offer-1',capturedAt:new Date().toISOString(),state}};}
async function isolated(fn){
 const token=process.env.CAPTURE_TOKEN,key=process.env.OPENAI_API_KEY,fetcher=globalThis.fetch;
 process.env.CAPTURE_TOKEN='test-'+Math.random();process.env.OPENAI_API_KEY='test-only-not-a-real-key';
 try{await fn();}finally{
  globalThis.fetch=fetcher;
  if(token===undefined)delete process.env.CAPTURE_TOKEN;else process.env.CAPTURE_TOKEN=token;
  if(key===undefined)delete process.env.OPENAI_API_KEY;else process.env.OPENAI_API_KEY=key;
 }
}
const advice={action:'TAKE',reason:'Short local cycle.',afterDropoff:'Stay near Culver Steps.',nextTrigger:'Review after five available minutes.',confidence:.8,assumptions:['12 mph urban estimate']};
test('OpenAI endpoint requires the private Radar token before any provider request',()=>isolated(async()=>{
 let called=false;globalThis.fetch=async()=>{called=true;throw Error();};
 const req=request();req.headers={};const res=response();await handler(req,res);
 assert.equal(res.code,401);assert.equal(called,false);
}));
test('missing server key returns an explicit configuration state without calling OpenAI',()=>isolated(async()=>{
 delete process.env.OPENAI_API_KEY;let called=false;globalThis.fetch=async()=>{called=true;throw Error();};
 const res=response();await handler(request(),res);assert.equal(res.code,503);assert.equal(res.payload.configured,false);assert.equal(called,false);
}));
test('expired screenshot cannot incur an AI charge',()=>isolated(async()=>{
 let called=false;globalThis.fetch=async()=>{called=true;throw Error();};
 const req=request();req.body.capturedAt=new Date(Date.now()-60000).toISOString();
 const res=response();await handler(req,res);assert.equal(res.code,409);assert.equal(called,false);
}));
test('valid native context uses structured Responses output and duplicate reviews are cached',()=>isolated(async()=>{
 let calls=0;
 globalThis.fetch=async(url,options)=>{
  calls++;assert.equal(url,'https://api.openai.com/v1/responses');
  const body=JSON.parse(options.body);assert.equal(body.store,false);assert.equal(body.text.format.strict,true);
  assert.equal(body.model,'gpt-5.4-mini');assert.equal(body.max_output_tokens,800);
  return {ok:true,json:async()=>({status:'completed',output:[{type:'message',content:[{type:'output_text',text:JSON.stringify(advice)}]}],usage:{input_tokens:100,output_tokens:80}})};
 };
 const req=request(),a=response();await handler(req,a);assert.equal(a.code,200);assert.equal(a.payload.advice.action,'TAKE');
 const b=response();await handler(req,b);assert.equal(b.payload.cached,true);assert.equal(calls,1);
 assert.ok(!JSON.stringify(a.payload).includes(process.env.OPENAI_API_KEY));
}));
test('provider failure returns a usable native-math fallback without exposing provider body',()=>isolated(async()=>{
 globalThis.fetch=async()=>({ok:false,status:429,json:async()=>({secret:'do not expose'})});
 const res=response();await handler(request(),res);assert.equal(res.code,502);assert.equal(res.payload.providerStatus,429);
 assert.ok(!JSON.stringify(res.payload).includes('do not expose'));
}));
test('malformed screenshots are rejected before provider access',()=>isolated(async()=>{
 let called=false;globalThis.fetch=async()=>{called=true;throw Error();};
 const req=request();req.body.screenshotBase64='https://example.com/not-an-image';
 const res=response();await handler(req,res);assert.equal(res.code,400);assert.equal(called,false);
}));
test('incomplete responses never become a TAKE recommendation',()=>isolated(async()=>{
 globalThis.fetch=async()=>({ok:true,json:async()=>({status:'incomplete',output:[]})});
 const res=response();await handler(request(),res);assert.equal(res.code,502);assert.ok(!res.payload.advice);
}));
