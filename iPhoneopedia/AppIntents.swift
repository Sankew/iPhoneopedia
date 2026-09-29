import AppIntents
import CoreImage
import FoundationModels
import UIKit
import VisualIntelligence

/// Opens a model in the app: Siri, Shortcuts, Spotlight and Visual Intelligence results all route here.
nonisolated struct OpenPhoneIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open iPhone Model"

    @Parameter(title: "iPhone Model", requestValueDialog: "Which iPhone?")
    var target: PhoneModelEntity

    @MainActor func perform() async throws -> some IntentResult {
        Navigation.shared.open(target.model)
        return .result()
    }
}

nonisolated struct PhoneShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenPhoneIntent(),
            phrases: ["Open \(\.$target) in \(.applicationName)", "Show \(\.$target) in \(.applicationName)"],
            shortTitle: "Open iPhone Model",
            systemImageName: "iphone"
        )
    }
}

/// Visual Intelligence: point the camera at a phone, get matching catalog models.
nonisolated struct PhoneVisualSearch: IntentValueQuery {
    func values(for input: SemanticContentDescriptor) async throws -> [PhoneModelEntity] {
        // Labels are generic ("phone"), never model names: use them only to skip non-phones,
        // then let the on-device model look at the pixels.
        guard input.labels.contains(where: { $0.localizedCaseInsensitiveContains("phone") }),
              SystemLanguageModel.default.isAvailable,
              let buffer = input.pixelBuffer
        else { return [] }
        let image = CIImage(cvPixelBuffer: buffer)
        guard let cgImage = CIContext().createCGImage(image, from: image.extent) else { return [] }
        return try await PhoneIdentifier.identify(UIImage(cgImage: cgImage)).map(PhoneModelEntity.init)
    }
}
