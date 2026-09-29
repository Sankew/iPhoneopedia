import FoundationModels
import UIKit

/// Grounds the Ask tab in the catalog: the model looks facts up here instead of recalling them.
nonisolated struct CatalogTool: Tool {
    let name = "searchCatalog"
    let description = "Looks up iPhone models in the iPhoneopedia catalog and returns their facts. Search by model name, chip, identifier or release year."

    @Generable nonisolated struct Arguments {
        @Guide(description: "One search term per model, chip or year, e.g. [\"iPhone 13 mini\", \"iPhone 16e\"], [\"A17 Pro\"] or [\"2016\"]")
        var terms: [String]
    }

    @concurrent func call(arguments: Arguments) async throws -> String {
        let catalog = await CatalogStore.shared.catalog
        let matches = arguments.terms.flatMap { catalog.search($0).prefix(4) }.uniqued
        // ponytail: capped at 8 summaries to stay inside the on-device model's small context window.
        return matches.isEmpty ? "No matching iPhone models in the catalog." : matches.prefix(8).map(\.summary).joined(separator: "\n")
    }
}

/// Best guess at which catalog models a photo shows. Used by the Ask tab and Visual Intelligence.
nonisolated enum PhoneIdentifier {
    @Generable nonisolated struct Guess {
        @Guide(description: "Exact model names from the provided list, most likely first. Empty if no iPhone is visible.", .maximumCount(3))
        var models: [String]
    }

    /// Takes a UIImage so camera photos keep their EXIF orientation.
    static func identify(_ image: UIImage) async throws -> [PhoneModel] {
        let catalog = await CatalogStore.shared.catalog
        let names = catalog.models.map(\.name).joined(separator: ", ")
        let session = LanguageModelSession {
            "You identify iPhone models in photos. Answer only with model names from this list: \(names)."
        }
        let guess = try await session.respond(generating: Guess.self) {
            "Which iPhone model is in this photo? Consider the camera layout, notch or Dynamic Island, edges and color."
            Attachment(image)
        }
        return guess.content.models.compactMap { name in
            catalog.models.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
        }.uniqued
    }
}
