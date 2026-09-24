import * as maplibregl from 'https://unpkg.com/maplibre-gl@6.10.0/dist/maplibre-gl.mjs';
let map=null,ready=null,centeredOnce=false;const DEFAULT_CENTER=[-118.3965,34.0211];const collection=(features=[])=>({type:'FeatureCollection',features});
export function initRadarMap(){if(ready)return ready;ready=new Promise((resolve,reject)=>{try{
 map=new maplibregl.Map({container:'radarMap',style:'https://tiles.openfreemap.org/styles/liberty',center:DEFAULT_CENTER,zoom:14.1,attributionControl:false});
 map.addControl(new maplibregl.AttributionControl({compact:true}),'bottom-right');
 map.on('load',()=>{
  map.addSource('radar-cells',{type:'geojson',data:collection([])});
  map.addLayer({id:'radar-cells-fill',type:'fill',source:'radar-cells',paint:{'fill-color':['interpolate',['linear'],['coalesce',['get','score'],0],0,'#ff625e',45,'#ffb341',70,'#c8e84d',100,'#5df28f'],'fill-opacity':['interpolate',['linear'],['coalesce',['get','confidence'],.1],0,.08,1,.28]}});
  map.addLayer({id:'radar-cells-line',type:'line',source:'radar-cells',paint:{'line-color':['interpolate',['linear'],['coalesce',['get','score'],0],0,'#ff625e',55,'#ffb341',100,'#5df28f'],'line-width':1.2,'line-opacity':.5}});
  map.addSource('radar-pickups',{type:'geojson',data:collection([]),cluster:true,clusterMaxZoom:16,clusterRadius:34});
  map.addLayer({id:'pickup-clusters',type:'circle',source:'radar-pickups',filter:['has','point_count'],paint:{'circle-color':'#00dca0','circle-radius':['step',['get','point_count'],14,4,18,10,22,25,27],'circle-opacity':.92,'circle-stroke-color':'#d9fff3','circle-stroke-width':1.5}});
  map.addLayer({id:'pickup-cluster-count',type:'symbol',source:'radar-pickups',filter:['has','point_count'],layout:{'text-field':['get','point_count_abbreviated'],'text-size':11},paint:{'text-color':'#001d16'}});
  map.addLayer({id:'pickup-dot',type:'circle',source:'radar-pickups',filter:['!',['has','point_count']],paint:{'circle-radius':7,'circle-color':'#00f58a','circle-opacity':.95,'circle-stroke-color':'#e4fff5','circle-stroke-width':1.5}});
  map.addSource('radar-user',{type:'geojson',data:collection([])});
  map.addSource('radar-destination',{type:'geojson',data:collection([])});map.addSource('radar-target',{type:'geojson',data:collection([])});
  map.addLayer({id:'radar-user-halo',type:'circle',source:'radar-user',paint:{'circle-radius':18,'circle-color':'#147cff','circle-opacity':.18}});
  map.addLayer({id:'radar-user-dot',type:'circle',source:'radar-user',paint:{'circle-radius':7,'circle-color':'#147cff','circle-stroke-color':'#fff','circle-stroke-width':2.5}});
  map.addLayer({id:'radar-destination-halo',type:'circle',source:'radar-destination',paint:{'circle-radius':17,'circle-color':'#ffb341','circle-opacity':.18}});
  map.addLayer({id:'radar-destination-dot',type:'circle',source:'radar-destination',paint:{'circle-radius':8,'circle-color':'#ffb341','circle-stroke-color':'#fff','circle-stroke-width':2}});map.addLayer({id:'radar-target-halo',type:'circle',source:'radar-target',paint:{'circle-radius':22,'circle-color':'#a3ff55','circle-opacity':.14}});map.addLayer({id:'radar-target-dot',type:'circle',source:'radar-target',paint:{'circle-radius':9,'circle-color':'#a3ff55','circle-stroke-color':'#07131b','circle-stroke-width':3}});
  map.on('click','pickup-clusters',async e=>{const f=e.features?.[0];if(!f)return;const zoom=await map.getSource('radar-pickups').getClusterExpansionZoom(f.properties.cluster_id);map.easeTo({center:f.geometry.coordinates,zoom,duration:450})});
  map.on('click','pickup-dot',e=>{const f=e.features?.[0];if(!f)return;const p=f.properties||{};new maplibregl.Popup({closeButton:false,offset:10}).setLngLat(e.lngLat).setHTML(`<div class="radar-popup"><b>${escapeHtml(p.merchant||'Pickup')}</b><div>Pickup arrival${p.payout?` · $${Number(p.payout).toFixed(2)}`:''}</div><div>${escapeHtml(p.zone||'')}</div></div>`).addTo(map)});
  map.on('click','radar-cells-fill',e=>{const f=e.features?.[0];if(!f)return;const p=f.properties||{};new maplibregl.Popup({closeButton:false,offset:8}).setLngLat(e.lngLat).setHTML(`<div class="radar-popup"><b>${escapeHtml(p.label||p.zone||'Demand area')}</b><div>${escapeHtml(p.heat||'LEARNING')} · ${p.offers??0} offers</div><div>${p.offersPerOnlineHour??'—'} observed offers/hr · ${Math.round(Number(p.confidence||0)*100)}% confidence</div>${p.merchants?`<div>${escapeHtml(p.merchants)}</div>`:''}</div>`).addTo(map)});
  resolve(map);
 });
 map.on('error',event=>{const message=event?.error?.message||'';if(message&&!message.includes('404'))console.warn('Map error:',message)});
}catch(error){reject(error)}});return ready}
export async function updateRadarMap({features=[],position=null,destination=null,target=null,history=[],fit=false}={}){
 await initRadarMap();map.getSource('radar-cells')?.setData(collection(features));
 const pickups=(history||[]).filter(p=>p.event==='arrived'&&Number.isFinite(Number(p.lat))&&Number.isFinite(Number(p.lng))).map(p=>({type:'Feature',properties:{zone:p.zone||'',merchant:p.merchant||'',payout:p.payout||null},geometry:{type:'Point',coordinates:[Number(p.lng),Number(p.lat)]}}));
 map.getSource('radar-pickups')?.setData(collection(pickups));
 if(position&&Number.isFinite(position.lat)&&Number.isFinite(position.lng)){map.getSource('radar-user')?.setData(collection([{type:'Feature',properties:{},geometry:{type:'Point',coordinates:[position.lng,position.lat]}}]));if(fit||!centeredOnce){centeredOnce=true;map.easeTo({center:[position.lng,position.lat],zoom:14.6,duration:650})}}else map.getSource('radar-user')?.setData(collection([]));
 if(destination&&Number.isFinite(Number(destination.lat))&&Number.isFinite(Number(destination.lng)))map.getSource('radar-destination')?.setData(collection([{type:'Feature',properties:{zone:destination.zone||''},geometry:{type:'Point',coordinates:[Number(destination.lng),Number(destination.lat)]}}]));else map.getSource('radar-destination')?.setData(collection([]));
 if(target&&Number.isFinite(Number(target.lat))&&Number.isFinite(Number(target.lng)))map.getSource('radar-target')?.setData(collection([{type:'Feature',properties:{label:target.label||''},geometry:{type:'Point',coordinates:[Number(target.lng),Number(target.lat)]}}]));else map.getSource('radar-target')?.setData(collection([]));
 map.resize();
}
export async function centerRadarMap(position){await initRadarMap();if(position&&Number.isFinite(position.lat)&&Number.isFinite(position.lng))map.easeTo({center:[position.lng,position.lat],zoom:Math.max(map.getZoom(),14.6),duration:500})}
function escapeHtml(value=''){return String(value).replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[m]))}