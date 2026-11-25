import SwiftUI
import UIKit

enum AppAppearance {
    /// Gezinme çubuğu başlıkları (büyük ve satır içi) `textPrimary` rengini kullanır.
    /// `UIColor(named:)` asset'teki açık/koyu varyantları otomatik izler.
    static func configure() {
        guard let titleColor = UIColor(named: "textPrimary") else { return }

        let standard = UINavigationBarAppearance()
        // Opak ve "background" renginde: kaydırınca sistemin bulanık beyaz/gri zemini çıkmaz (tüm ekranlar ve sheet'ler).
        standard.configureWithOpaqueBackground()
        standard.backgroundColor = UIColor(named: "background")
        standard.shadowColor = .clear
        standard.titleTextAttributes = [.foregroundColor: titleColor]
        standard.largeTitleTextAttributes = [.foregroundColor: titleColor]

        let scrollEdge = UINavigationBarAppearance()
        scrollEdge.configureWithTransparentBackground()
        scrollEdge.titleTextAttributes = [.foregroundColor: titleColor]
        scrollEdge.largeTitleTextAttributes = [.foregroundColor: titleColor]

        let bar = UINavigationBar.appearance()
        bar.standardAppearance = standard
        bar.compactAppearance = standard
        bar.scrollEdgeAppearance = scrollEdge
    }
}
