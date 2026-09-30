import Foundation
import RadarCore

/// Short-lived local cache for the user-triggered iOS Shortcut.
/// Never use a stale position to fabricate offer exposure.
enum RadarRecentGPS {
    private static let key="RadarRecentGPSV1"
    static func save(_ point:GeoPoint,accuracy:Double) {
        guard point.isValid,accuracy>=0,accuracy<=350 else{return}
        UserDefaults.standard.set(["lat":point.lat,"lng":point.lng,
            "accuracy":accuracy,"at":Date().timeIntervalSince1970],forKey:key)
    }
    static func latest() -> GeoPoint? {
        guard let record=UserDefaults.standard.dictionary(forKey:key),
              let lat=record["lat"] as? Double,
              let lng=record["lng"] as? Double,
              let at=record["at"] as? Double,
              let accuracy=record["accuracy"] as? Double,
              accuracy>=0,accuracy<=350,
              Date().timeIntervalSince1970-at>=0,
              Date().timeIntervalSince1970-at<=120 else{return nil}
        let point=GeoPoint(lat:lat,lng:lng)
        return point.isValid ? point:nil
    }
}
