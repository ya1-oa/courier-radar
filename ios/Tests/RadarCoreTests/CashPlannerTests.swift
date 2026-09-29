import XCTest
@testable import RadarCore

final class CashPlannerTests:XCTestCase {
    let westwood=GeoPoint(lat:34.0627,lng:-118.4455)
    let culver=GeoPoint(lat:34.0211,lng:-118.3965)
    let date=ISO8601DateFormatter().date(from:"2026-09-29T19:00:00Z")!
    func data(_ zone:String, _ rate:Double, _ n:Double=12, _ duration:Double=19) -> DispatchSnapshot {
        DispatchSnapshot(pooled:.init(rate:0.065,payout:8,duration:22),
            zones:[.init(zone:zone,block:"LUNCH",availableMinutes:180,offers:n,
                          rate:rate,payout:9,duration:duration,confidence:0.91,sampled:true,
                          lat:zone=="Westwood" ? westwood.lat:culver.lat,
                          lng:zone=="Westwood" ? westwood.lng:culver.lng)])
    }
    func offer(_ payout:Double=8,_ miles:Double=1,_ eta:Double=20) -> RadarOffer {
        RadarOffer(merchant:"Test",payout:payout,miles:miles,etaMinutes:eta,
                   lat:westwood.lat,lng:westwood.lng)
    }
    func testZoneAndDaypart() {
        XCTAssertEqual(MarketZone.identify(westwood),"Westwood")
        XCTAssertEqual(WorkClock.block(at:date),"LUNCH")
        XCTAssertEqual(WorkClock.workday(at:date),"2026-09-29")
        XCTAssertNil(MarketZone.identify(nil))
    }
    func testCalibrationDoesNotRejectFeasibleLowOffer() {
        let planner=CashPlanner(snapshot:data("Westwood",0.2),
                         history:[],policy:.init(calibrationDay:"2026-09-29"),now:date)
        XCTAssertEqual(planner.offerDecision(offer(4,1,45),position:westwood).kind,.take)
    }
    func testMissingEconomicsMustBeChecked() {
        let planner=CashPlanner(snapshot:data("Westwood",0.1),history:[],
               policy:.init(calibrationDay:"2026-09-28"),now:date)
        XCTAssertEqual(planner.offerDecision(offer(8,0,0),position:westwood).kind,.check)
    }
    func testBatteryReserveStopsUnsafeOffer() {
        let planner=CashPlanner(snapshot:data("Westwood",0.1),history:[],
               policy:.init(calibrationDay:"2026-09-29",batteryMiles:4.5),now:date)
        XCTAssertEqual(planner.offerDecision(offer(20,3,25),position:westwood).kind,.check)
        XCTAssertEqual(planner.waitDecision(position:westwood).kind,.wait)
    }
    func testSparseHistoryDoesNotInventSkipOrMove() {
        let snapshot=DispatchSnapshot()
        let planner=CashPlanner(snapshot:snapshot,history:[],
               policy:.init(calibrationDay:"2026-09-28"),now:date)
        XCTAssertEqual(planner.offerDecision(offer(7,2,26),position:westwood).kind,.take)
        XCTAssertEqual(planner.waitDecision(position:westwood).kind,.wait)
    }
    func testEmptyBatterySignalsCharge() {
        let planner=CashPlanner(snapshot:data("Westwood",0.12),history:[],
               policy:.init(calibrationDay:"2026-09-28",batteryMiles:3.5),now:date)
        XCTAssertEqual(planner.waitDecision(position:westwood).kind,.charge)
    }
    func testStopTimeCrossesMidnight() {
        let date=ISO8601DateFormatter().date(from:"2026-09-30T05:00:00Z")!
        XCTAssertTrue(WorkClock.minutesUntilStop(now:date,clock:"01:00")>0)
        XCTAssertEqual(WorkClock.workday(at:date),"2026-09-29")
    }
    func testNoInventedDeclineCausality() {
        let p=CashPlanner(snapshot:data("Westwood",0.12),history:[],
               policy:.init(calibrationDay:"2026-09-28"),now:date)
        XCTAssertNotNil(p.offerDecision(offer(),position:westwood).skipValue)
    }
}
