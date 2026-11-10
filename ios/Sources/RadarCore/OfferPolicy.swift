import Foundation

/// A direct mirror of the web payout checker. No private Uber queue assumptions.
/// Requires the three Uber-screen fields: total payout, total miles, total ETA.
public struct OfferAssessment: Sendable {
    public let action:RecommendationKind
    public let tier:String
    public let reason:String
    public let hourlyGross:Double
    public let dollarsPerMile:Double
    public let adjustedMinutes:Double
    public let minimumPayout:Double
    public let validInput:Bool
}

public enum OfferPolicy {
    public static let bufferPercent=10.0
    public static let hourlyFloor=24.0
    public static let strongHourly=28.0
    public static let borderlineHourly=20.0
    public static let perMileFloor=1.50

    public static func evaluate(_ offer:RadarOffer,cruiseMph:Double=21,batteryMiles:Double?=nil) -> OfferAssessment {
        func check(_ message:String,_ hourly:Double=0,_ perMile:Double=0,_ adjusted:Double=0,_ minimum:Double=0)->OfferAssessment {
            .init(action:.check,tier:"CHECK",reason:message,hourlyGross:hourly,dollarsPerMile:perMile,
                  adjustedMinutes:adjusted,minimumPayout:minimum,validInput:hourly>0)
        }
        guard let payout=offer.payout,payout.isFinite,payout>0,
              let miles=offer.miles,miles.isFinite,miles>0,
              let eta=offer.etaMinutes,eta.isFinite,eta>0 else {
            return check("Uber payout, total miles and Uber estimated minutes are all required.")
        }
        let adjusted=eta*1.10
        let hourly=payout*60/adjusted
        let perMile=payout/miles
        let minimum=max(hourlyFloor*adjusted/60,perMileFloor*miles)
        let speed=cruiseMph.isFinite ? min(22,max(6,cruiseMph)) : 21
        if let range=batteryMiles,range.isFinite,miles+2>range {
            return check("Battery range may not cover this order plus a 2-mile reserve.",hourly,perMile,adjusted,minimum)
        }
        if eta+0.5 < miles/speed*60 {
            return check("Uber ETA is shorter than estimated nonstop bike riding time. Verify route.",hourly,perMile,adjusted,minimum)
        }
        if offer.offerKind=="addon" {
            return check("Add-on: verify combined-route payout, miles and extra minutes.",hourly,perMile,adjusted,minimum)
        }
        if offer.isShop == true {
            return check("Shop & Pay: verify ETA includes shopping and checkout time.",hourly,perMile,adjusted,minimum)
        }
        let take=hourly>=hourlyFloor && perMile>=perMileFloor
        let strong=take && hourly>=strongHourly
        let action:RecommendationKind=take ? .take : (hourly>=borderlineHourly ? .check : .skip)
        let tier=strong ? "STRONG ACCEPT" : (take ? "ACCEPT" : (hourly>=borderlineHourly ? "BORDERLINE" : "DECLINE"))
        let reason=String(format:"%@: $%.2f/hr, $%.2f/mi, %.1f min including 10%% buffer. No extra pickup/dropoff time.",
                          tier,hourly,perMile,adjusted)
        return .init(action:action,tier:tier,reason:reason,hourlyGross:hourly,
                     dollarsPerMile:perMile,adjustedMinutes:adjusted,minimumPayout:minimum,validInput:true)
    }
}
