import Foundation
import SwiftData

@Model
final class Contact {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var ownerUserID: String = ""

    var fullName: String = ""
    var title: String = ""
    var phone: String = ""
    var email: String = ""
    var notes: String = ""
    var isPrimary: Bool = false

    var customer: Customer?
    /// Ziyaret ↔ kişi çoka-çok ilişkisi (ters taraf: `Visit.contacts`).
    var visits: [Visit]?

    init(
        fullName: String,
        title: String = "",
        phone: String = "",
        email: String = "",
        notes: String = "",
        isPrimary: Bool = false,
        ownerUserID: String = ""
    ) {
        self.fullName = fullName
        self.title = title
        self.phone = phone
        self.email = email
        self.notes = notes
        self.isPrimary = isPrimary
        self.ownerUserID = ownerUserID
    }
}
