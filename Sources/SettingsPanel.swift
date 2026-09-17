import SwiftUI

/// The app's one settings screen — deliberately small and on the same faceplate language
/// as everything else, not a system Form/List that would suddenly look like a different
/// app. Two controls, both asked for directly: which edge the adjustments panel slides in
/// from, and how see-through it is.
struct SettingsPanel: View {
    @ObservedObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack {
                    Text("Einstellungen")
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .tracking(1.0)
                        .foregroundStyle(Brand.paper)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white.opacity(0.5))
                            .font(.title3)
                    }
                }
                .padding(.top, 4)

                PanelGroove()

                PanelLegend(text: "Menü-Richtung")
                HStack(spacing: 10) {
                    ForEach(PanelEdge.allCases) { edge in
                        Button {
                            settings.panelEdge = edge
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: edge.icon)
                                    .font(.title3)
                                Text(edge.label)
                                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                    .tracking(0.5)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(settings.panelEdge == edge ? Brand.rose.opacity(0.25) : Color.white.opacity(0.05))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(settings.panelEdge == edge ? Brand.rose : .white.opacity(0.12), lineWidth: 1)
                            )
                            .foregroundStyle(settings.panelEdge == edge ? Brand.rose : .white.opacity(0.75))
                        }
                    }
                }

                PanelGroove()

                PanelLegend(text: "Transparenz")
                VStack(spacing: 6) {
                    Slider(value: $settings.panelOpacity, in: 0.35...1.0)
                        .tint(Brand.rose)
                    HStack {
                        Text("Durchsichtig").font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(settings.panelOpacity * 100))%")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.primary.opacity(0.85))
                        Spacer()
                        Text("Blickdicht").font(.caption2).foregroundStyle(.secondary)
                    }
                }

                Text("Bei niedriger Transparenz bleibt der Sucher hinter dem Bedienfeld sichtbar — praktisch, wenn du beim Einstellen aufs Bild schauen willst statt aufs Panel.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            .padding()
        }
        .scrollContentBackground(.hidden)
        .background { FaceplateBackground() }
        .presentationDetents([.height(360)])
        .presentationDragIndicator(.visible)
    }
}
