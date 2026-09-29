import SwiftUI
import RadarCore

/// Explicit recovery of an order the courier forgot to record.
/// Manual entries appear in earnings/history but cannot count as observed Uber dispatch.
struct MissedOrderDraft:Sendable {
    let clientId:String
    let merchant:String
    let payout:Double
    let miles:Double?
    let etaMinutes:Int?
    let state:String
    let acceptedAt:Date
    let finishedAt:Date?
}

struct MissedOrderView:View {
    @EnvironmentObject private var store:RadarStore
    @Environment(\.dismiss) private var dismiss
    @State private var merchant=""
    @State private var payout=""
    @State private var miles=""
    @State private var estimatedMinutes=""
    @State private var selectedStage="delivered"
    @State private var acceptedAt=Date().addingTimeInterval(-20*60)
    @State private var finishedAt=Date()
    @State private var clientId=UUID().uuidString
    @State private var timesConfirmed=false
    @State private var saving=false
    @State private var showingAdvanced=false

    private let stages:[(key:String,label:String)]=[
        ("accepted","Accepted / on the way"),
        ("arrived","At pickup"),
        ("picked_up","Picked up / delivering"),
        ("delivered","Completed")
    ]

    var body:some View {
        NavigationStack {
            Form {
                Section {
                    Text("Forgot to capture an order? Enter what Uber actually showed, then resume its delivery stage.")
                        .font(.system(size:13))
                    TextField("Restaurant or merchant",text:$merchant)
                        .textInputAutocapitalization(.words)
                    HStack{
                        Text("$").foregroundStyle(.secondary)
                        TextField("Payout, e.g. 11.75",text:$payout)
                            .keyboardType(.decimalPad)
                    }
                    Picker("Current stage",selection:$selectedStage){
                        ForEach(stages,id:\.key){stage in
                            Text(stage.label).tag(stage.key)
                        }
                    }
                }header:{Text("Missed order")}
                Section {
                    DatePicker("Order started",selection:$acceptedAt,
                               in:Date().addingTimeInterval(-14*86400)...Date(),
                               displayedComponents:[.date,.hourAndMinute])
                    if selectedStage=="delivered" {
                        DatePicker("Delivered",selection:$finishedAt,
                                   in:acceptedAt...Date(),
                                   displayedComponents:[.date,.hourAndMinute])
                    }
                    Toggle("These times are actual or my closest estimates",isOn:$timesConfirmed)
                }header:{Text("When it happened")}
                footer:{
                    Text("Enter when the actual Uber order happened. Recovered entries are labeled manual; missing offers must not distort the wait-zone model.")
                }
                Section {
                    HStack{
                        Text("Trip miles")
                        Spacer()
                        TextField("Optional",text:$miles)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                    }
                    HStack{
                        Text("Estimated trip minutes")
                        Spacer()
                        TextField("Optional",text:$estimatedMinutes)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                    }
                }header:{Text("Additional details")}
                Section {
                    if selectedStage=="delivered" {
                        Label("Adds this delivery to recorded earnings and History. It won't replace your verified Uber daily total.",systemImage:"checkmark.circle")
                            .font(.system(size:12))
                    } else {
                        Label("Adds an active order and resumes the Next Stage workflow.",systemImage:"arrow.uturn.forward")
                            .font(.system(size:12))
                    }
                    Button{
                        Task{await recover()}
                    }label:{
                        HStack{
                            Spacer()
                            if saving{ProgressView().padding(.trailing,6)}
                            Text(saving ? "SAVING…" : "SAVE & RESUME")
                                .font(.system(size:14,weight:.bold))
                            Spacer()
                        }.frame(minHeight:40)
                    }
                    .disabled(!canSave||saving)
                }footer:{
                    Text("You are not reporting that Radar observed an Uber offer. This is a manually reconstructed entry.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(RadarStyle.background)
            .navigationTitle("Recover order")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.cancellationAction) {
                    Button("Cancel"){dismiss()}
                }
            }
        }
        .tint(RadarStyle.signal)
        .presentationDetents([.large])
    }

    private var canSave:Bool {
        guard !merchant.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,
              let p=Double(payout),p>0,p<=2000,
              let numericMiles=miles.isEmpty ? 0:Double(miles),
              numericMiles>=0,numericMiles<=250,
              let numericETA=estimatedMinutes.isEmpty ? 30:Int(estimatedMinutes),
              numericETA>=1,numericETA<=360,
              acceptedAt<=Date(),timesConfirmed else {return false}
        return selectedStage != "delivered" || finishedAt >= acceptedAt
    }

    private func recover() async {
        guard canSave else{return}
        saving=true
        let draft=MissedOrderDraft(clientId:clientId,
            merchant:merchant.trimmingCharacters(in:.whitespacesAndNewlines),
            payout:Double(payout) ?? 0,
            miles:Double(miles),
            etaMinutes:Int(estimatedMinutes),
            state:selectedStage,
            acceptedAt:acceptedAt,
            finishedAt:selectedStage=="delivered" ? finishedAt:nil)
        let ok=await store.recover(draft)
        saving=false
        if ok {dismiss()}
    }
}
