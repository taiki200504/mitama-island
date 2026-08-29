import SwiftUI

/// The time, as split-flap cards.
///
/// The treatment is borrowed from the flip clocks people put on an idle Mac —
/// Fliqlo and its kin. Nothing is ported: a card, a seam across its middle and
/// a fold on change is the whole idea, and it is shorter to write than to
/// depend on.
///
/// Each digit is its own card, so only the digit that changed flips. A single
/// card for "09" would fold the hour every minute.
struct FlipClockView: View {
    let date: Date
    /// Height of one card. Everything else is derived, so the clock scales from
    /// one number.
    var cardHeight: CGFloat = 132

    private var digits: [Character] {
        Array(Self.formatter.string(from: date))
    }

    var body: some View {
        HStack(spacing: cardHeight * 0.06) {
            ForEach(Array(digits.enumerated()), id: \.offset) { index, character in
                if character == ":" {
                    Text(":")
                        .font(.islandMono(size: cardHeight * 0.42, weight: .semibold))
                        .foregroundStyle(V6Palette.paper.opacity(0.35))
                        .padding(.horizontal, cardHeight * 0.02)
                } else {
                    FlipCard(digit: character, height: cardHeight)
                }
            }
        }
    }

    /// Fixed 24-hour. A locale that writes "9:00 AM" would change the number of
    /// cards through the day and shift the whole clock sideways at noon.
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

private struct FlipCard: View {
    let digit: Character
    let height: CGFloat

    private var width: CGFloat { height * 0.72 }
    private var corner: CGFloat { height * 0.09 }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(V6Palette.paper.opacity(0.055))
                .overlay(
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .stroke(V6Palette.paper.opacity(0.10), lineWidth: 1)
                )

            Text(String(digit))
                .font(.islandMono(size: height * 0.62, weight: .semibold))
                .foregroundStyle(V6Palette.paper.opacity(0.94))
                .monospacedDigit()
                .id(digit)
                .transition(.asymmetric(
                    insertion: .modifier(
                        active: FoldEffect(degrees: -84, opacity: 0),
                        identity: FoldEffect(degrees: 0, opacity: 1)
                    ),
                    removal: .modifier(
                        active: FoldEffect(degrees: 84, opacity: 0),
                        identity: FoldEffect(degrees: 0, opacity: 1)
                    )
                ))

            // The seam. A flip clock is recognisable by the line the card folds
            // along, and without it these are just rounded rectangles.
            Rectangle()
                .fill(V6Palette.ink.opacity(0.55))
                .frame(height: 1)
        }
        .frame(width: width, height: height)
        .animation(.easeOut(duration: 0.28), value: digit)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}

/// Folds a digit around the card's seam.
private struct FoldEffect: ViewModifier, @MainActor Animatable {
    var degrees: Double
    var opacity: Double

    var animatableData: AnimatablePair<Double, Double> {
        get { .init(degrees, opacity) }
        set {
            degrees = newValue.first
            opacity = newValue.second
        }
    }

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .rotation3DEffect(.degrees(degrees), axis: (x: 1, y: 0, z: 0), anchor: .center, perspective: 0.7)
    }
}
