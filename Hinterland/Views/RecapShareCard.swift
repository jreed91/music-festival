import SwiftUI

/// The picture that comes out of the share button: your weekend on one card.
///
/// Rendered by `ImageRenderer`, which draws it outside the view hierarchy — so nothing in
/// here reads the environment, and nothing in here is `appFont`. Type in a picture doesn't
/// scale with the reader's settings, and the reader of this one is whoever it gets sent to.
struct RecapShareCard: View {
    let recap: Recap

    /// Fixed, because a shared image has no container to fill. 1080pt wide at the renderer's
    /// 3× scale, which is what every social app wants and nothing has to resample.
    private let width: CGFloat = 360

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            VStack(alignment: .leading, spacing: 14) {
                numbers

                if !recap.rated.isEmpty {
                    Rectangle().fill(Theme.hairline).frame(height: 1)

                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(recap.best(limit: 5)) { entry in
                            row(entry)
                        }
                    }
                }

                footer
            }
            .padding(20)
        }
        .frame(width: width, alignment: .leading)
        .background(Theme.background)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("MY \(recap.festival.name.uppercased())")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(Theme.background.opacity(0.75))
            Text(String(recap.festival.year))
                .font(.system(size: 46, weight: .black, design: .rounded))
                .foregroundStyle(Theme.background)
            if let range = Format.dateRange(recap.festival.startDate, recap.festival.endDate) {
                Text("\(range) · \(recap.festival.city)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.background.opacity(0.75))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            LinearGradient(colors: [Theme.accent, Theme.accent.opacity(0.72)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
    }

    private var numbers: some View {
        HStack(alignment: .top, spacing: 0) {
            stat("\(recap.attendedCount)", recap.attendedCount == 1 ? "set seen" : "sets seen")
            stat(recap.watchedHours.formatted(.number.precision(.fractionLength(0...1))),
                 "hours")
            if let average = recap.average {
                stat(Format.rating(average), "average", tint: Theme.accent)
            }
        }
    }

    private func stat(_ value: String, _ label: String, tint: Color = .white) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 27, weight: .black, design: .rounded))
                .foregroundStyle(tint)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.tertiaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ entry: Recap.RatedSet) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            // Drawn as characters rather than as five SF Symbols: this is a picture that
            // gets looked at small, and the glyphs stay crisp where a stack of tinted
            // images at 9pt turns to mush.
            Text(String(repeating: "★", count: entry.rating.stars)
               + String(repeating: "☆", count: SetRating.scale.upperBound - entry.rating.stars))
                .font(.system(size: 12))
                .foregroundStyle(Theme.accent)
            Text(entry.performance.artist)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private var footer: some View {
        HStack(spacing: 4) {
            Image(systemName: "music.mic")
                .font(.system(size: 9))
            Text(recap.festival.venue)
                .font(.system(size: 9, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 0)
            if recap.ratedCount > 5 {
                Text("+\(recap.ratedCount - 5) more")
                    .font(.system(size: 9, weight: .medium))
            }
        }
        .foregroundStyle(Theme.tertiaryText)
    }
}
