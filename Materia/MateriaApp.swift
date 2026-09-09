internal import SwiftUI
import AppIntents
#if os(macOS)
import AppKit
#endif

@main
struct MateriaLogApp: App {
    @State private var store = LogStore()
    @State private var motion = TiltSource()
    @Environment(\.orbShading) private var sh
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("shimmerEnabled") private var shimmerEnabled = true

    var body: some Scene {
        mainWindow

        #if os(macOS)
        // Logging shouldn't require finding the window. One click from the
        // menu bar slots a jewel and gets out of the way.
        MenuBarExtra {
            MenuBarContent(store: store)
        } label: {
            Image(systemName: "circle.grid.2x2.fill")
        }
        .menuBarExtraStyle(.menu)
        #endif
    }

    // Kept as its own property so the macOS-only modifiers live in one
    // uninterrupted chain, rather than straddling a #if inside SceneBuilder.
    private var mainWindow: some Scene {
        #if os(macOS)
        return WindowGroup {
            rootView
        }
        .defaultSize(width: 940, height: 660)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
        #else
        return WindowGroup {
            rootView
        }
        #endif
    }

    private var rootView: some View {
        OrbLab.init()
        
//        ContentView()
//            .environment(store)
//            .environment(motion)
//            .onChange(of: scenePhase, initial: true) { _, phase in
//                motion.isActive = shimmerEnabled && phase == .active
//            }
//            .preferredColorScheme(.dark)
//            .tint(Color(hex: 0x4FB6FF))
//            #if os(macOS)
//            .frame(minWidth: 760, minHeight: 520)
//            #endif
    }
}

// MARK: - Menu bar

#if os(macOS)
private struct MenuBarContent: View {
    let store: LogStore

    var body: some View {
        if store.visibleActivities.isEmpty {
            Text("No activities yet")
        } else {
            ForEach(store.visibleActivities) { activity in
                let progress = store.progress(for: activity)
                Button {
                    store.slot(activity.id)
                } label: {
                    Text("\(activity.name)  ·  \(progress.count)/\(progress.target)")
                }
            }
        }

        Divider()

        Button("Open MateriaLog") {
            NSApp.activate(ignoringOtherApps: true)
        }

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
#endif
