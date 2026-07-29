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
                .font(.system(size: compact ? 9 : 10, weight: .semibold))
            Text(stage.displayName)
                .font(.system(size: compact ? 10 : 11, weight: .semibold))
        }
        .foregroundStyle(stage.color)
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, compact ? 3 : 4)
        .background(stage.color.opacity(0.14), in: Capsule())
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
                .font(.system(size: 40, weight: .light))
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
