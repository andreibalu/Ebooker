//
//  PagelessWidgetLiveActivity.swift
//  PagelessWidget
//
//  Created by andreibalu on 03.04.2026.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct PagelessWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct PagelessWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PagelessWidgetAttributes.self) { context in
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

extension PagelessWidgetAttributes {
    fileprivate static var preview: PagelessWidgetAttributes {
        PagelessWidgetAttributes(name: "World")
    }
}

extension PagelessWidgetAttributes.ContentState {
    fileprivate static var smiley: PagelessWidgetAttributes.ContentState {
        PagelessWidgetAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: PagelessWidgetAttributes.ContentState {
         PagelessWidgetAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: PagelessWidgetAttributes.preview) {
   PagelessWidgetLiveActivity()
} contentStates: {
    PagelessWidgetAttributes.ContentState.smiley
    PagelessWidgetAttributes.ContentState.starEyes
}
