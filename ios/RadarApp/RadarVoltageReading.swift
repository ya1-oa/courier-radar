import Foundation

/// A manually read resting pack voltage. Optional trip miles from the bike display.
struct RadarVoltageReading:Codable,Identifiable {
    var id:UUID=UUID()
    var at:Date
    var volts:Double
    var nominalVolts:Int
    var tripMiles:Double?
}
