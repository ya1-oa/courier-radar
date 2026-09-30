import SwiftUI
import RadarCore

/// Fast, optional manual reading while safely stopped.
struct RadarVoltageSheet:View {
    @EnvironmentObject private var prefs:LocalPreferences
    @EnvironmentObject private var store:RadarStore
    @Environment(\.dismiss) private var dismiss
    @State private var volts=""
    @State private var tripMiles=""
    @State private var saving=false

    var body:some View {
        NavigationStack {
            Form {
                Section("Bike display") {
                    HStack {
                        TextField("Battery voltage, e.g. 49.8",text:$volts)
                            .keyboardType(.decimalPad)
                        Text("V").foregroundStyle(.secondary)
                    }
                    TextField("Trip odometer (optional miles)",text:$tripMiles)
                        .keyboardType(.decimalPad)
                    Text("Read voltage while stopped, ideally after the throttle has rested.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let value=Double(volts),
                       let estimate=BatteryVoltage.estimate(volts:value,
                           nominal:prefs.batteryNominalVolts,fullRangeMiles:prefs.fullChargeMiles) {
                        Text(String(format:"Approx. %.0f%% · %.1f usable miles",estimate.percent,estimate.usableMiles))
                            .foregroundStyle(RadarStyle.signal)
                    }
                }
                Section("Recent readings") {
                    if prefs.voltageReadings.isEmpty {
                        Text("No readings yet").foregroundStyle(.secondary)
                    }
                    ForEach(Array(prefs.voltageReadings.reversed().prefix(12))) { entry in
                        HStack {
                            Text(entry.at.formatted(date:.abbreviated,time:.shortened))
                                .font(.caption)
                            Spacer()
                            Text(String(format:"%.1f V",entry.volts))
                            if let trip=entry.tripMiles {
                                Text(String(format:"· %.1f mi",trip)).foregroundStyle(.secondary)
                            }
                        }.font(.caption)
                    }
                }
            }
            .navigationTitle("Battery voltage")
            .toolbar {
                ToolbarItem(placement:.cancellationAction) {
                    Button("Close"){dismiss()}
                }
                ToolbarItem(placement:.confirmationAction) {
                    Button(saving ? "Saving…" : "Save") {
                        guard let value=Double(volts),!saving else{return}
                        saving=true
                        Task {
                            await store.recordVoltage(value,tripMiles:Double(tripMiles))
                            saving=false
                            if store.error == nil {dismiss()}
                        }
                    }
                    .disabled(saving || Double(volts)==nil)
                }
            }
        }
        .onAppear {volts=prefs.batteryVoltage.map{String(format:"%.1f",$0)} ?? ""}
    }
}
