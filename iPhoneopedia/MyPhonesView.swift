import SwiftData
import SwiftUI

/// A model the user has owned. CloudKit-ready: every property has a default and nothing is unique.
@Model final class OwnedPhone {
    var modelID: String = ""
    var addedAt: Date = Date.now

    init(modelID: String) {
        self.modelID = modelID
    }
}

struct MyPhonesView: View {
    private let store = CatalogStore.shared
    @Query private var owned: [OwnedPhone]
    @Environment(\.modelContext) private var context
    @Namespace private var zoom

    var body: some View {
        let mine = store.catalog.search("").filter { model in owned.contains { $0.modelID == model.id } }
        List {
            ForEach(mine) { model in
                NavigationLink(value: model) { PhoneRow(model: model) }
                    .matchedTransitionSource(id: model.id, in: zoom)
            }
            .onDelete { offsets in
                let ids = Set(offsets.map { mine[$0].id })
                owned.filter { ids.contains($0.modelID) }.forEach(context.delete)
            }
        }
        .overlay {
            if mine.isEmpty {
                ContentUnavailableView("No iPhones yet", systemImage: "iphone",
                                       description: Text("Open any iPhone and tap \"I owned this\"."))
            }
        }
        .navigationTitle("My iPhones")
        .phoneDetailDestination(models: mine, zoom: zoom)
    }
}

#Preview {
    NavigationStack { MyPhonesView() }
        .modelContainer(for: OwnedPhone.self, inMemory: true)
}
