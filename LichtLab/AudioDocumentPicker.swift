import SwiftUI
import UniformTypeIdentifiers

/// Dateitypen für die Musikauswahl. Bewusst großzügig (inkl. `.data`): Heruntergeladene Dateien haben oft
/// keinen sauberen Audio-Typ und wären sonst in der Dateien-App ausgegraut. Nicht abspielbare Dateien
/// meldet `MusicEngine.load` mit einer verständlichen Fehlermeldung.
enum AudioFileTypes {
    static var all: [UTType] {
        [.audio, .mp3, .mpeg4Audio, .wav, .aiff]
            + ["m4a", "aac", "flac", "caf", "alac"].compactMap { UTType(filenameExtension: $0) }
            + [.data]
    }
}

#if os(iOS)
import UIKit

/// Nativer iOS-Dateiauswahldialog im Kopiermodus: iOS lädt die Datei bei Bedarf aus iCloud
/// und legt eine Kopie in der App ab – damit entfallen Zugriffsprobleme mit Fremd-Ordnern.
struct AudioDocumentPicker: UIViewControllerRepresentable {
    var onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: AudioFileTypes.all, asCopy: true)
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void

        init(onPick: @escaping (URL) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)
        }
    }
}
#endif
