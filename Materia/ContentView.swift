internal import SwiftUI

struct ContentView: View {
    @Environment(LogStore.self) private var store
    @State private var selection: Activity.ID?
    @State private var editing: Activity?
    @State private var creatingNew = false

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            if let activity = store.activity(selection) {
                ActivityDetailView(activityID: activity.id)
                    .id(activity.id)
            } else {
                DetailPlaceholder(hasActivities: !store.activities.isEmpty)
            }
        }
        .sheet(isPresented: $creatingNew) {
            ActivityEditor(mode: .create) { activity in
                store.add(activity)
                selection = activity.id
            }
        }
        .sheet(item: $editing) { activity in
            ActivityEditor(mode: .edit(activity)) { updated in
                store.update(updated)
            }
        }
        .onAppear {
            if selection == nil { selection = store.activities.first?.id }
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        @Bindable var store = store

        return List(selection: $selection) {
            if store.activities.isEmpty {
                EmptySidebar { creatingNew = true }
                    .listRowBackground(Color.clear)
            } else {
                ForEach(store.activities) { activity in
                    SidebarRow(activity: activity)
                        .tag(activity.id)
                        .contextMenu {
                            Button("Edit") { editing = activity }
                            Button("Delete", role: .destructive) {
                                if selection == activity.id { selection = nil }
                                store.delete(activity.id)
                            }
                        }
                }
                .onMove { store.move(from: $0, to: $1) }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Chrome.panel)
        .navigationTitle("Materia")
        #if os(macOS)
        .frame(minWidth: 240)
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

// MARK: - Sidebar row

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

// MARK: - Empty states

private struct EmptySidebar: View {
    var create: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No activities yet")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
            Text("Create one to get a button and a row of sockets to fill.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Create an activity", action: create)
                .buttonStyle(.borderedProminent)
                .padding(.top, 2)
        }
        .padding(.vertical, 8)
    }
}

private struct DetailPlaceholder: View {
    let hasActivities: Bool

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 18) {
                MateriaSocket(size: 42)
                MateriaSocket(size: 42)
                MateriaSocket(size: 42)
            }
            Text(hasActivities ? "Pick an activity" : "Create an activity to begin")
                .font(.system(.title3, design: .rounded, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Chrome.panel)
    }
}
