import SwiftUI

/// A day hour by hour: a giant hour numeral down the left, that hour's sets beside it,
/// and a red line across the list at now. Used by Schedule and My Lineup.
///
/// Hours with nothing starting are skipped, so there's never a numeral with nothing next
/// to it. The now line only shows while the day is under way — after the first set has
/// started and before the last one does — placed above the first set still to come.
struct HourTimeline: View {
    let performances: [Performance]
    let now: Date
    /// Sets that overlap another starred set, flagged with the clash bar. My Lineup only.
    var clashing: Set<String> = []

    private var groups: [HourGroup] {
        var result: [HourGroup] = []
        for performance in performances.sorted(by: { $0.start < $1.start }) {
            let hour = Self.hourKey(performance.start)
            if let last = result.indices.last, result[last].key == hour {
                result[last].sets.append(performance)
            } else {
                result.append(HourGroup(key: hour, start: performance.start, sets: [performance]))
            }
        }
        return result
    }

    /// The first set that hasn't started yet, if the day is under way.
    private var nextUp: Performance? {
        let sorted = performances.sorted { $0.start < $1.start }
        guard let first = sorted.first, first.start <= now else { return nil }
        return sorted.first { $0.start > now }
    }

    var body: some View {
        let next = nextUp
        VStack(alignment: .leading, spacing: 0) {
            ForEach(groups) { group in
                HStack(alignment: .top, spacing: 8) {
                    HourNumeral(date: group.start, state: state(of: group))
                        .frame(width: 52, alignment: .leading)
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(group.sets) { performance in
                            if performance.id == next?.id {
                                NowLine(now: now)
                            }
                            NavigationLink(value: performance) {
                                PerformanceRow(performance: performance,
                                               showsConflictWarning: clashing.contains(performance.id))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func state(of group: HourGroup) -> HourNumeral.Phase {
        if group.sets.contains(where: { $0.isLive(at: now) }) || Self.hourKey(now) == group.key {
            return .now
        }
        if group.sets.allSatisfy({ $0.end <= now }) { return .past }
        return .upcoming
    }

    /// The hour a set starts in, in the festival's own time zone.
    private static func hourKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = Format.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH"
        return formatter.string(from: date)
    }

    private struct HourGroup: Identifiable {
        let key: String
        let start: Date
        var sets: [Performance]
        var id: String { key }
    }
}

/// "9" over "PM", in Six Caps, down the left of the timeline.
private struct HourNumeral: View {
    enum Phase { case upcoming, now, past }

    let date: Date
    let state: Phase

    var body: some View {
        let hour = Format.hourNumeral(date)
        VStack(alignment: .leading, spacing: 4) {
            Text(hour.number)
                .marqueeFont(72)
                .foregroundStyle(color)
                .fixedSize()
            Text(hour.period)
                .appFont(10, weight: .bold)
                .tracking(1.6)
                .foregroundStyle(color)
        }
        .padding(.top, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(hour.number) \(hour.period)")
        .accessibilityAddTraits(.isHeader)
    }

    private var color: Color {
        switch state {
        case .now: return Theme.sodium
        case .past: return Theme.unlit
        case .upcoming: return Theme.inkFaint
        }
    }
}

/// The 2pt `signal` line across the list at the current time, with its NOW tag.
struct NowLine: View {
    let now: Date

    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(Theme.signal)
                .frame(height: 2)
                .shadow(color: Theme.signal.opacity(0.9), radius: 4)
            Text("NOW \(Format.clock(now))")
                .appFont(10, weight: .heavy)
                .tracking(1.4)
                .monospacedDigit()
                .foregroundStyle(Theme.night)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Theme.signal)
                .fixedSize()
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Now, \(Format.time(now))")
    }
}

/// The day picker, drawn as four car-radio preset buttons: weekday, date and, once the
/// forecast reaches that far, the day's high.
struct DayPresets: View {
    let days: [FestivalDay]
    let selected: String?
    var forecast: (FestivalDay) -> DayConditions? = { _ in nil }
    var spokenLabel: (FestivalDay) -> String = { "\($0.weekday), \(Format.dayLabel($0))" }
    let onSelect: (FestivalDay) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(days) { day in
                let isSelected = day.date == selected
                Button {
                    onSelect(day)
                } label: {
                    VStack(spacing: 3) {
                        Text(day.shortWeekday.uppercased())
                            .appFont(15, weight: .bold)
                            .tracking(1.8)
                        Text(Format.dayLabel(day))
                            .appFont(11, weight: .medium)
                            .foregroundStyle(isSelected ? Theme.sodium : Theme.inkFaint)
                        if let conditions = forecast(day) {
                            HStack(spacing: 3) {
                                Image(systemName: conditions.symbolName)
                                    .appFont(9)
                                Text(Format.temperature(conditions.high))
                                    .appFont(11, weight: .semibold)
                            }
                            .foregroundStyle(isSelected ? Theme.sodium : Theme.inkMuted)
                        }
                    }
                    // A quarter of the screen is a quarter of the screen however big the
                    // type is, and "86°" breaking after the 8 reads as a different number
                    // entirely. Shrink to fit rather than wrap.
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .foregroundStyle(isSelected ? Theme.sodium : Theme.inkMuted)
                    .background(Theme.glass, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(isSelected ? Theme.sodium : Theme.hairline, lineWidth: 1)
                    )
                    .shadow(color: isSelected ? Theme.sodium.opacity(0.6) : .clear, radius: 6)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(spokenLabel(day))
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        // Four days always have to be four columns — there's nowhere for a fifth line to
        // go. Capped like iOS caps its own segmented controls; everything below, which
        // is the part you actually read, scales the whole way.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }
}

/// A square toggle chip: map categories, stage filters, dietary filters. Off is
/// `nightRaised` with a hairline; on is solid `ink`, or a colour the caller passes
/// (dietary filters light up `firefly`). Never `sodium`: a filter isn't yours or on air.
struct FilterChip: View {
    let title: String
    var systemImage: String?
    let isOn: Bool
    var onColor: Color = Theme.ink
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .appFont(11, weight: .semibold)
                }
                Text(title.uppercased())
                    .appFont(12, weight: .bold)
                    .tracking(1.4)
            }
            .foregroundStyle(isOn ? Theme.night : Theme.inkMuted)
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .background(isOn ? onColor : Theme.nightRaised)
            .overlay(Rectangle().strokeBorder(isOn ? onColor : Theme.hairline, lineWidth: 1))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

/// Black corn against a faint warm glow, with a few fireflies blinking over it. Sits at
/// the foot of Now Playing, My Lineup, the recap and empty states. Drawn in code so it's
/// sharp at every size and costs nothing offline; still with Reduce Motion on.
struct Horizon: View {
    var height: CGFloat = 110
    var fireflies = 7

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 15, paused: reduceMotion)) { context in
            Canvas { canvas, size in
                let glow = Gradient(colors: [Theme.glass, Theme.night])
                canvas.fill(Path(CGRect(origin: .zero, size: size)),
                            with: .radialGradient(glow,
                                                  center: CGPoint(x: size.width / 2, y: size.height * 1.3),
                                                  startRadius: 0, endRadius: size.width * 0.8))

                var generator = SeededRandom(seed: 11)
                let t = context.date.timeIntervalSinceReferenceDate
                for _ in 0..<fireflies {
                    let x = CGFloat(0.06 + generator.next() * 0.88) * size.width
                    let y = CGFloat(0.08 + generator.next() * 0.45) * size.height
                    let phase = generator.next() * 3.2
                    let level: Double = reduceMotion ? 0.6 : 0.15 + 0.85 * (0.5 + 0.5 * sin((t + phase) * .pi * 2 / 3.2))
                    let dot = CGRect(x: x - 2, y: y - 2, width: 4, height: 4)
                    var halo = canvas
                    halo.addFilter(.blur(radius: 4))
                    halo.fill(Path(ellipseIn: dot.insetBy(dx: -2, dy: -2)),
                              with: .color(Theme.firefly.opacity(0.7 * level)))
                    canvas.fill(Path(ellipseIn: dot), with: .color(Theme.firefly.opacity(level)))
                }

                canvas.fill(Self.corn(in: size, seed: 7), with: .color(.black))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    /// Stalks with alternating leaves, the same every time for a given seed.
    private static func corn(in size: CGSize, seed: UInt64) -> Path {
        var generator = SeededRandom(seed: seed)
        var path = Path()
        let count = max(8, Int(size.width / 12.5))
        let step = size.width / CGFloat(count)
        for i in 0...count {
            let x = CGFloat(i) * step + CGFloat(generator.next()) * step * 0.5
            let h = size.height * (0.5 + CGFloat(generator.next()) * 0.45)
            let base = size.height
            path.move(to: CGPoint(x: x, y: base))
            path.addLine(to: CGPoint(x: x + 1.5, y: base - h))
            path.addLine(to: CGPoint(x: x + 3, y: base))
            path.closeSubpath()
            for j in 0..<4 {
                let y = base - h * (0.25 + CGFloat(j) * 0.18)
                let side: CGFloat = (i + j) % 2 == 0 ? -1 : 1
                let length = 14 + CGFloat(generator.next()) * 10
                let c = x + 1.5
                path.move(to: CGPoint(x: c, y: y))
                path.addQuadCurve(to: CGPoint(x: c + side * length, y: y - 2),
                                  control: CGPoint(x: c + side * length * 0.6, y: y - 12))
                path.addQuadCurve(to: CGPoint(x: c, y: y + 3),
                                  control: CGPoint(x: c + side * length * 0.5, y: y - 6))
                path.closeSubpath()
            }
        }
        return path
    }
}

/// A tiny deterministic generator, so the corn and the fireflies land in the same
/// places on every frame and every launch.
private struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }

    /// A value in 0..<1.
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double((state >> 33) & 0xFFFFFF) / Double(0x1000000)
    }
}
