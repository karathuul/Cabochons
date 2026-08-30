import WidgetKit
internal import SwiftUI

@main
struct MateriaWidgetBundle: WidgetBundle {
    var body: some Widget {
        MateriaWidget()
    }
}

struct MateriaWidget: Widget {
    let kind = "MateriaTodayWidget"

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
