import Foundation
import Security
import RadarCore

enum RadarAPIError: LocalizedError {
    case invalidServer
    case missingToken
    case badResponse(Int,String)
    case invalidData
    var errorDescription:String? {
        switch self {
        case .invalidServer:return "Use the HTTPS URL of your deployed Radar server."
        case .missingToken:return "Enter your private Radar capture token in Settings."
        case .badResponse(let code,let message):return "Radar API \(code): \(message)"
        case .invalidData:return "Radar returned an unexpected response."
        }
    }
}
enum DateParsing {
    static let fractional:ISO8601DateFormatter = {
        let f=ISO8601DateFormatter()
        f.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
        return f
    }()
    static let plain=ISO8601DateFormatter()
    static func parse(_ source:String) -> Date? { fractional.date(from:source) ?? plain.date(from:source) }
    static func decoder() -> JSONDecoder {
        let d=JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { decoder in
            let value=try decoder.singleValueContainer().decode(String.self)
            guard let date=parse(value) else {
                throw DecodingError.dataCorruptedError(in:try decoder.singleValueContainer(),
                                                      debugDescription:"Invalid ISO8601 date")
            }
            return date
        }
        return d
    }
}
struct RadarShift:Decodable {
    let id:String?
    let startedAt:Date
    let endedAt:Date?
    let vehicle:String?
}
struct MerchantIntelligence:Decodable,Identifiable {
    var id:String {merchant}
    let merchant:String
    let offers:Int?
    let completed:Int?
    let avgWaitMinutes:Double?
}
struct CompletedDelivery:Decodable,Identifiable {
    let id:String
    let merchant:String?
    let payout:Double?
    let miles:Double?
    let state:String?
    let capturedAt:Date?
    let acceptedAt:Date?
    let deliveredAt:Date?
    let zone:String?
    let dropoffZone:String?
}
struct StatsPayload:Decodable {
    var activeShift:RadarShift?
    var todayEarnings:Double?
    var todayEarningsSource:String?
    var todayCapturedEarnings:Double?
    var todayEarningsUpdatedAt:Date?
    var todayOrders:Int?
    var todayOnlineMinutes:Double?
    var todayActiveMinutes:Double?
    var todayPaidUtilization:Double?
    var todayOnlineDph:Double?
    var totalEarnings:Double?
    var onlineMinutes:Double?
    var idleMinutes:Double?
    var completed:Int?
    var offers:Int?
    var merchantStats:[MerchantIntelligence]?
    var todayCompleted:[CompletedDelivery]?
    var dispatchModel:DispatchSnapshot?
}
struct FeedPayload:Decodable { let offers:[RadarOffer] }
struct ShiftPayload:Decodable { var ok:Bool?;var shift:RadarShift?;var resumed:Bool? }
struct LatestCapture:Decodable {
    var payout:Double?
    var merchant:String?
    var miles:Double?
    var etaMinutes:Double?
    var confidence:Double?
}
struct ScreenResult:Decodable {
    var kind:String?
    var stage:String?
    var confidence:Double?
    var reason:String?
}
struct ServerDecision:Decodable {
    var verdict:String?
    var reason:String?
    var takeValue:Double?
    var skipValue:Double?
    var confidence:Double?
    var mode:String?
}
struct CapturePayload:Decodable {
    var ok:Bool?
    var persisted:Bool?
    var updated:Bool?
    var duplicate:Bool?
    var verdict:String?
    var parsed:LatestCapture?
    var screen:ScreenResult?
    var state:String?
    var decision:ServerDecision?
    var reason:String?
    var error:String?
}
struct ActionPayload:Decodable {
    var ok:Bool?
    var state:String?
    var event:String?
    var label:String?
    var error:String?
}
struct EarningPayload:Decodable {
    var ok:Bool?
    var amount:Double?
}
struct PolicyPayload:Decodable {
    var policy:RemotePolicy?
}
struct RemotePolicy:Codable {
    var calibrationDay:String?
    var stopTime:String?
    var batteryMiles:Double?
}
struct RemoteSettingsPayload:Decodable {
    var settings:RiderSettings?
}
struct RiderSettings:Codable {
    var vehicle:String?
    var targetDph:Double?
    var speedLowMph:Double?
    var speedMidMph:Double?
    var speedHighMph:Double?
    var activeSpeedLevel:String?
    var serviceOverheadMinutes:Double?
    var acceptanceRateCurrent:Double?
    var acceptanceRateFloor:Double?
}

/// Persist the token in the iOS keychain, never UserDefaults or captured screenshots.
enum RadarKeychain {
    private static let service="com.courierradar.native.secure"
    private static let account="capture-token"
    static func load() -> String {
        let query:[String:Any]=[kSecClass as String:kSecClassGenericPassword,
                                kSecAttrService as String:service,
                                kSecAttrAccount as String:account,
                                kSecReturnData as String:true,kSecMatchLimit as String:kSecMatchLimitOne]
        var item:CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary,&item)==errSecSuccess,
              let data=item as? Data,
              let value=String(data:data,encoding:.utf8) else {return ""}
        return value
    }
    @discardableResult static func save(_ token:String) -> Bool {
        let query:[String:Any]=[kSecClass as String:kSecClassGenericPassword,
                                kSecAttrService as String:service,
                                kSecAttrAccount as String:account]
        SecItemDelete(query as CFDictionary)
        guard !token.isEmpty else{return true}
        var insert=query
        insert[kSecValueData as String]=Data(token.utf8)
        insert[kSecAttrAccessible as String]=kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(insert as CFDictionary,nil)==errSecSuccess
    }
}
struct RadarEndpoint:Sendable {
    let url:URL
    let token:String
    init(server:String,token:String) throws {
        let formatted=server.trimmingCharacters(in:.whitespacesAndNewlines)
        guard let url=URL(string:formatted),url.scheme=="https",url.host != nil else {
            throw RadarAPIError.invalidServer
        }
        self.url=url;self.token=token
    }
    func get<T:Decodable>(_ path:String) async throws -> T {
        try await request(path,method:"GET",json:nil)
    }
    func post<T:Decodable>(_ path:String,json:[String:Any]) async throws -> T {
        try await request(path,method:"POST",json:json)
    }
    private func request<T:Decodable>(_ path:String,method:String,json:[String:Any]?) async throws -> T {
        guard !token.isEmpty else {throw RadarAPIError.missingToken}
        guard let dest=URL(string:path,relativeTo:url)?.absoluteURL else {throw RadarAPIError.invalidServer}
        var request=URLRequest(url:dest)
        request.httpMethod=method
        request.setValue(token,forHTTPHeaderField:"x-capture-token")
        request.setValue("application/json",forHTTPHeaderField:"Accept")
        request.timeoutInterval=22
        if let json {
            request.setValue("application/json",forHTTPHeaderField:"Content-Type")
            request.httpBody=try JSONSerialization.data(withJSONObject:json,options:[])
        }
        let (body,response)=try await URLSession.shared.data(for:request)
        guard let http=response as? HTTPURLResponse else{throw RadarAPIError.invalidData}
        guard (200..<300).contains(http.statusCode) else {
            let description=String(data:body,encoding:.utf8).map{String($0.prefix(240))} ?? ""
            throw RadarAPIError.badResponse(http.statusCode,description)
        }
        do{return try DateParsing.decoder().decode(T.self,from:body)}
        catch { throw RadarAPIError.badResponse(http.statusCode,"Decoding failure: \(error.localizedDescription)") }
    }
}
