import XCTest
@testable import RadarCore

final class BatteryVoltageTests:XCTestCase {
    func testFull48VPack() {
        let e=BatteryVoltage.estimate(volts:54.6,nominal:48,fullRangeMiles:20)
        XCTAssertNotNil(e)
        XCTAssertEqual(e!.percent,100,accuracy:0.1)
        XCTAssertLessThan(e!.usableMiles,20)
    }
    func testHalfRangeConservative() {
        let e=BatteryVoltage.estimate(volts:47.8,nominal:48,fullRangeMiles:20)!
        XCTAssertEqual(e.percent,50,accuracy:0.1)
        XCTAssertLessThan(e.usableMiles,10)
    }
    func testWrongProfileRejected() {
        XCTAssertNil(BatteryVoltage.estimate(volts:54,nominal:60,fullRangeMiles:20))
        XCTAssertNil(BatteryVoltage.estimate(volts:80,nominal:48,fullRangeMiles:20))
    }
    func testNearEmptyReserve() {
        let e=BatteryVoltage.estimate(volts:42,nominal:48,fullRangeMiles:20)!
        XCTAssertEqual(e.usableMiles,0,accuracy:0.1)
    }
}
