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
    @State private var cadenceCount = 1
    @State private var cadenceUnit: Cadence.Unit = .day
    
    enum Schedule: String, CaseIterable, Identifiable {
        case scheduled = "On a schedule", whenever = "Whenever"
        var id: String { rawValue }
    }
    @State private var schedule: Schedule = .scheduled

    private var cadence: Cadence {
        Cadence(count: cadenceCount, unit: cadenceUnit)
    }

    /// What actually gets written. The stepper always holds a real number;
    /// "whenever" is the one place a target of 0 is produced.
    private var savedTarget: Int {
        schedule == .whenever ? 0 : target
    }

    /// Open-ended activities are bucketed by day. Leaving a weekly cadence on
    /// one would drop it into the "This period" list with nothing to say.
    private var savedCadence: Cadence {
        schedule == .whenever ? .daily : cadence
    }

    private var sentence: String {
        let times = target == 1 ? "Once" : "\(target) times"
        return cadence.isDaily ? "\(times) a day" : "\(times) every \(cadence.phrase)"
    }
    /// Mirrors `color` for the system picker, which speaks in `Color`.
    @State private var picked: Color = MateriaColor.magic.core
    @State private var adjusted = false

    init(mode: Mode, onSave: @escaping (Activity) -> Void) {
        self.mode = mode
        self.onSave = onSave
        if case .edit(let activity) = mode {
            _name = State(initialValue: activity.name)
            _color = State(initialValue: activity.color)
            // The stepper's range starts at 1, so an open-ended activity's 0
            // is expressed through `schedule` and the stepper keeps a sane seed.
            _schedule = State(initialValue: activity.isOpenEnded ? .whenever : .scheduled)
            _target = State(initialValue: max(1, activity.target))
            _cadenceCount = State(initialValue: activity.cadence.count)
            _cadenceUnit = State(initialValue: activity.cadence.unit)
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
                            // Say so rather than silently overriding the pick.
                            Text("brightened to read against the socket")
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

            VStack(alignment: .leading, spacing: 10) {
                FieldLabel("How often")

                Picker("", selection: $schedule) {
                    ForEach(Schedule.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if schedule == .scheduled {
                    HStack(spacing: 10) {
                        Stepper(value: $target, in: 1...40) {
                            Text("\(target)")
                                .font(.system(.body, design: .rounded, weight: .semibold))
                                .monospacedDigit()
                                .frame(minWidth: 26, alignment: .leading)
                        }
                        .fixedSize()

                        Text("every")
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(.secondary)

                        Stepper(value: $cadenceCount, in: 1...30) {
                            Text("\(cadenceCount)")
                                .font(.system(.body, design: .rounded, weight: .semibold))
                                .monospacedDigit()
                                .frame(minWidth: 26, alignment: .leading)
                        }
                        .fixedSize()

                        Picker("", selection: $cadenceUnit) {
                            ForEach(Cadence.Unit.allCases) { unit in
                                Text(unit.label(count: cadenceCount)).tag(unit)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    Text(sentence)
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(color.core)

                    SlotRail(count: 0, color: color, capacity: target, size: 18, maxSlots: 40)

                    Text("Fill every socket to master the \(cadence.phrase). Extra jewels are kept and marked gold.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No sockets, no target. Every tap is just a jewel.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

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
            onSave(Activity(name: trimmed, color: color, target: savedTarget, cadence: savedCadence))
        case .edit(let existing):
            var updated = existing
            updated.name = trimmed
            updated.color = color
            updated.target = savedTarget
            updated.cadence = savedCadence
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

/// Every jewel logged on one calendar day, newest first. Used by the combined
/// day view, where the day is the unit regardless of anyone's cadence.
struct DayEntriesSheet: View {
    @Environment(LogStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let day: Date
    let capacity: Int

    var body: some View {
        let entries = store.entries(on: day)
        EntryList(
            title: store.calc.label(for: day),
            subtitle: day.formatted(.dateTime.weekday(.wide).month(.wide).day().year()),
            entries: entries,
            capacity: capacity,
            dismiss: { dismiss() }
        )
    }
}

// MARK: - Period detail

/// Every jewel one activity logged in one turn of its cadence.
struct PeriodEntriesSheet: View {
    @Environment(LogStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let period: PeriodSummary
    let title: String
    let activityID: UUID

    var body: some View {
        let entries = store.entries(in: period, activityID: activityID)
        EntryList(
            title: title,
            subtitle: span,
            entries: entries,
            capacity: period.target,
            dismiss: { dismiss() }
        )
    }

    private var span: String {
        let last = store.calc.offsetting(period.end, by: -1)
        if store.calc.daysBetween(period.start, last) == 0 {
            return period.start.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
        }
        return period.start.formatted(.dateTime.month(.abbreviated).day())
            + " – " + last.formatted(.dateTime.month(.abbreviated).day().year())
    }
}

// MARK: - Shared list

private struct EntryList: View {
    @Environment(LogStore.self) private var store
    @State private var editing: LoggedJewel?

    let title: String
    let subtitle: String
    let entries: [LoggedJewel]
    let capacity: Int
    let dismiss: () -> Void

    var body: some View {
        let fills = entries.reversed().map(\.rail)
        let mixed = Set(entries.map(\.activityID)).count > 1

        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(.title3, design: .rounded, weight: .bold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done", action: dismiss)
                    .keyboardShortcut(.defaultAction)
            }

            SlotRail(fills: fills, capacity: capacity, size: 24, maxSlots: 40)

            Divider().overlay(Chrome.steel.opacity(0.3))

            List {
                ForEach(entries) { entry in
                    Button {
                        editing = entry
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            MateriaOrb(
                                color: entry.color,
                                size: 18,
                                glint: NoteRules.glint(for: entry.note),
                                glow: 0.6
                            )
                            .padding(.top, 1)

                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 8) {
                                    Text(entry.timestamp.formatted(date: .omitted, time: .shortened))
                                        .font(.system(.body, design: .rounded))
                                        .monospacedDigit()

                                    if mixed {
                                        Text(entry.activityName)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }

                                    Text(entry.timestamp.formatted(.dateTime.month(.abbreviated).day()))
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }

                                if let note = entry.note, entry.hasNote {
                                    Text(note)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                } else {
                                    Text("Add a note")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }

                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
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
        .sheet(item: $editing) { entry in
            NoteEditor(entry: entry)
        }
    }
}

// MARK: - Note editor

/// Deliberately not in the tap path. One-tap logging is the point of the app,
/// so a note is attached after the fact rather than gating the press behind a
/// keyboard.
struct NoteEditor: View {
    @Environment(LogStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let entry: LoggedJewel
    @State private var text: String
    @FocusState private var focused: Bool

    init(entry: LoggedJewel) {
        self.entry = entry
        _text = State(initialValue: entry.note ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                // Flares as you type. This is the whole lure: watch the gem
                // catch more light the more you actually say.
                MateriaOrb(color: entry.color, size: 30, glint: NoteRules.glint(for: text))
                    .animation(.easeOut(duration: 0.25), value: NoteRules.glint(for: text))

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.activityName)
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                    Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            TextEditor(text: $text)
                .font(.system(.body, design: .rounded))
                .scrollContentBackground(.hidden)
                .padding(10)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Chrome.socketVoid.opacity(0.6))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Chrome.steel.opacity(0.4), lineWidth: 1)
                        }
                }
                .frame(minHeight: 140)
                .focused($focused)
                .onChange(of: text) { _, new in
                    // Editor-side stop. The store clamps too, so this is only
                    // about not letting you type past the line.
                    if new.count > NoteRules.limit {
                        text = String(new.prefix(NoteRules.limit))
                    }
                }

            HStack(alignment: .firstTextBaseline) {
                Text("Anything worth remembering about this one. The more you write, the brighter it flares.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 12)

                Text("\(text.count)/\(NoteRules.limit)")
                    .font(.system(.caption2, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(text.count >= NoteRules.limit
                                     ? AnyShapeStyle(Chrome.gold)
                                     : AnyShapeStyle(.tertiary))
            }

            HStack {
                if entry.hasNote {
                    Button("Remove note", role: .destructive) {
                        store.setNote("", for: entry.id, in: entry.activityID)
                        dismiss()
                    }
                }

                Spacer()

                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button("Save") {
                    store.setNote(text, for: entry.id, in: entry.activityID)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Chrome.panel)
        #if os(macOS)
        .frame(width: 420, height: 380)
        #endif
        .onAppear { focused = true }
    }
}
