internal import SwiftUI


// MARK: - Model

/// A GitHub-style day grid for one activity: columns are weeks, rows are
/// weekdays, each cell is how many jewels landed on that day.
///
/// Pure data. Built once per timeline entry from the shared file, then handed
/// to `HistoryGridView` to draw. Nothing in here knows about pixels, so the
/// same history can back the widget today and a detail-screen graph later.
struct ActivityHistory {

    struct Cell: Hashable {
        let day: Date
        /// Row in the grid: 0 = the calendar's first weekday, 6 = the last.
        let weekday: Int
        let count: Int
    }

    /// Oldest week first. Each inner array runs first-weekday → last-weekday.
    /// Every column is a full seven except the last, which stops at today.
    let columns: [[Cell]]

    /// Busiest single day in the window. Drives the intensity scale.
    let maxCount: Int

    /// 0 for an empty day, 1...4 for everything else, scaled against the
    /// busiest day in the window so a light month doesn't wash out to nothing.
    func level(for count: Int) -> Int {
        guard count > 0, maxCount > 0 else { return 0 }
        let fraction = Double(count) / Double(maxCount)
        return min(4, Int((fraction * 4).rounded(.up)))
    }
    
    /// The orb's opacity for a day's count: half-lit at level 1, solid at the
    /// busiest day in the window, 0 for an empty day (a bare socket).
    ///
    /// Lives on the model rather than in a view so the widget grid, the detail
    /// screen's year panel and the Canvas ramp can't drift apart — they did.
    static func opacity(forLevel level: Int) -> Double {
        guard level > 0 else { return 0 }
        return 0.5 + Double(level - 1) * (0.5 / 3)
    }

    func opacity(for count: Int) -> Double {
        Self.opacity(forLevel: level(for: count))
    }

    // MARK: Building

    /// `weeks` columns ending on today. Today's week is the partial trailing
    /// column, so `weeks: 1` means "this week so far".
    static func build(
        for activity: Activity,
        weeks: Int,
        calc: DayCalculator
    ) -> ActivityHistory {
        // One pass over the jewels, bucketed by logical day. This is the same
        // fold `Stats.compute` does — kept separate so the widget doesn't pay
        // for streak maths it never shows.
        var counts: [Date: Int] = [:]
        for jewel in activity.jewels {
            counts[calc.day(for: jewel.timestamp), default: 0] += 1
        }
        return build(counts: counts, weeks: weeks, calc: calc)
    }

    /// Lays pre-bucketed counts onto the week grid. Shared with `sample` so
    /// the placeholder goes through the real layout code.
    static func build(
        counts: [Date: Int],
        weeks: Int,
        calc: DayCalculator
    ) -> ActivityHistory {
        let today = calc.today
        let todayIndex = weekdayIndex(of: today, calendar: calc.calendar)

        // Full weeks before this one, plus this week up to and including today.
        // Counting back that many days lands exactly on a first-weekday, so the
        // oldest column is always complete and only the newest is partial.
        let dayCount = max(0, weeks - 1) * 7 + todayIndex + 1

        var columns: [[Cell]] = []
        var column: [Cell] = []
        var maxCount = 0

        for offset in stride(from: dayCount - 1, through: 0, by: -1) {
            let day = calc.offsetting(today, by: -offset)
            let count = counts[day] ?? 0
            maxCount = max(maxCount, count)
            column.append(Cell(day: day, weekday: column.count, count: count))
            if column.count == 7 {
                columns.append(column)
                column.removeAll()
            }
        }
        if !column.isEmpty { columns.append(column) }

        return ActivityHistory(columns: columns, maxCount: maxCount)
    }

    /// Fake but plausible, for the widget gallery. Deterministic so the
    /// preview doesn't reshuffle every time it's rendered.
    static func sample(weeks: Int, calc: DayCalculator) -> ActivityHistory {
        let today = calc.today
        var counts: [Date: Int] = [:]
        for offset in 0..<(weeks * 7) {
            // Knuth's multiplicative hash: cheap, and spreads evenly enough that
            // the fake data has the clumpy-with-gaps look of real logging.
            let hash = Int((UInt32(truncatingIfNeeded: offset + 1) &* 2_654_435_761) >> 27)  // 0...31
            if hash < 18 {
                counts[calc.offsetting(today, by: -offset)] = hash / 6 + 1     // 1...3
            }
        }
        return build(counts: counts, weeks: weeks, calc: calc)
    }

    /// Row index for a day, honouring the user's locale (Monday-first in most
    /// of the world, Sunday-first in the US).
    static func weekdayIndex(of day: Date, calendar: Calendar) -> Int {
        let weekday = calendar.component(.weekday, from: day)   // 1 = Sunday, always
        return (weekday - calendar.firstWeekday + 7) % 7
    }
}

// MARK: - View

/// Draws an `ActivityHistory` as a grid of squares.
///
/// Sizes itself to whatever space it's given: cell size comes from the height
/// (seven rows always fit), then however many weeks fit the width are drawn,
/// newest at the trailing edge. The same view works in the small widget, the
/// medium widget, and a detail screen — it just shows more history when there
/// is more room.
///
/// Every day is an orb in a socket. Empty days are hollow wells — lit from the
/// lower right, the way a concave thing is. Logged days are spheres lit from
/// the upper left, climbing from the orb's shadowed underside at level 1 to its
/// full core colour at level 4.
///
/// Shaded by hand in the `Canvas` rather than by stacking real `MateriaOrb`
/// views: a full year is 371 of them, and the tilt-reactive specular has no
/// meaning in a widget snapshot anyway. The shading maths matches
/// `MateriaColor`'s `rim` and `deep` exactly, so these read as the same glass.
struct HistoryGridView: View {
    let history: ActivityHistory
    let color: MateriaColor
    var showsMonths = true
    var maxCellSize: CGFloat = 12
    /// Circles already carry visual air at their corners, so they need less
    /// gutter than squares did to avoid reading as a solid block.
    var gap: CGFloat = 2
    var emptyColor: Color = Chrome.socketVoid
    var calendar: Calendar = .current

    private static let labelBand: CGFloat = 12

    var body: some View {
        Canvas { context, size in
            let band = showsMonths ? Self.labelBand : 0
            let side = min(maxCellSize, (size.height - band - gap * 6) / 7)
            guard side > 1 else { return }
            let step = side + gap

            let fit = max(1, Int((size.width + gap) / step))
            let columns = Array(history.columns.suffix(fit))

            let gridWidth = CGFloat(columns.count) * step - gap
            let gridHeight = 7 * step - gap
            let originX = size.width - gridWidth   // newest week hugs the trailing edge
            let originY = band + (size.height - band - gridHeight) / 2

            for (c, column) in columns.enumerated() {
                let x = originX + CGFloat(c) * step
                for cell in column {
                    let y = originY + CGFloat(cell.weekday) * step
                    let rect = CGRect(x: x, y: y, width: side, height: side)
                    draw(&context, orbIn: rect, level: history.level(for: cell.count))
                }
            }

            guard showsMonths else { return }
            for label in monthLabels(for: columns) {
                let x = originX + CGFloat(label.column) * step
                guard x + 20 <= size.width else { continue }   // don't run off the edge
                let text = Text(label.day.formatted(.dateTime.month(.abbreviated)))
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .foregroundStyle(Chrome.steelHi)
                context.draw(text, at: CGPoint(x: x, y: 0), anchor: .topLeading)
            }
        }
    }

    // MARK: Orb shading

    /// The three faces of one orb at one intensity level.
    private struct Shades {
        let core: Color
        let rim: Color
        let deep: Color
    }

    /// Level 1 sits near the orb's `deep` shade, level 4 is its `core`.
    /// Saturation eases down slightly as brightness climbs, matching how the
    /// real orb's underside is more saturated than its centre.
    ///
    /// Built from raw hue/saturation/brightness rather than by constructing a
    /// `MateriaColor` per level — that initialiser runs the readability pass,
    /// which would drag every dim level back up to socket contrast and flatten
    /// the whole ramp into one shade.
    private func shades(for level: Int) -> Shades {
        let t = Double(level - 1) / 3            // 0, ⅓, ⅔, 1
        let s = min(1, color.saturation * (1.2 - 0.2 * t))
        let b = color.brightness * (0.42 + 0.58 * t)
        return Shades(
            core: Color(hue: color.hue, saturation: s, brightness: b),
            rim: Color(
                hue: color.hue,
                saturation: min(1, s * 0.48),
                brightness: min(1, b * 0.15 + 0.85)
            ),
            deep: Color(
                hue: color.hue,
                saturation: min(1, s * 1.25),
                brightness: b * 0.34
            )
        )
    }

    private func draw(_ context: inout GraphicsContext, orbIn rect: CGRect, level: Int) {
        guard level > 0 else { return draw(&context, socketIn: rect) }

        let side = rect.width
        let sh = shades(for: level)
        let sphere = Path(ellipseIn: rect)

        // Light from the upper left. Pushing the gradient's centre there — not
        // just its highlight — is what makes a flat disc read as a ball.
        let light = CGPoint(x: rect.minX + side * 0.34, y: rect.minY + side * 0.30)
        context.fill(
            sphere,
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: sh.core, location: 0),
                    .init(color: sh.core, location: 0.42),
                    .init(color: sh.deep, location: 1)
                ]),
                center: light,
                startRadius: 0,
                endRadius: side * 0.98
            )
        )

        // Below about 5pt the rim and specular stop being detail and start
        // being noise — the orb reads better as a clean shaded ball.
        guard side >= 5 else { return }

        let t = Double(level - 1) / 3
        context.stroke(
            Path(ellipseIn: rect.insetBy(dx: side * 0.045, dy: side * 0.045)),
            with: .color(sh.rim.opacity(0.30 + 0.28 * t)),
            lineWidth: side * 0.085
        )

        let spec = CGRect(
            x: light.x - side * 0.15,
            y: light.y - side * 0.13,
            width: side * 0.30,
            height: side * 0.24
        )
        context.fill(
            Path(ellipseIn: spec),
            with: .color(.white.opacity(0.30 + 0.30 * t))
        )
    }

    /// An empty socket: a well, so its shading is the orb's inverted. The lit
    /// edge sits lower right where the far wall catches light, and the near lip
    /// at the upper left stays in shadow.
    private func draw(_ context: inout GraphicsContext, socketIn rect: CGRect) {
        let side = rect.width
        let well = Path(ellipseIn: rect)

        context.fill(
            well,
            with: .radialGradient(
                Gradient(colors: [emptyColor, Color.black.opacity(0.85)]),
                center: CGPoint(x: rect.maxX - side * 0.2, y: rect.maxY - side * 0.2),
                startRadius: 0,
                endRadius: side * 1.1
            )
        )

        guard side >= 5 else { return }
        context.stroke(
            Path(ellipseIn: rect.insetBy(dx: side * 0.04, dy: side * 0.04)),
            with: .color(Chrome.steel.opacity(0.22)),
            lineWidth: side * 0.07
        )
    }

    // MARK: Month labels

    private struct MonthLabel {
        let column: Int
        let day: Date
    }

    /// A label wherever the month changes, plus one at the far left if there's
    /// room before the first change — otherwise two labels would collide.
    private func monthLabels(for columns: [[ActivityHistory.Cell]]) -> [MonthLabel] {
        var labels: [MonthLabel] = []
        var previousMonth: Int?

        for (index, column) in columns.enumerated() {
            guard let day = column.first?.day else { continue }
            let month = calendar.component(.month, from: day)
            if let previousMonth, month != previousMonth {
                labels.append(MonthLabel(column: index, day: day))
            }
            previousMonth = month
        }

        let firstChange = labels.first?.column ?? columns.count
        if firstChange >= 3, let day = columns.first?.first?.day {
            labels.insert(MonthLabel(column: 0, day: day), at: 0)
        }
        return labels
    }
}

#if DEBUG
#Preview("Grid") {
    let calc = DayCalculator()
    HistoryGridView(
        history: .sample(weeks: 53, calc: calc),
        color: MateriaColor(hue: 0.38, saturation: 0.75, brightness: 0.9)
    )
    .frame(width: 306, height: 104)
    .padding()
    .background(Chrome.panel)
}
#endif
