internal import SwiftUI
import UniformTypeIdentifiers

/// A read-only `FileDocument` that wraps a snapshot of the store as JSON.
/// We only ever *write* this (fileExporter needs a FileDocument to hand to
/// the system save panel); reading is stubbed so the protocol is satisfied.
///
/// Uses `SharedStorage.makeEncoder()` so the exported file is byte-for-byte
/// the same format the app reads — which means a future "Import" is just
/// `SharedStorage.makeDecoder().decode(LogFile.self, from:)`.
struct MateriaExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    static var writableContentTypes: [UTType] { [.json] }

    let file: LogFile

    init(file: LogFile) {
        self.file = file
    }

    /// Required by the protocol; export never goes through this path.
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        file = try SharedStorage.makeDecoder().decode(LogFile.self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try SharedStorage.makeEncoder().encode(file)
        return FileWrapper(regularFileWithContents: data)
    }
}

/// Drop this anywhere in the settings sheet. It snapshots the *live* store
/// state at tap time (not the on-disk file), so an export taken mid-session
/// always matches what's on screen.
struct ExportDataButton: View {
    private var store: LogStore { .shared }
    
    @State private var document: MateriaExportDocument?
    @State private var isExporting = false
    @State private var exportError: String?

    var body: some View {
        Button {
            document = MateriaExportDocument(file: snapshot())
            isExporting = true
        } label: {
            Label("Export All Data as JSON", systemImage: "square.and.arrow.up")
        }
        .fileExporter(
            isPresented: $isExporting,
            document: document,
            contentType: .json,
            defaultFilename: Self.defaultFilename()
        ) { result in
            if case .failure(let error) = result {
                exportError = error.localizedDescription
            }
        }
        .alert("Export Failed", isPresented: .init(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
    }

    private func snapshot() -> LogFile {
        LogFile(
            dayStartHour: store.dayStartHour,
            activities: store.activities
        )
    }

    /// e.g. "MateriaLog-2026-09-08.json"
    private static func defaultFilename() -> String {
        let stamp = Date.now.formatted(
            .iso8601.year().month().day().dateSeparator(.dash)
        )
        return "MateriaLog-\(stamp)"
    }
}
