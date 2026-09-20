//
//  HistoryYearPanel.swift
//
//  A year-at-a-glance grid for one activity on the detail screen: one cell per
//  day, seven rows per column, one column per week, newest week at the trailing
//  edge. Empty days are bare sockets; logged days are orbs that brighten with
//  the day's count. Scrolls horizontally because a year of legible cells is
//  wider than a phone, and opens anchored to today. Tapping a day names it
//  under the grid.
//
//  Built on `ActivityHistory` — the same model the History widget draws from,
//  so the wall in the app and the wall on the Home Screen are the same wall,
//  down to the brightness ramp (`ActivityHistory.opacity(for:)`).
//  Real `MateriaSocket`/`MateriaOrb` views rather than the widget's Canvas:
//  in-app the cells need hit testing, and at this size they take the orb's
//  static tier anyway (no tilt subscription, no blur passes).
//

internal import SwiftUI

// MARK: - Panel

struct HistoryYearPanel: View {
    let history: ActivityHistory
    let color: MateriaColor
    var side: CGFloat = 13
    var gap: CGFloat = 3
    var calendar: Calendar = .current

    @State private var selected: ActivityHistory.Cell?

    /// Month labels sit in their own band above the grid, inside the scroll
    /// view so they travel with the weeks they label.
    private static let band: CGFloat = 13
    private static let gutter: CGFloat = 20

    private var step: CGFloat { side + gap }
    private var gridWidth: CGFloat { CGFloat(history.columns.count) * step - gap }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            HStack(alignment: .top, spacing: 6) {
                weekdayGutter
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        monthBand
                        weeks
                    }
                }
                .defaultScrollAnchor(.trailing)   // opens on the newest week
            }

            footer
        }
        .panel()
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("The year")
                .font(.system(.headline, design: .rounded, weight: .semibold))

            Spacer()

            Text("\(daysLogged) of \(dayCount) days")
                .font(.system(.caption, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    private var dayCount: Int {
        history.columns.reduce(0) { $0 + $1.count }
    }

    private var daysLogged: Int {
        history.columns.reduce(0) { $0 + $1.filter { $0.count > 0 }.count }
    }

    // MARK: Grid

    /// Every other row is labelled. Seven labels at this cell size crowd into
    /// a grey stripe; three read as a scale.
    private var weekdayGutter: some View {
        VStack(alignment: .trailing, spacing: gap) {
            // The stack's own spacing sits under this, so the spacer is one
            // gap short of the band or every label lands a row low.
            Color.clear.frame(height: Self.band - gap)
            ForEach(0..<7, id: \.self) { row in
                Text(row.isMultiple(of: 2) ? "" : symbol(forRow: row))
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(Chrome.steelHi)
                    .frame(height: side)
            }
        }
        .frame(width: Self.gutter, alignment: .trailing)
    }

    /// Row 0 is the calendar's first weekday, so the symbol index has to be
    /// rotated by the locale — Monday-first in most of the world, Sunday-first
    /// in the US.
    private func symbol(forRow row: Int) -> String {
        let index = (calendar.firstWeekday - 1 + row) % 7
        return calendar.veryShortStandaloneWeekdaySymbols[index]
    }

    private var monthBand: some View {
        ZStack(alignment: .topLeading) {
            ForEach(monthLabels, id: \.column) { label in
                Text(label.day.formatted(.dateTime.month(.abbreviated)))
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(Chrome.steelHi)
                    .offset(x: CGFloat(label.column) * step)
            }
        }
        .frame(width: gridWidth, height: Self.band, alignment: .topLeading)
    }

    /// Lazy so a year of sockets doesn't all materialise for the six weeks
    /// that fit on screen.
    private var weeks: some View {
        LazyHStack(alignment: .top, spacing: gap) {
            ForEach(history.columns.indices, id: \.self) { c in
                VStack(spacing: gap) {
                    ForEach(history.columns[c], id: \.day) { cell in
                        self.cell(cell)
                    }
                }
            }
        }
        .frame(width: gridWidth, alignment: .leading)
    }

    private func cell(_ cell: ActivityHistory.Cell) -> some View {
        let opacity = history.opacity(for: cell.count)
        return ZStack {
            MateriaSocket(size: side)

            if opacity > 0 {
                MateriaOrb(color: color, size: side)
                    .opacity(opacity)
            }

            if selected == cell {
                Circle()
                    .strokeBorder(Chrome.gold, lineWidth: 1.5)
                    .frame(width: side + 5, height: side + 5)
            }
        }
        .frame(width: side, height: side)
        .contentShape(Rectangle())
        .onTapGesture {
            selected = (selected == cell) ? nil : cell
        }
        .accessibilityLabel(
            "\(cell.day.formatted(date: .abbreviated, time: .omitted)): \(cell.count) jewels"
        )
    }

    // MARK: Footer

    /// The legend doubles as the readout: tap a day and it names that day
    /// instead, so the grid never needs a popover.
    @ViewBuilder
    private var footer: some View {
        if let selected {
            HStack(spacing: 6) {
                Text(selected.day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    .font(.system(.caption, design: .rounded, weight: .medium))
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(selected.count == 0
                     ? "nothing"
                     : "\(selected.count) \(selected.count == 1 ? "jewel" : "jewels")")
                    .font(.system(.caption, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(selected.count == 0 ? .secondary : .primary)
            }
        } else {
            HStack(spacing: 5) {
                Text("Less")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.secondary)
                MateriaSocket(size: 10)
                ForEach(1...4, id: \.self) { level in
                    MateriaOrb(color: color, size: 10)
                        .opacity(ActivityHistory.opacity(forLevel: level))
                }
                Text("More")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Month labels

    private struct MonthLabel {
        let column: Int
        let day: Date
    }

    /// A label wherever the month changes, plus one at the far left if there's
    /// room before the first change — otherwise two labels collide.
    private var monthLabels: [MonthLabel] {
        var labels: [MonthLabel] = []
        var previousMonth: Int?

        for (index, column) in history.columns.enumerated() {
            guard let day = column.first?.day else { continue }
            let month = calendar.component(.month, from: day)
            if let previousMonth, month != previousMonth {
                labels.append(MonthLabel(column: index, day: day))
            }
            previousMonth = month
        }

        let firstChange = labels.first?.column ?? history.columns.count
        if firstChange >= 3, let day = history.columns.first?.first?.day {
            labels.insert(MonthLabel(column: 0, day: day), at: 0)
        }
        return labels
    }
}

#if DEBUG
#Preview("Year") {
    let calc = DayCalculator()
    ScrollView {
        HistoryYearPanel(
            history: .sample(weeks: 53, calc: calc),
            color: MateriaColor(hue: 0.38, saturation: 0.75, brightness: 0.9)
        )
        .padding(20)
    }
    .background(Chrome.panel)
    .preferredColorScheme(.dark)
}
#endif
