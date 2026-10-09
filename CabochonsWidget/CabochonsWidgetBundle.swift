import WidgetKit
internal import SwiftUI

@main
struct CabochonsWidgetBundle: WidgetBundle {
    var body: some Widget {
        CabochonsWidget()
        HistoryWidget()
    }
}

struct CabochonsWidget: Widget {
    let kind = "CabochonsTodayWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CabochonsProvider()) { entry in
            CabochonsWidgetView(entry: entry)
                .preferredColorScheme(.dark)
        }
        .configurationDisplayName("Today")
        .description("Your jewels for today, and the current streak.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium
        ])
    }
}
