import Foundation
import UserNotifications

/// Optional local alert after a user-initiated screenshot analysis.
/// iOS cannot place a persistent floating overlay above Uber.
enum RadarCaptureNotification {
    static func show(title:String,body:String) async {
        let center=UNUserNotificationCenter.current()
        let settings=await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options:[.alert,.sound])
        }
        let content=UNMutableNotificationContent()
        content.title=title
        content.body=body
        content.sound = .default
        let request=UNNotificationRequest(
            identifier:"radar-capture-\(UUID().uuidString)",
            content:content,
            trigger:UNTimeIntervalNotificationTrigger(timeInterval:1,repeats:false))
        try? await center.add(request)
    }
}
