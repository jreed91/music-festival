import SwiftUI
import UIKit

/// Small views shared across the app's screens, and the map pin colours that go with
/// `MapData`. Split out from `Theme` when the palette moved to `Shared` — the widget
/// needs the colours and the formatting, but none of this.
extension POICategory {
    /// Pin colours, kept bright enough to read as markers over both the illustration and
    /// satellite imagery.
    var tint: Color {
        switch self {
        case .stage: return Theme.accent
        case .entrance: return Color(red: 0.42, green: 0.82, blue: 0.70)
        case .gate: return Color(red: 0.55, green: 0.75, blue: 0.98)
        case .food: return Color(red: 0.45, green: 0.82, blue: 0.45)
        case .drink: return Color(red: 0.96, green: 0.55, blue: 0.78)
        case .water: return Color(red: 0.38, green: 0.84, blue: 0.92)
        case .restroom: return Color(red: 0.66, green: 0.74, blue: 0.86)
        case .merch: return Color(red: 0.84, green: 0.58, blue: 0.96)
        case .info: return Color(red: 0.92, green: 0.93, blue: 0.96)
        case .medical: return Theme.warning
        case .accessibility: return Color(red: 0.42, green: 0.66, blue: 0.98)
        case .shade: return Color(red: 0.88, green: 0.76, blue: 0.56)
        case .services: return Color(red: 0.95, green: 0.82, blue: 0.42)
        case .camping: return Color(red: 0.72, green: 0.55, blue: 0.96)
        case .parking: return Color(red: 0.62, green: 0.62, blue: 0.98)
        case .exit: return Color(red: 0.72, green: 0.78, blue: 0.70)
        }
    }
}

/// Stage name in its colour, used everywhere a set is listed.
struct StageBadge: View {
    let stage: Stage
    var compact = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: stage.symbol)
                .appFont(compact ? 9 : 10, weight: .semibold)
            Text(stage.displayName)
                .appFont(compact ? 10 : 11, weight: .semibold)
        }
        .foregroundStyle(stage.color)
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, compact ? 3 : 4)
        .background(stage.color.opacity(0.14), in: Capsule())
    }
}

/// The one-to-five stars you tap to rate a set you watched.
///
/// Deliberately not a `Binding`: `Ratings` decides what a tap means — including that
/// tapping the star you already gave clears the rating — and a binding would put half of
/// that rule in the view.
struct StarRating: View {
    let stars: Int
    var size: CGFloat = 22
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(SetRating.scale), id: \.self) { value in
                let filled = value <= stars
                Button {
                    onSelect(value)
                } label: {
                    Image(systemName: filled ? "star.fill" : "star")
                        .appFont(size, weight: .medium)
                        .foregroundStyle(filled ? Theme.accent : Theme.tertiaryText)
                        // Comfortable to hit with a drink in the other hand, in the dark.
                        .frame(minWidth: 40, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(value == stars
                                    ? "Clear rating"
                                    : "Rate \(value) star\(value == 1 ? "" : "s")")
            }
        }
    }
}

/// A rating at a glance, for rows that list a set rather than ask about one.
struct RatingBadge: View {
    let stars: Int
    var compact = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "star.fill")
                .appFont(compact ? 9 : 10, weight: .semibold)
            Text("\(stars)")
                .appFont(compact ? 10 : 11, weight: .semibold, design: .rounded)
        }
        .foregroundStyle(Theme.accent)
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, compact ? 3 : 4)
        .background(Theme.accent.opacity(0.14), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("You rated this \(stars) out of 5")
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
            Theme.surfaceRaised
            Text(initials)
                // Deliberately not scaled: this is lettering inside a fixed-size piece of
                // artwork, sized as a fraction of that box rather than as text to read.
                // Growing it with Dynamic Type would just overflow the thumbnail.
                .font(.system(size: (size ?? 44) * 0.34, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.tertiaryText)
        }
    }

    private var initials: String {
        let words = (artist?.name ?? "?").split(separator: " ").prefix(2)
        return words.compactMap { $0.first }.map(String.init).joined().uppercased()
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .appFont(40, weight: .light)
                .foregroundStyle(Theme.tertiaryText)
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 300)
        .padding(32)
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
