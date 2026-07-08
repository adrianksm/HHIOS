import SwiftUI

enum AppTab: String { case today, schedule, hauliers, more }

struct MainTabView: View {
    @Environment(Session.self) private var session
    @State private var store = JobStore()
    @State private var selection: AppTab = AppTab(rawValue: UserDefaults.standard.string(forKey: "startTab") ?? "") ?? .today

    var body: some View {
        TabView(selection: $selection) {
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.max") }
                .tag(AppTab.today)

            ScheduleView()
                .tabItem { Label("Schedule", systemImage: "calendar") }
                .tag(AppTab.schedule)

            HaulierListView()
                .tabItem { Label("Hauliers", systemImage: "person.2") }
                .tag(AppTab.hauliers)

            MoreView()
                .tabItem { Label("More", systemImage: "ellipsis.circle") }
                .tag(AppTab.more)
        }
        .environment(store)
        .task {
            store.configure(session: session)
            await store.loadIfNeeded()
        }
    }
}
