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

/// Dead air: what a screen says when there's nothing on it. A quiet callsign saying what's
/// missing, DEAD AIR big and faint, and one sentence saying what will be there or what to do.
struct EmptyStateView: View {
    let title: String
    let message: String
    /// The big words. Dead air, unless something is on its way.
    var headline = "Dead air"

    var body: some View {
        VStack(spacing: 10) {
            Text(title.uppercased())
                .appFont(13, weight: .bold)
                .tracking(2.4)
                .foregroundStyle(Theme.inkFaint)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(headline.uppercased())
                .marqueeFont(56)
                .foregroundStyle(Theme.inkFaint)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                // Set dressing: the callsign and the sentence already say it.
                .accessibilityHidden(true)
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

/// An empty state that is the whole screen: dead air in the middle and the corn along the
/// foot. It scrolls, so at the largest text sizes the sentence runs on rather than being
/// cut off at the bottom.
struct DeadAirScreen: View {
    let title: String
    let message: String
    var headline = "Dead air"

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 48)
                    EmptyStateView(title: title, message: message, headline: headline)
                    Spacer(minLength: 48)
                    Horizon()
                }
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
        }
        .background(Theme.night)
    }
}

/// How a section opens on a screen with more than one: a quiet callsign over a 2pt `ink`
/// rule, with an optional count on the right ("3 OF 9 STANDS").
struct SectionHeading: View {
    let title: String
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title.uppercased())
                .appFont(13, weight: .bold)
                .tracking(2.4)
                .foregroundStyle(Theme.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if let detail {
                Text(detail.uppercased())
                    .appFont(11, weight: .bold)
                    .tracking(1.6)
                    .foregroundStyle(Theme.inkFaint)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 24)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.ink).frame(height: 2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Buttons shaped like a car radio's lit buttons: the GlowButton of the design system.
///
/// `.primary` is the one `sodium`-outlined button a screen gets, and lights solid while
/// it's pressed, the way the hardware does. `.on` is a toggle that's on (In my lineup).
/// `.quiet` is everything else: Directions, Apple Maps, Refresh. Works on `Link` and
/// `ShareLink` as well as `Button`. Labels wrap rather than truncate.
struct GlowButtonStyle: ButtonStyle {
    enum Kind { case primary, on, quiet }

    var kind: Kind

    init(_ kind: Kind = .primary) {
        self.kind = kind
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .appFont(15, weight: .bold)
            .tracking(2)
            .textCase(.uppercase)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(textColor(pressed: configuration.isPressed))
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .frame(minHeight: 48)
            .background(fill(pressed: configuration.isPressed),
                        in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .strokeBorder(kind == .quiet ? Theme.hairline : Theme.sodium, lineWidth: 1.5))
            .shadow(color: kind == .quiet ? .clear : Theme.sodium.opacity(0.7), radius: 5)
            .opacity(kind == .quiet && configuration.isPressed ? 0.6 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 6))
    }

    private func isLit(pressed: Bool) -> Bool {
        kind == .on || (kind == .primary && pressed)
    }

    private func textColor(pressed: Bool) -> Color {
        if isLit(pressed: pressed) { return Theme.onSodium }
        return kind == .quiet ? Theme.ink : Theme.sodium
    }

    private func fill(pressed: Bool) -> Color {
        if isLit(pressed: pressed) { return Theme.sodium }
        return kind == .quiet ? Color.clear : Theme.glass
    }
}

/// A switch drawn as a lit hardware rocker: a `glass` slot whose square key slides across
/// and lights `sodium` when the setting is on, since a setting you turned on is yours.
/// The label sits to its left in `ink` and wraps.
///
/// VoiceOver gets a plain system switch in its place, so it's read and flipped exactly as
/// every other switch on the phone.
struct GlowToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(alignment: .center, spacing: 14) {
                configuration.label
                    .appFont(17, weight: .semibold)
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                GlowSwitch(isOn: configuration.isOn)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) {
                configuration.label
            }
            .toggleStyle(.switch)
        }
    }
}

private struct GlowSwitch: View {
    let isOn: Bool

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Theme.glass)
            RoundedRectangle(cornerRadius: 3)
                .fill(isOn ? Theme.sodium : Theme.unlit)
                .frame(width: 22, height: 22)
                .shadow(color: isOn ? Theme.sodium.opacity(0.7) : .clear, radius: 5)
                .padding(4)
        }
        .frame(width: 58, height: 30)
        .overlay(RoundedRectangle(cornerRadius: 6)
            .strokeBorder(isOn ? Theme.sodium : Theme.hairline, lineWidth: 1.5))
        .animation(.snappy(duration: 0.18), value: isOn)
    }
}

/// The search box, set into the page under the title rather than up in the navigation
/// bar, where iOS draws its own rounded grey field: a square `nightRaised` field with a
/// hairline edge that turns `ink` while you type.
struct SearchField: View {
    let prompt: String
    @Binding var text: String

    @FocusState private var isFocused: Bool

    /// Written out because the private focus state would otherwise leave the synthesized
    /// initializer private to this file.
    init(prompt: String, text: Binding<String>) {
        self.prompt = prompt
        _text = text
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .appFont(15, weight: .semibold)
                .foregroundStyle(Theme.inkFaint)
                .accessibilityHidden(true)
            TextField(prompt, text: $text,
                      prompt: Text(prompt).foregroundStyle(Theme.inkFaint))
                .appFont(17)
                .foregroundStyle(Theme.ink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($isFocused)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark")
                        .appFont(13, weight: .bold)
                        .foregroundStyle(Theme.inkMuted)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 12)
        .frame(minHeight: 44)
        .background(Theme.nightRaised)
        .overlay(Rectangle().strokeBorder(isFocused ? Theme.ink : Theme.hairline, lineWidth: 1))
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
