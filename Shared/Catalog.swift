import Foundation
import Observation

// Value types are nonisolated so App Intents and WidgetKit can use them off the main actor.
nonisolated struct Catalog: Codable, Sendable {
    static let supportedSchema = 1

    var schemaVersion: Int
    var generatedAt: Date
    var models: [PhoneModel] // oldest first

    static func decode(_ data: Data) throws -> Catalog {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let string = try decoder.singleValueContainer().decode(String.self)
            // Release dates are calendar days ("2010-06-24"): parse them in the user's time zone
            // so they display as that day everywhere. generatedAt is a full ISO 8601 timestamp.
            let style: Date.ISO8601FormatStyle =
                string.count == 10 ? .init(timeZone: .current).year().month().day() : .iso8601
            return try style.parse(string)
        }
        return try decoder.decode(Catalog.self, from: data)
    }

    /// The catalog shipped inside the app or widget bundle: shown instantly and offline.
    static let bundled: Catalog = {
        guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json"),
              let catalog = try? decode(Data(contentsOf: url))
        else { preconditionFailure("catalog.json missing from bundle or invalid; check target membership of Shared/") }
        return catalog
    }()

    func model(identifier: String) -> PhoneModel? {
        models.first { $0.identifiers.contains(identifier) }
    }

    var newestFirst: [PhoneModel] { models.reversed() }

    /// Newest first. Matches name, chip, identifier or release year; used by search, Siri/Spotlight and Ask.
    func search(_ query: String) -> [PhoneModel] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return newestFirst }
        let hits = newestFirst.filter { model in
            model.name.localizedStandardContains(query) || model.chip.localizedStandardContains(query)
                || model.identifiers.contains { $0.localizedStandardContains(query) } || String(model.year) == query
        }
        // An exact name ("iPhone 16") ranks above its longer siblings ("iPhone 16 Pro Max").
        let exact = hits.filter { $0.name.localizedCaseInsensitiveCompare(query) == .orderedSame }
        return exact + hits.filter { !exact.contains($0) }
    }

    /// Hardware identifier of the device running this code, e.g. "iPhone17,1".
    static var deviceIdentifier: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return simulated }
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }
}

nonisolated struct PhoneModel: Codable, Sendable, Identifiable, Hashable {
    var id: String
    var name: String
    var identifiers: [String]
    var released: Date
    var discontinued: Date?
    var chip: String
    var tagline: String?
    var launchPriceUSD: Int?
    var displayInches: Double?
    var imageURL: URL?
    var colors: [PhoneColor]
    var specs: [SpecSection]
    var about: String?
    var aboutSource: URL?

    var year: Int { Calendar.current.component(.year, from: released) }

    /// Plain-text facts: Spotlight descriptions and the Ask tool's grounding data.
    var summary: String {
        var facts = ["released \(released.formatted(date: .long, time: .omitted))"]
        if let discontinued { facts.append("discontinued \(discontinued.formatted(date: .long, time: .omitted))") }
        if let launchPriceUSD { facts.append("US launch price $\(launchPriceUSD)") }
        facts += specs.flatMap(\.rows).filter { $0.count == 2 }.map { "\($0[0]): \($0[1])" }
        if !colors.isEmpty { facts.append("colors: \(colors.map(\.name).joined(separator: ", "))") }
        return "\(name): " + facts.joined(separator: "; ")
    }
}

extension [PhoneModel] {
    /// First occurrence of each model, order kept: ForEach, paging and transitions need unique ids.
    nonisolated var uniqued: [PhoneModel] {
        var seen = Set<PhoneModel.ID>()
        return filter { seen.insert($0.id).inserted }
    }
}

nonisolated struct PhoneColor: Codable, Sendable, Hashable {
    var name: String
    var hex: String
}

/// Generic label/value sections, so new spec types need no app update.
nonisolated struct SpecSection: Codable, Sendable, Hashable {
    var title: String
    var rows: [[String]] // [label, value]
}

@MainActor @Observable final class CatalogStore {
    static let shared = CatalogStore()
    static let remoteURL = URL(string: "https://raw.githubusercontent.com/Sankew/iPhoneopedia/main/Shared/catalog.json")!

    private(set) var catalog = Catalog.bundled

    var models: [PhoneModel] { catalog.models }
    var current: PhoneModel? { catalog.model(identifier: Catalog.deviceIdentifier) }

    /// Fetches the latest catalog. URLCache handles ETag revalidation; on any failure the current data stays.
    func refresh() async {
        guard let (data, _) = try? await URLSession.shared.data(from: Self.remoteURL),
              let remote = try? Catalog.decode(data),
              remote.schemaVersion <= Catalog.supportedSchema,
              remote.generatedAt >= catalog.generatedAt
        else { return }
        catalog = remote
    }
}
