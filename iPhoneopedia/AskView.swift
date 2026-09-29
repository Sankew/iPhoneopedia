import FoundationModels
import PhotosUI
import SwiftUI

/// On-device Q&A over the catalog, plus "which iPhone is this?" from a photo.
/// Only shown when `SystemLanguageModel.default.isAvailable` (see RootView).
struct AskView: View {
    struct Exchange: Identifiable {
        let id = UUID()
        let question: String
        let answer: String
        var models: [PhoneModel] = []
    }

    @State private var session = AskView.newSession()
    @State private var question = ""
    @State private var exchanges: [Exchange] = []
    @State private var photo: PhotosPickerItem?
    @State private var busy = false
    @Namespace private var zoom

    var body: some View {
        List {
            ForEach(exchanges) { exchange in
                Section(exchange.question) {
                    Text(exchange.answer)
                    ForEach(exchange.models) { model in
                        NavigationLink(value: model) { PhoneRow(model: model) }
                            .matchedTransitionSource(id: model.id, in: zoom)
                    }
                }
            }
        }
        .overlay {
            if exchanges.isEmpty {
                ContentUnavailableView("Ask about any iPhone", systemImage: "sparkles",
                                       description: Text("Answers come from the iPhoneopedia catalog, on device. Pick a photo to identify a model."))
            }
        }
        .navigationTitle("Ask")
        .phoneDetailDestination(models: exchanges.flatMap(\.models), zoom: zoom)
        .safeAreaInset(edge: .bottom) {
            HStack {
                PhotosPicker(selection: $photo, matching: .images) {
                    Label("Identify from photo", systemImage: "photo")
                }
                .labelStyle(.iconOnly)
                TextField("Which iPhones came in a mini size?", text: $question)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(ask)
                if busy {
                    ProgressView()
                } else {
                    Button("Ask", systemImage: "arrow.up.circle.fill", action: ask)
                        .labelStyle(.iconOnly)
                        .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .disabled(busy)
            .padding()
            .background(.bar)
        }
        .onChange(of: photo) { _, item in
            if let item { identify(item) }
        }
    }

    private static func newSession() -> LanguageModelSession {
        LanguageModelSession(tools: [CatalogTool()]) {
            "You answer questions about iPhone models for the iPhoneopedia app."
            "Always call searchCatalog to look facts up, and answer only from its results. If the catalog doesn't have the answer, say so."
            "Keep answers short."
        }
    }

    private func ask() {
        let prompt = question.trimmingCharacters(in: .whitespaces)
        guard !prompt.isEmpty, !busy else { return }
        question = ""
        busy = true
        Task {
            defer { busy = false }
            do {
                let response = try await session.respond { prompt }
                exchanges.append(Exchange(question: prompt, answer: response.content))
            } catch {
                exchanges.append(Exchange(question: prompt, answer: "Couldn't answer: \(error.localizedDescription)"))
                session = Self.newSession() // context window full or guardrail hit: start fresh
            }
        }
    }

    private func identify(_ item: PhotosPickerItem) {
        photo = nil
        busy = true
        Task {
            defer { busy = false }
            let title = "Which iPhone is this?"
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data)?.cgImage
                else { throw CocoaError(.fileReadCorruptFile) }
                let models = try await PhoneIdentifier.identify(image)
                exchanges.append(Exchange(question: title,
                                          answer: models.isEmpty ? "No catalog model matches this photo." : "Best guess, most likely first:",
                                          models: models))
            } catch {
                exchanges.append(Exchange(question: title, answer: "Couldn't identify it: \(error.localizedDescription)"))
            }
        }
    }
}

#Preview {
    NavigationStack { AskView() }
}
