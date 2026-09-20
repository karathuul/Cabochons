import WidgetKit
internal import SwiftUI

@main
struct MemoriaWidgetBundle: WidgetBundle {
    var body: some Widget {
        MemoriaWidget()
        HistoryWidget()
    }
}

struct MemoriaWidget: Widget {
    let kind = "MemoriaTodayWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MateriaProvider()) { entry in
            MateriaWidgetView(entry: entry)
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
