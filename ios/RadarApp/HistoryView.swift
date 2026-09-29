import SwiftUI
import RadarCore

struct HistoryView:View {
    @EnvironmentObject private var store:RadarStore
    @State private var range=0
    private var filtered:[RadarOffer] {
        let date=Date(),cut=Date().addingTimeInterval(-7*86400)
        let today=WorkClock.workday(at:date)
        return store.offers.filter { offer in
            guard let captured=offer.capturedAt else{return false}
            return range==0 ? WorkClock.workday(at:captured)==today:captured>=cut
        }
    }
    private var completed:[RadarOffer] {
        filtered.filter {["completed","delivered"].contains($0.state ?? "")}
    }
    private var trackedTotal:Double {completed.reduce(0){$0+$1.settledPayout}}
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:15) {
                VStack(alignment:.leading,spacing:6){
                    RadarKicker(text:"Your recorded Uber offers")
                    Text("Order history").font(.system(size:31,weight:.bold))
                    Text("Captured lifecycle, actual times and recorded amounts.")
                        .font(.system(size:12)).foregroundStyle(RadarStyle.subtle)
                }
                Picker("Range",selection:$range) {
                    Text("Today").tag(0);Text("Last 7 days").tag(1)
                }.pickerStyle(.segmented)
                RadarCard {
                    HStack{
                        RadarMetric(title:"Recorded deliveries",value:"\(completed.count)")
                        RadarMetric(title:"Captured payouts",value:Money.dollars(trackedTotal),color:RadarStyle.signal)
                    }
                    if range==0 {
                        Divider().overlay(RadarStyle.line)
                        HStack {
                            Text("Uber total (if reconciled)")
                                .font(.system(size:11)).foregroundStyle(RadarStyle.subtle)
                            Spacer()
                            Text(Money.dollars(store.stats?.todayEarnings))
                                .font(.system(size:13,weight:.bold))
                        }
                    }
                }
                historyGroup(title:"Completed",detail:"Actual recorded drop-offs",offers:completed)
                historyGroup(title:"Offers",detail:"Includes observed, declined and open orders",
                             offers:filtered.filter{!["completed","delivered"].contains($0.state ?? "")})
                if filtered.isEmpty {
                    RadarCard {
                        ContentUnavailableView("No orders yet",systemImage:"bag",
                          description:Text("Capture an Uber offer from Home or your iPhone Shortcut."))
                    }
                }
            }.padding(16)
        }
        .scrollContentBackground(.hidden)
        .background(RadarStyle.background)
        .refreshable {await store.refresh()}
    }
    @ViewBuilder private func historyGroup(title:String,detail:String,offers:[RadarOffer]) -> some View {
        if !offers.isEmpty {
            RadarCard {
                VStack(alignment:.leading,spacing:0){
                    HStack{
                        Text(title).font(.system(size:17,weight:.bold))
                        Spacer()
                        Text(detail).font(.system(size:9)).foregroundStyle(RadarStyle.subtle)
                    }.padding(.bottom,10)
                    ForEach(offers){offer in
                        Divider().overlay(RadarStyle.line)
                        HStack(alignment:.center,spacing:10){
                            VStack(alignment:.leading,spacing:4){
                                Text(offer.merchant ?? "Unknown merchant")
                                    .font(.system(size:13,weight:.semibold)).lineLimit(1)
                                HStack(spacing:7){
                                    Text((offer.state ?? "observed").replacingOccurrences(of:"_",with:" ").uppercased())
                                        .foregroundStyle(["delivered","completed"].contains(offer.state ?? "") ?
                                                         RadarStyle.signal:RadarStyle.subtle)
                                    if let miles=offer.miles{Text("\(Money.number(miles)) mi")}
                                    if let eta=offer.etaMinutes{Text("\(Int(eta)) min")}
                                }.font(.system(size:10))
                                if let date=offer.capturedAt {
                                    Text(date.formatted(date:.abbreviated,time:.shortened))
                                        .font(.system(size:10)).foregroundStyle(RadarStyle.subtle)
                                }
                            }
                            Spacer()
                            Text(Money.dollars(offer.settledPayout))
                                .font(.system(size:15,weight:.bold))
                        }.padding(.vertical,12)
                    }
                }
            }
        }
    }
}
