import Foundation

/// Kurulu baz formunun düzenlenen değerleri (ekrandan bağımsız, birim testle denenir).
struct InstalledProductDraft: Equatable {
    var catalogNumber = ""
    var family = ""
    var quantity = 1
    var lifecycle: LifecycleStatus = .active
    var notes = ""

    init() {}

    init(product: InstalledProduct) {
        catalogNumber = product.catalogNumber
        family = product.productFamily
        quantity = max(product.quantity, 1)
        lifecycle = product.lifecycleStatus
        notes = product.notes
    }

    var trimmedCatalogNumber: String { catalogNumber.trimmingCharacters(in: .whitespacesAndNewlines) }

    var canSave: Bool { !trimmedCatalogNumber.isEmpty && quantity >= 1 }

    /// Aile seçilince yaşam döngüsü ailenin varsayılanına çekilir (sonra elle değiştirilebilir).
    /// Listede olmayan (serbest yazılmış) aile yaşam döngüsünü değiştirmez.
    mutating func selectFamily(_ name: String, families: [ProductFamily]) {
        family = name
        if let found = ProductFamily.find(name, in: families) {
            lifecycle = found.lifecycle
        }
    }

    func apply(to product: InstalledProduct) {
        product.catalogNumber = trimmedCatalogNumber
        product.productFamily = family.trimmingCharacters(in: .whitespacesAndNewlines)
        product.quantity = max(quantity, 1)
        product.lifecycleStatus = lifecycle
        product.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func makeProduct() -> InstalledProduct {
        let product = InstalledProduct(catalogNumber: trimmedCatalogNumber)
        apply(to: product)
        return product
    }
}

/// "Fırsat aç": kurulu baz satırından migrasyon fırsatı için hazır başlık ve açıklama.
struct MigrationOpportunityPrefill: Equatable {
    var title: String
    var details: String

    init(product: InstalledProduct) {
        let family = product.productFamily.trimmingCharacters(in: .whitespacesAndNewlines)
        let catalog = product.catalogNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        title = "\(family.isEmpty ? catalog : family) migrasyonu"

        var parts = ["Ürün: \(catalog)"]
        if !family.isEmpty { parts[0] += " (\(family))" }
        parts.append("Adet: \(product.quantity)")
        parts.append("Yaşam döngüsü: \(product.lifecycleStatus.title)")
        details = parts.joined(separator: "\n")
        let note = product.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty { details += "\nNot: \(note)" }
    }
}
