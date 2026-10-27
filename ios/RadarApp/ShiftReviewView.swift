import SwiftUI

/// End-of-session / end-of-day debrief. Measured numbers first; AI commentary is labeled.
struct ShiftReviewView:View {
    let payload:ShiftReviewPayload
    @Environment(\.dismiss) private var dismiss
    @State private var showDay=false
    private var review:ShiftReview {showDay ? payload.dayReview:payload.session}
    private static let time:DateFormatter = {
        let f=DateFormatter();f.timeZone=TimeZone(identifier:"America/Los_Angeles");f.dateFormat="h:mm a";return f
    }()

    var body:some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:14) {
                    Picker("Scope",selection:$showDay) {
                        Text("This session").tag(false)
                        Text("Whole day").tag(true)
                    }.pickerStyle(.segmented)
                    tierCard
                    aiCard
                    metricsCard
                    upsideCard
                    if !review.mistakes.isEmpty {mistakesCard}
                    decisionsCard
                    if !review.segments.isEmpty {movementCard}
                    tuningCard
                    Text("Tier = 40% $/h vs $35 · 25% gross vs $270 (pro-rated for a session) · 20% paid time vs 80% · 15% acceptance vs 60% target / 50% floor. S ≥ 90 · A ≥ 80 · B ≥ 68 · C ≥ 55 · D ≥ 40.")
                        .font(.system(size:10)).foregroundStyle(RadarStyle.subtle)
                    if let e=payload.saveError {
                        Text(e).font(.system(size:11)).foregroundStyle(RadarStyle.amber)
                    }
                }.padding(16)
            }
            .background(RadarStyle.background.ignoresSafeArea())
            .navigationTitle(showDay ? "Day review \(payload.day)":"Session review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {ToolbarItem(placement:.confirmationAction){Button("Done"){dismiss()}}}
        }
    }
    private func tierColor(_ t:String)->Color {
        switch t {case "S","A":return RadarStyle.signal;case "B","C":return RadarStyle.amber;default:return RadarStyle.danger}
    }
    private var tierCard:some View {
        RadarCard {
            HStack(alignment:.center,spacing:16) {
                Text(review.tier).font(.system(size:64,weight:.heavy,design:.rounded))
                    .foregroundStyle(tierColor(review.tier)).accessibilityLabel("Tier \(review.tier)")
                VStack(alignment:.leading,spacing:4) {
                    Text("\(review.score) / 100").font(.system(size:20,weight:.bold))
                    if let c=review.components {
                        Text("$/h \(pct(c.dph)) · gross \(pct(c.gross)) · paid \(pct(c.utilization)) · accept \(pct(c.acceptance))")
                            .font(.system(size:11)).foregroundStyle(RadarStyle.subtle)
                    }
                    if let s=review.start,let e=review.end {
                        Text("\(Self.time.string(from:s)) – \(Self.time.string(from:e))")
                            .font(.system(size:11)).foregroundStyle(RadarStyle.subtle)
                    }
                }
            }
        }
    }
    @ViewBuilder private var aiCard:some View {
        RadarCard {
            RadarKicker(text:"AI debrief")
            if let ai=payload.ai,let headline=ai.headline {
                Text(headline).font(.system(size:16,weight:.bold))
                if let s=ai.summary {Text(s).font(.system(size:13))}
                if let items=ai.improvements,!items.isEmpty {
                    Text("Do differently").font(.system(size:12,weight:.bold)).padding(.top,6)
                    ForEach(items){i in bullet(i.title,i.detail,gain:i.estimatedGain)}
                }
                if let items=ai.tomorrow,!items.isEmpty {
                    Text("Next shift plan").font(.system(size:12,weight:.bold)).padding(.top,6)
                    ForEach(items,id:\.self){Text("• "+$0).font(.system(size:12))}
                }
            } else {
                Text(payload.ai?.configured == false ? "OpenAI isn't configured on the Radar server (OPENAI_API_KEY). The measured review below still applies.":
                     payload.ai?.skipped == true ? "OpenAI review is off in Settings. The measured review below still applies.":
                     (payload.ai?.error ?? "No AI debrief for this review."))
                    .font(.system(size:12)).foregroundStyle(RadarStyle.subtle)
            }
        }
    }
    private var metricsCard:some View {
        let m=review.metrics
        return RadarCard {
            RadarKicker(text:m.earningsSource=="uber_daily_total" ? "Measured · Uber daily total":"Measured · Radar-captured payouts")
            HStack(spacing:10) {
                RadarMetric(title:"Earned",value:Money.dollars(m.earnings),color:RadarStyle.signal)
                RadarMetric(title:"$/hour",value:Money.dollars(m.dph))
                RadarMetric(title:"Orders",value:"\(m.orders ?? 0)")
            }
            HStack(spacing:10) {
                RadarMetric(title:"Online",value:minutes(m.onlineMinutes))
                RadarMetric(title:"Paid time",value:Money.percent(m.utilization))
                RadarMetric(title:"Waiting",value:minutes(m.waitingMinutes))
            }.padding(.top,6)
            HStack(spacing:10) {
                RadarMetric(title:"Acceptance",value:Money.percent(m.acceptance))
                RadarMetric(title:"Took / skipped",value:"\(m.taken ?? 0) / \(m.skipped ?? 0)")
                RadarMetric(title:"Followed Radar",value:"\(m.followedRadar ?? 0) of \((m.followedRadar ?? 0)+(m.overrodeRadar ?? 0))")
            }.padding(.top,6)
        }
    }
    @ViewBuilder private var upsideCard:some View {
        if let e=review.estimate,let up=e.upside,up>0 {
            RadarCard {
                RadarKicker(text:"Estimated money left on the table")
                Text("+\(Money.dollars(up))").font(.system(size:28,weight:.bold,design:.rounded)).foregroundStyle(RadarStyle.amber)
                Text("Potential \(Money.dollars(e.potentialEarnings)) · \(Money.dollars(e.potentialDph))/h with the fixes below.")
                    .font(.system(size:12))
                if let b=e.basis {Text(b).font(.system(size:10)).foregroundStyle(RadarStyle.subtle)}
            }
        }
    }
    private var mistakesCard:some View {
        RadarCard {
            RadarKicker(text:"Mistakes · measured")
            ForEach(review.mistakes){m in
                HStack(alignment:.top) {
                    VStack(alignment:.leading,spacing:2) {
                        Text(mistakeTitle(m))
                            .font(.system(size:13,weight:.semibold))
                        if let d=m.detail {Text(d).font(.system(size:11)).foregroundStyle(RadarStyle.subtle)}
                    }
                    Spacer()
                    Text(costText(m.estimatedCost)).font(.system(size:13,weight:.bold)).foregroundStyle(RadarStyle.danger)
                }.padding(.vertical,3)
            }
        }
    }
    private var decisionsCard:some View {
        RadarCard {
            RadarKicker(text:"Every decision")
            if review.decisions.isEmpty {
                Text("No captured offers in this window.").font(.system(size:12)).foregroundStyle(RadarStyle.subtle)
            }
            ForEach(review.decisions.reversed()){d in decisionRow(d)}
        }
    }
    private func decisionDetail(_ d:ReviewDecision)->String {
        var parts:[String]=[]
        if let v=d.impliedDph {parts.append(String(format:"$%.0f/h cycle",v))}
        if let r=d.radar {parts.append("Radar: "+r+(d.followedRadar == false ? " (overrode)":""))}
        if let w=d.restaurantWait {parts.append(String(format:"%.0f min at restaurant",w))}
        return parts.joined(separator:" · ")
    }
    private func decisionRow(_ d:ReviewDecision)->some View {
        let when:String=d.at.map{Self.time.string(from:$0)} ?? "—"
        let title:String="\(d.action) \(d.merchant ?? "Offer") · \(Money.dollars(d.payout))"
        return HStack(alignment:.top,spacing:8) {
            Text(when).font(.system(size:11,design:.monospaced))
                .foregroundStyle(RadarStyle.subtle).frame(width:62,alignment:.leading)
            VStack(alignment:.leading,spacing:2) {
                Text(title).font(.system(size:13,weight:.semibold))
                Text(decisionDetail(d)).font(.system(size:11)).foregroundStyle(RadarStyle.subtle)
            }
            Spacer()
            RadarPill(text:d.grade.uppercased(),color:gradeColor(d.grade))
        }.padding(.vertical,2)
    }
    private var movementCard:some View {
        RadarCard {
            RadarKicker(text:"Where your time went")
            ForEach(review.segments){s in
                HStack {
                    Text(s.start.map{Self.time.string(from:$0)} ?? "—").font(.system(size:11,design:.monospaced))
                        .foregroundStyle(RadarStyle.subtle).frame(width:62,alignment:.leading)
                    Text("\(s.zone) · \(s.block.capitalized)").font(.system(size:12))
                    Spacer()
                    Text("\(Int(s.busyMinutes ?? 0))m paid · \(Int(s.idleMinutes ?? 0))m idle")
                        .font(.system(size:11)).foregroundStyle((s.idleMinutes ?? 0)>=20 ? RadarStyle.amber:RadarStyle.subtle)
                }
            }
            if !review.zoneBlocks.isEmpty {
                Text("Offer rate while idle (today vs 30-day)").font(.system(size:12,weight:.bold)).padding(.top,6)
                ForEach(review.zoneBlocks){z in
                    HStack {
                        Text("\(z.zone) · \(z.block.capitalized)").font(.system(size:12))
                        Spacer()
                        Text("\(Money.number(z.offersPerIdleHour))/h vs \(Money.number(z.historyPerHour))/h · \(Money.dollars(z.earned))")
                            .font(.system(size:11)).foregroundStyle(RadarStyle.subtle)
                    }
                }
            }
        }
    }
    private var tuningCard:some View {
        RadarCard {
            RadarKicker(text:"Algorithm tuning")
            let today=(payload.adjustments ?? [:]).sorted{$0.key<$1.key}
            if today.isEmpty {
                Text("No zone rate changes today. Radar needs 30+ idle minutes in a zone and time block, or a clear gap, before adjusting.")
                    .font(.system(size:12)).foregroundStyle(RadarStyle.subtle)
            }
            ForEach(today,id:\.key){k,v in
                tuningRow(key:k,value:v)
            }
            Text("Each day moves a zone's expected offer rate at most ±10%, and never beyond ±30% in total. Math compares today's rate with your 30-day rate; the AI can only nudge within the same bound.")
                .font(.system(size:10)).foregroundStyle(RadarStyle.subtle).padding(.top,4)
        }
    }
    private func mistakeTitle(_ m:ReviewMistake)->String {
        let place:String=m.merchant ?? m.zone ?? ""
        return place.isEmpty ? m.kind.capitalized:m.kind.capitalized+" · "+place
    }
    private func costText(_ v:Double?)->String {"−"+Money.dollars(v)}
    private func tuningRow(key:String,value:Double)->some View {
        let reason:String?=payload.ai?.adjustments?.first(where:{$0.key==key})?.reason
        let arrow:String=value<1 ? "↓":"↑"
        let change:String=String(format:"%+.0f%%",(value-1)*100)
        let total:String=String(format:"%.2f×",payload.learned?[key] ?? value)
        let label:String=key.replacingOccurrences(of:"|",with:" · ")+": offer rate "+arrow+" "+change+" today · now "+total
        return VStack(alignment:.leading,spacing:1) {
            Text(label).font(.system(size:12,weight:.semibold))
            if let reason {Text(reason).font(.system(size:11)).foregroundStyle(RadarStyle.subtle)}
        }
    }
    private func bullet(_ title:String,_ detail:String,gain:Double?)->some View {
        VStack(alignment:.leading,spacing:1) {
            Text("• "+title+((gain ?? 0)>0 ? " (+\(Money.dollars(gain)) est.)":"")).font(.system(size:12,weight:.semibold))
            Text(detail).font(.system(size:11)).foregroundStyle(RadarStyle.subtle)
        }
    }
    private func gradeColor(_ g:String)->Color {
        switch g {case "good take","good skip","skip paid off":return RadarStyle.signal
        case "weak take":return RadarStyle.amber;case "costly skip","missed offer":return RadarStyle.danger
        default:return RadarStyle.subtle}
    }
    private func pct(_ v:Double?)->String {v.map{"\(Int(($0*100).rounded()))%"} ?? "—"}
    private func minutes(_ v:Double?)->String {
        guard let v else{return "—"}
        let m=Int(v.rounded());return m>=60 ? "\(m/60)h \(m%60)m":"\(m)m"
    }
}
