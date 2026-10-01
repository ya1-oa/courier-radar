import ActivityKit
import Foundation

/// Shared contract between the iOS app and the Dynamic Island widget extension.
/// Only a short-lived, user-captured offer is displayed. This is not an Uber overlay.
struct RadarDecisionAttributes:ActivityAttributes {
    struct ContentState:Codable,Hashable {
        var verdict:String
        var merchant:String
        var payout:String
        var reason:String
        var capturedAt:Date
        var expiresAt:Date
        var nextAction:String?
        var progress:String?
    }
    var label:String
}
