import SwiftUI
import RadarCore

enum RadarStyle {
    static let background=Color(red:0.043,green:0.067,blue:0.082)
    static let surface=Color(red:0.075,green:0.115,blue:0.139)
    static let inset=Color(red:0.103,green:0.149,blue:0.172)
    static let line=Color(red:0.21,green:0.29,blue:0.29).opacity(0.55)
    static let text=Color(red:0.93,green:0.96,blue:0.94)
    static let subtle=Color(red:0.64,green:0.71,blue:0.72)
    static let signal=Color(red:0.73,green:0.95,blue:0.45)
    static let danger=Color(red:0.95,green:0.53,blue:0.53)
    static let amber=Color(red:0.95,green:0.77,blue:0.45)
    static let insetRadius:CGFloat=13
}
struct RadarCard<Content:View>:View {
    @ViewBuilder var content:Content
    var body:some View {
        content
            .frame(maxWidth:.infinity,alignment:.leading)
            .padding(15)
            .background(RadarStyle.surface,in:RoundedRectangle(cornerRadius:18,style:.continuous))
            .overlay(RoundedRectangle(cornerRadius:18).strokeBorder(RadarStyle.line,lineWidth:1))
    }
}
struct RadarKicker:View {
    let text:String
    var body:some View {
        Text(text.uppercased())
            .font(.system(size:10,weight:.bold,design:.rounded))
            .tracking(1.6)
            .foregroundStyle(RadarStyle.subtle)
    }
}
struct RadarMetric:View {
    let title:String
    let value:String
    var color:Color=RadarStyle.text
    var body:some View {
        VStack(alignment:.leading,spacing:4) {
            Text(value).font(.system(size:22,weight:.bold,design:.rounded))
                .foregroundStyle(color).contentTransition(.numericText())
                .lineLimit(1).minimumScaleFactor(0.72)
            Text(title).font(.system(size:10,weight:.medium))
                .foregroundStyle(RadarStyle.subtle).lineLimit(1)
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
}
private struct RadarPressStyle:ButtonStyle {
    func makeBody(configuration:Configuration)->some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.spring(response:0.18,dampingFraction:0.72),value:configuration.isPressed)
    }
}
struct RadarActionButton:View {
    let title:String
    let systemImage:String
    var highlighted:Bool=false
    var disabled:Bool=false
    let action:()->Void
    var body:some View {
        Button(action:action){
            Label(title,systemImage:systemImage)
                .font(.system(size:13,weight:.bold))
                .frame(maxWidth:.infinity,minHeight:46)
                .foregroundStyle(highlighted ? RadarStyle.background:RadarStyle.text)
                .background(highlighted ? RadarStyle.signal:RadarStyle.inset,
                            in:RoundedRectangle(cornerRadius:13))
        }
        .buttonStyle(RadarPressStyle())
        .sensoryFeedback(.impact(weight:.light),trigger:disabled)
        .disabled(disabled)
        .opacity(disabled ? 0.5:1)
    }
}
struct RadarPill:View {
    let text:String
    let color:Color
    var body:some View {
        Text(text.uppercased()).font(.system(size:10,weight:.bold)).tracking(0.7)
            .foregroundStyle(color)
            .padding(.horizontal,9).padding(.vertical,6)
            .background(color.opacity(0.12),in:RoundedRectangle(cornerRadius:9))
    }
}
enum Money {
    static func dollars(_ value:Double?) -> String {
        (value ?? 0).formatted(.currency(code:"USD"))
    }
    static func number(_ value:Double?,decimals:Int=1) -> String {
        guard let value else{return "—"}
        return value.formatted(.number.precision(.fractionLength(decimals)))
    }
    static func percent(_ value:Double?) -> String {
        guard let value else{return "—"}
        return "\(Int((value*100).rounded()))%"
    }
}
