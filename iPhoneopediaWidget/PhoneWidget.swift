import AppIntents
import SwiftUI
import WidgetKit

nonisolated struct PhoneWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "iPhone"
    static let description = IntentDescription("Shows an iPhone model and how long ago it came out.")

    /// Empty means "this iPhone".
    @Parameter(title: "iPhone Model")
    var model: PhoneModelEntity?
}

nonisolated struct PhoneEntry: TimelineEntry {
    let date: Date
    let model: PhoneModel?
    let isThisDevice: Bool
}

nonisolated struct PhoneTimeline: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> PhoneEntry {
        PhoneEntry(date: .now, model: Catalog.bundled.models.last, isThisDevice: false)
    }

    func snapshot(for configuration: PhoneWidgetIntent, in context: Context) async -> PhoneEntry {
        await entry(for: configuration)
    }

    func timeline(for configuration: PhoneWidgetIntent, in context: Context) async -> Timeline<PhoneEntry> {
        await CatalogStore.shared.refresh()
        return Timeline(entries: [await entry(for: configuration)], policy: .after(.now.addingTimeInterval(24 * 60 * 60)))
    }

    /// The configured model, else this device, else the newest released iPhone.
    private func entry(for configuration: PhoneWidgetIntent) async -> PhoneEntry {
        let catalog = await CatalogStore.shared.catalog
        if let id = configuration.model?.id, let model = catalog.models.first(where: { $0.id == id }) {
            return PhoneEntry(date: .now, model: model, isThisDevice: false)
        }
        let device = catalog.model(identifier: Catalog.deviceIdentifier)
        let newest = catalog.models.last { $0.released <= .now } ?? catalog.models.last
        return PhoneEntry(date: .now, model: device ?? newest, isThisDevice: device != nil)
    }
}

struct PhoneWidgetView: View {
    let entry: PhoneEntry

    var body: some View {
        if let model = entry.model {
            VStack(alignment: .leading, spacing: 2) {
                Image(systemName: "iphone").font(.title2).foregroundStyle(.tint)
                Spacer()
                Text(entry.isThisDevice ? "Your iPhone" : model.chip)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(model.name)
                    .font(.headline)
                    .minimumScaleFactor(0.7)
                Text(model.released > entry.date
                     ? "Coming \(model.released.formatted(date: .abbreviated, time: .omitted))"
                     : model.released.formatted(.relative(presentation: .named)))
                    .font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ContentUnavailableView("No catalog", systemImage: "iphone")
        }
    }
}

@main
struct PhoneWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "PhoneWidget", intent: PhoneWidgetIntent.self, provider: PhoneTimeline()) { entry in
            PhoneWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("iPhone")
        .description("An iPhone model and how long ago it came out.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
