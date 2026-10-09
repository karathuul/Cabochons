//
//  CabochonsWidgetLiveActivity.swift
//  CabochonsWidget
//
//  Created by Karl Brandenberger on 8/29/26.
//

import ActivityKit
import WidgetKit
internal import SwiftUI

struct CabochonsWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct CabochonsWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CabochonsWidgetAttributes.self) { context in
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

extension CabochonsWidgetAttributes {
    fileprivate static var preview: CabochonsWidgetAttributes {
        CabochonsWidgetAttributes(name: "World")
    }
}

extension CabochonsWidgetAttributes.ContentState {
    fileprivate static var smiley: CabochonsWidgetAttributes.ContentState {
        CabochonsWidgetAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: CabochonsWidgetAttributes.ContentState {
         CabochonsWidgetAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: CabochonsWidgetAttributes.preview) {
   CabochonsWidgetLiveActivity()
} contentStates: {
    CabochonsWidgetAttributes.ContentState.smiley
    CabochonsWidgetAttributes.ContentState.starEyes
}
