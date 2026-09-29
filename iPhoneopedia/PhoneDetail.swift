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
        .sensoryFeedback(.selection, trigger: selection)
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
        ScrollView {
            VStack(spacing: 16) {
                PhoneImage(url: model.imageURL)
                    .padding(.horizontal) // inside the measured frame, so the parallax rests at zero
                    .frame(maxWidth: .infinity)
                    .frame(height: 280)
                    // Parallax while paging: the photo lags behind its page and shrinks as it leaves.
                    .visualEffect { content, proxy in
                        let x = proxy.frame(in: .scrollView(axis: .horizontal)).minX
                        let progress = min(abs(x) / max(proxy.size.width, 1), 1)
                        return content
                            .offset(x: -x * 0.4)
                            .scaleEffect(1 - progress * 0.25)
                            .opacity(1 - progress * 0.6)
                    }

                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.name).font(.largeTitle.bold())
                        if let tagline = model.tagline {
                            Text(tagline).foregroundStyle(.secondary)
                        }
                    }
                    FactPills(model: model)

                    GlassCard("Overview") {
                        SpecRow(label: model.released > .now ? "Available" : "Released",
                                value: model.released.formatted(date: .long, time: .omitted))
                        if let discontinued = model.discontinued {
                            SpecRow(label: "Discontinued", value: discontinued.formatted(date: .long, time: .omitted))
                        }
                        if !model.colors.isEmpty {
                            ColorSwatches(colors: model.colors)
                        }
                    }

                    ForEach(model.specs, id: \.title) { section in
                        GlassCard(section.title) {
                            ForEach(section.rows, id: \.self) { row in
                                SpecRow(label: row.first ?? "", value: row.last ?? "")
                            }
                        }
                    }

                    if let about = model.about {
                        GlassCard("About") {
                            Text(about)
                            if let source = model.aboutSource {
                                Link(source.host()?.contains("wikipedia") == true ? "Source: Wikipedia (CC BY-SA 4.0)" : "Source",
                                     destination: source)
                                    .font(.footnote)
                            }
                        }
                    }
                }
                .padding([.horizontal, .bottom])
            }
        }
        .background { Backdrop(colors: model.colors) }
    }
}

/// The phone's own finishes, washed out behind the glass: every page has its color.
private struct Backdrop: View {
    let colors: [PhoneColor]

    var body: some View {
        let tints = colors.isEmpty ? [Color.accentColor] : colors.prefix(3).map(\.color)
        LinearGradient(colors: tints.map { $0.opacity(0.35) } + [Color(.systemGroupedBackground)],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}

/// Year, chip, price and screen size as glass capsules; they stack when Dynamic Type makes them too wide.
private struct FactPills: View {
    let model: PhoneModel

    var body: some View {
        var facts = [String(model.year), model.chip]
        if let price = model.launchPriceUSD {
            facts.append(price.formatted(.currency(code: "USD").precision(.fractionLength(0))))
        }
        if let inches = model.displayInches {
            facts.append("\(inches.formatted())″")
        }
        let pills = ForEach(facts, id: \.self) { fact in
            Text(fact)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassEffect(in: .capsule)
        }
        return GlassEffectContainer(spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { pills }
                VStack(alignment: .leading, spacing: 8) { pills }
            }
        }
    }
}

private struct GlassCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(in: .rect(cornerRadius: 24))
    }
}

private struct SpecRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(value).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }
}

struct ColorSwatches: View {
    let colors: [PhoneColor]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 6) {
                    ForEach(colors, id: \.name) { color in
                        Circle()
                            .fill(color.color)
                            .padding(4)
                            .frame(width: 30, height: 30)
                            .glassEffect(in: .circle)
                    }
                }
            }
            Text(colors.map(\.name).formatted()).font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Colors: \(colors.map(\.name).formatted())")
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
        let isOwned = !records.isEmpty
        Button {
            if isOwned {
                records.forEach(context.delete)
            } else {
                context.insert(OwnedPhone(modelID: model.id))
            }
        } label: {
            Label(isOwned ? "Owned" : "I owned this", systemImage: isOwned ? "checkmark.circle.fill" : "plus.circle")
                .contentTransition(.symbolEffect(.replace))
        }
        .symbolEffect(.bounce, value: isOwned)
        .sensoryFeedback(.success, trigger: isOwned) { _, owned in owned }
    }
}

#Preview {
    let models = Catalog.bundled.models
    NavigationStack { PhoneDetail(models: models, selection: models.last?.id) }
        .modelContainer(for: OwnedPhone.self, inMemory: true)
}
