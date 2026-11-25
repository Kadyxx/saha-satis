import MessageUI
import SwiftUI

/// `MFMailComposeViewController` sarmalayıcısı. Mail hesabı yoksa `MFMailComposeViewController.canSendMail()`
/// false döner; çağıran taraf bu durumda `ShareSheet` açar.
struct MailComposeView: UIViewControllerRepresentable {
    let subject: String
    let body: String
    let recipients: [String]
    let onFinish: (MFMailComposeResult) -> Void

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setSubject(subject)
        controller.setMessageBody(body, isHTML: false)
        controller.setToRecipients(recipients)
        return controller
    }

    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: (MFMailComposeResult) -> Void

        init(onFinish: @escaping (MFMailComposeResult) -> Void) {
            self.onFinish = onFinish
        }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            onFinish(result)
        }
    }
}

/// Paylaşım metni ve konusu: Mail gibi uygulamalar konuyu da alır.
final class ReportActivityItem: NSObject, UIActivityItemSource {
    let text: String
    let subject: String

    init(text: String, subject: String) {
        self.text = text
        self.subject = subject
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any { text }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? { text }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        subjectForActivityType activityType: UIActivity.ActivityType?
    ) -> String { subject }
}

/// Mail hesabı yoksa açılan sistem paylaşım menüsü.
struct ShareSheet: UIViewControllerRepresentable {
    let text: String
    let subject: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [ReportActivityItem(text: text, subject: subject)], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
