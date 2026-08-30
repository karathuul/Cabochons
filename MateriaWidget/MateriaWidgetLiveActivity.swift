//
//  MateriaWidgetLiveActivity.swift
//  MateriaWidget
//
//  Created by Karl Brandenberger on 8/29/26.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct MateriaWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct MateriaWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MateriaWidgetAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension MateriaWidgetAttributes {
    fileprivate static var preview: MateriaWidgetAttributes {
        MateriaWidgetAttributes(name: "World")
    }
}

extension MateriaWidgetAttributes.ContentState {
    fileprivate static var smiley: MateriaWidgetAttributes.ContentState {
        MateriaWidgetAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: MateriaWidgetAttributes.ContentState {
         MateriaWidgetAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: MateriaWidgetAttributes.preview) {
   MateriaWidgetLiveActivity()
} contentStates: {
    MateriaWidgetAttributes.ContentState.smiley
    MateriaWidgetAttributes.ContentState.starEyes
}
