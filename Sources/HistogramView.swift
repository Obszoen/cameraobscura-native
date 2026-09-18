import SwiftUI

/// A small live luminance histogram bar chart — asked for directly ("Histogramm-Overlay
/// statt blind auf Belichtung zu vertrauen"), the same trust-but-verify instinct behind
/// the composition coach's real distance callouts.
struct HistogramView: View {
    let bins: [Double] // 0...1, normalized to the tallest bin

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .bottom, spacing: 1.5) {
                ForEach(bins.indices, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Brand.skyBlue.opacity(0.85))
                        .frame(height: max(2, geo.size.height * bins[i]))
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
}

/// A small "?" that shows a short explanation on tap — asked for directly, for the parts
/// of the UI (Composition Coach, Tonwerte) that only got a one-time onboarding tip and
/// nothing since. `.popover` (not a full sheet) so it stays light for a one-liner.
struct HelpButton: View {
    let text: String
    @State private var showing = false

    var body: some View {
        Button {
            showing = true
        } label: {
            Image(systemName: "questionmark.circle")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
        }
        .popover(isPresented: $showing) {
            Text(text)
                .font(.caption)
                .padding(12)
                .frame(maxWidth: 240)
                .presentationCompactAdaptation(.popover)
        }
    }
}

/// Shown once, ever, on first launch — asked for directly, and matches the app's own
/// marketing claim: no location/metadata gets attached without being asked.
struct PrivacyNoteSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 36))
                .foregroundStyle(Brand.mint)
            Text("Kurz und ehrlich")
                .font(.system(size: 18, weight: .bold, design: .serif))
                .foregroundStyle(Brand.paper)
            Text("CameraObscura hängt deinen Fotos keinen Standort und keine zusätzlichen Metadaten an, ohne dass du danach gefragt wirst. Alles bleibt lokal auf deinem Gerät — nichts geht an einen Server von uns.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.75))
                .padding(.horizontal, 20)
            Button("Verstanden") { dismiss() }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Brand.rose, in: Capsule())
                .foregroundStyle(Brand.ground)
                .padding(.horizontal, 40)
        }
        .padding(.vertical, 30)
        .presentationDetents([.height(320)])
        .background { FaceplateBackground() }
    }
}
