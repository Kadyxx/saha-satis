import SwiftUI
import UIKit

enum AppAppearance {
    /// Gezinme çubuğu başlıkları (büyük ve satır içi) `textPrimary` rengini kullanır.
    /// `UIColor(named:)` asset'teki açık/koyu varyantları otomatik izler.
    static func configure() {
        guard let titleColor = UIColor(named: "textPrimary") else { return }

        let standard = UINavigationBarAppearance()
        standard.configureWithDefaultBackground()
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
