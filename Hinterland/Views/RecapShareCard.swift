import SwiftUI

/// The picture that comes out of the share button: your weekend on one card, set like the
/// app — the year in Six Caps on `night`, your ratings as fireflies, the corn along the foot.
///
/// Rendered by `ImageRenderer`, which draws it outside the view hierarchy — so nothing in
/// here reads the app's environment objects, and nothing in here is `appFont`. Type in a
/// picture doesn't scale with the reader's settings, and the reader of this one is whoever
/// it gets sent to. Names wrap rather than truncate: the card grows taller instead.
struct RecapShareCard: View {
    let recap: Recap

    /// Fixed, because a shared image has no container to fill. 1080pt wide at the renderer's
    /// 3× scale, which is what every social app wants and nothing has to resample.
    private let width: CGFloat = 360

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                header
                numbers

                if !recap.rated.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("MY BEST SETS")
                            .font(Self.text(.bold, 13))
                            .tracking(2.2)
                            .foregroundStyle(Theme.inkFaint)
                            .padding(.bottom, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(Theme.ink).frame(height: 2)
                            }
                        ForEach(Array(recap.best(limit: 5).enumerated()), id: \.element.id) { index, entry in
                            row(entry, rank: index + 1)
                        }
                    }
                }

                footer
            }
            .padding(.horizontal, 22)
            .padding(.top, 24)

            Horizon(height: 72, fireflies: 6, isStill: true)
                .padding(.top, 8)
        }
        .frame(width: width, alignment: .leading)
        .background(Theme.night)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("MY \(recap.festival.name.uppercased())")
                .font(Self.text(.heavy, 13))
                .tracking(2.4)
                .foregroundStyle(Theme.sodium)
            Text(String(recap.festival.year))
                .font(.custom(AppFontFace.marquee, fixedSize: 120))
                .foregroundStyle(Theme.ink)
            if let range = Format.dateRange(recap.festival.startDate, recap.festival.endDate) {
                Text("\(range) · \(recap.festival.city)".uppercased())
                    .font(Self.text(.bold, 13))
                    .tracking(1.6)
                    .foregroundStyle(Theme.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var numbers: some View {
        HStack(alignment: .top, spacing: 10) {
            stat("\(recap.attendedCount)", recap.attendedCount == 1 ? "set seen" : "sets seen")
            stat(recap.watchedHours.formatted(.number.precision(.fractionLength(0...1))),
                 "hours")
            if let average = recap.average {
                stat(Format.rating(average), "my average", tint: Theme.sodium)
            }
        }
    }

    private func stat(_ value: String, _ label: String, tint: Color = Theme.ink) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.custom(AppFontFace.marquee, fixedSize: 64))
                .foregroundStyle(tint)
                .shadow(color: tint == Theme.sodium ? Theme.sodiumGlow : .clear, radius: 12)
            Text(label.uppercased())
                .font(Self.text(.bold, 13))
                .tracking(1.4)
                .foregroundStyle(Theme.inkFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.nightRaised)
    }

    private func row(_ entry: Recap.RatedSet, rank: Int) -> some View {
        HStack(alignment: .center, spacing: 12) {
            // The same heavy Barlow as names in the app's lists: Six Caps this small
            // turns to hairlines, more so once a social app has recompressed the picture.
            Text("\(rank)")
                .font(Self.text(.heavy, 24))
                .foregroundStyle(Theme.inkFaint)
                .frame(minWidth: 18, alignment: .leading)
            Text(entry.performance.artist.uppercased())
                .font(Self.text(.heavy, 24))
                .tracking(0.5)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            // Fireflies rather than stars, as in the app. Drawn, not typed: neither
            // bundled face has a star, and a fallback glyph would break the set.
            HStack(spacing: 4) {
                ForEach(Array(SetRating.scale), id: \.self) { value in
                    let lit = value <= entry.rating.stars
                    Circle()
                        .fill(lit ? Theme.sodium : Theme.unlit)
                        .frame(width: 8, height: 8)
                        .shadow(color: lit ? Theme.sodium.opacity(0.7) : .clear, radius: 3)
                }
            }
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
    }

    private var footer: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(recap.festival.venue.uppercased())
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if recap.ratedCount > 5 {
                Text("+\(recap.ratedCount - 5) MORE")
            }
        }
        .font(Self.text(.bold, 13))
        .tracking(1.4)
        .foregroundStyle(Theme.inkFaint)
    }

    /// Barlow Condensed at a fixed size: a picture's type doesn't follow Dynamic Type.
    private static func text(_ weight: Font.Weight, _ size: CGFloat) -> Font {
        .custom(AppFontFace.text(weight), fixedSize: size)
    }
}
