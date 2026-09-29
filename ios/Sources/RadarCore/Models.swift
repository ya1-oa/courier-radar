import Foundation

public struct GeoPoint: Hashable, Codable, Sendable {
    public let lat: Double
    public let lng: Double
    public init(lat: Double, lng: Double) { self.lat = lat; self.lng = lng }
    public var isValid: Bool {
        lat.isFinite && lng.isFinite && abs(lat) > 1 && abs(lat) <= 90 && abs(lng) > 1 && abs(lng) <= 180
    }
    public func miles(to other: GeoPoint) -> Double {
        let radians = Double.pi / 180
        let a = pow(sin((other.lat-lat)*radians/2),2)
            + cos(lat*radians)*cos(other.lat*radians)*pow(sin((other.lng-lng)*radians/2),2)
        return 3958.76 * 2 * asin(min(1, sqrt(max(0,a))))
    }
}

public enum MarketZone {
    public static let anchors: [(String,GeoPoint)] = [
        ("Westwood", .init(lat:34.0627,lng:-118.4455)),
        ("Century City", .init(lat:34.0554,lng:-118.4174)),
        ("Culver City", .init(lat:34.0211,lng:-118.3965)),
        ("Palms", .init(lat:34.026,lng:-118.4212)),
        ("Westside Village", .init(lat:34.027,lng:-118.444)),
        ("Mar Vista", .init(lat:34.006,lng:-118.431)),
        ("Santa Monica", .init(lat:34.018,lng:-118.491)),
        ("Venice", .init(lat:33.991,lng:-118.466)),
        ("Fox Hills", .init(lat:33.990,lng:-118.391)),
        ("USC", .init(lat:34.023,lng:-118.285)),
        ("Koreatown", .init(lat:34.063,lng:-118.301)),
        ("DTLA", .init(lat:34.046,lng:-118.250)),
        ("Sawtelle", .init(lat:34.037,lng:-118.449)),
        ("Brentwood", .init(lat:34.052,lng:-118.474))
    ]
    public static func identify(_ point: GeoPoint?) -> String? {
        guard let point, point.isValid else { return nil }
        if let candidate = anchors.min(by: { point.miles(to:$0.1) < point.miles(to:$1.1) }),
           point.miles(to:candidate.1) < 1.45 { return candidate.0 }
        return String(format: "Area %.3f,%.3f", (point.lat/0.014).rounded()*0.014, (point.lng/0.017).rounded()*0.017)
    }
}

public enum WorkClock {
    public static let laTimeZone = TimeZone(identifier:"America/Los_Angeles")!
    public static func calendar() -> Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = laTimeZone; return c
    }
    public static func block(at date: Date) -> String {
        let c=calendar(), parts=c.dateComponents([.hour,.minute],from:date)
        let h=Double(parts.hour ?? 0)+Double(parts.minute ?? 0)/60
        if h >= 6 && h < 10.5 { return "BREAKFAST" }
        if h >= 10.5 && h < 14.5 { return "LUNCH" }
        if h >= 14.5 && h < 16.5 { return "AFTERNOON" }
        if h >= 16.5 && h < 21 { return "DINNER" }
        if h >= 21 || h < 1 { return "LATE" }
        return "OFF-PEAK"
    }
    /// Shifts crossing midnight count toward the workday preceding 04:00.
    public static func workday(at date: Date) -> String {
        let shifted = date.addingTimeInterval(-4*3600)
        let c=calendar(), p=c.dateComponents([.year,.month,.day],from:shifted)
        return String(format:"%04d-%02d-%02d",p.year ?? 2026,p.month ?? 1,p.day ?? 1)
    }
    public static func minutesUntilStop(now:Date, clock:String) -> Int {
        let hhmm=clock.split(separator:":").compactMap { Int($0) }
        guard hhmm.count == 2 else { return 180 }
        let p=calendar().dateComponents([.hour,.minute],from:now)
        let minute=(p.hour ?? 0)*60+(p.minute ?? 0)
        let target=hhmm[0]*60+hhmm[1]
        let delta=target-minute
        return max(10,delta > 0 ? delta : delta+1440)
    }
}

public struct DispatchZone: Codable, Identifiable, Sendable {
    public var id: String { zone+"|"+block }
    public var zone:String
    public var block:String
    public var availableMinutes:Double
    public var offers:Double
    public var offersPerHour:Double?
    public var rate:Double
    public var payout:Double
    public var duration:Double
    public var confidence:Double
    public var sampled:Bool
    public var lat:Double?
    public var lng:Double?
    public var point: GeoPoint? {
        guard let lat,let lng else{return nil}
        let p=GeoPoint(lat:lat,lng:lng);return p.isValid ? p:nil
    }
    public init(zone:String,block:String,availableMinutes:Double,offers:Double,rate:Double,
                payout:Double,duration:Double,confidence:Double=0,sampled:Bool=false,
                lat:Double?=nil,lng:Double?=nil) {
        self.zone=zone;self.block=block;self.availableMinutes=availableMinutes;self.offers=offers
        self.offersPerHour=rate*60;self.rate=rate;self.payout=payout;self.duration=duration
        self.confidence=confidence;self.sampled=sampled;self.lat=lat;self.lng=lng
    }
}

public struct DispatchPooled: Codable, Sendable {
    public var rate:Double
    public var payout:Double
    public var duration:Double
    public init(rate:Double=1.0/16,payout:Double=7.5,duration:Double=24) {
        self.rate=rate;self.payout=payout;self.duration=duration
    }
}
public struct DeclineEvidence: Codable, Sendable {
    public var sampleSize:Int?
    public var baselineSize:Int?
    public var observedExcessMinutes:Double?
    public var isCausal:Bool?
}
public struct DispatchSnapshot: Codable, Sendable {
    public var version:Int?
    public var offersCaptured:Int?
    public var offersObservedAvailable:Int?
    public var verifiedAvailableMinutes:Double?
    public var shiftAvailableMinutes:Double?
    public var gpsSamples:Int?
    public var completedWindows:Int?
    public var pooled:DispatchPooled
    public var zones:[DispatchZone]
    public var decline:DeclineEvidence?
    public var limitations:[String]?
    public init(pooled:DispatchPooled = .init(),zones:[DispatchZone]=[]) {
        self.version=5; self.offersCaptured=0;self.offersObservedAvailable=0
        self.verifiedAvailableMinutes=0;self.shiftAvailableMinutes=0
        self.gpsSamples=0;self.completedWindows=0
        self.pooled=pooled;self.zones=zones;self.decline=nil;self.limitations=nil
    }
    public func estimate(zone:String?,block:String) -> DispatchZone {
        if let zone,let hit=zones.first(where:{$0.zone==zone && $0.block==block}) { return hit }
        return DispatchZone(zone:zone ?? "Unknown",block:block,availableMinutes:0,offers:0,
                            rate:pooled.rate,payout:pooled.payout,duration:pooled.duration)
    }
}
public struct RadarOffer: Codable, Identifiable, Sendable {
    public var id:String
    public var merchant:String?
    public var payout:Double?
    public var finalPayout:Double?
    public var miles:Double?
    public var etaMinutes:Double?
    public var radarEtaMinutes:Double?
    public var state:String?
    public var capturedAt:Date?
    public var lat:Double?
    public var lng:Double?
    public var dropoffLat:Double?
    public var dropoffLng:Double?
    public var dropoffZone:String?
    public var zone:String?
    public var isShop:Bool?
    public var itemCount:Int?
    public var stackCount:Int?
    public var offerKind:String?
    public var parserConfidence:Double?
    public var tripETA:Double { etaMinutes ?? radarEtaMinutes ?? 0 }
    public var pickupPoint:GeoPoint? {
        guard let lat, let lng else { return nil }
        return GeoPoint(lat:lat,lng:lng)
    }
    public var dropoffPoint:GeoPoint? {
        guard let dropoffLat,let dropoffLng else{return nil}
        return GeoPoint(lat:dropoffLat,lng:dropoffLng)
    }
    public var settledPayout:Double { finalPayout ?? payout ?? 0 }
    public init(id:String=UUID().uuidString,merchant:String?=nil,payout:Double?=nil,
                miles:Double?=nil,etaMinutes:Double?=nil,state:String?="observed",
                capturedAt:Date?=Date(),lat:Double?=nil,lng:Double?=nil,
                dropoffLat:Double?=nil,dropoffLng:Double?=nil) {
        self.id=id;self.merchant=merchant;self.payout=payout;self.miles=miles
        self.etaMinutes=etaMinutes;self.state=state;self.capturedAt=capturedAt
        self.lat=lat;self.lng=lng;self.dropoffLat=dropoffLat;self.dropoffLng=dropoffLng
        self.finalPayout=nil;self.radarEtaMinutes=nil;self.dropoffZone=nil;self.zone=nil
        self.isShop=nil;self.itemCount=nil;self.stackCount=nil;self.offerKind=nil;self.parserConfidence=nil
    }
}
public enum RecommendationKind:String,Codable,Sendable {
    case take="TAKE",skip="SKIP",check="CHECK",wait="WAIT",move="MOVE",
    returning="RETURN",charge="CHARGE",active="ON DELIVERY"
}
public struct CashDecision: Sendable {
    public var kind:RecommendationKind
    public var reason:String
    public var takeValue:Double?
    public var skipValue:Double?
    public var modelConfidence:Double
    public var zone:String?
    public var destination:String?
    public var expectedAdvantage:Double?
    public var expectedWaitMinutes:Double?
    public init(kind:RecommendationKind,reason:String,takeValue:Double?=nil,
                skipValue:Double?=nil,modelConfidence:Double=0,zone:String?=nil,
                destination:String?=nil,expectedAdvantage:Double?=nil,
                expectedWaitMinutes:Double?=nil) {
        self.kind=kind;self.reason=reason;self.takeValue=takeValue;self.skipValue=skipValue
        self.modelConfidence=modelConfidence;self.zone=zone;self.destination=destination
        self.expectedAdvantage=expectedAdvantage;self.expectedWaitMinutes=expectedWaitMinutes
    }
}
public struct DriverPolicy: Codable, Sendable {
    public var dailyGoal:Double
    public var calibrationDay:String
    public var stopTime:String
    public var batteryMiles:Double?
    public var lastBatteryUpdate:Date?
    public var estimatedSpeedMPH:Double
    public init(dailyGoal:Double=200,calibrationDay:String="2026-09-29",stopTime:String="01:00",
                batteryMiles:Double?=nil,lastBatteryUpdate:Date?=nil,estimatedSpeedMPH:Double=11) {
        self.dailyGoal=dailyGoal;self.calibrationDay=calibrationDay;self.stopTime=stopTime
        self.batteryMiles=batteryMiles;self.lastBatteryUpdate=lastBatteryUpdate
        self.estimatedSpeedMPH=estimatedSpeedMPH
    }
    public func isCalibration(at date:Date) -> Bool { WorkClock.workday(at:date)==calibrationDay }
}
