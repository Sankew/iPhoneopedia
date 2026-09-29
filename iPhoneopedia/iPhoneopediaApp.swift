import AppIntents
import CoreSpotlight
import FoundationModels
import SwiftData
import SwiftUI

@main
struct iPhoneopediaApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: OwnedPhone.self)
    }
}

enum AppTab: Hashable { case phones, trends, mine, ask, search }

/// App-wide navigation state, so App Intents (Siri, Spotlight, Visual Intelligence) can open a model.
@Observable final class Navigation {
    static let shared = Navigation()
    var tab = AppTab.phones
    var path: [PhoneModel] = []

    func open(_ model: PhoneModel) {
        tab = .phones
        path = [model]
    }
}

struct RootView: View {
    @Bindable private var navigation = Navigation.shared
    private let store = CatalogStore.shared

    var body: some View {
        TabView(selection: $navigation.tab) {
            Tab("iPhones", systemImage: "iphone", value: .phones) {
                NavigationStack(path: $navigation.path) { PhoneList() }
            }
            Tab("Trends", systemImage: "chart.xyaxis.line", value: .trends) {
                NavigationStack { TrendsView() }
            }
            Tab("My iPhones", systemImage: "person.crop.circle", value: .mine) {
                NavigationStack { MyPhonesView() }
            }
            if SystemLanguageModel.default.isAvailable {
                Tab("Ask", systemImage: "sparkles", value: .ask) {
                    NavigationStack { AskView() }
                }
            }
            Tab(value: .search, role: .search) {
                NavigationStack { SearchView() }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
        .task {
            await index() // bundled catalog: right away, even offline
            await store.refresh()
            await index()
        }
    }

    /// Spotlight entities and Siri shortcut parameters follow the catalog.
    private func index() async {
        try? await CSSearchableIndex.default().indexAppEntities(store.models.map(PhoneModelEntity.init))
        PhoneShortcuts.updateAppShortcutParameters()
    }
}
