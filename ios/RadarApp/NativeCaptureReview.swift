import Foundation
import UIKit
import RadarCore

/// Shared Action Button / text Shortcut path. Uses the same SWIFT planner as Home.
@MainActor enum NativeCaptureReview {
    static func evaluate(result:CapturePayload,api:RadarEndpoint,policy:DriverPolicy,
                         position:GeoPoint?,text:String,image:UIImage?=nil,
                         aiEnabled:Bool,acceptancePercent:Double?,capturedAt:Date,
                         plannedWorkHours:Double=10) async -> CashDecision {
        async let statsRequest:StatsPayload? = try? api.get("/api/stats")
        async let feedRequest:FeedPayload? = try? api.get("/api/feed?hours=168")
        let (stats,feed)=await (statsRequest,feedRequest)
        guard Date().timeIntervalSince(capturedAt)<45 else {
            return .init(kind:.check,reason:"Offer expired while loading context. Capture the current screen.")
        }
        let destination=result.destination
        let offer=feed?.offers.first(where:{$0.id==result.id}) ?? RadarOffer(
            id:result.id ?? UUID().uuidString,merchant:result.parsed?.merchant,payout:result.parsed?.payout,
            miles:result.parsed?.miles,etaMinutes:result.parsed?.etaMinutes,
            capturedAt:capturedAt,lat:position?.lat,lng:position?.lng,
            dropoffLat:destination?.lat,dropoffLng:destination?.lng)
        var checkedOffer=offer
        checkedOffer.destinationConfidence=destination?.confidence ?? offer.destinationConfidence
        checkedOffer.offerKind=result.offerKind ?? offer.offerKind
        let availableSince=(UserDefaults.standard.object(forKey:"RadarAvailableSince") as? Date) ?? Date()
        let baseline=max(availableSince,stats?.dispatchModel?.trainedAt ?? availableSince)
        let history=feed?.offers ?? []
        let context=AdaptiveContext(idleMinutes:max(0,Date().timeIntervalSince(availableSince)/60),
            additionalAvailableMinutes:max(0,Date().timeIntervalSince(baseline)/60),
            additionalOffers:history.filter{($0.capturedAt ?? .distantPast)>baseline}.count,
            acceptancePercent:acceptancePercent,
            workingMinutesLeft:min(Double(WorkClock.minutesUntilStop(now:Date(),clock:policy.stopTime)),
                max(1,plannedWorkHours*60-(stats?.todayOnlineMinutes ?? 0))),earned:stats?.todayEarnings ?? 0,
                marketSignals:MarketSignalCache.load())
        let cycle=AdaptivePlanner(snapshot:stats?.dispatchModel ?? DispatchSnapshot(),history:history,
            policy:policy,context:context).evaluate(checkedOffer,position:position)
        var decision=cycle.cashDecision
        guard aiEnabled else{return decision}
        let day=WorkClock.workday(at:Date()),countKey="RadarCoachCount_"+day
        let count=UserDefaults.standard.integer(forKey:countKey)
        guard count<100 else{return decision}
        guard let mathData=try? JSONEncoder().encode(cycle),let math=try? JSONSerialization.jsonObject(with:mathData) else{return decision}
        var state:[String:Any]=["algorithm":math,"ocrText":String(text.prefix(6000)),
            "clusters":HuntCluster.culver.map{["name":$0.name,"merchants":$0.merchants.joined(separator:", ")]}]
        if let position {state["position"]=["lat":position.lat,"lng":position.lng]}
        var body:[String:Any]=["offerId":offer.id,"capturedAt":ISO8601DateFormatter().string(from:capturedAt),"state":state]
        if let image {
            let scale=min(1,768/max(image.size.width,image.size.height))
            let size=CGSize(width:max(1,image.size.width*scale),height:max(1,image.size.height*scale))
            let resized=UIGraphicsImageRenderer(size:size).image{_ in image.draw(in:CGRect(origin:.zero,size:size))}
            if let data=resized.jpegData(compressionQuality:0.6),data.count<800_000{body["screenshotBase64"]=data.base64EncodedString()}
        }
        UserDefaults.standard.set(count+1,forKey:countKey)
        if let review:CoachPayload=try? await api.post("/api/coach",json:body),review.expiresAt>Date(),review.advice.confidence>=0.7 {
            if decision.kind != .check && (review.advice.action=="CHECK" || (decision.kind == .take && review.advice.action=="SKIP")) {
                decision.kind = .check;decision.reason="AI: "+review.advice.reason+" Native: "+decision.reason
            }else {decision.reason += " AI: "+review.advice.reason}
        }
        if Date().timeIntervalSince(capturedAt)>=45{return .init(kind:.check,reason:"Review expired; capture again.")}
        return decision
    }
}
