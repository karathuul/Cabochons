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

    @Environment(\.self) private var environment

    @State private var name = ""
    @State private var color: MateriaColor = .magic
    @State private var target = 4
    /// Mirrors `color` for the system picker, which speaks in `Color`.
    @State private var picked: Color = MateriaColor.magic.core
    @State private var adjusted = false

    init(mode: Mode, onSave: @escaping (Activity) -> Void) {
        self.mode = mode
        self.onSave = onSave
        if case .edit(let activity) = mode {
            _name = State(initialValue: activity.name)
            _color = State(initialValue: activity.color)
            _target = State(initialValue: activity.dailyTarget)
            _picked = State(initialValue: activity.color.core)
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

            VStack(alignment: .leading, spacing: 10) {
                FieldLabel("Jewel")

                HStack(spacing: 14) {
                    ForEach(MateriaColor.presets) { preset in
                        Button {
                            color = preset.color
                            picked = preset.color.core
                        } label: {
                            MateriaOrb(
                                color: preset.color,
                                size: 38,
                                glow: color.matches(preset.color) ? 1.4 : 0.4
                            )
                            .overlay {
                                Circle()
                                    .strokeBorder(
                                        .white.opacity(color.matches(preset.color) ? 0.9 : 0),
                                        lineWidth: 2
                                    )
                                    .padding(-4)
                            }
                            .saturation(color.matches(preset.color) ? 1 : 0.55)
                        }
                        .buttonStyle(OrbButtonStyle())
                        .help(preset.name)
                    }
                }

                HStack(spacing: 12) {
                    ColorPicker("Custom", selection: $picked, supportsOpacity: false)
                        .labelsHidden()

                    VStack(alignment: .leading, spacing: 1) {
                        Text(color.displayName)
                            .font(.system(.caption, design: .rounded, weight: .medium))
                        if adjusted {
                            // Declare that we are overriding the user's color selection.
                            Text("The selected color brightened to read against the socket.")
                                .font(.caption2)
                                .foregroundStyle(Chrome.gold)
                        }
                    }

                    Spacer()
                }
                .onChange(of: picked) { _, new in
                    let rgb = new.resolve(in: environment)
                    let r = Double(rgb.red), g = Double(rgb.green), b = Double(rgb.blue)
                    color = MateriaColor(red: r, green: g, blue: b)
                    adjusted = MateriaColor.wasAdjusted(red: r, green: g, blue: b)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                FieldLabel("Sockets per day")
                Stepper(value: $target, in: 1...40) {
                    Text("\(target)")
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                }
                SlotRail(count: 0, color: color, capacity: target, size: 18, maxSlots: 40)
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

/// Every jewel logged on one day, newest first. Pass an `activityID` to narrow
/// it to a single activity; leave it nil for the combined day.
struct DayEntriesSheet: View {
    @Environment(LogStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let day: Date
    let capacity: Int
    var activityID: UUID? = nil

    var body: some View {
        // Newest first for the list, chronological for the rail.
        let entries = store.entries(on: day, activityID: activityID)
        let fills = entries.reversed().map(\.color)
        let mixed = Set(entries.map(\.activityID)).count > 1

        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.calc.label(for: day))
                        .font(.system(.title3, design: .rounded, weight: .bold))
                    Text(day.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            SlotRail(fills: fills, capacity: capacity, size: 24, maxSlots: 40)

            Divider().overlay(Chrome.steel.opacity(0.3))

            List {
                ForEach(entries) { entry in
                    HStack(spacing: 12) {
                        MateriaOrb(color: entry.color, size: 18, glow: 0.6)

                        Text(entry.timestamp.formatted(date: .omitted, time: .shortened))
                            .font(.system(.body, design: .rounded))
                            .monospacedDigit()

                        if mixed {
                            Text(entry.activityName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()
                    }
                    .contextMenu {
                        Button("Delete", role: .destructive) {
                            store.remove(jewel: entry.id, from: entry.activityID)
                        }
                    }
                }
                .onDelete { offsets in
                    for index in offsets {
                        let entry = entries[index]
                        store.remove(jewel: entry.id, from: entry.activityID)
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
        .frame(width: 400, height: 480)
        #endif
    }
}
