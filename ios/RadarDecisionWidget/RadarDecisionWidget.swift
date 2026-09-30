import ActivityKit
import SwiftUI
import WidgetKit

private enum DecisionVisual {
    static func color(_ verdict:String,stale:Bool)->Color {
        if stale{return .gray}
        switch verdict {
        case "TAKE":return .green
        case "SKIP":return .orange
        default:return .yellow
        }
    }
    static func label(_ verdict:String,stale:Bool)->String {
        stale ? "EXPIRED" : verdict
    }
}

struct RadarDecisionWidget:Widget {
    var body:some WidgetConfiguration {
        ActivityConfiguration(for:RadarDecisionAttributes.self) { context in
            VStack(alignment:.leading,spacing:8) {
                HStack {
                    Text("COURIER RADAR").font(.caption2.bold()).foregroundStyle(.secondary)
                    Spacer()
                    Text(DecisionVisual.label(context.state.verdict,stale:context.isStale))
                        .font(.title3.bold())
                        .foregroundStyle(DecisionVisual.color(context.state.verdict,stale:context.isStale))
                }
                HStack {
                    Text(context.state.merchant).font(.headline).lineLimit(1)
                    Spacer(minLength:6)
                    Text(context.state.payout).font(.headline.monospacedDigit())
                }
                Text(context.isStale ? "Offer snapshot expired. Capture a new screenshot." : context.state.reason)
                    .font(.caption).lineLimit(2)
                HStack {
                    Text("Check the live Uber offer before acting")
                    Spacer(minLength:5)
                    Text(context.state.expiresAt,style:.timer)
                        .monospacedDigit()
                }.font(.caption2).foregroundStyle(.secondary)
            }
            .padding(14)
            .activityBackgroundTint(Color.black)
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(DecisionVisual.label(context.state.verdict,stale:context.isStale))
                        .font(.title2.bold())
                        .foregroundStyle(DecisionVisual.color(context.state.verdict,stale:context.isStale))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.payout)
                        .font(.title2.bold().monospacedDigit())
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.merchant).font(.caption.bold()).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment:.leading,spacing:5) {
                        Text(context.isStale ? "Offer snapshot expired." : context.state.reason)
                            .font(.caption).lineLimit(3)
                        HStack {
                            Text("Check Uber before acting")
                            Spacer()
                            Text(context.state.expiresAt,style:.timer).monospacedDigit()
                        }.font(.caption2).foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                Text(DecisionVisual.label(context.state.verdict,stale:context.isStale))
                    .font(.caption2.bold())
                    .foregroundStyle(DecisionVisual.color(context.state.verdict,stale:context.isStale))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            } compactTrailing: {
                Text(context.state.payout)
                    .font(.caption2.bold().monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } minimal: {
                Image(systemName:context.isStale ? "clock" :
                    context.state.verdict=="TAKE" ? "checkmark" :
                    context.state.verdict=="SKIP" ? "xmark" : "questionmark")
                    .foregroundStyle(DecisionVisual.color(context.state.verdict,stale:context.isStale))
            }
            .keylineTint(DecisionVisual.color(context.state.verdict,stale:context.isStale))
        }
    }
}

@main struct RadarDecisionWidgetBundle:WidgetBundle {
    var body:some Widget {
        RadarDecisionWidget()
    }
}
