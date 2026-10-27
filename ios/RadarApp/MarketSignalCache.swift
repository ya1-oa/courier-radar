import Foundation
import RadarCore

struct StartPlanPayload:Decodable {
    struct Candidate:Decodable {
        var lat:Double
        var lng:Double
        var nearbyRestaurantCount:Int?
        var uberObservedRestaurantCount:Int?
        var externalBusyness:Double?
    }
    var candidates:[Candidate]
    var source:String?
}
enum MarketSignalCache {
    static func load()->[MarketSignal]{
        guard let data=UserDefaults.standard.data(forKey:"RadarMarketSignals"),
              let rows=try? JSONDecoder().decode([MarketSignal].self,from:data) else{return []}
        return rows.filter{Date().timeIntervalSince($0.capturedAt)<1200}
    }
    static func save(_ rows:[MarketSignal]){
        if let data=try? JSONEncoder().encode(rows){UserDefaults.standard.set(data,forKey:"RadarMarketSignals")}
    }
}
