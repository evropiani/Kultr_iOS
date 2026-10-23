import SwiftUI
import UIKit
import UniformTypeIdentifiers

/**
 * The Files app's picker, straight from UIKit. SwiftUI's fileImporter and
 * fileExporter only show from some places (one of each on a view, not from
 * inside every sheet or settings page), and when they don't, nothing happens
 * at all. This presents UIDocumentPickerViewController over whatever is on
 * screen, from anywhere.
 */
@MainActor
enum FilePicker {
    /** Pick one file or folder of [types]. [copy]: get a private copy rather than access to the original. */
    static func open(_ types: [UTType], copy: Bool = false, done: @escaping (URL) -> Void) {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: copy)
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        present(picker) { urls in
            if let url = urls.first { done(url) }
        }
    }

    /** Save [file] (a temporary file) wherever the user chooses; [done] is told whether it was saved. */
    static func export(_ file: URL, done: @escaping (Bool) -> Void) {
        let picker = UIDocumentPickerViewController(forExporting: [file], asCopy: true)
        picker.shouldShowFileExtensions = true
        present(picker) { urls in
            try? FileManager.default.removeItem(at: file)
            done(!urls.isEmpty)
        }
    }

    // ----------------------------------------------------------- presenting --

    /** The picker's delegate, kept alive while it is on screen (UIKit holds it weakly). */
    private static var coordinator: Coordinator?

    @MainActor
    private final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let finish: ([URL]) -> Void

        init(finish: @escaping ([URL]) -> Void) {
            self.finish = finish
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            finish(urls)
            FilePicker.coordinator = nil
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            finish([])
            FilePicker.coordinator = nil
        }
    }

    private static func present(_ picker: UIDocumentPickerViewController, finish: @escaping ([URL]) -> Void) {
        guard let host = topViewController() else {
            AppGraph.shared.messages.error("The Files picker could not be opened.")
            return
        }
        let coordinator = Coordinator(finish: finish)
        Self.coordinator = coordinator
        picker.delegate = coordinator
        host.present(picker, animated: true)
    }

    /** The view controller on top: the one showing now, above any sheets. */
    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let active = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        let window = active?.windows.first { $0.isKeyWindow } ?? active?.windows.first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }
}
