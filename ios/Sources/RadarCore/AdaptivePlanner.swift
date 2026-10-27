import Foundation

public struct HuntCluster:Codable,Identifiable,Sendable {
    public var id:String
    public var name:String
    public var point:GeoPoint
    public var merchants:[String]
    public var breakfastFit:Double
    public var lunchFit:Double
    public var dinnerFit:Double
    public func fit(_ block:String)->Double {
        switch block {case "BREAKFAST":return breakfastFit;case "LUNCH":return lunchFit
        case "DINNER":return dinnerFit;default:return 0.2}
    }
    public static let culver:[HuntCluster]=[
        .init(id:"steps",name:"Culver Steps / downtown",point:.init(lat:34.024,lng:-118.3945),
              merchants:["Philz Coffee","Pop’s Bagels","Mendocino Farms","Erewhon"],breakfastFit:1,lunchFit:1,dinnerFit:0.85),
        .init(id:"west",name:"Tender Greens / downtown west",point:.init(lat:34.023,lng:-118.3968),
              merchants:["Tender Greens","Go Get Em Tiger"],breakfastFit:0.6,lunchFit:1,dinnerFit:0.85),
        .init(id:"platform",name:"Platform / Helms",point:.init(lat:34.0282,lng:-118.388),
              merchants:["sweetgreen","LOQUI","Pasta Sisters"],breakfastFit:0.15,lunchFit:0.85,dinnerFit:1)
    ]
}

public struct MarketSignal:Codable,Sendable {
    public var point:GeoPoint
    public var nearbyVenues:Int
    public var observedUberMerchants:Int
    public var footTrafficIndex:Double?
    public var capturedAt:Date
    public init(point:GeoPoint,nearbyVenues:Int,observedUberMerchants:Int,footTrafficIndex:Double?,capturedAt:Date){
        self.point=point;self.nearbyVenues=nearbyVenues;self.observedUberMerchants=observedUberMerchants
        self.footTrafficIndex=footTrafficIndex;self.capturedAt=capturedAt
    }
}
public struct AdaptiveContext:Sendable {
    public var idleMinutes:Double
    // Only exposure/arrivals AFTER the current server snapshot, to avoid double counting.
    public var additionalAvailableMinutes:Double
    public var additionalOffers:Int
    public var acceptancePercent:Double?
    public var workingMinutesLeft:Double
    public var earned:Double
    public var consecutiveSkips:Int
    public var bicycleRoute:[GeoPoint]
    public var routeMinutes:Double?
    public var routeTargetID:String?
    public var marketSignals:[MarketSignal]
    public init(idleMinutes:Double=0,additionalAvailableMinutes:Double=0,additionalOffers:Int=0,
                acceptancePercent:Double?=nil,workingMinutesLeft:Double=600,earned:Double=0,
                consecutiveSkips:Int=0,bicycleRoute:[GeoPoint]=[],routeMinutes:Double?=nil,routeTargetID:String?=nil,marketSignals:[MarketSignal]=[]){
        self.idleMinutes=idleMinutes;self.additionalAvailableMinutes=additionalAvailableMinutes
        self.additionalOffers=additionalOffers;self.acceptancePercent=acceptancePercent
        self.workingMinutesLeft=workingMinutesLeft;self.earned=earned;self.consecutiveSkips=consecutiveSkips
        self.bicycleRoute=bicycleRoute;self.routeMinutes=routeMinutes;self.routeTargetID=routeTargetID
        self.marketSignals=marketSignals
    }
}

public struct CycleEvaluation:Codable,Sendable {
    public var action:RecommendationKind
    public var reason:String
    public var payout:Double
    public var deliveryMinutes:Double
    public var extraRecoveryMinutes:Double
    public var cycleMinutes:Double
    public var cycleGrossHourly:Double
    public var replacementGrossHourly:Double
    public var minimumPayout:Double
    public var expectedWaitMinutes:Double
    public var predictedAcceptance:Double
    public var requiredGrossHourly:Double
    public var idleBudgetMinutes:Double
    public var afterDropoff:String
    public var recoveryTarget:GeoPoint?
    public var rateBasis:String
    public var routeBasis:String
    public var confidence:Double
    public var acceptanceWarning:String?
    public var nextReviewSeconds:Int
    public var cashDecision:CashDecision {
        CashDecision(kind:action,reason:reason,modelConfidence:confidence,
                     destination:afterDropoff,afterDelivery:afterDropoff,
                     expectedWaitMinutes:expectedWaitMinutes)
    }
}

/// Rolling renewal-reward policy. A SKIP pays zero and consumes another arrival wait.
/// Native math runs without a network or AI request on every clock/GPS/offer update.
public struct AdaptivePlanner {
    public var snapshot:DispatchSnapshot
    public var history:[RadarOffer]
    public var policy:DriverPolicy
    public var context:AdaptiveContext
    public var now:Date
    public init(snapshot:DispatchSnapshot,history:[RadarOffer],policy:DriverPolicy,
                context:AdaptiveContext,now:Date=Date()){
        self.snapshot=snapshot;self.history=history;self.policy=policy;self.context=context;self.now=now
    }
    private struct Economics {var hourly:Double;var wait:Double;var q:Double;var confidence:Double;var basis:String}
    private var speed:Double {max(6,min(18,policy.estimatedSpeedMPH))}
    public static func bikeMinutes(from:GeoPoint,to:GeoPoint,speed:Double=12)->Double {
        let miles=from.miles(to:to)
        return miles<0.05 ? 0 : miles*1.25/max(6,min(18,speed))*60+2
    }
    private func clusters()->[HuntCluster]{
        var result=HuntCluster.culver
        for z in snapshot.zones where z.availableMinutes>=30 && z.offers>=3 {
            guard let p=z.point,!result.contains(where:{$0.point.miles(to:p)<0.5}) else{continue}
            result.append(.init(id:z.id,name:z.zone,point:p,merchants:[],breakfastFit:0.5,lunchFit:0.5,dinnerFit:0.5))
        }
        return result
    }
    private func priorRate(at p:GeoPoint)->Double {
        let block=WorkClock.block(at:now)
        let base=max(1,clusters().map{(2+6*$0.fit(block))*exp(-p.miles(to:$0.point)/0.45)}.max() ?? 2)
        let signals=context.marketSignals.filter{now.timeIntervalSince($0.capturedAt)>=0 && now.timeIntervalSince($0.capturedAt)<1200 && $0.point.miles(to:p)<0.85}
        guard let signal=signals.min(by:{$0.point.miles(to:p)<$1.point.miles(to:p)}) else{return base}
        // Foot traffic and all-venue density are weak priors, not order counts.
        let foot=signal.footTrafficIndex.map{max(0.75,min(1.25,0.75+$0/200))} ?? 1
        let density=1+min(0.2,log(1+Double(max(0,signal.nearbyVenues))/10)*0.1)
        let uber=1+min(0.15,Double(max(0,signal.observedUberMerchants))*0.03)
        return min(14,base*foot*density*uber)
    }
    private func economics(at p:GeoPoint,live:Bool)->Economics {
        let zone=MarketZone.identify(p),block=WorkClock.block(at:now)
        let z=snapshot.estimate(zone:zone,block:block),hours=max(0,z.availableMinutes)/60
        let extra=live ? max(0,context.additionalAvailableMinutes)/60:0
        let arrivals=live ? max(0,context.additionalOffers):0
        let lambda=max(0.1,min(30,(max(0,z.offers)+priorRate(at:p)*0.5+Double(arrivals))/(hours+0.5+extra)))
        var seen=Set<String>()
        let recent=history.filter{o in
            guard let at=o.capturedAt,at<=now,now.timeIntervalSince(at)<14*86400,
                  WorkClock.block(at:at)==block,MarketZone.identify(o.pickupPoint)==zone,
                  let payout=o.payout,payout>0,o.tripETA>0,o.offerKind != "addon" else{return false}
            let key="\(o.merchant ?? "")|\(payout)|\(o.miles ?? 0)|\(Int(at.timeIntervalSince1970/180))"
            return seen.insert(key).inserted
        }.prefix(100)
        // Explicit bootstrap distribution supplies a starting strategy; not fake observed orders.
        var cases:[(p:Double,t:Double)]=recent.map{($0.payout ?? 0,$0.tripETA+3)}
        if cases.count<10 {cases += [(6,15),(8,19),(11,23),(14,28),(18,36)]}
        cases.sort{$0.p/$0.t > $1.p/$1.t}
        let minimum=max(1,Int(ceil(Double(cases.count)*0.6)))
        var best=Economics(hourly:0,wait:60/lambda,q:1,confidence:z.confidence,basis:recent.isEmpty ? "geographic/daypart prior":"personal offers + geographic prior")
        for count in minimum...cases.count {
            let chosen=cases.prefix(count),q=Double(count)/Double(cases.count)
            let reward=chosen.reduce(0){$0+$1.p}/Double(cases.count)
            let occupied=chosen.reduce(0){$0+$1.t}/Double(cases.count)
            let hourly=60*reward/(60/lambda+occupied)
            if hourly>best.hourly {best=Economics(hourly:hourly,wait:60/(lambda*q),q:q,confidence:z.confidence,basis:best.basis)}
        }
        return best
    }
    /// Integrate no-offer survival along supplied BICYCLE geometry; never label the
    /// approximate straight-line fallback a navigable cycling route.
    private func corridorNextWait(originWait:Double)->Double? {
        let points=context.bicycleRoute
        guard points.count>=2,points.count<=1000,points.allSatisfy(\.isValid),
              let minutes=context.routeMinutes,minutes.isFinite,minutes>0 else{return nil}
        let lengths=(1..<points.count).map{points[$0-1].miles(to:points[$0])},total=lengths.reduce(0,+)
        guard total>0 else{return nil}
        var survival=1.0,expected=0.0
        for i in lengths.indices {
            // Subdivide long geometry segments so intermediate pickup corridors matter.
            let pieces=max(1,Int(ceil(lengths[i]/0.12))),dt=minutes*lengths[i]/total/Double(pieces)
            for piece in 0..<pieces {
                let f=(Double(piece)+0.5)/Double(pieces)
                let p=GeoPoint(lat:points[i].lat+(points[i+1].lat-points[i].lat)*f,
                               lng:points[i].lng+(points[i+1].lng-points[i].lng)*f)
                let econ=economics(at:p,live:false),hazard=1/max(1,econ.wait)
                expected+=survival*(1-exp(-hazard*dt))/hazard
                survival*=exp(-hazard*dt)
            }
        }
        return expected+survival*originWait
    }
    public func evaluate(_ offer:RadarOffer,position:GeoPoint?)->CycleEvaluation {
        func check(_ reason:String)->CycleEvaluation {
            .init(action:.check,reason:reason,payout:offer.payout ?? 0,deliveryMinutes:0,extraRecoveryMinutes:0,
                  cycleMinutes:0,cycleGrossHourly:0,replacementGrossHourly:0,minimumPayout:0,expectedWaitMinutes:0,
                  predictedAcceptance:0.6,requiredGrossHourly:0,idleBudgetMinutes:5,afterDropoff:"Verify destination",
                  recoveryTarget:nil,rateBasis:"missing input",routeBasis:"none",confidence:0,acceptanceWarning:nil,nextReviewSeconds:15)
        }
        guard let price=offer.payout,price.isFinite,price>0,let miles=offer.miles,miles.isFinite,miles>=0,
              offer.tripETA.isFinite,offer.tripETA>0 else{return check("Verify payout, total minutes and mileage.")}
        guard let position,position.isValid,let drop=offer.dropoffPoint,drop.isValid else {
            return check("Capture a current GPS fix and destination pin to price recovery.")
        }
        if let confidence=offer.destinationConfidence,confidence<0.75{return check("Street-level destination: verify the drop-off map pin before pricing recovery.")}
        if offer.offerKind == "addon" {return check("Add-on: verify EXTRA minutes and delay to the first customer.")}
        if let range=policy.batteryMiles,miles+3>range{return check("Trip exceeds remaining range plus a 3-mile reserve.")}
        let origin=economics(at:position,live:true),dest=economics(at:drop,live:false)
        var recovery=max(0,dest.wait-origin.wait),after="STAY near drop-off",target:GeoPoint?=nil,travel=0.0
        var routeBasis="estimated road factor 1.25; urban e-bike speed"
        for cluster in clusters() {
            let backMiles=drop.miles(to:cluster.point)*1.25
            let back=Self.bikeMinutes(from:drop,to:cluster.point,speed:speed)
            guard back<=45,policy.batteryMiles.map({miles+backMiles+3<=$0}) ?? true else{continue}
            let next=economics(at:cluster.point,live:false)
            var cost=max(0,back+next.wait-origin.wait),usedGeometry=false
            if context.routeTargetID==cluster.id,let first=context.bicycleRoute.first,
               let last=context.bicycleRoute.last,first.miles(to:drop)<0.3,last.miles(to:cluster.point)<0.3,
               let routeWait=corridorNextWait(originWait:next.wait) {
                cost=max(0,routeWait-origin.wait);usedGeometry=true
            }
            if cost<recovery {
                recovery=cost;after="REDEPLOY to "+cluster.name;target=cluster.point
                travel=usedGeometry ? (context.routeMinutes ?? back):back
                if usedGeometry{routeBasis="supplied bicycle geometry + estimated offer interception"}
            }
        }
        let delivery=max(offer.tripETA,miles/speed*60+4),cycle=delivery+recovery
        let threshold=origin.hourly*cycle/60,surplus=price-threshold
        var action:RecommendationKind=surplus>=0 ? .take:.skip
        let ar=context.acceptancePercent
        let warning=ar.map{$0<=56 ? "Acceptance near guard: favor marginal local jobs; preserve 50% floor.":"Target 60%; exact skip budget needs the rolling exclusive-offer queue."}
        if let ar,ar<=56,surplus>=(-1),price/cycle*60>=origin.hourly*0.85{action = .take}
        if policy.isCalibration(at:now){action = .take}
        if delivery+travel>context.workingMinutesLeft{action = .skip}
        let required=max(0,policy.dailyGoal-context.earned)/max(1,context.workingMinutesLeft)*60
        let reason=String(format:"%@ · $%.2f / %.0f cycle min = $%.1f/h. Replacement $%.1f/h includes waiting. %@.",
                          action.rawValue,price,cycle,price/cycle*60,origin.hourly,after)
        return .init(action:action,reason:reason,payout:price,deliveryMinutes:delivery,extraRecoveryMinutes:recovery,
                     cycleMinutes:cycle,cycleGrossHourly:price/cycle*60,replacementGrossHourly:origin.hourly,
                     minimumPayout:threshold,expectedWaitMinutes:origin.wait,predictedAcceptance:origin.q,
                     requiredGrossHourly:required,idleBudgetMinutes:delivery*0.25,afterDropoff:after,recoveryTarget:target,
                     rateBasis:origin.basis,routeBasis:routeBasis,confidence:origin.confidence,
                     acceptanceWarning:warning,nextReviewSeconds:30)
    }
    public func waitDecision(position:GeoPoint?,active:Bool)->CashDecision {
        if active{return .init(kind:.active,reason:"Finish the delivery; evaluate the next pickup position at drop-off.")}
        if let range=policy.batteryMiles,range<4{return .init(kind:.charge,reason:"Estimated range is under four miles.")}
        guard let position,position.isValid else{return .init(kind:.check,reason:"Refresh GPS before repositioning.")}
        let here=economics(at:position,live:true)
        let idle=max(0,context.idleMinutes),zone=MarketZone.identify(position)
        // Move only if the next 45 minutes repay travel and a $2 hysteresis margin.
        var winner:HuntCluster?,advantage=2.0
        for c in clusters() {
            let miles=position.miles(to:c.point)*1.25,travel=Self.bikeMinutes(from:position,to:c.point,speed:speed)
            guard travel>2,travel<12,policy.batteryMiles.map({miles+4<=$0}) ?? true else{continue}
            let there=economics(at:c.point,live:false)
            let gain=there.hourly*max(0,45-travel)/60-here.hourly*45/60
            if gain>advantage{advantage=gain;winner=c}
        }
        if let winner,idle>=5 {
            return .init(kind:.move,reason:String(format:"%.0f idle min. Nearby cluster repays travel in the next 45 min; forecast advantage $%.2f.",idle,advantage),
                         modelConfidence:here.confidence,zone:zone,destination:winner.name,expectedAdvantage:advantage,expectedWaitMinutes:here.wait)
        }
        let reason=String(format:"%.0f available min · next useful offer ~%.1f min. %@%@",idle,here.wait,
            idle>=5 ? "Re-evaluate fast local offers; no worthwhile move yet. ":"Hold this pickup cluster. ",
            context.consecutiveSkips>=3 ? "Three skips: review replacement quality, not acceptance alone.":"")
        return .init(kind:.wait,reason:reason,modelConfidence:here.confidence,zone:zone,expectedWaitMinutes:here.wait)
    }
}
