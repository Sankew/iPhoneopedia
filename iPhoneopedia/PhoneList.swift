import SwiftUI

struct PhoneList: View {
    private let store = CatalogStore.shared
    @Namespace private var zoom

    var body: some View {
        List {
            if let current = store.current {
                Section("Your iPhone") {
                    NavigationLink(value: current) { PhoneRow(model: current) }
                }
            }
            ForEach(years, id: \.year) { section in
                Section(String(section.year)) {
                    ForEach(section.models) { model in
                        NavigationLink(value: model) { PhoneRow(model: model) }
                            .matchedTransitionSource(id: model.id, in: zoom)
                    }
                }
            }
        }
        .navigationTitle("iPhoneopedia")
        .refreshable { await store.refresh() }
        .phoneDetailDestination(models: store.catalog.newestFirst, zoom: zoom)
    }

    /// Newest year first; newest model first within a year.
    private var years: [(year: Int, models: [PhoneModel])] {
        Dictionary(grouping: store.models, by: \.year)
            .map { (year: $0.key, models: Array($0.value.reversed())) }
            .sorted { $0.year > $1.year }
    }
}

struct SearchView: View {
    private let store = CatalogStore.shared
    @State private var query = ""
    @Namespace private var zoom

    var body: some View {
        let results = store.catalog.search(query)
        List(results) { model in
            NavigationLink(value: model) { PhoneRow(model: model) }
                .matchedTransitionSource(id: model.id, in: zoom)
        }
        .overlay {
            if results.isEmpty { ContentUnavailableView.search(text: query) }
        }
        .navigationTitle("Search")
        .searchable(text: $query, prompt: "Name, chip, identifier or year")
        .phoneDetailDestination(models: results, zoom: zoom)
    }
}

struct PhoneRow: View {
    let model: PhoneModel

    var body: some View {
        HStack(spacing: 12) {
            PhoneImage(url: model.imageURL)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading) {
                Text(model.name).font(.headline)
                Text("\(String(model.year)) · \(model.chip)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Apple's product photo; decorative because the model name is always shown next to it.
struct PhoneImage: View {
    let url: URL?

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFit()
        } placeholder: {
            Image(systemName: "iphone")
                .resizable()
                .scaledToFit()
                .padding(4)
                .foregroundStyle(.tertiary)
        }
        .accessibilityHidden(true)
    }
}

extension View {
    /// Pushes the paging detail for a tapped model, zooming from its row.
    func phoneDetailDestination(models: [PhoneModel], zoom: Namespace.ID) -> some View {
        navigationDestination(for: PhoneModel.self) { model in
            PhoneDetail(models: models.contains { $0.id == model.id } ? models : [model], selection: model.id)
                .navigationTransition(.zoom(sourceID: model.id, in: zoom))
        }
    }
}

#Preview {
    NavigationStack { PhoneList() }
}
