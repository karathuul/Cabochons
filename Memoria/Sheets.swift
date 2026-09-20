// MARK: - Sheets
// Every modal the app presents: the activity editor, the tag editor and its
// symbol picker, the day and period jewel lists, and the note editor.

internal import SwiftUI

// MARK: - Activity editor

struct ActivityEditor: View {
    enum Mode {
        case create
        case edit(Activity)
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(LogStore.self) private var store

    let mode: Mode
    let onSave: (Activity) -> Void

    @Environment(\.self) private var environment

    /// Which tags this activity belongs to. Membership lives on the tag, so
    /// this is seeded from the store on appear (the environment isn't
    /// available in `init`) and written back through `store.setTags`.
    @State private var tagIDs: Set<Tag.ID> = []
    @State private var seededTags = false

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

            if !store.tags.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    FieldLabel("Tags")
                    TagChips(tags: store.tags, selected: $tagIDs)
                    Text("Every jewel here also counts toward each tag it's in.")
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
        .frame(width: 420, height: store.tags.isEmpty ? 540 : 620)
        #endif
        .onAppear {
            guard !seededTags else { return }
            seededTags = true
            if case .edit(let activity) = mode {
                tagIDs = Set(store.tags(containing: activity.id).map(\.id))
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        // `onSave` puts the activity in the store; membership is written
        // second because `setTags` needs the activity to exist to mean anything.
        switch mode {
        case .create:
            let activity = Activity(name: trimmed, color: color, target: savedTarget, cadence: savedCadence)
            onSave(activity)
            store.setTags(tagIDs, for: activity.id)
        case .edit(let existing):
            var updated = existing
            updated.name = trimmed
            updated.color = color
            updated.target = savedTarget
            updated.cadence = savedCadence
            onSave(updated)
            store.setTags(tagIDs, for: existing.id)
        }
        dismiss()
    }
}

/// Toggleable pills, one per tag. Shared by the activity editor (pick tags for
/// this activity) — the tag editor goes the other way and picks activities.
private struct TagChips: View {
    let tags: [Tag]
    @Binding var selected: Set<Tag.ID>

    var body: some View {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(tags) { tag in
                let on = selected.contains(tag.id)
                Button {
                    if on { selected.remove(tag.id) } else { selected.insert(tag.id) }
                } label: {
                    HStack(spacing: 5) {
                        // The tag's own symbol until it's on. Fixed width, so
                        // swapping to the checkmark doesn't reflow the row.
                        Image(systemName: on ? "checkmark" : tag.symbol)
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 14)
                        Text(tag.name)
                            .font(.system(.caption, design: .rounded, weight: .medium))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background {
                        Capsule().fill(on ? Chrome.steel.opacity(0.55) : Chrome.socketVoid.opacity(0.6))
                    }
                    .overlay {
                        Capsule().strokeBorder(on ? Chrome.steelHi : Chrome.steel.opacity(0.4), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tag.name)
                .accessibilityValue(on ? "in" : "out")
            }
        }
    }
}

// MARK: - Tag editor

/// Name, symbol, cadence, target, and which activities feed it. The rail is
/// live: toggle a member in and its jewels from this period appear, so you're
/// configuring a rail you can already see.
struct TagEditor: View {
    enum Mode {
        case create
        case edit(Tag)
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(LogStore.self) private var store

    let mode: Mode
    let onSave: (Tag) -> Void

    @State private var name = ""
    @State private var symbol = Tag.defaultSymbol
    @State private var choosingSymbol = false
    @FocusState private var nameFocused: Bool
    @State private var target = 5
    @State private var cadenceCount = 1
    @State private var cadenceUnit: Cadence.Unit = .week
    @State private var selected: Set<Activity.ID> = []

    init(mode: Mode, onSave: @escaping (Tag) -> Void) {
        self.mode = mode
        self.onSave = onSave
        if case .edit(let tag) = mode {
            _name = State(initialValue: tag.name)
            _symbol = State(initialValue: tag.symbol)
            _target = State(initialValue: max(1, tag.target))
            _cadenceCount = State(initialValue: tag.cadence.count)
            _cadenceUnit = State(initialValue: tag.cadence.unit)
            _selected = State(initialValue: Set(tag.activityIDs))
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var cadence: Cadence {
        Cadence(count: cadenceCount, unit: cadenceUnit)
    }

    /// Sidebar order, so the rail's legend is stable regardless of the order
    /// things were ticked.
    private var orderedMembers: [UUID] {
        store.activities.map(\.id).filter(selected.contains)
    }

    /// What the tag would be if saved right now. Drives the preview rail.
    private var draft: Tag {
        switch mode {
        case .create:
            return Tag(name: name, symbol: symbol, target: target, cadence: cadence, activityIDs: orderedMembers)
        case .edit(let existing):
            var updated = existing
            updated.name = name
            updated.symbol = symbol
            updated.target = target
            updated.cadence = cadence
            updated.activityIDs = orderedMembers
            return updated
        }
    }

    private var sentence: String {
        let times = target == 1 ? "Once" : "\(target) times"
        return cadence.isDaily ? "\(times) a day" : "\(times) every \(cadence.phrase)"
    }

    var body: some View {
        // Only the verbs stay put. With the symbol grid open, the rest is
        // taller than a phone screen, and a sheet that can't scroll is a
        // sheet with fields you can't reach.
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(isEditing ? "Edit tag" : "New tag")
                        .font(.system(.title2, design: .rounded, weight: .bold))

                    nameAndSymbol
                    schedule
                    members
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollDismissesKeyboard(.interactively)

            Divider().overlay(Chrome.steel.opacity(0.3))

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(isEditing ? "Save changes" : "Create tag") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Chrome.panel)
        #if os(macOS)
        .frame(width: 420, height: 600)
        #endif
    }

    // MARK: Sections

    /// Symbol and name together, because they're the same question: what this
    /// tag is called and what it looks like. The grid opens underneath rather
    /// than in a popover — a popover anchored this high on a phone lands over
    /// the sheet with nowhere to go.
    private var nameAndSymbol: some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldLabel("Name")

            HStack(spacing: 8) {
                SymbolWell(symbol: symbol, isOpen: choosingSymbol) {
                    // Keyboard down first, so the grid opens into the space it
                    // was covering.
                    nameFocused = false
                    withAnimation(.snappy(duration: 0.25)) {
                        choosingSymbol.toggle()
                    }
                }

                TextField("Exercise, social, creative…", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .rounded))
                    .focused($nameFocused)
            }

            if choosingSymbol {
                TagSymbolGrid(selection: $symbol) {
                    withAnimation(.snappy(duration: 0.25)) {
                        choosingSymbol = false
                    }
                }
                .padding(.top, 6)
            }
        }
    }

    private var schedule: some View {
        let preview = store.progress(for: draft)

        return VStack(alignment: .leading, spacing: 10) {
            FieldLabel("How often")

            HStack(spacing: 10) {
                Stepper(value: $target, in: 1...60) {
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
                .foregroundStyle(.secondary)

            SlotRail(fills: preview.fills, capacity: target, size: 18, maxSlots: 40)
                .animation(.spring(response: 0.35, dampingFraction: 0.6), value: preview.fills)

            Text(selected.isEmpty
                 ? "Pick activities below. Their jewels fill these sockets together."
                 : "\(preview.count) so far this \(cadence.phrase). Any member's jewel counts.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Plain rows, not a `List`: a list inside a scroll view has no height of
    /// its own and fights its parent for the gesture.
    private var members: some View {
        VStack(alignment: .leading, spacing: 10) {
            FieldLabel("Activities")

            if store.activities.isEmpty {
                Text("No activities to tag yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(store.activities) { activity in
                        memberRow(activity)

                        if activity.id != store.activities.last?.id {
                            Divider().overlay(Chrome.steel.opacity(0.25))
                        }
                    }
                }
            }
        }
    }

    private func memberRow(_ activity: Activity) -> some View {
        let on = selected.contains(activity.id)

        return Button {
            if on { selected.remove(activity.id) } else { selected.insert(activity.id) }
        } label: {
            HStack(spacing: 12) {
                MateriaOrb(color: activity.color, size: 22, glow: on ? 1 : 0.4)
                    .saturation(on ? 1 : 0.5)

                Text(activity.name)
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .lineLimit(1)

                if activity.isHidden {
                    Image(systemName: "eye.slash")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 0)

                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(on ? Chrome.gold : Chrome.steel)
            }
            .padding(.vertical, 9)
            .contentShape(Rectangle())
            .opacity(activity.isHidden ? 0.6 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityValue(on ? "in" : "out")
    }

    private func save() {
        var tag = draft
        tag.name = name.trimmingCharacters(in: .whitespaces)
        guard !tag.name.isEmpty else { return }
        onSave(tag)
        dismiss()
    }
}

// MARK: - Tag symbols

/// The tag's symbol in a small recessed tile beside its name: the same mark
/// its sidebar row wears. Sized to sit flush with the text field, and lit
/// while the grid below it is open.
private struct SymbolWell: View {
    let symbol: String
    let isOpen: Bool
    let action: () -> Void

    #if os(macOS)
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 22
    #else
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 34
    #endif

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: side * 0.5, weight: .medium))
                .foregroundStyle(Chrome.steelHi)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: side, height: side)
                .background {
                    RoundedRectangle(cornerRadius: side * 0.24, style: .continuous)
                        .fill(isOpen ? Chrome.steel.opacity(0.5) : Chrome.socketVoid.opacity(0.6))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: side * 0.24, style: .continuous)
                        .strokeBorder(isOpen ? Chrome.steelHi : Chrome.steel.opacity(0.4), lineWidth: 1)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Choose a symbol")
        .accessibilityLabel("Symbol")
        .accessibilityValue(TagSymbol.label(for: symbol))
        .accessibilityHint(isOpen ? "Closes the symbol grid" : "Opens the symbol grid")
    }
}

/// The tray that opens under the name field. Columns are adaptive rather than
/// a fixed seven, so it fills a Mac sheet and still fits a narrow phone; the
/// page scrolls behind it. Picking closes the tray and the well swaps to the
/// new symbol right above it.
private struct TagSymbolGrid: View {
    @Binding var selection: String
    let done: () -> Void

    #if os(macOS)
    private let cell: CGFloat = 32
    #else
    private let cell: CGFloat = 42
    #endif

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: cell, maximum: cell * 1.35), spacing: 8)],
            spacing: 8
        ) {
            ForEach(TagSymbol.all) { option in
                cellButton(option)
            }
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Chrome.socketVoid.opacity(0.35))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Chrome.steel.opacity(0.35), lineWidth: 1)
        }
    }

    private func cellButton(_ option: TagSymbol) -> some View {
        let on = option.name == selection

        return Button {
            withAnimation(.snappy(duration: 0.2)) {
                selection = option.name
            }
            done()
        } label: {
            Image(systemName: option.name)
                .font(.system(size: cell * 0.42, weight: .medium))
                .foregroundStyle(Chrome.steelHi)
                .frame(maxWidth: .infinity)
                .frame(height: cell)
                .background {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(on ? Chrome.steel.opacity(0.55) : Chrome.socketVoid.opacity(0.6))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(on ? Chrome.steelHi : Chrome.steel.opacity(0.4), lineWidth: 1)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(option.label)
        .accessibilityLabel(option.label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// What a tag can wear. Curated rather than the whole SF Symbols library:
/// every one reads at sidebar size, and all are old enough (SF Symbols 4 or
/// earlier) to exist on every OS the app supports. Grouped in sevens so
/// related marks stay together as the grid reflows. Adding one is one line.
private struct TagSymbol: Identifiable, Sendable {
    let name: String
    /// Spoken by VoiceOver, and the tooltip on macOS.
    let label: String
    var id: String { name }

    init(_ name: String, _ label: String) {
        self.name = name
        self.label = label
    }

    /// Falls back to the raw name for anything not in the list, e.g. a
    /// symbol written by a newer build.
    static func label(for name: String) -> String {
        all.first { $0.name == name }?.label ?? name
    }

    static let all: [TagSymbol] = [
        // Marks
        .init("tag.fill", "Tag"),
        .init("star.fill", "Star"),
        .init("heart.fill", "Heart"),
        .init("sparkles", "Sparkles"),
        .init("diamond.fill", "Diamond"),
        .init("hexagon.fill", "Hexagon"),
        .init("flame.fill", "Flame"),

        // Nature
        .init("bolt.fill", "Bolt"),
        .init("drop.fill", "Drop"),
        .init("leaf.fill", "Leaf"),
        .init("snowflake", "Snowflake"),
        .init("sun.max.fill", "Sun"),
        .init("moon.fill", "Moon"),
        .init("mountain.2.fill", "Mountains"),

        // Body
        .init("figure.run", "Running"),
        .init("dumbbell.fill", "Strength"),
        .init("figure.yoga", "Yoga"),
        .init("figure.mind.and.body", "Meditation"),
        .init("figure.hiking", "Hiking"),
        .init("bicycle", "Cycling"),
        .init("figure.pool.swim", "Swimming"),

        // Home and care
        .init("bed.double.fill", "Sleep"),
        .init("fork.knife", "Food"),
        .init("cup.and.saucer.fill", "Coffee"),
        .init("cross.case.fill", "Health"),
        .init("house.fill", "Home"),
        .init("cart.fill", "Errands"),
        .init("pawprint.fill", "Pets"),

        // Mind
        .init("book.fill", "Reading"),
        .init("brain.head.profile", "Mind"),
        .init("graduationcap.fill", "Study"),
        .init("lightbulb.fill", "Ideas"),
        .init("puzzlepiece.fill", "Puzzles"),
        .init("globe.americas.fill", "World"),
        .init("pencil", "Writing"),

        // Making and play
        .init("paintpalette.fill", "Art"),
        .init("music.note", "Music"),
        .init("camera.fill", "Photography"),
        .init("hammer.fill", "Building"),
        .init("wrench.and.screwdriver.fill", "Fixing"),
        .init("chevron.left.forwardslash.chevron.right", "Code"),
        .init("gamecontroller.fill", "Games"),

        // People and the rest
        .init("person.2.fill", "People"),
        .init("bubble.left.and.bubble.right.fill", "Talking"),
        .init("gift.fill", "Giving"),
        .init("briefcase.fill", "Work"),
        .init("dollarsign.circle.fill", "Money"),
        .init("airplane", "Travel"),
        .init("trophy.fill", "Goals"),
    ]
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
