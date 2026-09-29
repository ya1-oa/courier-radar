import SwiftUI
import UniformTypeIdentifiers
import RadarCore

struct SettingsView:View {
    @EnvironmentObject private var store:RadarStore
    @EnvironmentObject private var prefs:LocalPreferences
    @State private var serverText=""
    @State private var newToken=""
    @State private var batteryText=""
    @State private var uberTotalText=""
    @State private var trainingDate=Date()
    @State private var stopClock=Date()
    @State private var showingCSVImporter=false
    @State private var savedMessage:String?
    @State private var uploadingCSV=false

    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:14){
                VStack(alignment:.leading,spacing:5){
                    RadarKicker(text:"Courier Radar / native")
                    Text("Settings").font(.system(size:31,weight:.bold))
                    Text("Control the shift, the sensors and the money model.")
                        .font(.system(size:12)).foregroundStyle(RadarStyle.subtle)
                }
                RadarCard {
                    VStack(alignment:.leading,spacing:12){
                        Text("Server connection").font(.system(size:17,weight:.bold))
                        RadarKicker(text:store.authReady ? "Keychain token configured":"Connection required")
                        TextField("https://your-radar-server.vercel.app",text:$serverText)
                            .keyboardType(.URL).textInputAutocapitalization(.never)
                            .autocorrectionDisabled().radarInput()
                        SecureField(store.authReady ? "Replace private capture token":"Paste private capture token",text:$newToken)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .radarInput()
                        RadarActionButton(title:"SAVE CONNECTION",systemImage:"lock.shield.fill",highlighted:true) {
                            prefs.server=serverText.trimmingCharacters(in:.whitespacesAndNewlines)
                            if !newToken.isEmpty {store.changeToken(newToken);newToken=""}
                            Task{await store.refresh()}
                            savedMessage="Connection settings saved. Token remains in iOS Keychain."
                        }
                        Text("The existing Radar Vercel API and Supabase database remain the backend. No Uber username, password or private API credentials are stored.")
                            .font(.system(size:11)).foregroundStyle(RadarStyle.subtle)
                    }
                }
                RadarCard{
                    VStack(alignment:.leading,spacing:12){
                        Text("Daily cash policy").font(.system(size:17,weight:.bold))
                        HStack{
                            VStack(alignment:.leading,spacing:3){
                                RadarKicker(text:"Daily goal")
                                Text(Money.dollars(prefs.goal)).font(.system(size:25,weight:.bold))
                                    .foregroundStyle(RadarStyle.signal)
                            }
                            Spacer()
                            Stepper("",value:$prefs.goal,in:50...400,step:5)
                                .labelsHidden().fixedSize()
                        }
                        Divider().overlay(RadarStyle.line)
                        DatePicker("Take-all calibration day",selection:$trainingDate,displayedComponents:.date)
                            .datePickerStyle(.compact)
                            .font(.system(size:13,weight:.medium))
                        DatePicker("Stop working at",selection:$stopClock,displayedComponents:.hourAndMinute)
                            .font(.system(size:13,weight:.medium))
                        Text("Calibration accepts feasible orders. From the next workday, evidence-based TAKE/SKIP becomes active; low-data periods continue favoring guaranteed cash.")
                            .font(.system(size:11)).foregroundStyle(RadarStyle.subtle)
                        RadarActionButton(title:"SAVE POLICY",systemImage:"checkmark",highlighted:true) {
                            prefs.calibrationDay=formattedDay(trainingDate)
                            prefs.stopTime=formattedClock(stopClock)
                            Task{await store.syncPolicy()}
                            savedMessage="Workday settings updated."
                        }
                    }
                }
                RadarCard{
                    VStack(alignment:.leading,spacing:12){
                        Text("E-bike range").font(.system(size:17,weight:.bold))
                        Text("Current estimated miles left: \(store.inferredBatteryMiles.map{Money.number($0)} ?? "unknown")")
                            .font(.system(size:13,weight:.medium)).foregroundStyle(RadarStyle.signal)
                        TextField("Miles after last charge (e.g. 20)",text:$batteryText)
                            .keyboardType(.decimalPad).radarInput()
                        HStack{
                            RadarActionButton(title:"SET AFTER CHARGING",systemImage:"bolt.fill",
                                              highlighted:true) {
                                guard let miles=Double(batteryText),miles>=0,miles<=100 else{
                                    store.error="Enter a real-world 0–100-mile battery estimate."
                                    return
                                }
                                prefs.updateBattery(miles)
                                Task{await store.syncPolicy()}
                                savedMessage="Battery estimate reset after charging."
                            }
                            RadarActionButton(title:"CLEAR",systemImage:"xmark") {
                                prefs.updateBattery(nil);batteryText=""
                                Task{await store.syncPolicy()}
                            }
                        }
                        Text("This is an approximate range ledger, not physical battery telemetry. Radar subtracts captured trip distances with a reserve; confirm remaining range yourself.")
                            .font(.system(size:11)).foregroundStyle(RadarStyle.subtle)
                    }
                }
                RadarCard {
                    VStack(alignment:.leading,spacing:12){
                        Text("Uber earnings reconciliation")
                            .font(.system(size:17,weight:.bold))
                        TextField("Today's total in Uber, e.g. 65.64",text:$uberTotalText)
                            .keyboardType(.decimalPad).radarInput()
                        RadarActionButton(title:"RECORD UBER TOTAL",systemImage:"dollarsign.circle.fill",
                                          highlighted:true) {
                            guard let total=Double(uberTotalText) else{
                                store.error="Enter the complete daily Uber earnings figure."
                                return
                            }
                            Task{await store.syncUberTotal(total)}
                        }
                        Text("A daily Uber total replaces Radar's incomplete captured total. It is never added to already recorded deliveries.")
                            .font(.system(size:11)).foregroundStyle(RadarStyle.subtle)
                        RadarActionButton(title:uploadingCSV ? "IMPORTING…" : "IMPORT UBER CSV",
                                          systemImage:"doc.text",disabled:uploadingCSV) {
                            showingCSVImporter=true
                        }
                    }
                }
                RadarCard {
                    VStack(alignment:.leading,spacing:13) {
                        Text("Fast Uber screen capture").font(.system(size:17,weight:.bold))
                        Text("1. In Shortcuts create: Take Screenshot → Extract Text from Image → Radar: Analyze Uber Screen.")
                            .font(.system(size:12))
                        Text("2. Pass the extracted text into the Radar action. Optional: pass Latitude and Longitude from Get Current Location.")
                            .font(.system(size:12))
                        Text("3. Settings → Accessibility → Touch → Back Tap → Double Tap → your Shortcut.")
                            .font(.system(size:12))
                        Text("You can also choose a screenshot on Home. OCR runs on your iPhone; Radar sends recognized text, not the image, to your own server.")
                            .font(.system(size:11)).foregroundStyle(RadarStyle.subtle)
                        Label("No silent screen monitoring of Uber is installed.",
                              systemImage:"hand.raised").font(.system(size:11))
                            .foregroundStyle(RadarStyle.amber)
                    }
                }
                RadarCard {
                    VStack(alignment:.leading,spacing:9){
                        Text("Shift diagnostics").font(.system(size:17,weight:.bold))
                        diagnostic("Connection",store.status)
                        diagnostic("GPS",store.gps.status)
                        diagnostic("GPS samples queued","\(store.pendingGPS)")
                        diagnostic("GPS-confirmed available time","\(Int(store.stats?.dispatchModel?.verifiedAvailableMinutes ?? 0)) minutes")
                        diagnostic("Captured offers","\(store.stats?.dispatchModel?.offersCaptured ?? 0)")
                        diagnostic("Model confidence","Time + area specific; see Stats")
                        Text("Keep Radar's shift active only while you're actually online in Uber. Every network observation can be missing or censored; the app never claims access to Uber's private dispatch algorithm.")
                            .font(.system(size:11)).foregroundStyle(RadarStyle.subtle)
                    }
                }
                if let message=savedMessage {
                    Text(message).font(.system(size:11)).foregroundStyle(RadarStyle.signal)
                }
                Text("Personal Team builds expire after seven days. Re-sign and reinstall with your own Apple account to continue using the app.")
                    .font(.system(size:11)).foregroundStyle(RadarStyle.subtle)
                    .padding(.horizontal,4)
            }
            .padding(16)
        }
        .scrollContentBackground(.hidden).background(RadarStyle.background)
        .onAppear{
            serverText=prefs.server
            batteryText=prefs.batteryMiles.map{String(format:"%.1f",$0)} ?? ""
            uberTotalText=String(format:"%.2f",store.verifiedCash)
            trainingDate=parseDate(prefs.calibrationDay) ?? Date()
            stopClock=parseClock(prefs.stopTime) ?? Date()
        }
        .fileImporter(isPresented:$showingCSVImporter,
                      allowedContentTypes:[.commaSeparatedText,.plainText]){result in
            Task{await importCSV(result)}
        }
    }
    private func diagnostic(_ label:String,_ value:String)->some View {
        HStack(spacing:10){
            Text(label).font(.system(size:11)).foregroundStyle(RadarStyle.subtle)
            Spacer()
            Text(value).font(.system(size:11,weight:.medium))
                .multilineTextAlignment(.trailing)
        }
    }
    private func formattedDay(_ d:Date)->String {
        let c=Calendar.current,dc=c.dateComponents([.year,.month,.day],from:d)
        return String(format:"%04d-%02d-%02d",dc.year ?? 2026,dc.month ?? 1,dc.day ?? 1)
    }
    private func formattedClock(_ d:Date)->String {
        let components=Calendar.current.dateComponents([.hour,.minute],from:d)
        return String(format:"%02d:%02d",components.hour ?? 1,components.minute ?? 0)
    }
    private func parseDate(_ text:String)->Date? {
        let p=text.split(separator:"-").compactMap{Int($0)}
        guard p.count==3 else{return nil}
        return Calendar.current.date(from:DateComponents(year:p[0],month:p[1],day:p[2],hour:12))
    }
    private func parseClock(_ text:String)->Date? {
        let p=text.split(separator:":").compactMap{Int($0)}
        guard p.count==2 else{return nil}
        return Calendar.current.date(from:DateComponents(year:2026,month:9,day:29,hour:p[0],minute:p[1]))
    }
    private func importCSV(_ result:Result<URL,Error>) async {
        uploadingCSV=true;defer{uploadingCSV=false}
        do {
            let url=try result.get()
            guard url.startAccessingSecurityScopedResource() else{
                throw CocoaError(.fileReadNoPermission)
            }
            defer{url.stopAccessingSecurityScopedResource()}
            let content=try String(contentsOf:url,encoding:.utf8)
            let rows=UberCSV.rows(content)
            guard !rows.isEmpty else {
                throw NSError(domain:"RadarCSV",code:1,
                    userInfo:[NSLocalizedDescriptionKey:"No payout entries found in this CSV."])
            }
            let api=try RadarEndpoint(server:prefs.server,token:RadarKeychain.load())
            let chunks=stride(from:0,to:rows.count,by:300).map{Array(rows[$0..<min(rows.count,$0+300)])}
            for chunk in chunks {
                let _:CSVImportResult=try await api.post("/api/earnings",json:["rows":chunk])
            }
            savedMessage="Imported \(rows.count) CSV earnings lines."
            await store.refresh()
        }catch{store.error=error.localizedDescription}
    }
}

private struct CSVImportResult:Decodable {let ok:Bool?;let saved:Int?}
extension View {
    func radarInput()->some View {
        self.font(.system(size:14))
            .padding(.horizontal,12).padding(.vertical,10)
            .background(RadarStyle.inset,in:RoundedRectangle(cornerRadius:11))
            .overlay(RoundedRectangle(cornerRadius:11)
                .strokeBorder(RadarStyle.line,lineWidth:1))
    }
}

/// Quote-aware CSV parser supporting commas and newlines inside quoted cells.
enum UberCSV {
    static func rows(_ csv:String)->[[String:Any]]{
        var records=[[String]](),record=[String](),field="",quoted=false
        let chars=Array(csv);var i=0
        while i<chars.count {
            let ch=chars[i]
            if ch=="\""{
                if quoted && i+1<chars.count && chars[i+1]=="\"" {field.append("\"");i+=1}
                else{quoted.toggle()}
            }else if ch=="," && !quoted {record.append(field);field=""}
            else if (ch=="\n" || ch=="\r") && !quoted {
                if ch=="\r" && i+1<chars.count && chars[i+1]=="\n"{i+=1}
                record.append(field);field=""
                if record.contains(where:{!$0.isEmpty}){records.append(record)}
                record=[]
            }else{field.append(ch)}
            i+=1
        }
        if !field.isEmpty || !record.isEmpty {
            record.append(field);records.append(record)
        }
        guard let headings=records.first else{return []}
        let names=headings.map{$0.trimmingCharacters(in:.whitespacesAndNewlines).lowercased()}
        guard let amount=names.firstIndex(where:{$0.contains("earning") || $0.contains("amount") ||
                  $0.contains("payout") || $0=="fare"}) else{return []}
        let date=names.firstIndex(where:{$0.contains("date") || $0.contains("time")})
        let id=names.firstIndex(where:{$0.contains("trip") && $0.contains("id")})
        return records.dropFirst().enumerated().compactMap { n,cols -> [String:Any]? in
            guard cols.indices.contains(amount) else{return nil}
            let stripped=cols[amount].replacingOccurrences(of:"$",with:"").replacingOccurrences(of:",",with:"")
            guard let number=Double(stripped.trimmingCharacters(in:.whitespacesAndNewlines)),
                  number.isFinite else{return nil}
            var row:[String:Any]=["amount":number,"source":"uber_csv",
                                  "external_id":(id.flatMap{cols.indices.contains($0) ? cols[$0]:nil}) ?? "ios-\(n)-\(number)"]
            if let date,date<cols.count{row["date"]=cols[date]}
            return row
        }
    }
}
