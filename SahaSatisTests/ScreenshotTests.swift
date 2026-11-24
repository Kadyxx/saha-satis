import SwiftUI
import XCTest

/// Widget görünümlerini açık ve koyu modda PNG'ye çevirir. CI bu dosyaları artifact olarak yükler.
/// Çıktı klasörü: TEST_RUNNER_SCREENSHOT_DIR ortam değişkeni (yoksa geçici klasör).
final class ScreenshotTests: XCTestCase {
    private var outputDirectory: URL {
        if let path = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    }

    @MainActor
    private func render(name: String, size: CGSize, scheme: ColorScheme) throws {
        let view = HelloWidgetView(date: Date())
            .frame(width: size.width, height: size.height)
            .background(Theme.background)
            .environment(\.colorScheme, scheme)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3

        let image = try XCTUnwrap(renderer.uiImage, "Widget görüntüsü üretilemedi")
        let data = try XCTUnwrap(image.pngData())

        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        try data.write(to: outputDirectory.appendingPathComponent("\(name).png"))
    }

    @MainActor
    func testRenderSmallWidget() throws {
        try render(name: "widget-small", size: CGSize(width: 158, height: 158), scheme: .light)
        try render(name: "widget-small-dark", size: CGSize(width: 158, height: 158), scheme: .dark)
    }

    @MainActor
    func testRenderMediumWidget() throws {
        try render(name: "widget-medium", size: CGSize(width: 338, height: 158), scheme: .light)
        try render(name: "widget-medium-dark", size: CGSize(width: 338, height: 158), scheme: .dark)
    }
}
