import Foundation
import SwiftData

/// Müşterideki kurulu baz (ör. 1756-L71).
@Model
final class InstalledProduct {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var ownerUserID: String = ""

    var catalogNumber: String = ""
    var productFamily: String = ""
    var quantity: Int = 1
    var lifecycleStatusRaw: String = LifecycleStatus.active.rawValue
    var notes: String = ""

    var customer: Customer?

    init(
        catalogNumber: String,
        productFamily: String = "",
        quantity: Int = 1,
        lifecycleStatus: LifecycleStatus = .active,
        notes: String = "",
        ownerUserID: String = ""
    ) {
        self.catalogNumber = catalogNumber
        self.productFamily = productFamily
        self.quantity = quantity
        self.lifecycleStatusRaw = lifecycleStatus.rawValue
        self.notes = notes
        self.ownerUserID = ownerUserID
    }

    var lifecycleStatus: LifecycleStatus {
        get { LifecycleStatus(rawValue: lifecycleStatusRaw) ?? .active }
        set { lifecycleStatusRaw = newValue.rawValue }
    }
}
