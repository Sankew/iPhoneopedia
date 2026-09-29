import Foundation
import Testing
@testable import iPhoneopedia

/// Checks the committed Shared/catalog.json against the app's real Codable types.
struct CatalogTests {
    let catalog: Catalog

    init() throws {
        let url = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../Shared/catalog.json").standardized
        catalog = try Catalog.decode(Data(contentsOf: url))
    }

    @Test func decodesCurrentSchema() {
        #expect(catalog.schemaVersion == Catalog.supportedSchema)
        #expect(catalog.models.count >= 55)
    }

    @Test func idsAndIdentifiersAreUnique() {
        #expect(Set(catalog.models.map(\.id)).count == catalog.models.count)
        let identifiers = catalog.models.flatMap(\.identifiers)
        #expect(Set(identifiers).count == identifiers.count)
    }

    @Test func everyModelIsUsable() {
        for model in catalog.models {
            #expect(!model.identifiers.isEmpty, "\(model.name)")
            #expect(model.imageURL.map { $0.scheme == "https" } ?? true, "\(model.name)")
            #expect(model.specs.allSatisfy { $0.rows.allSatisfy { $0.count == 2 } }, "\(model.name)")
        }
    }

    @Test(arguments: [("iPhone3,2", "iPhone 4"), ("iPhone12,8", "iPhone SE (2nd generation)"), ("iPhone19,4", "iPhone Duo")])
    func identifierLookup(identifier: String, name: String) {
        #expect(catalog.model(identifier: identifier)?.name == name)
    }

    @Test(arguments: [("mini", "iPhone 13 mini"), ("A4", "iPhone 4"), ("iphone3,3", "iPhone 4"), ("2007", "iPhone")])
    func searchMatchesNameChipIdentifierAndYear(query: String, expected: String) {
        #expect(catalog.search(query).map(\.name).contains(expected))
    }

    @Test func exactNameRanksFirstAndDuplicatesCollapse() {
        let results = catalog.search("iPhone 16")
        #expect(results.first?.name == "iPhone 16")
        #expect((results + results).uniqued.map(\.id) == results.map(\.id))
    }

    @Test func searchIsNewestFirstAndSummaryHasFacts() throws {
        #expect(catalog.search("").first?.released == catalog.models.last?.released)
        let summary = try #require(catalog.model(identifier: "iPhone3,1")).summary
        #expect(summary.hasPrefix("iPhone 4: released"))
        #expect(summary.contains("Chip: A4") && summary.contains("US launch price $199"))
    }

    @Test func mentionedModelsPreferLongestNameAndKeepOrder() {
        let text = "The iPhone 4s followed the iPhone 4. Later came the iPhone SE (2nd generation), then more iPhones."
        #expect(catalog.models(mentionedIn: text).map(\.name) == ["iPhone 4S", "iPhone 4", "iPhone SE (2nd generation)"])
    }

    @Test func releaseDatesAreCalendarDaysInLocalTime() throws {
        let iPhone4 = try #require(catalog.model(identifier: "iPhone3,1"))
        let day = Calendar.current.dateComponents([.year, .month, .day], from: iPhone4.released)
        #expect((day.year, day.month, day.day) == (2010, 6, 24))
    }
}
