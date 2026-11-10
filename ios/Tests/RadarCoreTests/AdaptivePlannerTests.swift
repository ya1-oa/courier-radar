import XCTest
@testable import RadarCore

final class AdaptivePlannerTests:XCTestCase {
    let home=GeoPoint(lat:34.024,lng:-118.3945)
    let now=ISO8601DateFormatter().date(from:"2026-10-27T19:00:00Z")!

    func planner(idle:Double=0,range:Double?=nil,work:Double=600)->AdaptivePlanner {
        AdaptivePlanner(snapshot:DispatchSnapshot(),history:[],
            policy:DriverPolicy(dailyGoal:270,calibrationDay:"1900-01-01",batteryMiles:range,estimatedSpeedMPH:21),
            context:AdaptiveContext(idleMinutes:idle,additionalAvailableMinutes:idle,
                acceptancePercent:60,workingMinutesLeft:work),now:now)
    }
    func offer(price:Double=8,minutes:Double=15,miles:Double=1,drop:GeoPoint?=nil)->RadarOffer {
        let dest=drop ?? home
        return RadarOffer(payout:price,miles:miles,etaMinutes:minutes,capturedAt:now,
            lat:home.lat,lng:home.lng,dropoffLat:dest.lat,dropoffLng:dest.lng)
    }

    func testOfferVerdictStaysStableAsIdleTimeIncreases(){
        let first=planner().evaluate(offer(),position:home)
        let later=planner(idle:10).evaluate(offer(),position:home)
        XCTAssertEqual(first.action,later.action)
        XCTAssertEqual(first.minimumPayout,later.minimumPayout,accuracy:0.001)
        XCTAssertGreaterThanOrEqual(first.minimumPayout,6)
    }
    func testDestinationDistanceDoesNotInventNewDeliveryTime(){
        let local=planner().evaluate(offer(),position:home)
        let far=planner().evaluate(offer(drop:.init(lat:33.99,lng:-118.414)),position:home)
        XCTAssertEqual(far.deliveryMinutes,local.deliveryMinutes)
        XCTAssertEqual(far.minimumPayout,local.minimumPayout,accuracy:0.001)
        XCTAssertEqual(far.action,local.action)
    }
    func testFastSmallOfferBeatsSlowHighPayout(){
        XCTAssertEqual(planner().evaluate(offer(price:6,minutes:8),position:home).action,.take)
        XCTAssertEqual(planner().evaluate(offer(price:13.15,minutes:52.4),position:home).action,.skip)
    }
    func testBatteryMilesAndMissingUberETAAreChecks(){
        XCTAssertEqual(planner(range:2).evaluate(offer(price:30),position:home).action,.check)
        var missing=offer();missing.etaMinutes=nil;missing.radarEtaMinutes=15
        XCTAssertEqual(planner().evaluate(missing,position:home).action,.check)
    }
    func testMissingGPSPinDoesNotOverrideThreeScreenInputs(){
        var missing=offer();missing.dropoffLat=nil;missing.dropoffLng=nil
        XCTAssertEqual(planner().evaluate(missing,position:nil).action,.take)
    }
    func testDailyGoalPaceDiagnosticUsesRemainingOnlineHours(){
        let result=planner().evaluate(offer(),position:home)
        XCTAssertEqual(result.requiredGrossHourly,27,accuracy:0.001)
        XCTAssertEqual(result.idleBudgetMinutes,result.deliveryMinutes*0.25,accuracy:0.001)
    }
    func testExtraStopsRequireCheckingCombinedOffer(){
        var addon=offer(price:6,minutes:8);addon.offerKind="addon"
        XCTAssertEqual(planner().evaluate(addon,position:home).action,.check)
    }
    func testNativeCashPlannerUsesSamePolicy(){
        let p=CashPlanner(snapshot:DispatchSnapshot(),history:[],
                          policy:.init(calibrationDay:"1900-01-01"),now:now,
                          adaptiveContext:.init(additionalAvailableMinutes:10))
        XCTAssertEqual(p.offerDecision(offer(),position:home).kind,.take)
    }
    func testReturnRouteGeometryRemainsConservative(){
        let miles=home.miles(to:.init(lat:34.04,lng:-118.42))
        XCTAssertEqual(AdaptivePlanner.bikeMinutes(from:home,to:.init(lat:34.04,lng:-118.42)),
                       miles*1.25/12*60+2,accuracy:0.001)
    }
    func testObservedSignalCanInfluenceWaitEconomicsButNotOfferVerdict(){
        let base=planner(),original=base.evaluate(offer(),position:home)
        var fresh=base
        fresh.context.marketSignals=[.init(point:home,nearbyVenues:30,observedUberMerchants:4,
            footTrafficIndex:100,capturedAt:now)]
        let updated=fresh.evaluate(offer(),position:home)
        XCTAssertEqual(updated.action,original.action)
        XCTAssertEqual(updated.minimumPayout,original.minimumPayout,accuracy:0.001)
    }
}
