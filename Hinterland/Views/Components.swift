import SwiftUI
import UIKit

/// Small views shared across the app's screens, and the map pin colours that go with
/// `MapData`. Split out from `Theme` when the palette moved to `Shared` — the widget
/// needs the colours and the formatting, but none of this.
extension POICategory {
    /// Pin colours. After Dark keeps the map to the system's few signals rather than a
    /// colour per category: stages in their stage colour, medical in `signal`, water in
    /// `rain`, and everything else in cream, so the pins you need in a hurry stand out.
    var tint: Color {
        switch self {
        case .stage: return Theme.sodium
        case .medical: return Theme.signal
        case .water: return Theme.rain
        default: return Theme.ink
        }
    }
}

extension View {
    /// The festival's maps are bright daytime art. Graded for night — darker, less
    /// saturated, a `night` wash on top — so pins and labels are the brightest things on
    /// them.
    func nightGraded() -> some View {
        self
            .brightness(-0.35)
            .saturation(0.45)
            .contrast(1.08)
            .overlay(Theme.night.opacity(0.25))
    }
}

/// Stage name in its colour with its shape, used everywhere a set is listed. Set like the
/// design system's callsigns: uppercase, tracked, no pill behind it.
struct StageBadge: View {
    let stage: Stage
    var compact = false

    var body: some View {
        HStack(spacing: 5) {
            StageGlyph(stage: stage, size: compact ? 8 : 10)
            Text(stage.displayName.uppercased())
                .appFont(compact ? 10 : 11, weight: .bold)
                .tracking(1.4)
        }
        .foregroundStyle(stage.color)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(stage.displayName)
    }
}

/// The one-to-five fireflies you tap to rate a set you watched. Lit ones glow `sodium`,
/// because the rating is yours; the rest sit `unlit`.
///
/// Deliberately not a `Binding`: `Ratings` decides what a tap means — including that
/// tapping the firefly you already lit clears the rating — and a binding would put half
/// of that rule in the view.
struct StarRating: View {
    let stars: Int
    var size: CGFloat = 22
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(SetRating.scale), id: \.self) { value in
                let lit = value <= stars
                Button {
                    onSelect(value)
                } label: {
                    Circle()
                        .fill(lit ? Theme.sodium : Theme.unlit)
                        .frame(width: size * 0.64, height: size * 0.64)
                        .shadow(color: lit ? Theme.sodium.opacity(0.7) : .clear, radius: 5)
                        // Comfortable to hit with a drink in the other hand, in the dark.
                        .frame(minWidth: 40, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        // One control to VoiceOver rather than five buttons, each read as "Rate 3 stars"
        // with nothing saying which one is lit: swipe up or down to change it, the way a
        // slider works. Swiping down from one star is the same as tapping the star you
        // gave, so it clears the rating under the same rule.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your rating")
        .accessibilityValue(stars == 0 ? "Not rated" : "\(stars) of 5 stars")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                if stars < SetRating.scale.upperBound { onSelect(stars + 1) }
            case .decrement:
                if stars > 1 { onSelect(stars - 1) } else if stars == 1 { onSelect(1) }
            @unknown default:
                break
            }
        }
    }
}

/// A rating at a glance, for rows that list a set rather than ask about one: one lit
/// firefly and the number.
struct RatingBadge: View {
    let stars: Int
    var compact = false

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Theme.sodium)
                .frame(width: compact ? 6 : 7, height: compact ? 6 : 7)
                .shadow(color: Theme.sodium.opacity(0.7), radius: 3)
            Text("\(stars)")
                .appFont(compact ? 11 : 12, weight: .bold)
                .monospacedDigit()
        }
        .foregroundStyle(Theme.sodium)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.spokenLabel(stars: stars))
    }

    /// Also what a row that summarises itself for VoiceOver says in the badge's place.
    static func spokenLabel(stars: Int) -> String {
        "You rated this \(stars) out of 5"
    }
}

/// What everyone else gave a set. Deliberately not `sodium` and not a firefly: those
/// mean *your* rating, and a row that showed both alike would read as one number.
struct CrowdBadge: View {
    let rating: CrowdRating
    var compact = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "person.2.fill")
                .appFont(compact ? 9 : 10, weight: .semibold)
            Text(Format.rating(rating.average))
                .appFont(compact ? 11 : 12, weight: .bold)
                .monospacedDigit()
        }
        .foregroundStyle(Theme.crowd)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.spokenLabel(for: rating))
    }

    static func spokenLabel(for rating: CrowdRating) -> String {
        "Everyone rated this \(Format.rating(rating.average)) out of 5, "
            + "from \(rating.count) \(rating.count == 1 ? "person" : "people")"
    }
}

/// Bundled artist art, falling back to the remote URL for artists added by a schedule
/// refresh, and to initials when there is no art at all.
struct ArtistImage: View {
    let artist: Artist?
    var size: CGFloat?

    var body: some View {
        Group {
            if let asset = artist?.imageAsset, UIImage(named: asset) != nil {
                Image(asset).resizable().scaledToFill()
            } else if let remote = artist?.imageURL, let url = URL(string: remote) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipped()
    }

    private var placeholder: some View {
        ZStack {
            Theme.glass
            Text(initials)
                // Deliberately not scaled: this is lettering inside a fixed-size piece of
                // artwork, sized as a fraction of that box rather than as text to read.
                // Growing it with Dynamic Type would just overflow the thumbnail.
                .font(.custom(AppFontFace.marquee, fixedSize: (size ?? 44) * 0.5))
                .foregroundStyle(Theme.unlit)
        }
    }

    private var initials: String {
        let words = (artist?.name ?? "?").split(separator: " ").prefix(2)
        return words.compactMap { $0.first }.map(String.init).joined().uppercased()
    }
}

/// Dead air: what a screen says when there's nothing on it. A quiet callsign, the title
/// big and faint, and one sentence saying what will be there or what to do.
struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .appFont(28, weight: .semibold)
                .foregroundStyle(Theme.unlit)
                .accessibilityHidden(true)
            Text(title.uppercased())
                .marqueeFont(52)
                .foregroundStyle(Theme.inkFaint)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(message)
                .appFont(16)
                .foregroundStyle(Theme.inkMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 300)
        .padding(32)
        .accessibilityElement(children: .combine)
    }
}

/// Lays subviews out left to right, wrapping onto a new line when the next one won't fit.
///
/// The dietary filters used to sit in a horizontal `ScrollView`, which put Nut-free and
/// Sugar-free past the right edge with nothing on screen to suggest they were there —
/// while the vendor cards below went on showing "Nut-free" tags. Wrapping shows the whole
/// set at once, and it holds up as the chips grow with Dynamic Type, where no fixed number
/// of them per line would.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.replacingUnspecifiedDimensions().width
        let rows = rows(for: subviews, in: width)
        let height = rows.reduce(0) { $0 + $1.height }
            + lineSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, in: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var height: CGFloat = 0
    }

    private func rows(for subviews: Subviews, in width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        var x: CGFloat = 0
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            // Always keep at least one per line, or a chip wider than the container
            // would loop forever pushing itself onto a fresh line.
            if !current.indices.isEmpty, x + size.width > width {
                rows.append(current)
                current = Row()
                x = 0
            }
            current.indices.append(index)
            current.height = max(current.height, size.height)
            x += size.width + spacing
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
