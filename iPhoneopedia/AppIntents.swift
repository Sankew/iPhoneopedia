import AppIntents
import CoreImage
import FoundationModels
import UIKit
#if canImport(VisualIntelligence) // device SDK only; the simulator SDK doesn't ship it
import VisualIntelligence
#endif

/// Opens a model in the app: Siri, Shortcuts, Spotlight and Visual Intelligence results all route here.
struct OpenPhoneIntent: OpenIntent {
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

#if canImport(VisualIntelligence)
/// Visual Intelligence: point the camera at a phone, get matching catalog models.
nonisolated struct PhoneVisualSearch: IntentValueQuery {
    func values(for input: SemanticContentDescriptor) async throws -> [PhoneModelEntity] {
        // Labels are generic ("phone"), never model names: use them only to skip non-phones,
        // then let the on-device model look at the pixels.
        guard input.labels.contains(where: { $0.localizedCaseInsensitiveContains("phone") }),
              SystemLanguageModel.default.isAvailable,
              let buffer = input.pixelBuffer
        else { return [] }
        // Render inside the closure: the underlying CVPixelBuffer must not escape it.
        let cgImage = buffer.withUnsafeBuffer { pixels in
            let image = CIImage(cvPixelBuffer: pixels)
            return CIContext().createCGImage(image, from: image.extent)
        }
        guard let cgImage else { return [] }
        return try await PhoneIdentifier.identify(UIImage(cgImage: cgImage)).map(PhoneModelEntity.init)
    }
}
#endif
