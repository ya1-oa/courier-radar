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

    let prefs=LocalPreferences()
    let gps=LocationTracker()
    private var refreshTask:Task<Void,Never>?
    private var pingQueue:[LocationPing]=[]
    private var flushing=false
    private var lastDecisionLocationAt:Date = .distantPast
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
    var activeOffer:RadarOffer? { offers.first(where: {["accepted","arrived","picked_up"].contains($0.state ?? "")}) }
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
                    history:offers,policy:policyNow())
    }
    func decide(_ offer:RadarOffer) -> CashDecision {
        recommendations[offer.id] ?? engine().offerDecision(offer,position:gps.point)
    }
    var waitAdvice:CashDecision {
        recommendations["wait"] ?? CashDecision(kind:.wait,
            reason:"Waiting for location and offer history before evaluating a move.")
    }
    private func updateDecisions() {
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
    func start() {
        if refreshTask != nil{return}
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
    func stop(){refreshTask?.cancel();refreshTask=nil;gps.stop()}
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
            let _:ShiftPayload=try await api.post("/api/shift",json:["action":"end"])
            shiftActive=false
            gps.stop()
            await RadarDecisionLiveActivity.clear()
            await RadarVoltageReminder.cancel()
            await flushGPS()
            await refresh()
        }catch{self.error=error.localizedDescription}
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
            await RadarDecisionLiveActivity.clear()
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
            try await sendCapture(text:ocr.text)
        }catch{captureState="Capture failed";self.error=error.localizedDescription}
    }
    func sendCapture(text:String) async throws {
        let capturedAt=Date()
        let api=try endpoint()
        var body:[String:Any]=[
            "text":text,"source":"ios_native_vision","vehicle":prefs.vehicle,
            "remainingMinutes":WorkClock.minutesUntilStop(now:Date(),clock:prefs.stopTime),
            "calibrationDay":prefs.activeCalibrationDay,"stopTime":prefs.stopTime,
            "dailyEarned":verifiedCash
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
            if result.screen?.kind=="offer" || result.verdict != nil {
                _ = await RadarDecisionLiveActivity.show(
                    verdict:result.verdict ?? "CHECK",
                    merchant:result.parsed?.merchant ?? "Uber offer",
                    payout:Money.dollars(result.parsed?.payout),
                    reason:result.decision?.reason ?? result.reason ?? "Check Uber before acting.",
                    capturedAt:capturedAt)
            }
            captureState=(result.duplicate == true ? "Repeated screenshot · " : "")
                + (result.verdict ?? "CHECK")+" · "+(result.parsed?.merchant ?? "Uber offer")
        }
        await refresh()
        if let offer=latestOffer,result.screen?.kind=="offer" {
            let native=decide(offer)
            lastPredictionDisagreement=native.kind.rawValue != result.verdict
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
