import XCTest
@testable import RadarCore

final class AdaptivePlannerTests:XCTestCase {
    let home=GeoPoint(lat:34.024,lng:-118.3945)
    let now=ISO8601DateFormatter().date(from:"2026-10-27T19:00:00Z")!
    func planner(idle:Double=0,range:Double?=nil,work:Double=600)->AdaptivePlanner {
        AdaptivePlanner(snapshot:DispatchSnapshot(),history:[],
            policy:DriverPolicy(dailyGoal:270,calibrationDay:"1900-01-01",batteryMiles:range,estimatedSpeedMPH:12),
            context:AdaptiveContext(idleMinutes:idle,additionalAvailableMinutes:idle,
                acceptancePercent:60,workingMinutesLeft:work),now:now)
    }
    func offer(price:Double=8,minutes:Double=15,drop:GeoPoint?=nil)->RadarOffer {
        let dest=drop ?? home
        return RadarOffer(payout:price,miles:1,etaMinutes:minutes,capturedAt:now,
                          lat:home.lat,lng:home.lng,dropoffLat:dest.lat,dropoffLng:dest.lng)
    }
    func testIdleExposureReducesReplacementValueInsteadOfRepeatingSameSkipForever(){
        let first=planner().evaluate(offer(),position:home)
        let later=planner(idle:10).evaluate(offer(),position:home)
        XCTAssertLessThan(later.replacementGrossHourly,first.replacementGrossHourly)
        XCTAssertGreaterThan(later.expectedWaitMinutes,first.expectedWaitMinutes)
        XCTAssertLessThan(later.minimumPayout,first.minimumPayout)
    }
    func testOutboundReturnCostChangesAnOtherwiseIdenticalOffer(){
        let local=planner().evaluate(offer(),position:home)
        let outbound=planner().evaluate(offer(drop:.init(lat:33.99,lng:-118.414)),position:home)
        XCTAssertGreaterThan(outbound.extraRecoveryMinutes,10)
        XCTAssertGreaterThan(outbound.minimumPayout,local.minimumPayout)
        XCTAssertEqual(outbound.action,.skip)
    }
    func testFastSmallLocalOfferCanBeatAnEightDollarLongCycle(){
        XCTAssertEqual(planner().evaluate(offer(price:6,minutes:8),position:home).action,.take)
        XCTAssertEqual(planner().evaluate(offer(price:13.15,minutes:52.4),position:home).action,.skip)
    }
    func testPastWaitingNeverOverridesRangeOrMissingMapPin(){
        XCTAssertEqual(planner(idle:15,range:2).evaluate(offer(price:30),position:home).action,.check)
        var missing=offer();missing.dropoffLat=nil;missing.dropoffLng=nil
        XCTAssertEqual(planner(idle:15).evaluate(missing,position:home).action,.check)
    }
    func testLowPrecisionGeocodeIsNotAFreeReturn(){
        var street=offer();street.destinationConfidence=0.55
        XCTAssertEqual(planner().evaluate(street,position:home).action,.check)
    }
    func testFullWorkingDayGoalUsesOnlineHours(){
        let result=planner().evaluate(offer(),position:home)
        XCTAssertEqual(result.requiredGrossHourly,27,accuracy:0.001)
        XCTAssertEqual(result.idleBudgetMinutes,result.deliveryMinutes*0.25,accuracy:0.001)
    }
    func testShiftEndAndAddOnNeedSeparateChecks(){
        XCTAssertEqual(planner(work:10).evaluate(offer(price:40,minutes:30),position:home).action,.skip)
        var addon=offer(price:6,minutes:8);addon.offerKind="addon"
        XCTAssertEqual(planner().evaluate(addon,position:home).action,.check)
    }
    func testNativeCashPlannerActuallyRoutesToAdaptivePolicy(){
        let p=CashPlanner(snapshot:DispatchSnapshot(),history:[],policy:.init(calibrationDay:"1900-01-01"),now:now,
                          adaptiveContext:.init(additionalAvailableMinutes:10))
        var missing=offer();missing.dropoffLat=nil
        XCTAssertEqual(p.offerDecision(missing,position:home).kind,.check)
    }
    func testReturnSpeedUsesRoadFactorAndIntersectionTime(){
        let miles=home.miles(to:.init(lat:34.04,lng:-118.42))
        XCTAssertEqual(AdaptivePlanner.bikeMinutes(from:home,to:.init(lat:34.04,lng:-118.42)),miles*1.25/12*60+2,accuracy:0.001)
    }
    func testFreshMarketSignalsInfluencePriorButStaleSignalsDoNot(){
        let base=planner(),original=base.evaluate(offer(),position:home)
        var fresh=base
        fresh.context.marketSignals=[.init(point:home,nearbyVenues:30,observedUberMerchants:4,footTrafficIndex:100,capturedAt:now)]
        XCTAssertGreaterThan(fresh.evaluate(offer(),position:home).replacementGrossHourly,original.replacementGrossHourly)
        fresh.context.marketSignals[0].capturedAt=now.addingTimeInterval(-1800)
        XCTAssertEqual(fresh.evaluate(offer(),position:home).replacementGrossHourly,original.replacementGrossHourly,accuracy:0.001)
    }
}
