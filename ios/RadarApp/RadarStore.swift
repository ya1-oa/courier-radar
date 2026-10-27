import Foundation
import Combine
import UIKit
import RadarCore
import UserNotifications

enum RadarTab:Hashable {case live,history,stats,settings}

/// Single source of truth for all screens. Existing Vercel/Supabase APIs are reused.
/// A server capture token is deliberately never written to UserDefaults or an app log.
@MainActor final class RadarStore:ObservableObject {
    @Published var selectedTab:RadarTab = .live
    @Published var stats:StatsPayload?
    @Published var offers:[RadarOffer]=[]
    @Published var isRefreshing=false
    @Published var isActing=false
    @Published var captureState="No screenshot analyzed yet"
    @Published var latestResult:CapturePayload?
    @Published var status="Ready"
    @Published var error:String?
    @Published var lastSync:Date?
    @Published var shiftActive=false
    @Published var recommendations:[String:CashDecision]=[:]
    @Published var lastServerVerdict:String?
    @Published var lastPredictionDisagreement=false
    @Published var pendingGPS=0
    @Published var aiAdvice:CoachAdvice?
    @Published var aiStatus="OpenAI off"
    @Published var availableSince:Date?
    @Published var marketSignals:[MarketSignal]=MarketSignalCache.load()
    @Published var shiftReview:ShiftReviewPayload?
    @Published var reviewLoading=false

    let prefs=LocalPreferences()
    let gps=LocationTracker()
    private var refreshTask:Task<Void,Never>?
    private var decisionClockTask:Task<Void,Never>?
    private var pingQueue:[LocationPing]=[]
    private var flushing=false
    private var lastDecisionLocationAt:Date = .distantPast
    private var availableZone:String?
    private var coachTask:Task<Void,Never>?
    private var aiReviewedOffer:String?
    private var lastCoachRequestAt:Date = .distantPast
    private var aiOfferID:String?
    private var aiExpiresAt:Date = .distantPast
    private var marketTask:Task<Void,Never>?
    private var lastMarketRequestAt:Date = .distantPast
    private let queueKey="RadarPendingGPSSamplesV1"

    init(){
        if let d=UserDefaults.standard.data(forKey:queueKey),
           let queue=try? JSONDecoder().decode([LocationPing].self,from:d) {
            pingQueue=queue.filter{ Date().timeIntervalSince($0.capturedAt)<36*3600 }
        }
        pendingGPS=pingQueue.count
        gps.onPosition = { [weak self] _ in
            guard let self else{return}
            let zone=MarketZone.identify(self.gps.point)
            if self.recommendations["wait"]?.zone != zone ||
               Date().timeIntervalSince(self.lastDecisionLocationAt)>45 {
                self.lastDecisionLocationAt=Date()
                self.updateDecisions()
            }
        }
        gps.onPing = { [weak self] ping in
            guard let self else{return}
            self.queuePing(ping)
            if self.recommendations["wait"]?.zone != MarketZone.identify(self.gps.point) {
                self.updateDecisions()
            }
        }
    }
    var authReady:Bool { !RadarKeychain.load().isEmpty }
    var activeOffer:RadarOffer? { offers.first(where: {["accepted","arrived","picked_up"].contains($0.state ?? "") && Date().timeIntervalSince($0.capturedAt ?? .distantPast) < 4 * 3600}) }
    var latestOffer:RadarOffer? { offers.first }
    var available:Bool {shiftActive && activeOffer == nil}
    var capturedCash:Double {stats?.todayCapturedEarnings ?? 0}
    var verifiedCash:Double {stats?.todayEarnings ?? 0}
    var missingFromGoal:Double {max(0,prefs.goal-verifiedCash)}
    var paidUtilization:Double? {stats?.todayPaidUtilization}
    var inferredBatteryMiles:Double? {
        guard let start=prefs.batteryMiles else{return nil}
        let after=prefs.batteryUpdatedAt ?? Date.distantFuture
        var fingerprint=Set<String>(),used=0.0
        for o in offers where (o.capturedAt ?? .distantPast)>=after &&
            ["accepted","arrived","picked_up","delivered","completed"].contains(o.state ?? "") {
            let key="\(o.merchant ?? "")|\(o.payout ?? 0)|\(o.miles ?? 0)"
            if fingerprint.insert(key).inserted { used+=max(0,o.miles ?? 0) }
        }
        return max(0,start-used*1.2)
    }
    func policyNow() -> DriverPolicy {
        DriverPolicy(dailyGoal:prefs.goal,calibrationDay:prefs.activeCalibrationDay,
                     stopTime:prefs.stopTime,batteryMiles:inferredBatteryMiles,
                     lastBatteryUpdate:prefs.batteryUpdatedAt,estimatedSpeedMPH:prefs.speedMPH)
    }
    func engine() -> CashPlanner {
        CashPlanner(snapshot:stats?.dispatchModel ?? DispatchSnapshot(),
                    history:offers,policy:policyNow(),adaptiveContext:adaptiveContext())
    }
    func adaptiveContext() -> AdaptiveContext {
        let now=Date(),start=availableSince ?? now
        let baseline=max(start,stats?.dispatchModel?.trainedAt ?? start)
        let extraOffers=offers.filter{($0.capturedAt ?? .distantPast)>baseline}.count
        let skips=offers.prefix(while:{$0.state=="rejected"}).count
        return AdaptiveContext(idleMinutes:max(0,now.timeIntervalSince(start)/60),
            additionalAvailableMinutes:max(0,now.timeIntervalSince(baseline)/60),additionalOffers:extraOffers,
            acceptancePercent:prefs.acceptancePercent,
            workingMinutesLeft:min(Double(WorkClock.minutesUntilStop(now:now,clock:prefs.stopTime)),
                max(1,prefs.plannedWorkHours*60-(stats?.todayOnlineMinutes ?? 0))),
            earned:verifiedCash,consecutiveSkips:skips,marketSignals:marketSignals,
            learnedRateMultipliers:stats?.learning?.multipliers ?? [:])
    }
    func cycleEvaluation(_ offer:RadarOffer)->CycleEvaluation {
        AdaptivePlanner(snapshot:stats?.dispatchModel ?? DispatchSnapshot(),history:offers,
            policy:policyNow(),context:adaptiveContext()).evaluate(offer,position:gps.point)
    }
    func decide(_ offer:RadarOffer) -> CashDecision {
        if let at=offer.capturedAt,offer.state=="observed",Date().timeIntervalSince(at)>45 {
            return CashDecision(kind:.check,reason:"Offer expired. Capture the current Uber screen.")
        }
        var decision=engine().offerDecision(offer,position:gps.point)
        if prefs.aiEnabled,offer.state=="observed",aiOfferID==offer.id,aiExpiresAt>Date(),let aiAdvice,
           decision.kind != .check,aiAdvice.confidence>=0.7 {
            if aiAdvice.action=="CHECK" || (decision.kind == .take && aiAdvice.action=="SKIP") {
                decision.kind = .check
                decision.reason="AI review: "+aiAdvice.reason+" Native math: "+decision.reason
            }
        }
        return decision
    }
    var waitAdvice:CashDecision {
        recommendations["wait"] ?? CashDecision(kind:.wait,
            reason:"Waiting for location and offer history before evaluating a move.")
    }
    private func updateDecisions() {
        let zone=MarketZone.identify(gps.point)
        if available {
            if availableSince==nil || availableZone != zone {availableSince=Date();availableZone=zone}
        }else{availableSince=nil;availableZone=nil}
        if let availableSince{UserDefaults.standard.set(availableSince,forKey:"RadarAvailableSince")}
        else{UserDefaults.standard.removeObject(forKey:"RadarAvailableSince")}
        let planner=engine()
        var result:[String:CashDecision]=[:]
        var wait=planner.waitDecision(position:gps.point,active:activeOffer != nil)
        if wait.kind == .move,
           let prior=offers.first(where:{["delivered","completed"].contains($0.state ?? "")}),
           let origin=MarketZone.identify(prior.pickupPoint),
           origin==wait.destination {
            wait.kind = .returning
            wait.reason = "Returning toward a previously productive pickup area. "+wait.reason
        }
        result["wait"]=wait
        if let latest=latestOffer,latest.state=="observed" {
            result[latest.id]=planner.offerDecision(latest,position:gps.point)
        }
        if let active=activeOffer {
            result[active.id]=planner.offerDecision(active,position:gps.point)
        }
        recommendations=result
    }
    private func endpoint() throws -> RadarEndpoint {
        try RadarEndpoint(server:prefs.server,token:RadarKeychain.load())
    }
    private func refreshMarketSignalsIfNeeded() {
        guard shiftActive,Date().timeIntervalSince(lastMarketRequestAt)>900,
              let point=gps.point,point.isValid,let api=try? endpoint() else{return}
        lastMarketRequestAt=Date();marketTask?.cancel()
        marketTask=Task{[weak self] in
            guard let self else{return}
            do {
                let plan:StartPlanPayload=try await api.get("/api/start-plan?lat=\(point.lat)&lng=\(point.lng)&radius=6000")
                guard !Task.isCancelled,self.gps.point.map({$0.miles(to:point)<1}) ?? false else{return}
                let rows=plan.candidates.prefix(12).map{c in
                    MarketSignal(point:.init(lat:c.lat,lng:c.lng),nearbyVenues:c.nearbyRestaurantCount ?? 0,
                        observedUberMerchants:c.uberObservedRestaurantCount ?? 0,
                        footTrafficIndex:c.externalBusyness,capturedAt:Date())
                }
                self.marketSignals=rows;MarketSignalCache.save(rows);self.updateDecisions()
            }catch{/* Keep current math; discovery is not in the expiring-offer path. */}
        }
    }
    func start() {
        if refreshTask != nil{return}
        decisionClockTask=Task{[weak self] in
            while !Task.isCancelled {
                self?.updateDecisions()
                try? await Task.sleep(for:.seconds(30))
            }
        }
        UNUserNotificationCenter.current().requestAuthorization(options:[.alert,.badge,.sound]){_,_ in}
        refreshTask=Task{[weak self] in
            guard let self else{return}
            while !Task.isCancelled {
                if self.authReady { await self.refresh() }
                try? await Task.sleep(for:.seconds(self.shiftActive ? 20 : 45))
            }
        }
        Task{await self.refresh()}
    }
    func stop(){refreshTask?.cancel();refreshTask=nil;decisionClockTask?.cancel();decisionClockTask=nil;coachTask?.cancel();marketTask?.cancel();gps.stop()}
    func refresh() async {
        guard authReady,!isRefreshing else{return}
        isRefreshing=true
        defer{isRefreshing=false}
        do {
            let api=try endpoint()
            async let statsRequest:StatsPayload=api.get("/api/stats")
            async let feedRequest:FeedPayload=api.get("/api/feed?hours=168")
            let (newStats,newFeed)=try await (statsRequest,feedRequest)
            stats=newStats
            offers=newFeed.offers.sorted{($0.capturedAt ?? .distantPast)>($1.capturedAt ?? .distantPast)}
            shiftActive=newStats.activeShift != nil
            if shiftActive && !gps.recording {gps.start(vehicle:prefs.vehicle)}
            if !shiftActive && gps.recording {gps.stop()}
            updateDecisions()
            refreshMarketSignalsIfNeeded()
            error=nil;status="Synced";lastSync=Date()
            await flushGPS()
        } catch {
            self.error=error.localizedDescription
            status="Sync unavailable"
            // Retain prior data; a network failure must not clear the rider's order or earnings.
        }
    }
    func startShift() async {
        guard !isActing else{return};isActing=true;defer{isActing=false}
        do {
            let api=try endpoint()
            let result:ShiftPayload=try await api.post("/api/shift",json:["action":"start","vehicle":prefs.vehicle])
            guard result.shift != nil else{throw RadarAPIError.invalidData}
            shiftActive=true
            gps.start(vehicle:prefs.vehicle)
            if prefs.voltageRemindersEnabled {await RadarVoltageReminder.schedule()}
            await refresh()
        }catch{self.error=error.localizedDescription}
    }
    func endShift() async {
        guard !isActing else{return};isActing=true;defer{isActing=false}
        do {
            let api=try endpoint()
            let ended:ShiftPayload=try await api.post("/api/shift",json:["action":"end"])
            shiftActive=false
            gps.stop()
            await RadarDecisionLiveActivity.clear()
            await RadarVoltageReminder.cancel()
            await flushGPS()
            await refresh()
            await requestReview(shiftId:ended.shift?.id)
        }catch{self.error=error.localizedDescription}
    }
    /// Post-shift review: measured breakdown, S–F tier, OpenAI debrief and the day's bounded tuning.
    func requestReview(shiftId:String?=nil) async {
        guard !reviewLoading else{return}
        reviewLoading=true;defer{reviewLoading=false}
        do {
            let api=try endpoint()
            var body:[String:Any]=["action":"review","plannedHours":prefs.plannedWorkHours,"ai":prefs.aiEnabled]
            if let shiftId{body["shiftId"]=shiftId}
            shiftReview=try await api.post("/api/shift",json:body)
            await refresh()
        }catch{self.error="Shift review unavailable: "+error.localizedDescription}
    }
    func mark(_ state:String="next") async {
        guard !isActing else{return}
        isActing=true;defer{isActing=false}
        do {
            let api=try endpoint()
            var body:[String:Any]=["state":state,"vehicle":prefs.vehicle]
            if let fix=gps.point,fix.isValid {
                body["lat"]=fix.lat;body["lng"]=fix.lng
            }
            let result:ActionPayload=try await api.post("/api/action",json:body)
            captureState=result.label ?? "Recorded \(result.state ?? state)"
            let lifecycle=result.state ?? state
            _ = await RadarDecisionLiveActivity.updateStage(lifecycle,
                merchant:activeOffer?.merchant ?? latestOffer?.merchant ?? "Active delivery",
                payout:Money.dollars(activeOffer?.payout ?? latestOffer?.payout),
                stackCount:max(1,activeOffer?.stackCount ?? latestOffer?.stackCount ?? 1))
            if ["delivered","completed","passed","rejected","cancelled"].contains(lifecycle) {
                let terminalId = activeOffer?.id ?? latestOffer?.id
                if let terminalId { offers.removeAll { $0.id == terminalId } }
                updateDecisions()
            }
            await refresh()
        }catch{self.error=error.localizedDescription}
    }
    func capture(image:UIImage) async {
        guard !isActing else{return}
        isActing=true
        captureState="Recognizing screenshot on-device…"
        defer{isActing=false}
        do {
            let ocr=try await OnDeviceOCR.read(image:image)
            guard !ocr.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else{
                throw NSError(domain:"RadarOCR",code:2,userInfo:[NSLocalizedDescriptionKey:"No readable Uber text in screenshot"])
            }
            try await sendCapture(text:ocr.text,image:image)
        }catch{captureState="Capture failed";self.error=error.localizedDescription}
    }
    func sendCapture(text:String,image:UIImage?=nil) async throws {
        let capturedAt=Date()
        let api=try endpoint()
        var body:[String:Any]=[
            "text":text,"source":"ios_native_vision","vehicle":prefs.vehicle,
            "remainingMinutes":WorkClock.minutesUntilStop(now:Date(),clock:prefs.stopTime),
            "calibrationDay":prefs.activeCalibrationDay,"stopTime":prefs.stopTime,
            "dailyEarned":verifiedCash,"dailyTarget":prefs.goal
        ]
        if let b=inferredBatteryMiles{body["batteryMiles"]=b}
        if let fix=gps.point,fix.isValid{body["lat"]=fix.lat;body["lng"]=fix.lng}
        let result:CapturePayload=try await api.post("/api/capture",json:body)
        latestResult=result
        lastServerVerdict=result.verdict
        if result.screen?.kind=="lifecycle" {
            await RadarDecisionLiveActivity.clear()
            captureState=result.updated == true
                ? "Uber screen → \(result.state ?? "stage recorded")."
                : "State not advanced: \(result.reason ?? "verify manually")"
        } else {
            captureState=(result.duplicate == true ? "Repeated screenshot · " : "")
                + "Evaluating native cycle · "+(result.parsed?.merchant ?? "Uber offer")
        }
        await refresh()
        if let offer=offers.first(where:{$0.id==result.id}),result.screen?.kind=="offer" {
            let native=decide(offer)
            lastPredictionDisagreement=native.kind.rawValue != result.verdict
            captureState=native.kind.rawValue+" · "+(offer.merchant ?? "Uber offer")
            _ = await RadarDecisionLiveActivity.show(verdict:native.kind.rawValue,
                merchant:offer.merchant ?? "Uber offer",payout:Money.dollars(offer.payout),
                reason:native.reason,capturedAt:capturedAt)
            queueCoachReview(offer:offer,text:text,image:image,capturedAt:capturedAt)
        }
    }
    private func queueCoachReview(offer:RadarOffer,text:String,image:UIImage?,capturedAt:Date) {
        guard prefs.aiEnabled else{aiStatus="OpenAI off";return}
        guard Date().timeIntervalSince(offer.capturedAt ?? .distantPast)<45 else{return}
        guard aiReviewedOffer != offer.id,Date().timeIntervalSince(lastCoachRequestAt)>=15 else{return}
        let day=WorkClock.workday(at:Date()),key="RadarCoachCount_"+day
        let count=UserDefaults.standard.integer(forKey:key)
        guard count<100 else{aiStatus="100 AI reviews used today · native math active";return}
        let evaluation=cycleEvaluation(offer)
        guard let mathData=try? JSONEncoder().encode(evaluation),
              let math=try? JSONSerialization.jsonObject(with:mathData),
              let api=try? endpoint() else{return}
        var state:[String:Any]=["algorithm":math,"ocrText":String(text.prefix(6000)),
            "idleMinutes":adaptiveContext().idleMinutes,"earned":verifiedCash,"dailyGoal":prefs.goal,
            "clusters":HuntCluster.culver.map{["name":$0.name,"merchants":$0.merchants.joined(separator:", ")]}]
        state["marketSignals"]=marketSignals.prefix(4).map{s in
            ["lat":s.point.lat,"lng":s.point.lng,"nearbyVenues":Double(s.nearbyVenues),
             "observedUberMerchants":Double(s.observedUberMerchants),"footTrafficIndex":s.footTrafficIndex ?? -1]
        }
        if let point=gps.point {state["position"]=["lat":point.lat,"lng":point.lng]}
        if let range=inferredBatteryMiles{state["batteryMiles"]=range}
        if let ar=prefs.acceptancePercent{state["acceptancePercent"]=ar}
        var body:[String:Any]=["offerId":offer.id,"capturedAt":ISO8601DateFormatter().string(from:capturedAt),"state":state]
        if let image {
            let scale=min(1,768/max(image.size.width,image.size.height))
            let size=CGSize(width:max(1,image.size.width*scale),height:max(1,image.size.height*scale))
            let resized=UIGraphicsImageRenderer(size:size).image{_ in image.draw(in:CGRect(origin:.zero,size:size))}
            if let data=resized.jpegData(compressionQuality:0.6),data.count<800_000 {
                body["screenshotBase64"]=data.base64EncodedString()
            }
        }
        coachTask?.cancel();aiReviewedOffer=offer.id;lastCoachRequestAt=Date()
        aiAdvice=nil;aiStatus="OpenAI reviewing…"
        UserDefaults.standard.set(count+1,forKey:key)
        coachTask=Task{[weak self] in
            guard let self else{return}
            do {
                let result:CoachPayload=try await api.post("/api/coach",json:body)
                guard !Task.isCancelled,result.offerId==self.latestOffer?.id,result.expiresAt>Date(),
                      self.latestOffer?.state=="observed" else{return}
                self.aiAdvice=result.advice;self.aiOfferID=offer.id;self.aiExpiresAt=result.expiresAt
                self.aiStatus="OpenAI reviewed · "+result.advice.action
                self.updateDecisions()
                let final=self.decide(offer)
                _ = await RadarDecisionLiveActivity.show(verdict:final.kind.rawValue,
                    merchant:offer.merchant ?? "Uber offer",payout:Money.dollars(offer.payout),
                    reason:final.reason,capturedAt:capturedAt)
            }catch{self.aiStatus="AI unavailable · native math active"}
        }
    }
    func recordVoltage(_ volts:Double,tripMiles:Double?=nil) async {
        guard prefs.updateVoltage(volts,tripMiles:tripMiles) else {
            error="Voltage is outside the selected pack profile. Check the battery label."
            return
        }
        status=String(format:"Saved %.1fV · estimated %.1f mi left",volts,inferredBatteryMiles ?? 0)
        updateDecisions()
        if shiftActive && prefs.voltageRemindersEnabled {await RadarVoltageReminder.schedule()}
        if authReady {await syncPolicy()}
    }
    func updatePayout(offerId:String, amount:Double) async {
        guard amount>=0,amount<=1000 else{error="Enter a valid final payout.";return}
        do {
            let api=try endpoint()
            let _:EarningPayload=try await api.post("/api/earnings",json:["offerId":offerId,"finalPayout":amount])
            if let index=offers.firstIndex(where:{$0.id==offerId}) { offers[index].finalPayout=amount }
            await refresh()
            status="Order payout updated"
        }catch{self.error=error.localizedDescription}
    }
    func syncUberTotal(_ amount:Double) async {
        guard amount>=0,amount<=5000 else{error="Enter Uber's displayed daily total.";return}
        do {
            let api=try endpoint()
            let _:EarningPayload=try await api.post("/api/earnings",json:["dailyTotal":amount])
            await refresh()
            status="Uber total reconciled"
        }catch{self.error=error.localizedDescription}
    }
    func syncPolicy() async {
        do {
            let api=try endpoint()
            var body:[String:Any]=["calibrationDay":prefs.activeCalibrationDay,
              "stopTime":prefs.stopTime]
            if let battery=inferredBatteryMiles {body["batteryMiles"]=battery}
            else {body["batteryMiles"]=NSNull()}
            let _:PolicyPayload=try await api.post("/api/settings?resource=dispatch",json:body)
            status="Policy synced"
        }catch{self.error=error.localizedDescription}
    }
    func changeToken(_ text:String){
        if !RadarKeychain.save(text.trimmingCharacters(in:.whitespacesAndNewlines)) {
            error="Could not secure the capture token in Keychain."
        }else{
            status="Token stored in Keychain"
            Task{await refresh()}
        }
    }
    private func queuePing(_ sample:LocationPing){
        guard shiftActive else{return}
        pingQueue.append(sample)
        if pingQueue.count>500 {pingQueue.removeFirst(pingQueue.count-500)}
        saveQueue()
        Task{await flushGPS()}
    }
    private func saveQueue(){
        pendingGPS=pingQueue.count
        if let encoded=try? JSONEncoder().encode(pingQueue){UserDefaults.standard.set(encoded,forKey:queueKey)}
    }
    private func flushGPS() async {
        guard !flushing,authReady else{return}
        flushing=true
        defer{flushing=false;saveQueue()}
        guard let api=try? endpoint() else{return}
        // Replay the ORIGINAL sample timestamp; never counterfeit "available now" while offline.
        while let sample=pingQueue.first {
            if Date().timeIntervalSince(sample.capturedAt)>36*3600 {
                pingQueue.removeFirst();continue
            }
            do {
                let _:LocationAccepted=try await api.post("/api/presence",json:sample.json)
                pingQueue.removeFirst()
            }catch{break}
        }
    }
}
private struct LocationAccepted:Decodable {let ok:Bool?;let persisted:Bool?}
