import Foundation
import AppIntents
import UIKit
import RadarCore

/// User-triggered screenshot capture for an iPhone Action Button Shortcut.
/// Shortcut: Take Screenshot -> Analyze Uber Screenshot (pass Screenshot as input).
/// No continuous access to Uber's screen and no uploaded image.
struct RadarImageCaptureIntent:LiveActivityIntent {
    static var title:LocalizedStringResource="Analyze Uber Screenshot"
    static var description=IntentDescription("Recognize an Uber screenshot on-device and return a cash-first TAKE, SKIP, or CHECK decision.")
    static var openAppWhenRun=false

    @Parameter(title:"Screenshot",description:"Pass the output of Take Screenshot.")
    var screenshot:IntentFile

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let capturedAt=Date()
        guard let image=UIImage(data:screenshot.data) else {
            return .result(dialog:IntentDialog(stringLiteral:"Radar couldn't open the screenshot."))
        }
        let recognized:ScreenOCRResult
        do {recognized=try await OnDeviceOCR.read(image:image)}
        catch {return .result(dialog:IntentDialog(stringLiteral:"Radar couldn't recognize the screenshot."))}
        guard !recognized.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else {
            return .result(dialog:IntentDialog(stringLiteral:"No readable Uber text found."))
        }
        let token=RadarKeychain.load()
        guard !token.isEmpty else {
            return .result(dialog:IntentDialog(stringLiteral:"Open Radar Settings and save the capture token first."))
        }
        do {
            let config=await MainActor.run {LocalPreferences()}
            let api=try RadarEndpoint(server:await config.server,token:token)
            let policy=await config.policy
            let vehicle=await config.vehicle
            var payload:[String:Any]=[
                "text":recognized.text,
                "source":"ios_action_button_vision",
                "vehicle":vehicle,
                "calibrationDay":policy.calibrationDay,
                "stopTime":policy.stopTime,
                "remainingMinutes":WorkClock.minutesUntilStop(now:Date(),clock:policy.stopTime)
            ]
            if let miles=policy.batteryMiles {payload["batteryMiles"]=miles}
            if let gps=RadarRecentGPS.latest() {payload["lat"]=gps.lat;payload["lng"]=gps.lng}
            let result:CapturePayload=try await api.post("/api/capture",json:payload)
            var message:String
            if result.screen?.kind=="lifecycle" {
                await RadarDecisionLiveActivity.clear()
                message=result.updated == true ?
                    "Radar recorded \(result.state ?? "delivery stage")." :
                    "No stage change: \(result.reason ?? "check Uber first")."
            } else {
                let why=String((result.decision?.reason ?? result.reason ?? "Verify the Uber offer before acting.").prefix(130))
                message="\(result.verdict ?? "CHECK") · \(result.parsed?.merchant ?? "Uber offer") · \(Money.dollars(result.parsed?.payout)). \(why)"
                let displayed=await RadarDecisionLiveActivity.show(
                    verdict:result.verdict ?? "CHECK",
                    merchant:result.parsed?.merchant ?? "Uber offer",
                    payout:Money.dollars(result.parsed?.payout),
                    reason:why,capturedAt:capturedAt)
                if !displayed {
                    message+=". Dynamic Island unavailable: enable Live Activities for Radar."
                }
            }
            return .result(dialog:IntentDialog(stringLiteral:message))
        } catch {
            return .result(dialog:IntentDialog(stringLiteral:"Radar unavailable: \(error.localizedDescription)"))
        }
    }
}
