internal import SwiftUI

/// Sidebar destinations. The day is now a first-class place, not something you
/// reach through an activity.
enum Route: Hashable {
    case day
    case activity(Activity.ID)
}

struct ContentView: View {
    @Environment(LogStore.self) private var store
    @State private var selection: Route? = .day
    @State private var editing: Activity?
    @State private var creatingNew = false

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            switch selection {
            case .day, .none:
                DayView()
            case .activity(let id):
                if store.activity(id) != nil {
                    ActivityDetailView(activityID: id).id(id)
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
    }

    // MARK: Sidebar

    private var sidebar: some View {
        @Bindable var store = store

        return List(selection: $selection) {
            Section {
                TodayRow()
                    .tag(Route.day)
            }

            Section("Activities") {
                if store.activities.isEmpty {
                    EmptySidebar { creatingNew = true }
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(store.activities) { activity in
                        SidebarRow(activity: activity)
                            .tag(Route.activity(activity.id))
                            .contextMenu {
                                Button("Edit") { editing = activity }
                                Button("Delete", role: .destructive) {
                                    if selection == .activity(activity.id) { selection = .day }
                                    store.delete(activity.id)
                                }
                            }
                    }
                    .onMove { store.move(from: $0, to: $1) }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Chrome.panel)
        .navigationTitle("Materia")
        #if os(macOS)
        .frame(minWidth: 250)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    creatingNew = true
                } label: {
                    Label("New activity", systemImage: "plus")
                }
            }
            ToolbarItem {
                Menu {
                    Picker("Day starts at", selection: $store.dayStartHour) {
                        ForEach([0, 3, 4, 5, 6], id: \.self) { hour in
                            Text(hour == 0 ? "Midnight" : "\(hour):00 AM").tag(hour)
                        }
                    }
                    Divider()
                    Text("A later start keeps late-night entries on the previous day.")
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
    }
}

// MARK: - Sidebar rows

private struct TodayRow: View {
    @Environment(LogStore.self) private var store

    var body: some View {
        let stats = store.combined
        let fills = stats.today?.fills ?? []

        HStack(spacing: 12) {
            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 15))
                .foregroundStyle(Chrome.steelHi)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 3) {
                Text("Today")
                    .font(.system(.body, design: .rounded, weight: .medium))

                if fills.isEmpty {
                    Text("no jewels yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    SlotRail(fills: fills, capacity: stats.capacity, size: 9, maxSlots: 14)
                }
            }

            Spacer(minLength: 4)

            Text("\(fills.count)")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }
}

private struct SidebarRow: View {
    @Environment(LogStore.self) private var store
    let activity: Activity

    var body: some View {
        let today = store.todayCount(for: activity)

        HStack(spacing: 12) {
            ZStack {
                MateriaSocket(size: 26)
                if today > 0 {
                    MateriaOrb(color: activity.color, size: 26, glow: 0.7)
                }
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(activity.name)
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .lineLimit(1)
                Text("\(today) of \(activity.dailyTarget) today")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            if today >= activity.dailyTarget, activity.dailyTarget > 0 {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(Chrome.gold)
            }
        }
        .padding(.vertical, 3)
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
