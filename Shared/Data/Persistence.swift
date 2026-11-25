import Foundation
import SwiftData

enum Persistence {
    static let schema = Schema([
        Customer.self,
        Contact.self,
        Visit.self,
        Opportunity.self,
        Quote.self,
        QuoteItem.self,
        InstalledProduct.self,
        FollowUpTask.self
    ])

    /// Veri deposunu açar.
    /// - iCloud (CloudKit) senkronu bilinçli olarak kapalıdır (`cloudKitDatabase: .none`);
    ///   giriş ve iCloud ayrı bir adımda açılacak.
    /// - `groupContainer: .automatic`: imzalı derlemede App Group konteynerini kullanır
    ///   (widget'ın aynı depoyu okuyabilmesi için); imzasız simülatör derlemesinde varsayılan konuma düşer.
    @MainActor
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}

extension ModelContext {
    /// Bir modelin tüm kayıtlarını getirir. Veri hacmi küçük olduğu için filtreleme/sıralama
    /// çoğunlukla bellekte yapılır (Predicate'lerin derleme zamanı karmaşıklığından kaçınmak için).
    func fetchAll<T: PersistentModel>(_ type: T.Type) throws -> [T] {
        try fetch(FetchDescriptor<T>())
    }
}

extension Notification.Name {
    /// Repository'ler her başarılı kayıttan sonra bunu yayınlar; hatırlatma motoru ve Bugün ekranı yenilenir.
    static let appDataDidChange = Notification.Name("SahaSatis.appDataDidChange")
}

extension ModelContext {
    /// `save()` + "veri değişti" bildirimi. Repository'ler `save()` yerine bunu kullanır.
    func saveAndNotify() throws {
        try save()
        NotificationCenter.default.post(name: .appDataDidChange, object: nil)
    }
}
