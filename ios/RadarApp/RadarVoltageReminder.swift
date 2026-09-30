import Foundation
import UserNotifications

/// Twelve opt-in reminders 90 minutes apart, reset on each voltage reading.
/// iOS schedules these even when Radar is not running in the foreground.
enum RadarVoltageReminder {
    private static let ids=(1...12).map { "radar-voltage-\($0)" }
    static func cancel() async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers:ids)
    }
    static func schedule() async {
        await cancel()
        let center=UNUserNotificationCenter.current()
        let settings=await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options:[.alert,.sound])
        }
        for (index,id) in ids.enumerated() {
            let content=UNMutableNotificationContent()
            content.title="Bike battery check"
            content.body="When safely stopped, enter your resting battery voltage in Radar."
            content.sound = .default
            let request=UNNotificationRequest(identifier:id,content:content,
                trigger:UNTimeIntervalNotificationTrigger(timeInterval:TimeInterval((index+1)*5400),repeats:false))
            try? await center.add(request)
        }
    }
}
