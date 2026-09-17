internal import SwiftUI
import UniformTypeIdentifiers

/// A decoded-but-not-yet-applied import. Held in view state so the user
/// gets to see what they're about to overwrite before it happens.
struct ImportPreview {
    let file: LogFile
    let sourceName: String

    var activityCount: Int { file.activities.count }
}

/// Drop this next to `ExportDataButton` in the settings sheet.
///
/// Flow: pick file → decode with the app's own decoder → show a destructive
/// confirmation with counts → on confirm, hand the `LogFile` to the store.
/// Import is a *replace*, not a merge: it restores a backup, full stop.
struct ImportDataButton: View {
    @Environment(LogStore.self) private var store

    @State private var isImporting = false
    @State private var preview: ImportPreview?
    @State private var importError: String?

    var body: some View {
        Button {
            isImporting = true
        } label: {
            Label("Import Data from JSON", systemImage: "square.and.arrow.down")
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handle(result)
        }
        .confirmationDialog(
            "Replace all data?",
            isPresented: .init(
                get: { preview != nil },
                set: { if !$0 { preview = nil } }
            ),
            titleVisibility: .visible,
            presenting: preview
        ) { p in
            Button("Replace with \(p.activityCount) activities", role: .destructive) {
                store.replaceContents(with: p.file)
                preview = nil
            }
            Button("Cancel", role: .cancel) { preview = nil }
        } message: { p in
            Text("\(p.sourceName) contains \(p.activityCount) activities. Your current \(store.activities.count) activities and every jewel logged against them will be overwritten. This can't be undone — export first if you're not sure.")
        }
        .alert("Import Failed", isPresented: .init(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
    }

    // MARK: - Loading

    private func handle(_ result: Result<[URL], Error>) {
        do {
            // fileImporter always hands back an array, even with
            // allowsMultipleSelection: false. Take the first (only) one.
            guard let url = try result.get().first else { return }
            preview = try Self.load(from: url)
        } catch is DecodingError {
            importError = "That file isn't a Cabochon export, or it's from a newer version of the app."
        } catch {
            importError = error.localizedDescription
        }
    }

    /// Reads and decodes a picked file. Files from the document picker live
    /// outside our sandbox, so we have to explicitly claim access first.
    static func load(from url: URL) throws -> ImportPreview {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess { url.stopAccessingSecurityScopedResource() }
        }

        let data = try Data(contentsOf: url)
        let file = try SharedStorage.makeDecoder().decode(LogFile.self, from: data)
        return ImportPreview(file: file, sourceName: url.lastPathComponent)
    }
}
