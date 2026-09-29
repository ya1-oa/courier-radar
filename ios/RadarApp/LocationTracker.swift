import Foundation
import CoreLocation
import Combine
import RadarCore

struct LocationPing:Codable,Sendable {
    var lat:Double
    var lng:Double
    var capturedAt:Date
    var event:String
    var vehicle:String="ebike"
    var json:[String:Any] {
        ["lat":lat,"lng":lng,
         "capturedAt":ISO8601DateFormatter().string(from:capturedAt),
         "event":event,"vehicle":vehicle]
    }
}
/// No interpolated location samples: a GPS timestamp is retained end-to-end.
@MainActor final class LocationTracker:NSObject,ObservableObject,CLLocationManagerDelegate {
    @Published private(set) var point:GeoPoint?
    @Published private(set) var locationAge:TimeInterval?
    @Published private(set) var accuracy:Double?
    @Published private(set) var authorization:CLAuthorizationStatus
    @Published private(set) var recording=false
    @Published private(set) var status="Location inactive"
    var onPing:((LocationPing)->Void)?

    private let locationManager=CLLocationManager()
    private var lastSentAt:Date = .distantPast
    private var latestLocation:CLLocation?
    private var heartbeat:Timer?
    override init(){
        authorization=locationManager.authorizationStatus
        super.init()
        locationManager.delegate=self
        locationManager.desiredAccuracy=kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter=35
        locationManager.activityType = .fitness
        locationManager.pausesLocationUpdatesAutomatically=false
    }
    func requestPermission() {
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
    }
    func start(vehicle:String="ebike") {
        recording=true
        requestPermission()
        beginLocationIfAuthorized()
        heartbeat?.invalidate()
        // A stale last fix is never uploaded as fresh availability.
        heartbeat=Timer.scheduledTimer(withTimeInterval:110,repeats:true){ [weak self] _ in
            Task{ @MainActor [weak self] in self?.sendVerifiedPing(event:"heartbeat",vehicle:vehicle) }
        }
    }
    func stop(){
        if recording{sendVerifiedPing(event:"shift_end",vehicle:"ebike")}
        recording=false
        heartbeat?.invalidate();heartbeat=nil
        locationManager.stopUpdatingLocation()
        locationManager.allowsBackgroundLocationUpdates=false
        status="GPS stopped"
    }
    private func beginLocationIfAuthorized(){
        switch locationManager.authorizationStatus {
        case .authorizedAlways,.authorizedWhenInUse:
            // UIBackgroundModes = location must be present in Info.plist.
            locationManager.allowsBackgroundLocationUpdates=true
            locationManager.showsBackgroundLocationIndicator=true
            locationManager.startUpdatingLocation()
            status="GPS enabled during shift"
        case .notDetermined:
            status="Allow location access to log wait zones"
        default:
            status="Location permission denied"
        }
    }
    private func sendVerifiedPing(event:String,vehicle:String){
        guard recording,let fix=latestLocation,fix.horizontalAccuracy>=0,
              fix.horizontalAccuracy<=350,
              abs(fix.timestamp.timeIntervalSinceNow)<180 else{return}
        guard event != "heartbeat" || Date().timeIntervalSince(lastSentAt)>=90 else{return}
        guard fix.coordinate.latitude.isFinite,fix.coordinate.longitude.isFinite else{return}
        lastSentAt=Date()
        onPing?(LocationPing(lat:fix.coordinate.latitude,lng:fix.coordinate.longitude,
                             capturedAt:fix.timestamp,event:event,vehicle:vehicle))
    }
    nonisolated func locationManager(_ manager:CLLocationManager,didUpdateLocations locations:[CLLocation]) {
        guard let fix=locations.last else{return}
        Task{ @MainActor [weak self] in
            guard let self else{return}
            guard fix.horizontalAccuracy>=0,fix.horizontalAccuracy<=350 else{return}
            self.latestLocation=fix
            self.point=GeoPoint(lat:fix.coordinate.latitude,lng:fix.coordinate.longitude)
            self.accuracy=fix.horizontalAccuracy
            self.locationAge=abs(fix.timestamp.timeIntervalSinceNow)
            self.status=String(format:"GPS ±%.0fm",fix.horizontalAccuracy)
            if self.recording {self.sendVerifiedPing(event:"heartbeat",vehicle:"ebike")}
        }
    }
    nonisolated func locationManagerDidChangeAuthorization(_ manager:CLLocationManager) {
        Task{ @MainActor [weak self] in
            guard let self else{return}
            self.authorization=manager.authorizationStatus
            if self.recording{self.beginLocationIfAuthorized()}
        }
    }
    nonisolated func locationManager(_ manager:CLLocationManager,didFailWithError error:Error){
        Task{ @MainActor [weak self] in self?.status="GPS: \(error.localizedDescription)" }
    }
}
