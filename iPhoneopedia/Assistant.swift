import FoundationModels
import UIKit

/// Which Apple Intelligence model answers: the server model behind Siri, or the on-device one.
nonisolated enum Assistant: Sendable {
    case cloud, onDevice

    /// Set to true once Apple grants the managed entitlement `com.apple.developer.private-cloud-compute`
    /// and it's in the app's entitlements. Without it the cloud model still reports itself available,
    /// but its first response is a fatal error rather than a thrown one, so no fallback can catch it.
    private static let hasCloudEntitlement = false
    private static let cloudModel = PrivateCloudComputeLanguageModel()

    /// Private Cloud Compute when this app may use it (entitlement, Apple Intelligence device, quota left), else on device.
    static var preferred: Assistant {
        hasCloudEntitlement && cloudModel.isAvailable && !cloudModel.quotaUsage.isLimitReached ? .cloud : .onDevice
    }

    static var isAvailable: Bool { (hasCloudEntitlement && cloudModel.isAvailable) || SystemLanguageModel.default.isAvailable }

    var label: String { self == .cloud ? "Private Cloud Compute" : "On device" }
    var systemImage: String { self == .cloud ? "lock.icloud" : "iphone" }

    func session(tools: [any Tool] = [], instructions: String) -> LanguageModelSession {
        switch self {
        case .cloud: LanguageModelSession(model: Self.cloudModel, tools: tools, instructions: instructions)
        case .onDevice: LanguageModelSession(model: SystemLanguageModel.default, tools: tools, instructions: instructions)
        }
    }
}

/// Grounds the Ask tab in the catalog: the model looks facts up here instead of recalling them.
nonisolated struct CatalogTool: Tool {
    let name = "searchCatalog"
    let description = "Looks up iPhone models in the iPhoneopedia catalog and returns their facts. Search by model name, chip, identifier or release year."

    @Generable nonisolated struct Arguments {
        @Guide(description: "Short search terms: a keyword like \"mini\", \"Plus\" or \"Max\", a chip like \"A17 Pro\", a year like \"2016\", or a model name taken from the question")
        var terms: [String]
    }

    @concurrent func call(arguments: Arguments) async throws -> String {
        let catalog = await CatalogStore.shared.catalog
        let matches = arguments.terms.flatMap { catalog.search($0).prefix(4) }.uniqued
        // Say which terms missed: a bare "no matches" makes the model conclude the catalog lacks the whole topic.
        let misses = arguments.terms.filter { catalog.search($0).isEmpty }
            .map { "No model matches \"\($0)\"; try a shorter keyword." }
        // Capped at 8 summaries to stay inside the on-device model's small context window.
        return (matches.prefix(8).map(\.summary) + misses).joined(separator: "\n")
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
        let assistant = Assistant.preferred
        do {
            return try await identify(image, with: assistant)
        } catch where assistant == .cloud {
            // Server unreachable, over quota or not entitled: the on-device model can still look.
            return try await identify(image, with: .onDevice)
        }
    }

    private static func identify(_ image: UIImage, with assistant: Assistant) async throws -> [PhoneModel] {
        let catalog = await CatalogStore.shared.catalog
        let names = catalog.models.map(\.name).joined(separator: ", ")
        let session = assistant.session(instructions: "You identify iPhone models in photos. Answer only with model names from this list: \(names).")
        let guess = try await session.respond(generating: Guess.self) {
            "Which iPhone model is in this photo? Consider the camera layout, notch or Dynamic Island, edges and color."
            Attachment(image)
        }
        return guess.content.models.compactMap { name in
            catalog.models.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
        }.uniqued
    }
}
