import Foundation

/// Manual, rested voltage estimate for common lithium-ion e-bike packs.
/// This is not live BMS telemetry; load, temperature and aging affect voltage.
public struct BatteryVoltageEstimate:Sendable {
    public let percent:Double
    public let usableMiles:Double
    public let warning:String
}
public enum BatteryVoltage {
    public static func estimate(volts:Double,nominal:Int,fullRangeMiles:Double)->BatteryVoltageEstimate? {
        guard volts.isFinite,fullRangeMiles.isFinite,fullRangeMiles>0,
              fullRangeMiles<=150 else{return nil}
        let limits:(Double,Double)
        switch nominal {
        case 36: limits=(31.5,42.0)
        case 48: limits=(41.0,54.6)
        case 52: limits=(44.0,58.8)
        default:return nil
        }
        guard volts>=limits.0-2,volts<=limits.1+1.5 else{return nil}
        let percent=max(0,min(100,(volts-limits.0)/(limits.1-limits.0)*100))
        // Keep a 15% state-of-charge reserve, and discount the remaining usable range.
        let miles=max(0,fullRangeMiles*max(0,(percent-15)/85)*0.85)
        return BatteryVoltageEstimate(percent:percent,usableMiles:miles,
            warning:"Estimate from resting voltage only. Verify range on your bike.")
    }
}
