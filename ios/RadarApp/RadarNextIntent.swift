import Foundation
import AppIntents
import RadarCore

/// Native lifecycle control for Action Button / Back Tap shortcuts.
struct RadarNextIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Radar Next"
    static var description = IntentDescription("Advance the current Courier Radar delivery by exactly one lifecycle stage.")
    static var openAppWhenRun = false

    private struct NextResponse: Decodable {
        let state:String?
        let label:String?
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let token=RadarKeychain.load()
        guard !token.isEmpty else {
            return .result(dialog:IntentDialog(stringLiteral:"Open Radar Settings and save your capture token first."))
        }
        do {
            let config=await MainActor.run {LocalPreferences()}
            let api=try RadarEndpoint(server:await config.server,token:token)
            var body:[String:Any]=["state":"next","vehicle":await config.vehicle]
            if let gps=RadarRecentGPS.latest(){body["lat"]=gps.lat;body["lng"]=gps.lng}
            let result:NextResponse=try await api.post("/api/action",json:body)
            let stage=result.state ?? "updated"
            _ = await RadarDecisionLiveActivity.updateStage(stage)
            return .result(dialog:IntentDialog(stringLiteral:result.label ?? stage.replacingOccurrences(of:"_",with:" ").uppercased()))
        } catch {
            return .result(dialog:IntentDialog(stringLiteral:"Radar Next failed: \(error.localizedDescription)"))
        }
    }
}
