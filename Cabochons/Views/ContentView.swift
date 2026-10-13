// MARK: - ContentView
// The app's root split view. The sidebar lists the calendar spans (Today,
// this week, this month, this year), tags (each wearing its chosen symbol over
// a small period rail) and activities; the detail pane shows a span, one
// activity, or the day narrowed to a tag. The New and
// Settings menus sit in the wordmark's header row (the toolbar on the Mac).

internal import SwiftUI

/// Sidebar destinations. The day is now a first-class place, not something you
/// reach through an activity.
enum Route: Hashable {
    /// The day view over every activity, for one calendar span.
    case span(Scope.Span)
    case activity(Activity.ID)
    /// The day view, narrowed to one tag's members.
    case tag(Tag.ID)

    static let today = Route.span(.day)
}

struct ContentView: View {
    @Environment(LogStore.self) private var store
    @State private var selection: Route? = .today
    @State private var editing: Activity?
    @State private var creatingNew = false
    @State private var editingTag: Tag?
    @State private var showingGuide = false
    @State private var creatingTag = false
    @State private var showingData = false
    /// Persisted so the sidebar doesn't re-expand every launch — the whole
    /// point of hiding is to get things out of the way.
    @AppStorage("hiddenSectionExpanded") private var hiddenExpanded = false
    /// Remembered like the section above. `custom` is the order the rails were
    /// made in, so it's the default for anyone who never opens the menu.
    @AppStorage("activityOrder") private var activityOrder = ActivityOrder.custom

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            switch selection {
            case .none:
                DayView()
            case .span(let span):
                DayView(span: span).id(span)
            case .activity(let id):
                if store.activity(id) != nil {
                    ActivityDetailView(activityID: id, onDelete: { selection = .today }).id(id)
                } else {
                    DayView()
                }
            case .tag(let id):
                if store.tag(id) != nil {
                    DayView(tagID: id).id(id)
                } else {
                    DayView()
                }
            }
        }
        .sheet(isPresented: $creatingNew) {
            ActivityEditor(mode: .create) { activity in
                store.add(activity)
            }
        }
        .sheet(item: $editing) { activity in
            ActivityEditor(mode: .edit(activity)) { updated in
                store.update(updated)
            }
        }
        .sheet(isPresented: $showingData) { DataSheet() }
        .sheet(isPresented: $creatingTag) {
            TagEditor(mode: .create) { tag in
                store.add(tag)
            }
        }
        .sheet(item: $editingTag) { tag in
            TagEditor(mode: .edit(tag)) { updated in
                store.update(updated)
            }
        }
        .sheet(isPresented: $showingGuide) { GuideSheet() }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        @Bindable var store = store
        let visible = activityOrder.sorted(store.visibleActivities, calc: store.calc)
        let hidden = activityOrder.sorted(store.hiddenActivities, calc: store.calc)

        return List(selection: $selection) {
            Section {
                ForEach(Scope.Span.allCases, id: \.self) { span in
                    SpanRow(span: span)
                        .tag(Route.span(span))
                }
            }
            
            // Tags only make sense once there's something to tag.
            if !store.activities.isEmpty {
                Section {
                    if store.tags.isEmpty {
                        Button {
                            creatingTag = true
                        } label: {
                            Label("Add a tag", systemImage: "tag")
                                .font(.system(.subheadline, design: .rounded))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.tags) { tag in
                            TagSidebarRow(tag: tag)
                                .tag(Route.tag(tag.id))
                                .contextMenu {
                                    Button("Edit") { editingTag = tag }
                                    Divider()
                                    Button("Delete", role: .destructive) {
                                        if selection == .tag(tag.id) { selection = .today }
                                        store.delete(tag: tag.id)
                                    }
                                }
                                // The context menu is a long press, i.e. the
                                // same secret handshake that hid "New tag".
                                // Swipe is the gesture people already try on an
                                // iOS list, so the editor has a way in that
                                // nobody has to be told about. No full swipe:
                                // the first action here deletes.
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button("Delete", role: .destructive) {
                                        if selection == .tag(tag.id) { selection = .today }
                                        store.delete(tag: tag.id)
                                    }
                                    Button("Edit") { editingTag = tag }
                                }
                        }
                        .onMove { source, destination in
                            store.moveTags(from: source, to: destination)
                        }
                    }
                } header: {
                    // The + lives here as well as in the toolbar, because on
                    // iOS a toolbar menu is one more tap away and easy to miss.
                    HStack {
                        Text("Tags")
                        Spacer(minLength: 0)
                        Button {
                            creatingTag = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("New tag")
                    }
                }
            }

            Section {
                if store.activities.isEmpty {
                    EmptySidebar { creatingNew = true }
                        .listRowBackground(Color.clear)
                } else if store.visibleActivities.isEmpty {
                    Text("All hidden")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(visible) { activity in
                        SidebarRow(activity: activity)
                            .tag(Route.activity(activity.id))
                            .contextMenu {
                                Button("Edit") { editing = activity }
                                Button("Hide") { store.setHidden(activity.id, true) }
                                Divider()
                                Button("Delete", role: .destructive) {
                                    if selection == .activity(activity.id) { selection = .today }
                                    store.delete(activity.id)
                                }
                            }
                    }
                    // Only the custom order has a meaning to drag into; the
                    // computed orders would just snap back.
                    .onMove(perform: activityOrder == .custom
                        ? { store.moveVisible(from: $0, to: $1) }
                        : nil)
                }
            } header: {
                HStack {
                    Text("Activities")
                    Spacer(minLength: 0)
                    if !store.activities.isEmpty {
                        sortMenu
                    }
                }
            }


            if !store.hiddenActivities.isEmpty {
                Section {
                    if hiddenExpanded {
                        ForEach(hidden) { activity in
                            SidebarRow(activity: activity)
                                .tag(Route.activity(activity.id))
                                .contextMenu {
                                    Button("Unhide") { store.setHidden(activity.id, false) }
                                    Divider()
                                    Button("Delete", role: .destructive) {
                                        if selection == .activity(activity.id) { selection = .today }
                                        store.delete(activity.id)
                                    }
                                }
                        }
                    }
                } header: {
                    Button {
                        withAnimation(.snappy(duration: 0.22)) {
                            hiddenExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                                .rotationEffect(.degrees(hiddenExpanded ? 90 : 0))

                            Text("Hidden")

                            Text("\(store.hiddenActivities.count)")
                                .monospacedDigit()
                                .foregroundStyle(.tertiary)

                            Spacer(minLength: 0)
                        }
                        // Without this the row only responds to taps on the
                        // glyphs themselves, not the empty space beside them.
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } footer: {
                    if hiddenExpanded {
                        Text("Archived activity jewels remain for previous days.")
                            .font(.caption2)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Chrome.panel)
        .wordmarkTitle("Cabochons", asset: "Wordmark") {
            newMenu
            settingsMenu
        }
        #if os(macOS)
        .frame(minWidth: 250)
        #endif
    }

    // MARK: Header menus

    /// Beside the wordmark on iOS, in the toolbar on the Mac.
    ///
    /// No `primaryAction`: with one, iOS runs it on tap and only reveals the
    /// menu on a long press, which hides "New tag" from anyone who hasn't
    /// read the docs.
    private var newMenu: some View {
        Menu {
            Button("New activity", systemImage: "circle.fill") { creatingNew = true }
            Button("New tag", systemImage: "tag") { creatingTag = true }
                .disabled(store.activities.isEmpty)
        } label: {
            Label("New", systemImage: "plus")
        }
    }

    /// In the Activities header, beside the Tags "+". Picking an order keeps
    /// the check on it, so the current sort is visible without opening anything.
    private var sortMenu: some View {
        Menu {
            Picker("Sort activities", selection: $activityOrder) {
                ForEach(ActivityOrder.allCases) { order in
                    Text(order.label).tag(order)
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(activityOrder == .custom ? Color.secondary : Chrome.steelHi)
        }
        .accessibilityLabel("Sort activities")
    }

    private var settingsMenu: some View {
        @Bindable var store = store

        return Menu {
            Picker("Day starts at", selection: $store.dayStartHour) {
                ForEach([0, 3, 4, 5, 6], id: \.self) { hour in
                    Text(hour == 0 ? "Midnight" : "\(hour):00 AM").tag(hour)
                }
            }
            Divider()
            Text("A later start keeps late-night entries on the previous day.")
            Divider()
            Button("Guide…") { showingGuide = true }
            Button("Import & Export…") { showingData = true }
        } label: {
            Label("Settings", systemImage: "gearshape")
        }
    }
}

// MARK: - Sidebar rows

/// Today, this week, this month or this year: every activity's jewels in the
/// span's current period, against what they all ask for in it.
private struct SpanRow: View {
    @Environment(LogStore.self) private var store
    let span: Scope.Span

    var body: some View {
        let progress = store.progress(for: store.scope(span))
        let fills = progress.fills

        HStack(spacing: 12) {
            Image(systemName: span.symbol)
                .font(.system(size: 15))
                .foregroundStyle(progress.isMet ? Chrome.gold : Chrome.steelHi)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 3) {
                Text(span.name)
                    .font(.system(.body, design: .rounded, weight: .medium))

                if fills.isEmpty {
                    Text("no jewels yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    SlotRail(fills: fills, capacity: progress.target, size: 9, maxSlots: 14)
                }
            }

            Spacer(minLength: 4)

            Text(progress.target > 0 ? "\(fills.count)/\(progress.target)" : "\(fills.count)")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(progress.isMet ? Chrome.gold : .secondary)
        }
        .padding(.vertical, 3)
    }
}

/// A tag row is a small period rail: mixed colours from its members, sized
/// to the tag's own target, not the day's. The glyph is the tag's own symbol,
/// gold once the period's target is met.
private struct TagSidebarRow: View {
    @Environment(LogStore.self) private var store
    let tag: Tag

    var body: some View {
        let progress = store.progress(for: tag)

        HStack(spacing: 12) {
            Image(systemName: tag.symbol)
                .font(.system(size: 13))
                .foregroundStyle(progress.isMet ? Chrome.gold : Chrome.steelHi)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 3) {
                Text(tag.name)
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .lineLimit(1)

                SlotRail(fills: progress.fills, capacity: progress.target, size: 9, maxSlots: 14)

                Text("\(progress.count) of \(progress.target) this \(progress.cadence.phrase)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if progress.isMet {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(Chrome.gold)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct SidebarRow: View {
    @Environment(LogStore.self) private var store
    let activity: Activity

    var body: some View {
        let progress = store.progress(for: activity)

        HStack(spacing: 12) {
            ZStack {
                CabochonsSocket(size: 26)
                if progress.count > 0, !activity.isHidden {
                    CabochonsOrb(color: activity.color, size: 26, glow: 0.7)
                }
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(activity.name)
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .lineLimit(1)

                if activity.isHidden {
                    Text("\(activity.jewels.count) kept")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(progress.count) of \(progress.target) this \(progress.cadence.phrase)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            if activity.isHidden {
                Image(systemName: "eye.slash")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else if progress.isMet {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(Chrome.gold)
            }
        }
        .padding(.vertical, 3)
        .opacity(activity.isHidden ? 0.55 : 1)
        .saturation(activity.isHidden ? 0.3 : 1)
    }
}

// MARK: - Empty state

private struct EmptySidebar: View {
    var create: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No activities yet")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
            Text("Create one to get an orb to press and sockets to fill.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Create an activity", action: create)
                .buttonStyle(.borderedProminent)
                .padding(.top, 2)
        }
        .padding(.vertical, 8)
    }
}
