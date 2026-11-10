import XCTest
@testable import RadarCore

final class OfferPolicyTests:XCTestCase {
    func offer(_ pay:Double=13,_ miles:Double=3,_ minutes:Double=20)->RadarOffer {
        RadarOffer(payout:pay,miles:miles,etaMinutes:minutes)
    }
    func testThreeInputsUseTenPercentBufferAndBothThresholds(){
        let a=OfferPolicy.evaluate(offer())
        XCTAssertEqual(a.action,.take)
        XCTAssertEqual(a.tier,"STRONG ACCEPT")
        XCTAssertEqual(a.adjustedMinutes,22,accuracy:0.001)
        XCTAssertEqual(a.hourlyGross,35.4545,accuracy:0.01)
        XCTAssertEqual(a.dollarsPerMile,13.0/3,accuracy:0.001)
        XCTAssertEqual(a.minimumPayout,8.8,accuracy:0.001)
    }
    func testSixDollarFastOfferPasses(){
        XCTAssertEqual(OfferPolicy.evaluate(offer(6,1.2,10)).action,.take)
    }
    func testLongLowValueOfferFailsEvenWithSparseLearning(){
        XCTAssertEqual(OfferPolicy.evaluate(offer(8,4,35)).action,.skip)
    }
    func testTwentyFourDollarHourlyButPoorMileageRequiresReview(){
        XCTAssertEqual(OfferPolicy.evaluate(offer(10,7,23),cruiseMph:22).action,.check)
    }
    func testMissingUberETAIsNotReplacedWithRadarEstimate(){
        var o=offer()
        o.etaMinutes=nil
        o.radarEtaMinutes=20
        XCTAssertEqual(OfferPolicy.evaluate(o).action,.check)
    }
    func testBatteryAndSpeedSafeguards(){
        XCTAssertEqual(OfferPolicy.evaluate(offer(),batteryMiles:4).action,.check)
        XCTAssertEqual(OfferPolicy.evaluate(offer(15,6,8)).action,.check)
    }
    func testShopAndAddOnAreChecks(){
        var shop=offer()
        shop.isShop=true
        XCTAssertEqual(OfferPolicy.evaluate(shop).action,.check)
        var addon=offer()
        addon.offerKind="addon"
        XCTAssertEqual(OfferPolicy.evaluate(addon).action,.check)
    }
}
