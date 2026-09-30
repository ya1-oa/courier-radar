import Foundation
import AppIntents
import RadarCore

/// Run from a user-created iOS Shortcut:
/// Take Screenshot -> Extract Text from Image -> Radar: Analyze Uber Screen.
/// The recognized text stays on-device until this explicit user-initiated action.
/// Keychain access does not require handing the private token to iOS Shortcuts.
struct RadarCaptureIntent:AppIntent {
    static var title:LocalizedStringResource="Analyze Uber Screen"
    static var description=IntentDescription("Send recognized text from an Uber Driver screenshot to your private Courier Radar server.")
    static var openAppWhenRun=false

    @Parameter(title:"Screenshot text",description:"Use Extract Text from Image on a Take Screenshot action.")
    var recognizedText:String

    @Parameter(title:"Latitude",description:"Optional current latitude from Get Current Location.")
    var latitude:Double?

    @Parameter(title:"Longitude",description:"Optional current longitude from Get Current Location.")
    var longitude:Double?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let config=await MainActor.run {LocalPreferences()}
        let token=RadarKeychain.load()
        guard !token.isEmpty else {
            return .result(dialog:IntentDialog(stringLiteral:"Open Radar Settings and save your capture token first."))
        }
        let api=try RadarEndpoint(server:await config.server,token:token)
        let policy=await config.policy
        let vehicle=await config.vehicle
        var json:[String:Any]=[
            "text":recognizedText,"source":"ios_app_intents",
            "vehicle":vehicle,"calibrationDay":policy.calibrationDay,
            "stopTime":policy.stopTime,
            "remainingMinutes":WorkClock.minutesUntilStop(now:Date(),clock:policy.stopTime)
        ]
        if let latitude,let longitude {
            let coord=GeoPoint(lat:latitude,lng:longitude)
            if coord.isValid {json["lat"]=latitude;json["lng"]=longitude}
        }
        if let battery=policy.batteryMiles {json["batteryMiles"]=battery}
        if json["lat"] == nil,let gps=RadarRecentGPS.latest() {
            json["lat"]=gps.lat;json["lng"]=gps.lng
        }
        do{
            let output:CapturePayload=try await api.post("/api/capture",json:json)
            let answer:String
            if output.screen?.kind=="lifecycle" {
                answer=output.updated == true
                    ? "Radar updated \(output.state ?? "delivery stage")."
                    : "Radar did not advance: \(output.reason ?? "check the order stage")."
            }else{
                answer="\(output.verdict ?? "CHECK") · \(output.parsed?.merchant ?? "Uber offer") · \(Money.dollars(output.parsed?.payout))"
            }
            if output.screen?.kind=="offer" {
                await RadarCaptureNotification.show(title:"Radar: \(output.verdict ?? "CHECK")",body:answer)
            }
            return .result(dialog:IntentDialog(stringLiteral:answer))
        }catch{
            return .result(dialog:IntentDialog(stringLiteral:"Radar capture failed: \(error.localizedDescription)"))
        }
    }
}

struct RadarAppShortcuts:AppShortcutsProvider {
    static var appShortcuts:[AppShortcut] {
        AppShortcut(intent:RadarImageCaptureIntent(),
            phrases:["Analyze an Uber screenshot with \(.applicationName)"],
            shortTitle:"Analyze Uber Screenshot",systemImageName:"camera.viewfinder")
        AppShortcut(intent:RadarCaptureIntent(),
            phrases:["Analyze Uber text with \(.applicationName)"],
            shortTitle:"Analyze Uber Text",systemImageName:"text.viewfinder")
    }
}
