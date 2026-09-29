import SwiftData
import SwiftUI

/// One page per model; swipe sideways to move between models.
struct PhoneDetail: View {
    let models: [PhoneModel]
    @State var selection: PhoneModel.ID?

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(models) { model in
                    PhonePage(model: model)
                        .containerRelativeFrame(.horizontal)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $selection)
        .scrollIndicators(.hidden)
        .navigationTitle(current?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let current {
                ToolbarItem(placement: .topBarPinnedTrailing) { OwnedToggle(model: current) }
                ToolbarItem { ShareLink(item: current.summary) }
            }
        }
    }

    private var current: PhoneModel? { models.first { $0.id == selection } }
}

struct PhonePage: View {
    let model: PhoneModel

    var body: some View {
        List {
            Section {
                PhoneImage(url: model.imageURL)
                    .frame(maxWidth: .infinity)
                    .frame(height: 240)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.name).font(.largeTitle.bold())
                    if let tagline = model.tagline {
                        Text(tagline).foregroundStyle(.secondary)
                    }
                }
            }

            Section("Overview") {
                LabeledContent(model.released > .now ? "Available" : "Released",
                               value: model.released.formatted(date: .long, time: .omitted))
                if let discontinued = model.discontinued {
                    LabeledContent("Discontinued", value: discontinued.formatted(date: .long, time: .omitted))
                }
                if let price = model.launchPriceUSD {
                    LabeledContent("US launch price", value: price, format: .currency(code: "USD").precision(.fractionLength(0)))
                }
                if !model.colors.isEmpty {
                    ColorSwatches(colors: model.colors)
                }
            }

            ForEach(model.specs, id: \.title) { section in
                Section(section.title) {
                    ForEach(section.rows, id: \.self) { row in
                        LabeledContent(row.first ?? "", value: row.last ?? "")
                    }
                }
            }

            if let about = model.about {
                Section("About") {
                    Text(about)
                    if let source = model.aboutSource {
                        Link(source.host()?.contains("wikipedia") == true ? "Source: Wikipedia (CC BY-SA 4.0)" : "Source",
                             destination: source)
                            .font(.footnote)
                    }
                }
            }
        }
    }
}

struct ColorSwatches: View {
    let colors: [PhoneColor]

    var body: some View {
        LabeledContent("Colors") {
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 4) {
                    ForEach(colors, id: \.name) { color in
                        Circle().fill(color.color).stroke(.separator).frame(width: 18, height: 18)
                    }
                }
                Text(colors.map(\.name).formatted()).font(.caption)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

extension PhoneColor {
    var color: Color {
        let rgb = UInt32(hex, radix: 16) ?? 0
        return Color(red: Double(rgb >> 16 & 0xFF) / 255, green: Double(rgb >> 8 & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255)
    }
}

/// Adds or removes the model from "My iPhones".
struct OwnedToggle: View {
    let model: PhoneModel
    @Environment(\.modelContext) private var context
    @Query private var owned: [OwnedPhone] // a handful of rows; filtering in memory avoids #Predicate isolation issues

    var body: some View {
        let records = owned.filter { $0.modelID == model.id }
        Button(records.isEmpty ? "I owned this" : "Owned", systemImage: records.isEmpty ? "plus.circle" : "checkmark.circle.fill") {
            if records.isEmpty {
                context.insert(OwnedPhone(modelID: model.id))
            } else {
                records.forEach(context.delete)
            }
        }
    }
}

#Preview {
    let models = Catalog.bundled.models
    NavigationStack { PhoneDetail(models: models, selection: models.last?.id) }
        .modelContainer(for: OwnedPhone.self, inMemory: true)
}
