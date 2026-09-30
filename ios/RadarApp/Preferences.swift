import Foundation
import RadarCore

@MainActor final class LocalPreferences:ObservableObject {
    @Published var server:String {didSet{save()}}
    @Published var goal:Double {didSet{save()}}
    @Published var calibrationDay:String {didSet{save()}}
    @Published var calibrationEnabled:Bool {didSet{save()}}
    @Published var stopTime:String {didSet{save()}}
    @Published var batteryMiles:Double? {didSet{save()}}
    @Published var batteryNominalVolts:Int {didSet{save()}}
    @Published var fullChargeMiles:Double {didSet{save()}}
    @Published var batteryVoltage:Double? {didSet{save()}}
    @Published var batteryVoltageAt:Date? {didSet{save()}}
    @Published var voltageReadings:[RadarVoltageReading] {didSet{save()}}
    @Published var voltageRemindersEnabled:Bool {didSet{save()}}
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
        var calibrationEnabled:Bool?
        var batteryNominalVolts:Int?
        var fullChargeMiles:Double?
        var batteryVoltage:Double?
        var batteryVoltageAt:Date?
        var voltageReadings:[RadarVoltageReading]?
        var voltageRemindersEnabled:Bool?
    }
    init(){
        let saved=UserDefaults.standard.data(forKey:"RadarNativePreferencesV1")
            .flatMap{try? JSONDecoder().decode(Saved.self,from:$0)}
        server=saved?.server ?? "https://delivery-intelligence-ten.vercel.app"
        goal=saved?.goal ?? 200
        calibrationDay=saved?.calibrationDay ?? "2026-09-29"
        calibrationEnabled=saved?.calibrationEnabled ?? false
        stopTime=saved?.stopTime ?? "01:00"
        batteryMiles=saved?.batteryMiles
        batteryNominalVolts=saved?.batteryNominalVolts ?? 48
        fullChargeMiles=saved?.fullChargeMiles ?? 20
        batteryVoltage=saved?.batteryVoltage
        batteryVoltageAt=saved?.batteryVoltageAt
        voltageReadings=saved?.voltageReadings ?? []
        voltageRemindersEnabled=saved?.voltageRemindersEnabled ?? false
        batteryUpdatedAt=saved?.batteryUpdatedAt
        speedMPH=saved?.speedMPH ?? 11
        vehicle=saved?.vehicle ?? "ebike"
    }
    private func save(){
        let snapshot=Saved(server:server,goal:goal,calibrationDay:calibrationDay,
                  stopTime:stopTime,batteryMiles:batteryMiles,batteryUpdatedAt:batteryUpdatedAt,
                  speedMPH:speedMPH,vehicle:vehicle,calibrationEnabled:calibrationEnabled,
                  batteryNominalVolts:batteryNominalVolts,fullChargeMiles:fullChargeMiles,
                  batteryVoltage:batteryVoltage,batteryVoltageAt:batteryVoltageAt,
                  voltageReadings:voltageReadings,voltageRemindersEnabled:voltageRemindersEnabled)
        if let json=try? JSONEncoder().encode(snapshot){UserDefaults.standard.set(json,forKey:key)}
    }
    var activeCalibrationDay:String {calibrationEnabled ? calibrationDay : "1900-01-01"}
    var policy:DriverPolicy {
        DriverPolicy(dailyGoal:goal,calibrationDay:activeCalibrationDay,stopTime:stopTime,
            batteryMiles:batteryMiles,lastBatteryUpdate:batteryUpdatedAt,estimatedSpeedMPH:speedMPH)
    }
    var batteryEstimate:BatteryVoltageEstimate? {
        guard let volts=batteryVoltage else{return nil}
        return BatteryVoltage.estimate(volts:volts,nominal:batteryNominalVolts,
            fullRangeMiles:fullChargeMiles)
    }
    @discardableResult func updateVoltage(_ volts:Double,tripMiles:Double?=nil)->Bool {
        guard let estimate=BatteryVoltage.estimate(volts:volts,
            nominal:batteryNominalVolts,fullRangeMiles:fullChargeMiles) else{return false}
        let now=Date()
        batteryVoltage=volts
        batteryVoltageAt=now
        batteryMiles=estimate.usableMiles
        batteryUpdatedAt=now
        let trip=tripMiles.flatMap {$0.isFinite && $0>=0 && $0<=1_000_000 ? $0 : nil}
        voltageReadings.append(RadarVoltageReading(at:now,volts:volts,
            nominalVolts:batteryNominalVolts,tripMiles:trip))
        if voltageReadings.count>200 {voltageReadings.removeFirst(voltageReadings.count-200)}
        return true
    }
    func updateBattery(_ miles:Double?) {
        batteryUpdatedAt=miles == nil ? nil : Date()
        batteryMiles=miles
    }
}
