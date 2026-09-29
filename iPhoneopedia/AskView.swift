import FoundationModels
import PhotosUI
import SwiftUI

/// Apple Intelligence Q&A over the catalog, plus "which iPhone is this?" from a photo.
/// Only shown when `Assistant.isAvailable` (see RootView).
struct AskView: View {
    struct Exchange: Identifiable {
        let id = UUID()
        let question: String
        var photo: Image?
        var answer = ""
        var assistant: Assistant?
        var models: [PhoneModel] = []
    }

    private static let instructions = """
        You answer questions about iPhone models for the iPhoneopedia app. \
        Always call searchCatalog to look facts up, and answer only from its results. \
        If the catalog doesn't have the answer, say so. Keep answers short and use exact model names.
        """
    private static let suggestions = [
        "Which iPhones came in a mini size?",
        "What chip is in the iPhone 15 Pro?",
        "Compare iPhone 4 and iPhone 4S",
        "How much did the original iPhone cost?",
    ]

    private let store = CatalogStore.shared
    @State private var assistant = Assistant.preferred
    @State private var session: LanguageModelSession?
    @State private var question = ""
    @State private var exchanges: [Exchange] = []
    @State private var photo: PhotosPickerItem?
    @State private var busy = false
    @Namespace private var zoom
    @Namespace private var glass

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 24) {
                ForEach(exchanges) { exchange in
                    ExchangeView(exchange: exchange)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding()
        }
        .defaultScrollAnchor(.bottom)
        .defaultScrollAnchor(.bottom, for: .sizeChanges) // follow the answer as it streams in
        .scrollDismissesKeyboard(.interactively)
        .background {
            LinearGradient(colors: [.blue.opacity(0.10), .purple.opacity(0.08), .clear], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        }
        .overlay {
            if exchanges.isEmpty { emptyState.transition(.opacity) }
        }
        .navigationTitle("Ask")
        .toolbar {
            if !exchanges.isEmpty {
                Button("New Chat", systemImage: "square.and.pencil") {
                    withAnimation(.smooth) { exchanges = [] }
                    session = nil
                }
                .disabled(busy)
            }
        }
        .phoneDetailDestination(models: exchanges.flatMap(\.models), zoom: zoom)
        .safeAreaInset(edge: .bottom) { inputBar }
        .sensoryFeedback(.impact(weight: .light), trigger: exchanges.count)
        .onChange(of: photo) { _, item in
            if let item { identify(item) }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 24) {
            ContentUnavailableView {
                Label("Ask about any iPhone", systemImage: "apple.intelligence")
                    .symbolEffect(.breathe)
            } description: {
                Text("Answers come from the iPhoneopedia catalog through Apple Intelligence. Pick a photo to identify a model.")
            }
            .fixedSize(horizontal: false, vertical: true)
            GlassEffectContainer(spacing: 10) {
                VStack(spacing: 10) {
                    ForEach(Self.suggestions, id: \.self) { suggestion in
                        Button(suggestion) { ask(suggestion) }
                            .buttonStyle(.glass)
                    }
                }
            }
        }
        .padding()
    }

    private var inputBar: some View {
        let canSend = !question.trimmingCharacters(in: .whitespaces).isEmpty
        return GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                PhotosPicker(selection: $photo, matching: .images) {
                    Image(systemName: "camera.viewfinder")
                        .font(.title3)
                        .frame(width: 48, height: 48)
                }
                .glassEffect(.regular.interactive(), in: .circle)
                .disabled(busy)
                .accessibilityLabel("Identify from photo")

                // Stays enabled while busy so the keyboard doesn't drop; ask() ignores submits until done.
                TextField("Ask about any iPhone", text: $question)
                    .submitLabel(.send)
                    .onSubmit { ask() }
                    .padding(.horizontal, 18)
                    .frame(height: 48)
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .overlay { IntelligenceGlow(active: busy) }
                    .glassEffectID("field", in: glass)

                if canSend || busy {
                    Button { ask() } label: {
                        Image(systemName: busy ? "ellipsis" : "arrow.up")
                            .font(.title3.bold())
                            .contentTransition(.symbolEffect(.replace))
                            .symbolEffect(.variableColor.iterative, options: .repeating, isActive: busy)
                            .frame(width: 48, height: 48)
                    }
                    .foregroundStyle(.white)
                    .glassEffect(.regular.tint(.accentColor).interactive(), in: .circle)
                    .glassEffectID("send", in: glass)
                    .disabled(busy)
                    .accessibilityLabel(busy ? "Thinking" : "Ask")
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .animation(.bouncy, value: canSend || busy)
    }

    private func ask(_ text: String? = nil) {
        let prompt = (text ?? question).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !busy else { return }
        question = ""
        busy = true
        withAnimation(.smooth) { exchanges.append(Exchange(question: prompt)) }
        let index = exchanges.count - 1
        Task {
            defer { withAnimation(.smooth) { busy = false } }
            do {
                try await stream(prompt, into: index)
            } catch {
                // Retry once on a fresh session. A full context just needs that; any other cloud failure
                // (offline, over quota, not entitled) means staying on device from here on.
                if case .contextSizeExceeded? = error as? LanguageModelError {} else { assistant = .onDevice }
                session = nil
                do {
                    try await stream(prompt, into: index)
                } catch {
                    exchanges[index].answer = "Couldn't answer: \(error.localizedDescription)"
                    session = nil
                    return
                }
            }
            let mentioned = store.catalog.models(mentionedIn: exchanges[index].answer)
            withAnimation(.smooth) { exchanges[index].models = Array(mentioned.prefix(6)) }
        }
    }

    private func stream(_ prompt: String, into index: Int) async throws {
        let session = session ?? assistant.session(tools: [CatalogTool()], instructions: Self.instructions)
        self.session = session
        exchanges[index].assistant = assistant
        exchanges[index].answer = ""
        for try await snapshot in session.streamResponse(to: prompt) {
            withAnimation(.smooth) { exchanges[index].answer = snapshot.content }
        }
    }

    private func identify(_ item: PhotosPickerItem) {
        photo = nil
        busy = true
        withAnimation(.smooth) { exchanges.append(Exchange(question: "Which iPhone is this?", assistant: .preferred)) }
        let index = exchanges.count - 1
        Task {
            defer { withAnimation(.smooth) { busy = false } }
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data)
                else { throw CocoaError(.fileReadCorruptFile) }
                withAnimation(.smooth) { exchanges[index].photo = Image(uiImage: image) }
                let models = try await PhoneIdentifier.identify(image)
                withAnimation(.smooth) {
                    exchanges[index].answer = models.isEmpty ? "No catalog model matches this photo." : "Best guess, most likely first:"
                    exchanges[index].models = models
                }
            } catch {
                exchanges[index].answer = "Couldn't identify it: \(error.localizedDescription)"
            }
        }
    }
}

/// A question bubble and its glass answer card, with links to the models it names.
private struct ExchangeView: View {
    let exchange: AskView.Exchange

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .trailing, spacing: 8) {
                if let photo = exchange.photo {
                    photo
                        .resizable()
                        .scaledToFill()
                        .frame(width: 140, height: 140)
                        .clipShape(.rect(cornerRadius: 20))
                        .accessibilityLabel("Your photo")
                }
                Text(exchange.question)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .glassEffect(.regular.tint(.accentColor), in: .rect(cornerRadius: 20))
            }
            .frame(maxWidth: .infinity, alignment: .trailing)

            VStack(alignment: .leading, spacing: 12) {
                if exchange.answer.isEmpty {
                    Image(systemName: "ellipsis")
                        .font(.title2)
                        .symbolEffect(.variableColor.iterative, options: .repeating)
                        .accessibilityLabel("Thinking")
                } else {
                    Text(Self.markdown(exchange.answer))
                        .textSelection(.enabled)
                }
                // No matchedTransitionSource here: a model can appear in several answers.
                ForEach(exchange.models) { model in
                    NavigationLink(value: model) { PhoneRow(model: model) }
                        .buttonStyle(.plain)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
                if let assistant = exchange.assistant {
                    Label(assistant.label, systemImage: assistant.systemImage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(in: .rect(cornerRadius: 24))
        }
    }

    /// The server model likes **bold** and lists; render inline Markdown, keep line breaks.
    private static func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}

/// Apple Intelligence–style glow that circles the field while the model works.
private struct IntelligenceGlow: View {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: !active || reduceMotion)) { context in
            let angle = Angle.degrees(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3) * 120)
            Capsule()
                .strokeBorder(AngularGradient(colors: [.blue, .purple, .pink, .orange, .yellow, .cyan, .blue],
                                              center: .center, angle: angle),
                              lineWidth: 2.5)
                .blur(radius: 2)
        }
        .opacity(active ? 1 : 0)
        .animation(.easeInOut(duration: 0.4), value: active)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview {
    NavigationStack { AskView() }
}
