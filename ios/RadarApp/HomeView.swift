import SwiftUI
import MapKit
import PhotosUI
import RadarCore

struct HomeView:View {
    @EnvironmentObject private var store:RadarStore
    @EnvironmentObject private var tracker:LocationTracker
    @State private var camera:MapCameraPosition = .region(
        MKCoordinateRegion(center:CLLocationCoordinate2D(latitude:34.0211,longitude:-118.3965),
                           span:MKCoordinateSpan(latitudeDelta:0.035,longitudeDelta:0.035)))
    @State private var followedOnce=false
    @State private var selectedScreenshot:PhotosPickerItem?
    @State private var activeOfferExpanded=false
    @State private var confirmFinish=false
    @State private var showingRecovery=false
    @State private var finishOfferId:String?

    private var zones:[DispatchZone] {
        (store.stats?.dispatchModel?.zones ?? []).filter {
            $0.block==WorkClock.block(at:Date()) && $0.point != nil && $0.availableMinutes>0
        }
    }
    private var presentOffer:RadarOffer? {
        if let offer=store.latestOffer,offer.state=="observed",
           let at=offer.capturedAt,Date().timeIntervalSince(at)<180 {return offer}
        return store.activeOffer
    }
    private var currentDecision:CashDecision? {
        presentOffer.map{store.decide($0)}
    }
    var body:some View {
        ZStack(alignment:.top) {
            Map(position:$camera,interactionModes:[.pan,.zoom,.rotate]){
                UserAnnotation()
                ForEach(zones) { z in
                    if let coord=z.point {
                        Annotation(z.zone,coordinate:CLLocationCoordinate2D(latitude:coord.lat,longitude:coord.lng)) {
                            Button{
                                let span=MKCoordinateSpan(latitudeDelta:0.016,longitudeDelta:0.016)
                                withAnimation(.easeOut(duration:0.35)){
                                    camera = .region(MKCoordinateRegion(
                                        center:CLLocationCoordinate2D(latitude:coord.lat,longitude:coord.lng),
                                        span:span))
                                }
                            }label:{
                                VStack(spacing:3){
                                    Image(systemName:"circle.hexagongrid.fill")
                                        .font(.system(size:18))
                                    Text(String(format:"%.1f/h",z.rate*60))
                                        .font(.system(size:9,weight:.bold,design:.rounded))
                                }
                                .padding(8)
                                .foregroundStyle(z.confidence>0.5 ? RadarStyle.signal:RadarStyle.subtle)
                                .background(RadarStyle.background.opacity(0.95),
                                            in:RoundedRectangle(cornerRadius:11))
                                .overlay(RoundedRectangle(cornerRadius:11)
                                    .strokeBorder(RadarStyle.line,lineWidth:1))
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
            .mapStyle(.standard(elevation:.flat))
            .mapControls {MapCompass();MapScaleView()}
            .ignoresSafeArea(edges:.top)
            VStack(spacing:11) {
                HStack(spacing:9){
                    RadarCard {
                        VStack(alignment:.leading,spacing:5){
                            HStack {
                                RadarKicker(text:"Today banked")
                                Spacer(minLength:4)
                                Text(store.shiftActive ? "● ONLINE":"OFFLINE")
                                    .font(.system(size:9,weight:.bold))
                                    .foregroundStyle(store.shiftActive ? RadarStyle.signal:RadarStyle.subtle)
                            }
                            HStack(alignment:.firstTextBaseline){
                                Text(Money.dollars(store.verifiedCash))
                                    .font(.system(size:27,weight:.bold,design:.rounded))
                                    .foregroundStyle(RadarStyle.signal)
                                    .minimumScaleFactor(0.7).lineLimit(1)
                                Spacer(minLength:6)
                                VStack(alignment:.trailing,spacing:2) {
                                    Text(Money.dollars(store.missingFromGoal))
                                        .font(.system(size:14,weight:.bold))
                                    Text("to \(Money.dollars(store.prefs.goal))")
                                        .font(.system(size:9)).foregroundStyle(RadarStyle.subtle)
                                }
                            }
                            ProgressView(value:min(1,store.verifiedCash/max(1,store.prefs.goal)))
                                .tint(RadarStyle.signal)
                            HStack {
                                Text(store.stats?.todayEarningsSource=="uber_manual_total" ?
                                     "UBER TOTAL (MANUAL)":"RADAR CAPTURED")
                                Spacer()
                                Text("Active \(Money.percent(store.paidUtilization))")
                            }.font(.system(size:9,weight:.medium))
                                .foregroundStyle(RadarStyle.subtle)
                        }
                    }
                    .frame(maxWidth:.infinity)
                    Button {
                        if let point=store.gps.point {
                            camera = .region(MKCoordinateRegion(
                                center:CLLocationCoordinate2D(latitude:point.lat,longitude:point.lng),
                                span:MKCoordinateSpan(latitudeDelta:0.017,longitudeDelta:0.017)))
                        }else{store.gps.requestPermission()}
                    }label:{
                        Image(systemName:"location.fill")
                            .font(.system(size:18,weight:.semibold))
                            .frame(width:48,height:48)
                            .background(RadarStyle.surface,in:RoundedRectangle(cornerRadius:14))
                            .overlay(RoundedRectangle(cornerRadius:14)
                                .strokeBorder(RadarStyle.line))
                    }.buttonStyle(.plain)
                }
                waitPanel
                Spacer(minLength:5)
                if let offer=presentOffer {
                    currentOfferPanel(offer)
                }
                HStack(spacing:9){
                    PhotosPicker(selection:$selectedScreenshot,matching:.images) {
                        Label("SCREENSHOT",systemImage:"text.viewfinder")
                            .font(.system(size:12,weight:.bold))
                            .frame(maxWidth:.infinity,minHeight:47)
                            .foregroundStyle(RadarStyle.text)
                            .background(RadarStyle.surface,in:RoundedRectangle(cornerRadius:13))
                    }
                    .disabled(store.isActing)
                    Button{showingRecovery=true}label:{
                        Label("RECOVER",systemImage:"arrow.uturn.backward")
                            .font(.system(size:11,weight:.bold))
                            .frame(maxWidth:.infinity,minHeight:47)
                            .foregroundStyle(RadarStyle.signal)
                            .background(RadarStyle.surface,in:RoundedRectangle(cornerRadius:13))
                    }.buttonStyle(.plain)
                    Button{
                        Task{store.shiftActive ? await store.endShift():await store.startShift()}
                    }label:{
                        HStack(spacing:7){
                            Image(systemName:store.shiftActive ? "stop.fill":"play.fill")
                            Text(store.shiftActive ? "END SHIFT":"START SHIFT")
                        }.font(.system(size:12,weight:.bold))
                            .frame(maxWidth:.infinity,minHeight:47)
                            .foregroundStyle(store.shiftActive ? RadarStyle.text:RadarStyle.background)
                            .background(store.shiftActive ? RadarStyle.inset:RadarStyle.signal,
                                        in:RoundedRectangle(cornerRadius:13))
                    }.disabled(store.isActing)
                }
                HStack(spacing:6){
                    Circle().fill(store.authReady ? RadarStyle.signal:RadarStyle.amber).frame(width:6,height:6)
                    Text(store.gps.status)
                    Text("·")
                    Text(store.lastSync.map{"Synced "+$0.formatted(date:.omitted,time:.shortened)} ?? "Not synced")
                    if store.pendingGPS>0 {Text("· GPS queue \(store.pendingGPS)")}
                }
                .font(.system(size:10))
                .foregroundStyle(RadarStyle.subtle)
                .lineLimit(1)
            }
            .padding(.horizontal,12).padding(.top,12).padding(.bottom,12)
        }
        .background(RadarStyle.background)
        .onChange(of:tracker.point){_,value in
            guard !followedOnce,let point=value,point.isValid else{return}
            followedOnce=true
            camera = .region(MKCoordinateRegion(center:CLLocationCoordinate2D(
                latitude:point.lat,longitude:point.lng),
                span:MKCoordinateSpan(latitudeDelta:0.022,longitudeDelta:0.022)))
        }
        .onChange(of:selectedScreenshot){_,selected in
            guard let selected else{return}
            Task{
                if let bytes=try? await selected.loadTransferable(type:Data.self),
                   let image=UIImage(data:bytes){await store.capture(image:image)}
                else{store.error="Could not open the selected screenshot."}
                selectedScreenshot=nil
            }
        }
        .sheet(isPresented:$showingRecovery){MissedOrderView()}
        .confirmationDialog("Mark delivered in Radar?",
            isPresented:$confirmFinish,titleVisibility:.visible){
            Button("Uber delivery is finished"){Task{await store.mark("next",offerId:finishOfferId)}}
            Button("Cancel",role:.cancel){}
        }message:{Text("Only mark delivered after Uber confirms completion.")}
    }
    @ViewBuilder private var waitPanel:some View {
        let decision=store.waitAdvice
        RadarCard {
            HStack(alignment:.top,spacing:12){
                VStack(alignment:.leading,spacing:5){
                    HStack(spacing:7){
                        RadarPill(text:decision.kind.rawValue,
                                  color:decision.kind == .charge ? RadarStyle.amber:RadarStyle.signal)
                        RadarKicker(text:decision.zone ?? "GPS learning")
                    }
                    Text(decision.destination.map{"\($0) · evidence-backed destination"} ??
                         (decision.zone ?? "Waiting for location"))
                        .font(.system(size:14,weight:.bold))
                        .lineLimit(2)
                    Text(decision.reason)
                        .font(.system(size:11))
                        .foregroundStyle(RadarStyle.subtle)
                        .lineLimit(3)
                    if let advantage=decision.expectedAdvantage {
                        Text("Estimated additional cash: \(Money.dollars(advantage))")
                            .font(.system(size:11,weight:.bold)).foregroundStyle(RadarStyle.signal)
                    }
                    let m=store.stats?.dispatchModel
                    Text("\(m?.offersObservedAvailable ?? 0) matched offers · " +
                         "\(Int(m?.verifiedAvailableMinutes ?? 0)) GPS-verified minutes")
                        .font(.system(size:10,weight:.medium))
                        .foregroundStyle(RadarStyle.subtle)
                }
                Spacer(minLength:3)
                if decision.kind == .move || decision.kind == .returning,
                   let name=decision.destination,
                   let target=zones.first(where:{$0.zone == name}),let coord=target.point {
                    Button{
                        let item=MKMapItem(placemark:MKPlacemark(
                            coordinate:CLLocationCoordinate2D(latitude:coord.lat,longitude:coord.lng)))
                        item.name=name
                        item.openInMaps(launchOptions:[MKLaunchOptionsDirectionsModeKey:MKLaunchOptionsDirectionsModeWalking])
                    }label:{
                        Image(systemName:"arrow.triangle.turn.up.right.diamond.fill")
                            .font(.system(size:21)).foregroundStyle(RadarStyle.signal)
                            .frame(width:38,height:38).background(RadarStyle.inset,
                              in:RoundedRectangle(cornerRadius:12))
                    }.buttonStyle(.plain)
                } else {
                    Button{Task{await store.refresh()}}label:{
                        Image(systemName:"arrow.clockwise")
                            .font(.system(size:15,weight:.bold))
                            .frame(width:38,height:38).background(RadarStyle.inset,
                                in:RoundedRectangle(cornerRadius:12))
                    }.buttonStyle(.plain)
                }
            }
        }
    }
    @ViewBuilder private func currentOfferPanel(_ offer:RadarOffer) -> some View {
        let decision=store.decide(offer)
        RadarCard {
            VStack(alignment:.leading,spacing:10){
                HStack(spacing:10){
                    VStack(alignment:.leading,spacing:2){
                        RadarKicker(text:offer.state=="observed" ? "Latest Uber offer":"Active delivery")
                        Text(offer.merchant ?? "Uber offer")
                            .font(.system(size:15,weight:.bold)).lineLimit(1)
                    }
                    Spacer()
                    Text(Money.dollars(offer.payout))
                        .font(.system(size:24,weight:.bold,design:.rounded))
                    RadarPill(text:offer.state=="observed" ? decision.kind.rawValue : (offer.state ?? "ACTIVE"),
                              color:decision.kind == .skip && offer.state=="observed" ? RadarStyle.danger : RadarStyle.signal)
                }
                if offer.state=="observed" {
                    Text(decision.reason)
                        .font(.system(size:11)).foregroundStyle(RadarStyle.subtle)
                        .lineLimit(activeOfferExpanded ? nil:2)
                    if let after=decision.afterDelivery {
                        Text("AFTER DROPOFF → "+after.uppercased())
                            .font(.system(size:10,weight:.bold))
                            .foregroundStyle(RadarStyle.signal)
                    }
                    HStack(spacing:12){
                        Label("\(Money.number(offer.miles)) mi",systemImage:"point.topleft.down.curvedto.point.bottomright.up")
                        Label("\(Int(offer.tripETA)) min",systemImage:"clock")
                        if let t=decision.takeValue,let s=decision.skipValue {
                            Text("TAKE \(Money.dollars(t)) / SKIP \(Money.dollars(s))")
                        }
                    }
                    .font(.system(size:10,weight:.medium)).foregroundStyle(RadarStyle.subtle)
                    .lineLimit(1).minimumScaleFactor(0.75)
                }
                HStack(spacing:8){
                    RadarActionButton(title:nextStageLabel(offer.state),systemImage:"checkmark.circle.fill",
                                      highlighted:true,disabled:store.isActing){
                        if offer.state=="picked_up"{finishOfferId=offer.id;confirmFinish=true}
                        else{Task{await store.mark("next",offerId:offer.id)}}
                    }
                    Button{activeOfferExpanded.toggle()}label:{
                        Image(systemName:activeOfferExpanded ? "chevron.up":"ellipsis")
                            .frame(width:47,height:46)
                            .background(RadarStyle.inset,in:RoundedRectangle(cornerRadius:13))
                    }.buttonStyle(.plain)
                }
                if activeOfferExpanded {
                    HStack {
                        RadarActionButton(title:"DECLINED",systemImage:"xmark",disabled:store.isActing){
                            Task{await store.mark("rejected",offerId:offer.id)}
                        }
                        RadarActionButton(title:"CANCELLED",systemImage:"xmark.circle",disabled:store.isActing){
                            Task{await store.mark("cancelled",offerId:offer.id)}
                        }
                    }
                }
            }
        }
    }
    private func nextStageLabel(_ state:String?) -> String {
        switch state{
        case "observed":return "MARK ACCEPTED"
        case "accepted":return "AT PICKUP"
        case "arrived":return "PICKED UP"
        case "picked_up":return "MARK DELIVERED"
        default:return "NEXT STAGE"
        }
    }
}
