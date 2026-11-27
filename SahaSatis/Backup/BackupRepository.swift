import Foundation
import SwiftData

/// Tüm verinin toplu okunması ve değiştirilmesi (yedekleme / geri yükleme).
@MainActor
protocol BackupRepository {
    func snapshot() throws -> BackupData
    /// Cihazdaki tüm kayıtları siler ve yedektekileri yazar. Tek `save`; hata olursa hiçbir şey değişmez.
    func replaceAll(with data: BackupData) throws
}

@MainActor
final class SwiftDataBackupRepository: BackupRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Okuma

    func snapshot() throws -> BackupData {
        var data = BackupData()
        data.customers = try context.fetchAll(Customer.self).map { c in
            CustomerRecord(
                id: c.id, createdAt: c.createdAt, updatedAt: c.updatedAt, ownerUserID: c.ownerUserID,
                name: c.name, city: c.city, district: c.district, industrialZone: c.industrialZone,
                sector: c.sector, address: c.address, latitude: c.latitude, longitude: c.longitude,
                statusRaw: c.statusRaw, ratingRaw: c.ratingRaw, ratingNote: c.ratingNote, notes: c.notes
            )
        }.sorted { $0.id.uuidString < $1.id.uuidString }

        data.contacts = try context.fetchAll(Contact.self).map { c in
            ContactRecord(
                id: c.id, createdAt: c.createdAt, updatedAt: c.updatedAt, ownerUserID: c.ownerUserID,
                fullName: c.fullName, title: c.title, phone: c.phone, email: c.email, notes: c.notes,
                isPrimary: c.isPrimary, customerID: c.customer?.id
            )
        }.sorted { $0.id.uuidString < $1.id.uuidString }

        data.visits = try context.fetchAll(Visit.self).map { v in
            VisitRecord(
                id: v.id, createdAt: v.createdAt, updatedAt: v.updatedAt, ownerUserID: v.ownerUserID,
                date: v.date, typeRaw: v.typeRaw, transcript: v.transcript, summary: v.summary,
                topic: v.topic, topics: v.topics, nextStep: v.nextStep, nextStepDate: v.nextStepDate,
                exportedToCRM: v.exportedToCRM, exportedAt: v.exportedAt, customerID: v.customer?.id,
                contactIDs: (v.contacts ?? []).map(\.id).sorted { $0.uuidString < $1.uuidString },
                opportunityID: v.opportunity?.id
            )
        }.sorted { $0.id.uuidString < $1.id.uuidString }

        data.opportunities = try context.fetchAll(Opportunity.self).map { o in
            OpportunityRecord(
                id: o.id, createdAt: o.createdAt, updatedAt: o.updatedAt, ownerUserID: o.ownerUserID,
                title: o.title, details: o.details, estimatedValue: o.estimatedValue,
                currencyRaw: o.currencyRaw, stageRaw: o.stageRaw, expectedCloseDate: o.expectedCloseDate,
                lostReason: o.lostReason, customerID: o.customer?.id
            )
        }.sorted { $0.id.uuidString < $1.id.uuidString }

        data.quotes = try context.fetchAll(Quote.self).map { q in
            QuoteRecord(
                id: q.id, createdAt: q.createdAt, updatedAt: q.updatedAt, ownerUserID: q.ownerUserID,
                quoteNumber: q.quoteNumber, date: q.date, validUntil: q.validUntil,
                currencyRaw: q.currencyRaw, statusRaw: q.statusRaw, followUpDays: q.followUpDays,
                notes: q.notes, lostReason: q.lostReason, sentAt: q.sentAt,
                customerID: q.customer?.id, opportunityID: q.opportunity?.id
            )
        }.sorted { $0.id.uuidString < $1.id.uuidString }

        data.quoteItems = try context.fetchAll(QuoteItem.self).map { i in
            QuoteItemRecord(
                id: i.id, createdAt: i.createdAt, updatedAt: i.updatedAt, ownerUserID: i.ownerUserID,
                catalogNumber: i.catalogNumber, itemDescription: i.itemDescription, quantity: i.quantity,
                unitPrice: i.unitPrice, discountPercent: i.discountPercent, position: i.position,
                quoteID: i.quote?.id
            )
        }.sorted { $0.id.uuidString < $1.id.uuidString }

        data.installedProducts = try context.fetchAll(InstalledProduct.self).map { p in
            InstalledProductRecord(
                id: p.id, createdAt: p.createdAt, updatedAt: p.updatedAt, ownerUserID: p.ownerUserID,
                catalogNumber: p.catalogNumber, productFamily: p.productFamily, quantity: p.quantity,
                lifecycleStatusRaw: p.lifecycleStatusRaw, notes: p.notes, customerID: p.customer?.id
            )
        }.sorted { $0.id.uuidString < $1.id.uuidString }

        data.tasks = try context.fetchAll(FollowUpTask.self).map { t in
            TaskRecord(
                id: t.id, createdAt: t.createdAt, updatedAt: t.updatedAt, ownerUserID: t.ownerUserID,
                title: t.title, dueDate: t.dueDate, isDone: t.isDone, doneAt: t.doneAt,
                sourceRaw: t.sourceRaw, notificationID: t.notificationID, customerID: t.customer?.id,
                quoteID: t.quote?.id, visitID: t.visit?.id, opportunityID: t.opportunity?.id
            )
        }.sorted { $0.id.uuidString < $1.id.uuidString }
        return data
    }

    // MARK: - Geri yükleme

    func replaceAll(with data: BackupData) throws {
        // Silme ile ekleme arasında otomatik kayıt araya girmesin.
        let autosave = context.autosaveEnabled
        context.autosaveEnabled = false
        defer { context.autosaveEnabled = autosave }
        do {
            try deleteEverything()
            insert(data)
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        NotificationCenter.default.post(name: .appDataDidChange, object: nil)
    }

    /// Önce bağlı kayıtlar, sonra sahipleri.
    private func deleteEverything() throws {
        try deleteAll(FollowUpTask.self)
        try deleteAll(QuoteItem.self)
        try deleteAll(Quote.self)
        try deleteAll(Visit.self)
        try deleteAll(Contact.self)
        try deleteAll(InstalledProduct.self)
        try deleteAll(Opportunity.self)
        try deleteAll(Customer.self)
    }

    private func deleteAll<T: PersistentModel>(_ type: T.Type) throws {
        for model in try context.fetchAll(type) {
            context.delete(model)
        }
    }

    /// Yedekte karşılığı olmayan bir ilişki kimliği boş bırakılır.
    private func insert(_ data: BackupData) {
        var customers: [UUID: Customer] = [:]
        for r in data.customers {
            let model = Customer(name: r.name)
            context.insert(model)
            model.id = r.id; model.createdAt = r.createdAt; model.updatedAt = r.updatedAt
            model.ownerUserID = r.ownerUserID
            model.city = r.city; model.district = r.district; model.industrialZone = r.industrialZone
            model.sector = r.sector; model.address = r.address
            model.latitude = r.latitude; model.longitude = r.longitude
            model.statusRaw = r.statusRaw; model.ratingRaw = r.ratingRaw
            model.ratingNote = r.ratingNote; model.notes = r.notes
            customers[r.id] = model
        }

        var contacts: [UUID: Contact] = [:]
        for r in data.contacts {
            let model = Contact(fullName: r.fullName)
            context.insert(model)
            model.id = r.id; model.createdAt = r.createdAt; model.updatedAt = r.updatedAt
            model.ownerUserID = r.ownerUserID
            model.title = r.title; model.phone = r.phone; model.email = r.email
            model.notes = r.notes; model.isPrimary = r.isPrimary
            model.customer = r.customerID.flatMap { customers[$0] }
            contacts[r.id] = model
        }

        var opportunities: [UUID: Opportunity] = [:]
        for r in data.opportunities {
            let model = Opportunity(title: r.title)
            context.insert(model)
            model.id = r.id; model.createdAt = r.createdAt; model.updatedAt = r.updatedAt
            model.ownerUserID = r.ownerUserID
            model.details = r.details; model.estimatedValue = r.estimatedValue
            model.currencyRaw = r.currencyRaw; model.stageRaw = r.stageRaw
            model.expectedCloseDate = r.expectedCloseDate; model.lostReason = r.lostReason
            model.customer = r.customerID.flatMap { customers[$0] }
            opportunities[r.id] = model
        }

        var quotes: [UUID: Quote] = [:]
        for r in data.quotes {
            let model = Quote(quoteNumber: r.quoteNumber)
            context.insert(model)
            model.id = r.id; model.createdAt = r.createdAt; model.updatedAt = r.updatedAt
            model.ownerUserID = r.ownerUserID
            model.date = r.date; model.validUntil = r.validUntil
            model.currencyRaw = r.currencyRaw; model.statusRaw = r.statusRaw
            model.followUpDays = r.followUpDays; model.notes = r.notes
            model.lostReason = r.lostReason; model.sentAt = r.sentAt
            model.customer = r.customerID.flatMap { customers[$0] }
            model.opportunity = r.opportunityID.flatMap { opportunities[$0] }
            quotes[r.id] = model
        }

        for r in data.quoteItems {
            let model = QuoteItem()
            context.insert(model)
            model.id = r.id; model.createdAt = r.createdAt; model.updatedAt = r.updatedAt
            model.ownerUserID = r.ownerUserID
            model.catalogNumber = r.catalogNumber; model.itemDescription = r.itemDescription
            model.quantity = r.quantity; model.unitPrice = r.unitPrice
            model.discountPercent = r.discountPercent; model.position = r.position
            model.quote = r.quoteID.flatMap { quotes[$0] }
        }

        var visits: [UUID: Visit] = [:]
        for r in data.visits {
            let model = Visit()
            context.insert(model)
            model.id = r.id; model.createdAt = r.createdAt; model.updatedAt = r.updatedAt
            model.ownerUserID = r.ownerUserID
            model.date = r.date; model.typeRaw = r.typeRaw
            model.transcript = r.transcript; model.summary = r.summary
            model.topic = r.topic; model.topics = r.topics
            model.nextStep = r.nextStep; model.nextStepDate = r.nextStepDate
            model.exportedToCRM = r.exportedToCRM; model.exportedAt = r.exportedAt
            model.customer = r.customerID.flatMap { customers[$0] }
            model.contacts = r.contactIDs.compactMap { contacts[$0] }
            model.opportunity = r.opportunityID.flatMap { opportunities[$0] }
            visits[r.id] = model
        }

        for r in data.installedProducts {
            let model = InstalledProduct(catalogNumber: r.catalogNumber)
            context.insert(model)
            model.id = r.id; model.createdAt = r.createdAt; model.updatedAt = r.updatedAt
            model.ownerUserID = r.ownerUserID
            model.productFamily = r.productFamily; model.quantity = r.quantity
            model.lifecycleStatusRaw = r.lifecycleStatusRaw; model.notes = r.notes
            model.customer = r.customerID.flatMap { customers[$0] }
        }

        for r in data.tasks {
            let model = FollowUpTask(title: r.title)
            context.insert(model)
            model.id = r.id; model.createdAt = r.createdAt; model.updatedAt = r.updatedAt
            model.ownerUserID = r.ownerUserID
            model.dueDate = r.dueDate; model.isDone = r.isDone; model.doneAt = r.doneAt
            model.sourceRaw = r.sourceRaw; model.notificationID = r.notificationID
            model.customer = r.customerID.flatMap { customers[$0] }
            model.quote = r.quoteID.flatMap { quotes[$0] }
            model.visit = r.visitID.flatMap { visits[$0] }
            model.opportunity = r.opportunityID.flatMap { opportunities[$0] }
        }
    }
}
