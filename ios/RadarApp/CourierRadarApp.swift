import SwiftUI
import RadarCore

@main struct CourierRadarApp:App {
    @StateObject private var store=RadarStore()
    @Environment(\.scenePhase) private var scenePhase
    var body:some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(store)
                .environmentObject(store.prefs)
                .environmentObject(store.gps)
                .preferredColorScheme(.dark)
                .tint(RadarStyle.signal)
                .task { store.gps.startForeground(); store.start() }
                .onChange(of:scenePhase) { _,phase in
                    if phase == .active {store.gps.startForeground()}
                }
        }
    }
}
struct RootTabView:View {
    @EnvironmentObject var store:RadarStore
    var body:some View {
        TabView(selection:$store.selectedTab) {
            HomeView().tabItem{Label("Home",systemImage:"map")}.tag(RadarTab.live)
            HistoryView().tabItem{Label("History",systemImage:"clock.arrow.circlepath")}.tag(RadarTab.history)
            EarningsView().tabItem{Label("Stats",systemImage:"chart.bar.fill")}.tag(RadarTab.stats)
            SettingsView().tabItem{Label("Settings",systemImage:"slider.horizontal.3")}.tag(RadarTab.settings)
        }
        .toolbarBackground(RadarStyle.surface,for:.tabBar)
        .toolbarBackground(.visible,for:.tabBar)
        .alert("Radar",isPresented:Binding(
            get:{store.error != nil},
            set:{if !$0{store.error=nil}}
        )){
            Button("Dismiss",role:.cancel){store.error=nil}
        } message:{Text(store.error ?? "")}
    }
}
