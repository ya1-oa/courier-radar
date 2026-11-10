// Rider-owned payout checker. No Uber dispatch or supply/queue claims.
export const OFFER_POLICY=Object.freeze({
 bufferPercent:10, hourlyFloor:24, strongHourly:28, borderlineHourly:20,
 mileageFloor:1.50, cruiseMph:21, batteryReserveMiles:2
});
const present=x=>x!==null&&x!==undefined&&x!==''&&Number.isFinite(Number(x));
const round=(n,d=2)=>Number(n.toFixed(d));
/** Uber ETA is already a whole-order estimate; never add artificial pickup/dropoff time.
 *  Only use an explicit rider-provided miles-remaining value for battery safety.
 *  Do not infer remaining miles from nominal voltage or displayed battery percentage.
 */
export function evaluateOffer({payout,miles,uberMinutes,
 bufferPercent=OFFER_POLICY.bufferPercent,cruiseMph=OFFER_POLICY.cruiseMph,
 batteryMiles=null,offerKind='single',isShop=false}={}){
 const base={version:'offer-v1',mode:'PAYOUT_ETA_MILES',
  hourlyFloor:OFFER_POLICY.hourlyFloor,mileageFloor:OFFER_POLICY.mileageFloor};
 const check=(reason,fields={})=>({...base,...fields,verdict:'CHECK',tier:'CHECK',reason});
 if(!present(payout)||!present(miles)||!present(uberMinutes)||
    Number(payout)<=0||Number(miles)<=0||Number(uberMinutes)<=0)
  return check('Uber payout, total miles, and Uber estimated minutes are required.');
 const pay=Number(payout),distance=Number(miles),eta=Number(uberMinutes);
 const buffer=present(bufferPercent)?Math.max(0,Math.min(50,Number(bufferPercent))):10;
 const speed=present(cruiseMph)?Math.max(6,Math.min(22,Number(cruiseMph))):21;
 const time=eta*(1+buffer/100),hourly=pay*60/time,perMile=pay/distance;
 const cruisingMinutes=distance/speed*60;
 const fields={payout:pay,miles:distance,eta,bufferPercent:buffer,
  adjustedMinutes:round(time,1),hourlyGross:round(hourly),
  dollarsPerMile:round(perMile),cruiseMph:speed,
  minimumCruisingMinutes:round(cruisingMinutes,1),
  minimumPayout:round(Math.max(OFFER_POLICY.hourlyFloor*time/60,OFFER_POLICY.mileageFloor*distance))};
 if(present(batteryMiles)&&distance+OFFER_POLICY.batteryReserveMiles>Number(batteryMiles))
  return check('Check range: offer distance plus 2-mile safety reserve exceeds confirmed remaining miles.',fields);
 if(eta+0.5<cruisingMinutes)
  return check('Uber ETA appears shorter than nonstop riding time at your e-bike cruising speed. Verify route.',fields);
 if(offerKind==='addon')
  return check('Add-on: confirm total combined-route pay, distance and extra minutes before accepting.',fields);
 if(isShop)
  return check('Shopping order: verify Uber ETA includes shopping and checkout time.',fields);
 const meetsMiles=perMile>=OFFER_POLICY.mileageFloor,meetsHourly=hourly>=OFFER_POLICY.hourlyFloor;
 const accept=meetsMiles&&meetsHourly;
 const strong=accept&&hourly>=OFFER_POLICY.strongHourly;
 const borderline=hourly>=OFFER_POLICY.borderlineHourly;
 const verdict=accept?'TAKE':borderline?'CHECK':'SKIP';
 const tier=strong?'STRONG ACCEPT':accept?'ACCEPT':borderline?'BORDERLINE':'DECLINE';
 const reason=tier+': $'+round(hourly).toFixed(2)+'/hr, $'+round(perMile).toFixed(2)+
  '/mi, '+round(time,1)+' min including '+buffer+'% buffer. '+
  (meetsMiles?'':'Below $1.50/mi. ')+(meetsHourly?'':'Below $24/hr. ')+
  (verdict==='CHECK'?'Review route, destination and demand.':'No extra stop-time added.');
 return {...base,...fields,verdict,tier,reason};
}
