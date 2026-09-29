import SwiftUI
import Charts
import RadarCore

struct EarningsView:View {
    @EnvironmentObject private var store:RadarStore
    @State private var showAssumptions=false

    struct HourEarnings:Identifiable {
        let hour:Int
        let amount:Double
        var id:Int{hour}
    }
    private var hours:[HourEarnings] {
        let today=WorkClock.workday(at:Date())
        let deliveries=store.offers.filter {
            ["completed","delivered"].contains($0.state ?? "") &&
            ($0.capturedAt.map{WorkClock.workday(at:$0)} ?? "")==today
        }
        let calendar=WorkClock.calendar()
        return (0..<24).map{hour in
            HourEarnings(hour:hour,amount:deliveries.reduce(0){value,offer in
                let h=offer.capturedAt.map{calendar.component(.hour,from:$0)} ?? -1
                return value+(h==hour ? offer.settledPayout : 0)
            })
        }
    }
    var body:some View {
        ScrollView(.vertical,showsIndicators:true) {
            VStack(alignment:.leading,spacing:14) {
                VStack(alignment:.leading,spacing:5){
                    RadarKicker(text:"Delivery performance")
                    Text("Earnings").font(.system(size:31,weight:.bold))
                    Text("The goal is cash banked, not isolated offer $/hr.")
                        .font(.system(size:12)).foregroundStyle(RadarStyle.subtle)
                }
                RadarCard{
                    RadarKicker(text:"Today's total")
                    HStack(alignment:.firstTextBaseline) {
                        Text(Money.dollars(store.verifiedCash))
                            .font(.system(size:36,weight:.bold,design:.rounded))
                            .foregroundStyle(RadarStyle.signal)
                        Spacer()
                        Text("/ \(Money.dollars(store.prefs.goal))")
                            .font(.system(size:16,weight:.bold)).foregroundStyle(RadarStyle.subtle)
                    }
                    ProgressView(value:min(1,store.verifiedCash/max(1,store.prefs.goal)))
                        .tint(RadarStyle.signal).padding(.top,2)
                    Text(store.stats?.todayEarningsSource=="uber_manual_total" ?
                         "Uber total supplied manually — most reliable daily cash baseline.":
                         "Incomplete unless every delivery was captured or Uber earnings were imported.")
                        .font(.system(size:10)).foregroundStyle(RadarStyle.subtle)
                        .padding(.top,5)
                }
                RadarCard {
                    HStack(spacing:10){
                        RadarMetric(title:"Remaining goal",value:Money.dollars(store.missingFromGoal))
                        RadarMetric(title:"Online minutes",value:"\(Int(store.stats?.todayOnlineMinutes ?? 0))m")
                        RadarMetric(title:"Paid activity",value:Money.percent(store.paidUtilization))
                    }
                }
                RadarCard {
                    VStack(alignment:.leading,spacing:12) {
                        Text("Captured payouts by hour")
                            .font(.system(size:15,weight:.bold))
                        Chart(hours){ h in
                            BarMark(x:.value("Hour",h.hour),y:.value("USD",h.amount))
                                .foregroundStyle(RadarStyle.signal.gradient)
                                .cornerRadius(3)
                        }
                        .chartXAxis {
                            AxisMarks(values:[0,6,12,18,23]){
                                AxisValueLabel()
                            }
                        }
                        .chartYAxis {
                            AxisMarks(position:.leading)
                        }
                        .frame(height:145)
                        Text("Hourly chart uses completed orders captured by Radar; it may omit Uber earnings.")
                            .font(.system(size:10)).foregroundStyle(RadarStyle.subtle)
                    }
                }
                RadarCard {
                    VStack(alignment:.leading,spacing:12) {
                        HStack {
                            Text("Dispatch evidence").font(.system(size:16,weight:.bold))
                            Spacer()
                            RadarPill(text:"OBSERVATIONAL",color:RadarStyle.amber)
                        }
                        let model=store.stats?.dispatchModel
                        HStack{
                            RadarMetric(title:"Captured offers",value:"\(model?.offersCaptured ?? 0)")
                            RadarMetric(title:"Matched while available",value:"\(model?.offersObservedAvailable ?? 0)")
                            RadarMetric(title:"GPS available",value:"\(Int(model?.verifiedAvailableMinutes ?? 0))m")
                        }
                        Text("Contextual offer arrivals are estimated from GPS-confirmed availability and received offers. Missing screenshots and unknown Uber supply remain sources of uncertainty.")
                            .font(.system(size:11)).foregroundStyle(RadarStyle.subtle)
                    }
                }
                if let zones=store.stats?.dispatchModel?.zones,!zones.isEmpty {
                    RadarCard {
                        VStack(alignment:.leading,spacing:12){
                            Text("Learned wait zones")
                                .font(.system(size:16,weight:.bold))
                            ForEach(zones.sorted{$0.availableMinutes>$1.availableMinutes}.prefix(12)) {zone in
                                HStack(alignment:.center){
                                    VStack(alignment:.leading,spacing:4){
                                        Text(zone.zone).font(.system(size:12,weight:.semibold))
                                        Text(zone.block.capitalized+" · \(Int(zone.availableMinutes)) exposure min")
                                            .font(.system(size:10)).foregroundStyle(RadarStyle.subtle)
                                    }
                                    Spacer()
                                    VStack(alignment:.trailing,spacing:3) {
                                        Text("\(Money.number(zone.rate*60)) offers/h")
                                            .font(.system(size:12,weight:.bold))
                                        Text("\(Int(zone.confidence*100))% model confidence")
                                            .font(.system(size:10)).foregroundStyle(RadarStyle.subtle)
                                    }
                                }
                                Divider().overlay(RadarStyle.line)
                            }
                        }
                    }
                }
                if let merchants=store.stats?.merchantStats,!merchants.isEmpty {
                    RadarCard {
                        Text("Pickup intelligence").font(.system(size:16,weight:.bold))
                        ForEach(merchants.prefix(10)){m in
                            Divider().overlay(RadarStyle.line)
                            HStack{
                                Text(m.merchant).font(.system(size:12,weight:.medium))
                                    .lineLimit(1)
                                Spacer()
                                Text("\(m.completed ?? 0) delivered")
                                Text(m.avgWaitMinutes.map{"· \(Int($0))m pickup"} ?? "")
                            }.font(.system(size:10)).foregroundStyle(RadarStyle.subtle)
                                .padding(.vertical,7)
                        }
                    }
                }
                RadarCard {
                    Text("Model limitations").font(.system(size:15,weight:.bold))
                    Text("Decline/deprioritization patterns are correlations, not proof Uber applies an account penalty. Money predictions are uncertain and cannot guarantee a $170–$200 day.")
                        .font(.system(size:11)).foregroundStyle(RadarStyle.subtle)
                        .padding(.top,5)
                }
            }.padding(16)
        }
        .scrollContentBackground(.hidden).background(RadarStyle.background)
        .refreshable{await store.refresh()}
    }
}
