import AppIntents
import CoreSpotlight

/// A catalog model as the system sees it: Siri, Shortcuts, Spotlight, Visual Intelligence and widget configuration.
nonisolated struct PhoneModelEntity: IndexedEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "iPhone Model"
    static let defaultQuery = PhoneModelQuery()

    let model: PhoneModel
    var id: String { model.id }

    init(_ model: PhoneModel) {
        self.model = model
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(model.name)",
            subtitle: "\(String(model.year)) · \(model.chip)",
            image: .init(systemName: "iphone", isTemplate: true)
        )
    }

    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = defaultAttributeSet
        attributes.contentDescription = model.summary
        attributes.keywords = model.identifiers + [model.chip, String(model.year)]
        return attributes
    }
}

nonisolated struct PhoneModelQuery: EntityStringQuery {
    func entities(for identifiers: [PhoneModelEntity.ID]) async throws -> [PhoneModelEntity] {
        await CatalogStore.shared.models.filter { identifiers.contains($0.id) }.map(PhoneModelEntity.init)
    }

    func entities(matching string: String) async throws -> [PhoneModelEntity] {
        await CatalogStore.shared.catalog.search(string).map(PhoneModelEntity.init)
    }

    func suggestedEntities() async throws -> [PhoneModelEntity] {
        await CatalogStore.shared.catalog.search("").map(PhoneModelEntity.init)
    }
}
