import SwiftUI
import UIKit

struct RootView: View {
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var app: AppState
    @EnvironmentObject var capture: CaptureEngine

    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("今天", systemImage: "waveform") }
            RecordingsView()
                .tabItem { Label("记录", systemImage: "clock.arrow.circlepath") }
            ItemsView()
                .tabItem { Label("整理", systemImage: "checklist") }
            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
        .tint(Theme.accent)
        .onAppear {
            let appearance = UITabBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor(Theme.card)
            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance

            let nav = UINavigationBarAppearance()
            nav.configureWithOpaqueBackground()
            nav.backgroundColor = UIColor(Theme.bg)
            nav.titleTextAttributes = [.foregroundColor: UIColor(Theme.text)]
            nav.largeTitleTextAttributes = [.foregroundColor: UIColor(Theme.text)]
            UINavigationBar.appearance().standardAppearance = nav
            UINavigationBar.appearance().scrollEdgeAppearance = nav
        }
    }
}
