import SwiftUI
import XCTest
@testable import SahaSatis

/// Dört widget'ı hayali örnek veriyle açık ve koyu modda PNG'ye çevirir. CI bu dosyaları artifact olarak yükler.
/// Çıktı klasörü: SCREENSHOT_DIR ortam değişkeni (CI'da TEST_RUNNER_SCREENSHOT_DIR ile verilir; yoksa geçici klasör).
/// Boyutlar iPhone 14 Pro widget boyutlarıdır.
final class ScreenshotTests: XCTestCase {
    private var outputDirectory: URL {
        if let path = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    }

    private var sample: WidgetSnapshot {
        let now = Date()
        return WidgetSnapshot.make(data: .sample(now: now), at: now, calendar: .current)
    }

    private var emptySnapshot: WidgetSnapshot {
        WidgetSnapshot.make(data: WidgetData(), at: Date(), calendar: .current)
    }

    @MainActor
    private func write<V: View>(_ view: V, name: String, scheme: ColorScheme) throws {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, scheme))
        renderer.scale = 3
        let image = try XCTUnwrap(renderer.uiImage, "Widget görüntüsü üretilemedi: \(name)")
        let data = try XCTUnwrap(image.pngData())

        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        try data.write(to: outputDirectory.appendingPathComponent("\(name).png"))
    }

    /// Ana ekran widget'ı: gerçek widget gibi zemin + kenar boşluğu + yuvarlak köşe.
    @MainActor
    private func renderHome<V: View>(_ content: V, name: String, size: CGSize) throws {
        for scheme in [ColorScheme.light, .dark] {
            let view = content
                .padding(14)
                .frame(width: size.width, height: size.height)
                .background(Theme.background)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            try write(view, name: scheme == .light ? name : "\(name)-dark", scheme: scheme)
        }
    }

    /// Kilit ekranı widget'ı: sistem tek renge boyar; burada yarı saydam zemin üstünde sistem stilleriyle gösterilir.
    @MainActor
    private func renderLock<V: View>(_ content: V, name: String, size: CGSize, circular: Bool) throws {
        for scheme in [ColorScheme.light, .dark] {
            let backdrop = scheme == .dark ? Color(white: 0.08) : Color(white: 0.82)
            let plate = Color.primary.opacity(0.14)
            let view = ZStack {
                backdrop
                if circular {
                    Circle().fill(plate).frame(width: size.width, height: size.height)
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(plate)
                        .frame(width: size.width, height: size.height)
                }
                content.padding(circular ? 0 : 10).frame(width: size.width, height: size.height)
            }
            .frame(width: size.width + 24, height: size.height + 24)
            try write(view, name: scheme == .light ? name : "\(name)-dark", scheme: scheme)
        }
    }

    @MainActor
    func testRenderTodayTasksMedium() throws {
        try renderHome(TodayTasksWidgetView(snapshot: sample), name: "widget-today-medium", size: CGSize(width: 360, height: 169))
        try renderHome(TodayTasksWidgetView(snapshot: emptySnapshot), name: "widget-today-medium-empty", size: CGSize(width: 360, height: 169))
    }

    @MainActor
    func testRenderWeekLarge() throws {
        try renderHome(WeekWidgetView(snapshot: sample), name: "widget-week-large", size: CGSize(width: 360, height: 379))
    }

    @MainActor
    func testRenderNextTaskRectangular() throws {
        try renderLock(NextTaskWidgetView(snapshot: sample), name: "widget-next-rect", size: CGSize(width: 172, height: 76), circular: false)
        try renderLock(NextTaskWidgetView(snapshot: emptySnapshot), name: "widget-next-rect-empty", size: CGSize(width: 172, height: 76), circular: false)
    }

    @MainActor
    func testRenderPendingCountCircular() throws {
        try renderLock(PendingCountWidgetView(snapshot: sample), name: "widget-count-circular", size: CGSize(width: 76, height: 76), circular: true)
    }
}
