import Foundation

/// Observational finite-horizon semi-Markov planner for the driver's personal Uber offer stream.
/// It does NOT possess Uber dispatch source code, order queues, unobserved offers or causal AR effects.
/// Units: minutes, USD, miles. A non-captured offer is missing data, never a zero-dollar offer.
public struct CashPlanner {
    public var snapshot:DispatchSnapshot
    public var history:[RadarOffer]
    public var policy:DriverPolicy
    public var now:Date

    private let stepMinutes = 5.0
    private let maximumHorizon = 720.0

    public init(snapshot:DispatchSnapshot,history:[RadarOffer],policy:DriverPolicy,now:Date=Date()) {
        self.snapshot=snapshot;self.history=history;self.policy=policy;self.now=now
    }
    public func offerDecision(_ offer:RadarOffer,position:GeoPoint?) -> CashDecision {
        let zone=MarketZone.identify(position ?? offer.pickupPoint),
            block=WorkClock.block(at:now),z=snapshot.estimate(zone:zone,block:block)
        guard let payout=offer.payout,payout.isFinite,payout>0,
              let miles=offer.miles,miles.isFinite,miles>=0,
              offer.tripETA.isFinite,offer.tripETA>0 else {
            return CashDecision(kind:.check,reason:"Uber payout, time or distance is missing. Verify before deciding.",zone:zone)
        }
        if let remaining=policy.batteryMiles,miles+3>remaining {
            return CashDecision(kind:.check,reason:"Trip exceeds the estimated remaining e-bike range plus a 3-mile reserve. Charge or verify battery.",zone:zone)
        }
        if policy.isCalibration(at:now) {
            return CashDecision(kind:.take,reason:"Calibration day: accept feasible offers and record their real outcomes.",zone:zone)
        }
        guard z.availableMinutes>=60,z.offers>=5,z.confidence>=0.30,
              let zone else {
            return CashDecision(kind:.take,reason:"Not enough local available-time observations to justify rejecting guaranteed cash.",zone:zone,modelConfidence:z.confidence)
        }

        // Destination is learned from actual drop-off GPS. No restaurant count enters this function.
        let destination=MarketZone.identify(offer.dropoffPoint)
        let predictedDuration=max(5,min(150,offer.tripETA+(offer.isShop == true ? 5 : 0)))
        let cashTake:Double
        let cashSkip:Double
        var planner=MemoPlanner(snapshot:snapshot,history:history,now:now,
                                speed:policy.estimatedSpeedMPH,
                                battery:policy.batteryMiles,horizon:horizonMinutes)
        let remainingAfter=max(0,horizonMinutes-predictedDuration)
        let continuation=planner.cash(zone:destination ?? zone,minutes:remainingAfter,
                                      battery:policy.batteryMiles.map{max(0,$0-miles)})
        // Unknown drop-offs have a modest uncertainty cost, not a fictitious travel time.
        cashTake=payout+continuation-(destination == nil ? 1.0 : 0)
        cashSkip=planner.cash(zone:zone,minutes:horizonMinutes,battery:policy.batteryMiles)
        let ambiguity=3+5*(1-z.confidence)
        // AR effects are observational and confounded with time / location / supply.
        // We do not assume that Uber secretly penalizes declined offers.
        if cashSkip > cashTake+ambiguity {
            return CashDecision(kind:.skip,reason:"Observed local replacement value exceeds the offer plus post-delivery value, after an uncertainty margin.",
                takeValue:cashTake,skipValue:cashSkip,modelConfidence:z.confidence,zone:zone,destination:destination)
        }
        return CashDecision(kind:.take,reason:"The payout and estimated post-dropoff value beat an uncertain replacement offer.",
            takeValue:cashTake,skipValue:cashSkip,modelConfidence:z.confidence,zone:zone,destination:destination)
    }

    public func waitDecision(position:GeoPoint?,active:Bool=false) -> CashDecision {
        if active { return CashDecision(kind:.active,reason:"Finish the Uber delivery. Re-evaluate your waiting zone after drop-off.") }
        let current=MarketZone.identify(position),block=WorkClock.block(at:now)
        if let battery=policy.batteryMiles,battery<4 {
            return CashDecision(kind:.charge,reason:"Estimated battery range is under four miles. Recharge before taking a new order.",zone:current)
        }
        guard let point=position,point.isValid,let current else {
            return CashDecision(kind:.wait,reason:"No reliable GPS position. Don't chase a guessed hotspot.")
        }
        let local=snapshot.estimate(zone:current,block:block)
        if policy.isCalibration(at:now) {
            return CashDecision(kind:.wait,reason:"Calibration: hold a stable zone and log actual Uber offers.",zone:current,
                                expectedWaitMinutes:local.rate>0 ? 1/local.rate:nil)
        }
        guard local.availableMinutes>=45,local.offers>=4 else {
            return CashDecision(kind:.wait,reason:"Too little measured availability in this zone to justify moving.",zone:current,
                                expectedWaitMinutes:local.rate>0 ? 1/local.rate:nil)
        }
        var planner=MemoPlanner(snapshot:snapshot,history:history,now:now,
                                speed:policy.estimatedSpeedMPH,
                                battery:policy.batteryMiles,horizon:horizonMinutes)
        let stay=planner.cash(zone:current,minutes:horizonMinutes,battery:policy.batteryMiles)
        var best:CashDecision?
        for target in snapshot.zones where target.block==block && target.zone != current &&
            target.availableMinutes>=60 && target.offers>=6 && target.confidence>=0.5 {
            guard let dest=target.point else { continue }
            let miles=point.miles(to:dest)
            guard miles>0.1,miles<=4.5,
                  policy.batteryMiles.map({$0>=miles+4}) ?? true else {continue}
            let travel=2+miles/max(5,policy.estimatedSpeedMPH)*60
            guard travel<horizonMinutes/3,travel<=32 else {continue}
            let future=planner.cash(zone:target.zone,minutes:horizonMinutes-travel,
                                    battery:policy.batteryMiles.map{max(0,$0-miles)})
            let risk=5+10*(1-min(target.confidence,local.confidence))
            let advantage=future-stay-risk
            guard advantage>7 else {continue}
            if best == nil || advantage>(best?.expectedAdvantage ?? 0) {
                best=CashDecision(kind:.move,
                                  reason:"Observed offer exposure favors this zone after bike travel and uncertainty costs.",
                                  modelConfidence:min(target.confidence,local.confidence),zone:current,
                                  destination:target.zone,expectedAdvantage:advantage)
            }
        }
        return best ?? CashDecision(kind:.wait,
                   reason:"No alternative zone has demonstrated enough additional cash to justify deadheading.",
                   modelConfidence:local.confidence,zone:current,
                   expectedWaitMinutes:local.rate>0 ? 1/local.rate:nil)
    }
    public var horizonMinutes:Double { min(maximumHorizon,Double(WorkClock.minutesUntilStop(now:now,clock:policy.stopTime))) }
}

/// Computes E[earnings until the stop time]. Every recursion consumes time; memoization
/// bounds work to zone × time bucket × battery bucket. No network calls in the hot path.
private struct MemoPlanner {
    let snapshot:DispatchSnapshot
    let history:[RadarOffer]
    let now:Date
    let speed:Double
    let battery:Double?
    let horizon:Double
    private var memo:[State:Double]=[:]

    private struct State:Hashable {let zone:String;let steps:Int;let batteryBucket:Int}
    init(snapshot:DispatchSnapshot,history:[RadarOffer],now:Date,speed:Double,battery:Double?,horizon:Double){
        self.snapshot=snapshot;self.history=history;self.now=now;self.speed=speed;self.battery=battery;self.horizon=horizon
    }
    mutating func cash(zone:String,minutes:Double,battery:Double?) -> Double {
        let steps=max(0,Int(minutes/5.0))
        return value(zone:zone,steps:steps,battery:battery)
    }
    private func bucket(_ amount:Double?) -> Int { amount.map {max(0,min(30,Int($0/3)))} ?? 31 }
    private func representativeOffers(zone:String,block:String) -> [RadarOffer] {
        let matched=history.filter { o in
            guard let d=o.capturedAt,now.timeIntervalSince(d)<15*86400,
                  let payout=o.payout,payout>0,
                  o.tripETA>0,let from=MarketZone.identify(o.pickupPoint) else{return false}
            return from==zone && WorkClock.block(at:d)==block
        }.sorted {( $0.capturedAt ?? .distantPast )>( $1.capturedAt ?? .distantPast )}
        return Array(matched.prefix(18))
    }
    private mutating func value(zone:String,steps:Int,battery:Double?) -> Double {
        guard steps>0 else{return 0}
        if let battery,battery<3 {return 0}
        let state=State(zone:zone,steps:steps,batteryBucket:bucket(battery))
        if let value=memo[state]{return value}
        let elapsed=(horizon-Double(steps)*5)*60
        let block=WorkClock.block(at:now.addingTimeInterval(elapsed))
        let z=snapshot.estimate(zone:zone,block:block)
        let coverage=min(1,z.availableMinutes/100)*min(1,z.offers/8)
        let baseline=snapshot.pooled.rate
        // Zone-specific posterior shrinks toward personal daypart/global signal with low exposure.
        let lambda=max(0.003,min(0.3,coverage*z.rate+(1-coverage)*baseline))
        let next=value(zone:zone,steps:steps-1,battery:battery)
        let arrival=1-exp(-lambda*5)
        var candidateValue=0.0,totalWeight=0.0
        let cases=representativeOffers(zone:zone,block:block)
        for (index,o) in cases.enumerated(){
            guard let payout=o.payout, let distance=o.miles else{continue}
            if let battery,battery<distance+2 {continue}
            let travel=max(1,Int(ceil(max(5,o.tripETA)/5)))
            let nextZone=MarketZone.identify(o.dropoffPoint) ?? zone
            let reward=payout+value(zone:nextZone,steps:max(0,steps-1-travel),
                                     battery:battery.map{max(0,$0-distance)})
            let weight=exp(-Double(index)/12)
            candidateValue+=max(next,reward)*weight
            totalWeight+=weight
        }
        // Real offers and timing are always preferred. Sparse samples blend with a conservative prior.
        let priorReward=max(0,z.payout)+value(zone:zone,
                 steps:max(0,steps-1-Int(ceil(max(8,z.duration)/5))),
                 battery:battery.map{max(0,$0-2)})
        let priorWeight=cases.count<5 ? Double(5-cases.count):0.5
        candidateValue+=max(next,priorReward)*priorWeight
        totalWeight+=priorWeight
        let offerValue=totalWeight>0 ? candidateValue/totalWeight : next
        let expected=max(0,(1-arrival)*next+arrival*offerValue)
        memo[state]=expected
        return expected
    }
}
