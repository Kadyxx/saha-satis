import Foundation
import SwiftData

@Model
final class QuoteItem {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var ownerUserID: String = ""

    var catalogNumber: String = ""
    /// Açıklama (`description` adı NSObject ile çakıştığı için `itemDescription`).
    var itemDescription: String = ""
    var quantity: Int = 1
    var unitPrice: Double = 0
    var discountPercent: Double = 0

    var quote: Quote?

    init(
        catalogNumber: String = "",
        itemDescription: String = "",
        quantity: Int = 1,
        unitPrice: Double = 0,
        discountPercent: Double = 0,
        ownerUserID: String = ""
    ) {
        self.catalogNumber = catalogNumber
        self.itemDescription = itemDescription
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.discountPercent = discountPercent
        self.ownerUserID = ownerUserID
    }

    /// Hesaplanan: adet × birim fiyat × (1 − iskonto%).
    var lineTotal: Double {
        Double(quantity) * unitPrice * (1 - discountPercent / 100)
    }
}
