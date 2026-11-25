import Foundation
import Observation

enum PipelineSegment: Hashable {
    case opportunities
    case quotes
}

/// Fırsatlar listesinin durumu: aşama grupları ve hangilerinin açık olduğu. Veriye yalnızca repository'ler üzerinden erişir.
@MainActor
@Observable
final class PipelineModel {
    /// Kazanıldı ve Kaybedildi grupları varsayılan olarak kapalıdır (SPEC isteği).
    static let defaultExpanded: Set<OpportunityStage> = [.lead, .qualified, .quoted, .negotiation]

    private let repositories: Repositories

    private(set) var groups: [StageGroup] = []
    var expanded: Set<OpportunityStage> = PipelineModel.defaultExpanded
    var errorMessage: String?

    init(repositories: Repositories) {
        self.repositories = repositories
    }

    func reload() {
        do {
            groups = PipelineGrouping.groups(from: try repositories.opportunities.fetchAll())
        } catch {
            errorMessage = "Fırsatlar yüklenemedi: \(error.localizedDescription)"
        }
    }

    func isExpanded(_ stage: OpportunityStage) -> Bool { expanded.contains(stage) }

    func toggle(_ stage: OpportunityStage) {
        if expanded.contains(stage) {
            expanded.remove(stage)
        } else {
            expanded.insert(stage)
        }
    }
}
