import * as maplibregl from 'https://unpkg.com/maplibre-gl@6.10.0/dist/maplibre-gl.mjs';

let map=null;
let ready=null;
let centeredOnce=false;
const DEFAULT_CENTER=[-118.3965,34.0211];
const fc=(features=[])=>({type:'FeatureCollection',features});
const validPoint=p=>p&&Number.isFinite(Number(p.lat))&&Number.isFinite(Number(p.lng));
const escapeHtml=(value='')=>String(value).replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[m]));

export function initRadarMap(){
 if(ready)return ready;
 ready=new Promise((resolve,reject)=>{
  try{
   const container=document.getElementById('radarMap');
   if(!container)throw new Error('radarMap container missing');
   map=new maplibregl.Map({
    container,
    style:'https://tiles.openfreemap.org/styles/liberty',
    center:DEFAULT_CENTER,
    zoom:14.1,
    attributionControl:false
   });
   map.addControl(new maplibregl.AttributionControl({compact:true}),'bottom-right');
   map.on('load',()=>{
    map.addSource('radar-cells',{type:'geojson',data:fc()});
    map.addLayer({id:'radar-cells-fill',type:'fill',source:'radar-cells',paint:{'fill-color':['interpolate',['linear'],['coalesce',['get','score'],0],0,'#ff625e',45,'#ffb341',70,'#c8e84d',100,'#5df28f'],'fill-opacity':['interpolate',['linear'],['coalesce',['get','confidence'],.1],0,.08,1,.28]}});
    map.addLayer({id:'radar-cells-line',type:'line',source:'radar-cells',paint:{'line-color':['interpolate',['linear'],['coalesce',['get','score'],0],0,'#ff625e',55,'#ffb341',100,'#5df28f'],'line-width':1.2,'line-opacity':.5}});
    map.addSource('radar-pickups',{type:'geojson',data:fc(),cluster:true,clusterMaxZoom:16,clusterRadius:34});
    map.addLayer({id:'pickup-clusters',type:'circle',source:'radar-pickups',filter:['has','point_count'],paint:{'circle-color':'#00dca0','circle-radius':['step',['get','point_count'],14,4,18,10,22,25,27],'circle-opacity':.92,'circle-stroke-color':'#d9fff3','circle-stroke-width':1.5}});
    map.addLayer({id:'pickup-cluster-count',type:'symbol',source:'radar-pickups',filter:['has','point_count'],layout:{'text-field':['get','point_count_abbreviated'],'text-size':11},paint:{'text-color':'#001d16'}});
    map.addLayer({id:'pickup-dot',type:'circle',source:'radar-pickups',filter:['!',['has','point_count']],paint:{'circle-radius':7,'circle-color':'#00f58a','circle-opacity':.95,'circle-stroke-color':'#e4fff5','circle-stroke-width':1.5}});
    for(const name of ['radar-user','radar-destination','radar-target','radar-route'])map.addSource(name,{type:'geojson',data:fc()});
    map.addLayer({id:'radar-user-halo',type:'circle',source:'radar-user',paint:{'circle-radius':18,'circle-color':'#147cff','circle-opacity':.18}});
    map.addLayer({id:'radar-user-dot',type:'circle',source:'radar-user',paint:{'circle-radius':7,'circle-color':'#147cff','circle-stroke-color':'#fff','circle-stroke-width':2.5}});
    map.addLayer({id:'radar-destination-halo',type:'circle',source:'radar-destination',paint:{'circle-radius':17,'circle-color':'#ffb341','circle-opacity':.18}});
    map.addLayer({id:'radar-destination-dot',type:'circle',source:'radar-destination',paint:{'circle-radius':8,'circle-color':'#ffb341','circle-stroke-color':'#fff','circle-stroke-width':2}});
    map.addLayer({id:'radar-target-halo',type:'circle',source:'radar-target',paint:{'circle-radius':22,'circle-color':'#a3ff55','circle-opacity':.14}});
    map.addLayer({id:'radar-route-line',type:'line',source:'radar-route',paint:{'line-color':'#a3ff55','line-width':3,'line-opacity':.72,'line-dasharray':[2,2]}});
    map.addLayer({id:'radar-target-dot',type:'circle',source:'radar-target',paint:{'circle-radius':11,'circle-color':'#a3ff55','circle-stroke-color':'#07131b','circle-stroke-width':3}});
    map.addLayer({id:'radar-target-label',type:'symbol',source:'radar-target',layout:{'text-field':['coalesce',['get','label'],'MOVE TARGET'],'text-size':11,'text-offset':[0,1.8],'text-max-width':12},paint:{'text-color':'#07131b','text-halo-color':'#a3ff55','text-halo-width':2}});
    map.on('click','pickup-clusters',async e=>{const feature=e.features?.[0];if(!feature)return;const zoom=await map.getSource('radar-pickups').getClusterExpansionZoom(feature.properties.cluster_id);map.easeTo({center:feature.geometry.coordinates,zoom,duration:450})});
    map.on('click','pickup-dot',e=>{const feature=e.features?.[0];if(!feature)return;const p=feature.properties||{};new maplibregl.Popup({closeButton:false,offset:10}).setLngLat(e.lngLat).setHTML(`<div class="radar-popup"><b>${escapeHtml(p.merchant||'Pickup')}</b><div>Pickup arrival${p.payout?` · $${Number(p.payout).toFixed(2)}`:''}</div><div>${escapeHtml(p.zone||'')}</div></div>`).addTo(map)});
    map.on('click','radar-cells-fill',e=>{const feature=e.features?.[0];if(!feature)return;const p=feature.properties||{};const dph=p.onlineDph!=null?` · $${Number(p.onlineDph).toFixed(0)}/hr`:'';new maplibregl.Popup({closeButton:false,offset:8}).setLngLat(e.lngLat).setHTML(`<div class="radar-popup"><b>${escapeHtml(p.label||p.zone||'Demand cell')}</b><div>${escapeHtml(p.heat||'LEARNING')} · ${p.offers??0} offers</div><div>${p.offersPerOnlineHour??'—'} observed offers/hr${dph} · ${Math.round(Number(p.confidence||0)*100)}% confidence</div>${p.merchants?`<div>${escapeHtml(p.merchants)}</div>`:''}</div>`).addTo(map)});
    map.resize();
    resolve(map);
   });
   map.on('error',event=>{const message=event?.error?.message||'';if(message&&!message.includes('404'))console.warn('Map error:',message)});
  }catch(error){ready=null;reject(error)}
 });
 return ready;
}

export async function updateRadarMap({features=[],position=null,destination=null,target=null,history=[],fit=false}={}){
 await initRadarMap();
 map.getSource('radar-cells')?.setData(fc(features));
 const pickups=(history||[]).filter(p=>p.event==='arrived'&&Number.isFinite(Number(p.lat))&&Number.isFinite(Number(p.lng))).map(p=>({type:'Feature',properties:{zone:p.zone||'',merchant:p.merchant||'',payout:p.payout||null},geometry:{type:'Point',coordinates:[Number(p.lng),Number(p.lat)]}}));
 map.getSource('radar-pickups')?.setData(fc(pickups));
 map.getSource('radar-user')?.setData(validPoint(position)?fc([{type:'Feature',properties:{},geometry:{type:'Point',coordinates:[Number(position.lng),Number(position.lat)]}}]):fc());
 if(validPoint(position)&&(fit||!centeredOnce)){centeredOnce=true;map.easeTo({center:[Number(position.lng),Number(position.lat)],zoom:14.6,duration:650})}
 map.getSource('radar-destination')?.setData(validPoint(destination)?fc([{type:'Feature',properties:{zone:destination.zone||''},geometry:{type:'Point',coordinates:[Number(destination.lng),Number(destination.lat)]}}]):fc());
 if(validPoint(target)){
  map.getSource('radar-target')?.setData(fc([{type:'Feature',properties:{label:target.label||'MOVE TARGET',type:target.type||''},geometry:{type:'Point',coordinates:[Number(target.lng),Number(target.lat)]}}]));
  map.getSource('radar-route')?.setData(validPoint(position)?fc([{type:'Feature',properties:{},geometry:{type:'LineString',coordinates:[[Number(position.lng),Number(position.lat)],[Number(target.lng),Number(target.lat)]]}}]):fc());
 }else{
  map.getSource('radar-target')?.setData(fc());
  map.getSource('radar-route')?.setData(fc());
 }
 requestAnimationFrame(()=>map?.resize());
}

export async function centerRadarMap(position){
 await initRadarMap();
 if(validPoint(position))map.easeTo({center:[Number(position.lng),Number(position.lat)],zoom:Math.max(map.getZoom(),14.6),duration:500});
}
