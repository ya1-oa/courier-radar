import Foundation

/// Learned zone|block offer-rate multipliers from daily reviews (server-bounded 0.7–1.3).
struct LearningPayload:Decodable {
    var multipliers:[String:Double]?
    var days:Int?
    var lastDay:String?
    var lastTier:String?
    var lastScore:Int?
}
struct ReviewMetrics:Decodable {
    var earnings:Double?
    var capturedEarnings:Double?
    var earningsSource:String?
    var orders:Int?
    var offersSeen:Int?
    var taken:Int?
    var skipped:Int?
    var expired:Int?
    var acceptance:Double?
    var onlineMinutes:Double?
    var paidMinutes:Double?
    var waitingMinutes:Double?
    var utilization:Double?
    var dph:Double?
    var avgPayout:Double?
    var followedRadar:Int?
    var overrodeRadar:Int?
}
struct ReviewEstimate:Decodable {
    var upside:Double?
    var potentialEarnings:Double?
    var potentialDph:Double?
    var basis:String?
}
struct ReviewComponents:Decodable {
    var dph:Double?
    var gross:Double?
    var utilization:Double?
    var acceptance:Double?
}
struct ReviewMistake:Decodable,Identifiable {
    var kind:String
    var merchant:String?
    var zone:String?
    var block:String?
    var minutes:Double?
    var estimatedCost:Double?
    var detail:String?
    var id:String {kind+(merchant ?? zone ?? "")+(detail ?? "")}
}
struct ReviewDecision:Decodable,Identifiable {
    var at:Date?
    var merchant:String?
    var payout:Double?
    var miles:Double?
    var cycleMinutes:Double?
    var impliedDph:Double?
    var action:String
    var radar:String?
    var followedRadar:Bool?
    var grade:String
    var estimatedCost:Double?
    var restaurantWait:Double?
    var zone:String?
    var id:String {"\(at?.timeIntervalSince1970 ?? 0)|\(merchant ?? "")|\(payout ?? 0)"}
}
struct ReviewSegment:Decodable,Identifiable {
    var zone:String
    var block:String
    var start:Date?
    var end:Date?
    var minutes:Double?
    var busyMinutes:Double?
    var idleMinutes:Double?
    var id:String {"\(zone)|\(start?.timeIntervalSince1970 ?? 0)"}
}
struct ReviewZoneBlock:Decodable,Identifiable {
    var key:String
    var zone:String
    var block:String
    var minutes:Double?
    var idleMinutes:Double?
    var offers:Int?
    var earned:Double?
    var offersPerIdleHour:Double?
    var historyPerHour:Double?
    var id:String {key}
}
struct ShiftReview:Decodable {
    var scope:String
    var start:Date?
    var end:Date?
    var tier:String
    var score:Int
    var components:ReviewComponents?
    var metrics:ReviewMetrics
    var estimate:ReviewEstimate?
    var mistakes:[ReviewMistake]
    var decisions:[ReviewDecision]
    var segments:[ReviewSegment]
    var zoneBlocks:[ReviewZoneBlock]
}
struct AIImprovement:Decodable,Identifiable {
    var title:String
    var detail:String
    var estimatedGain:Double?
    var estimatedCost:Double?
    var id:String {title+detail}
}
struct AIAdjustment:Decodable,Identifiable {
    var key:String
    var multiplier:Double
    var reason:String
    var id:String {key}
}
struct AIReview:Decodable {
    var configured:Bool?
    var error:String?
    var skipped:Bool?
    var headline:String?
    var summary:String?
    var mistakes:[AIImprovement]?
    var improvements:[AIImprovement]?
    var tomorrow:[String]?
    var adjustments:[AIAdjustment]?
}
struct ShiftReviewPayload:Decodable {
    var ok:Bool?
    var day:String
    var shiftId:String?
    var session:ShiftReview
    var dayReview:ShiftReview
    var ai:AIReview?
    var adjustments:[String:Double]?
    var learned:[String:Double]?
    var saved:Bool?
    var saveError:String?
}
