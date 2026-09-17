internal import SwiftUI

/// Hosts the export/import buttons. Opened from the toolbar menu rather than
/// living inside it, because file pickers won't present from a `Menu` item.
struct DataSheet: View {
    @Environment(LogStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your data")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                    Text("\(store.activities.count) activities")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            Divider().overlay(Chrome.steel.opacity(0.3))

            VStack(alignment: .leading, spacing: 12) {
                ExportDataButton()
                Text("Saves everything as a single JSON file you can back up or move to another device.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                ImportDataButton()
                Text("Restores from an exported file. Replaces everything currently in the app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Chrome.panel)
        #if os(macOS)
        .frame(width: 400, height: 280)
        #endif
    }
}
