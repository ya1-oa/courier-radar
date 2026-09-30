import ActivityKit
import Foundation

/// Replaces an alert with an iOS-managed Live Activity. On supported iPhones
/// the result is visible in Dynamic Island while Uber remains in the foreground.
/// iOS does not allow Radar to draw an arbitrary floating window over Uber.
@MainActor enum RadarDecisionLiveActivity {
    static func show(verdict:String,merchant:String,payout:String,reason:String,
                     capturedAt:Date) async -> Bool {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else{return false}
        let expiresAt=capturedAt.addingTimeInterval(45)
        // Never display an old TAKE/SKIP decision after a slow network response.
        guard expiresAt>Date() else {
            await clear()
            return false
        }
        let normalized=verdict.uppercased()
        let safeVerdict=["TAKE","SKIP","CHECK"].contains(normalized) ? normalized : "CHECK"
        let state=RadarDecisionAttributes.ContentState(
            verdict:safeVerdict,
            merchant:String(merchant.prefix(55)),
            payout:String(payout.prefix(24)),
            reason:String(reason.prefix(190)),
            capturedAt:capturedAt,
            expiresAt:expiresAt)
        let content=ActivityContent(state:state,staleDate:expiresAt)
        do {
            let activities=Activity<RadarDecisionAttributes>.activities
            if let first=activities.first {
                await first.update(content)
                for duplicate in activities.dropFirst() {
                    await duplicate.end(nil,dismissalPolicy:.immediate)
                }
            } else {
                _ = try Activity<RadarDecisionAttributes>.request(
                    attributes:RadarDecisionAttributes(label:"Courier Radar"),
                    content:content,
                    pushType:nil)
            }
            return true
        } catch {
            return false
        }
    }

    static func clear() async {
        for activity in Activity<RadarDecisionAttributes>.activities {
            await activity.end(nil,dismissalPolicy:.immediate)
        }
    }
}
