internal import SwiftUI

// MARK: - Activity editor

struct ActivityEditor: View {
    enum Mode {
        case create
        case edit(Activity)
    }

    @Environment(\.dismiss) private var dismiss

    let mode: Mode
    let onSave: (Activity) -> Void

    @State private var name = ""
    @State private var color: MateriaColor = .magic
    @State private var target = 4

    init(mode: Mode, onSave: @escaping (Activity) -> Void) {
        self.mode = mode
        self.onSave = onSave
        if case .edit(let activity) = mode {
            _name = State(initialValue: activity.name)
            _color = State(initialValue: activity.color)
            _target = State(initialValue: activity.dailyTarget)
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(isEditing ? "Edit activity" : "New activity")
                .font(.system(.title2, design: .rounded, weight: .bold))

            VStack(alignment: .leading, spacing: 6) {
                FieldLabel("Name")
                TextField("Push-ups, sessions, pages…", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .rounded))
            }

            VStack(alignment: .leading, spacing: 8) {
                FieldLabel("Jewel")
                HStack(spacing: 14) {
                    ForEach(MateriaColor.allCases) { option in
                        Button {
                            color = option
                        } label: {
                            MateriaOrb(color: option, size: 38, glow: color == option ? 1.4 : 0.4)
                                .overlay {
                                    Circle()
                                        .strokeBorder(.white.opacity(color == option ? 0.9 : 0), lineWidth: 2)
                                        .padding(-4)
                                }
                                .saturation(color == option ? 1 : 0.55)
                        }
                        .buttonStyle(OrbButtonStyle())
                        .help(option.displayName)
                    }
                }
                Text(color.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                FieldLabel("Sockets per day")
                Stepper(value: $target, in: 1...40) {
                    Text("\(target)")
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                }
                SlotRail(filled: 0, capacity: target, color: color, size: 18, maxSlots: 40)
                Text("Fill every socket to master the day. Extra jewels are kept and marked gold.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(isEditing ? "Save changes" : "Create activity") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Chrome.panel)
        #if os(macOS)
        .frame(width: 420, height: 540)
        #endif
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        switch mode {
        case .create:
            onSave(Activity(name: trimmed, color: color, dailyTarget: target))
        case .edit(let existing):
            var updated = existing
            updated.name = trimmed
            updated.color = color
            updated.dailyTarget = target
            onSave(updated)
        }
        dismiss()
    }
}

private struct FieldLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .tracking(0.8)
            .foregroundStyle(.secondary)
    }
}

// MARK: - Day detail

struct DayDetailSheet: View {
    @Environment(LogStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let activity: Activity
    let summary: DaySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.calc.label(for: summary.day))
                        .font(.system(.title3, design: .rounded, weight: .bold))
                    Text(summary.day.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            SlotRail(
                filled: summary.count,
                capacity: summary.target,
                color: activity.color,
                size: 24
            )

            Divider().overlay(Chrome.steel.opacity(0.3))

            let jewels = store.jewels(on: summary.day, for: activity)

            List {
                ForEach(jewels) { jewel in
                    HStack(spacing: 12) {
                        MateriaOrb(color: activity.color, size: 18, glow: 0.6)
                        Text(jewel.timestamp.formatted(date: .omitted, time: .shortened))
                            .font(.system(.body, design: .rounded))
                            .monospacedDigit()
                        Spacer()
                    }
                    .contextMenu {
                        Button("Delete", role: .destructive) {
                            store.remove(jewel: jewel.id, from: activity.id)
                        }
                    }
                }
                .onDelete { offsets in
                    for index in offsets {
                        store.remove(jewel: jewels[index].id, from: activity.id)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Chrome.panel)
        #if os(macOS)
        .frame(width: 380, height: 460)
        #endif
    }
}
