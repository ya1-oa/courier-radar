import Foundation
import RadarCore

@MainActor final class LocalPreferences:ObservableObject {
    @Published var server:String {didSet{save()}}
    @Published var goal:Double {didSet{save()}}
    @Published var calibrationDay:String {didSet{save()}}
    @Published var stopTime:String {didSet{save()}}
    @Published var batteryMiles:Double? {didSet{save()}}
    @Published var batteryUpdatedAt:Date? {didSet{save()}}
    @Published var speedMPH:Double {didSet{save()}}
    @Published var vehicle:String {didSet{save()}}
    private let key="RadarNativePreferencesV1"
    private struct Saved:Codable {
        var server:String
        var goal:Double
        var calibrationDay:String
        var stopTime:String
        var batteryMiles:Double?
        var batteryUpdatedAt:Date?
        var speedMPH:Double
        var vehicle:String
    }
    init(){
        let saved=UserDefaults.standard.data(forKey:"RadarNativePreferencesV1")
            .flatMap{try? JSONDecoder().decode(Saved.self,from:$0)}
        server=saved?.server ?? "https://delivery-intelligence.vercel.app"
        goal=saved?.goal ?? 200
        calibrationDay=saved?.calibrationDay ?? "2026-09-29"
        stopTime=saved?.stopTime ?? "01:00"
        batteryMiles=saved?.batteryMiles
        batteryUpdatedAt=saved?.batteryUpdatedAt
        speedMPH=saved?.speedMPH ?? 11
        vehicle=saved?.vehicle ?? "ebike"
    }
    private func save(){
        let snapshot=Saved(server:server,goal:goal,calibrationDay:calibrationDay,
                  stopTime:stopTime,batteryMiles:batteryMiles,batteryUpdatedAt:batteryUpdatedAt,
                  speedMPH:speedMPH,vehicle:vehicle)
        if let json=try? JSONEncoder().encode(snapshot){UserDefaults.standard.set(json,forKey:key)}
    }
    var policy:DriverPolicy {
        DriverPolicy(dailyGoal:goal,calibrationDay:calibrationDay,stopTime:stopTime,
            batteryMiles:batteryMiles,lastBatteryUpdate:batteryUpdatedAt,estimatedSpeedMPH:speedMPH)
    }
    func updateBattery(_ miles:Double?) {
        batteryUpdatedAt=miles == nil ? nil : Date()
        batteryMiles=miles
    }
}
