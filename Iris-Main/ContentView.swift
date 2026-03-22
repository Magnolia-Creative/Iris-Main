//
//  ContentView.swift
//  Iris-Main
//
//  Created by Abdur-Rahman Rana on 2026-03-13.
//

import SwiftUI

struct ContentView: View {
    private let spacingTokens: [Spacing] = [.sp0, .sp1, .sp2, .sp3, .sp4, .sp5, .sp6, .sp7, .sp8, .sp9, .sp10]

    var body: some View {
        ZStack {
            Color.ds.bg
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: .spacing(.sp8)) {
                    heroSection
                    typographySection
                    colorSection
                    spacingSection
                    buttonSection
                    demoSection
                }
                .padding(.horizontal, .sp6)
                .padding(.vertical, .sp8)
            }
        }
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp4)) {
            Text("Iris Design System")
                .typography(.title)
                .foregroundStyle(Color.ds.text)

            Text("A single screen to validate the current typography, palette, spacing scale, and button treatments in realistic UI.")
                .typography(.body)
                .foregroundStyle(Color.ds.textMuted)

            HStack(spacing: .spacing(.sp3)) {
                pill(text: "5 type styles", foreground: Color.ds.text, background: Color.ds.surface)
                pill(text: "6 core colors", foreground: .white, background: Color.ds.accentBg)
                pill(text: "3 button variants", foreground: Color.ds.accentFg, background: Color.clear, border: Color.ds.accentFg)
            }
        }
    }

    private var typographySection: some View {
        sectionCard(title: "Typography", subtitle: "Each text token rendered with its intended sizing, line height, and tracking.") {
            VStack(alignment: .leading, spacing: .spacing(.sp5)) {
                typographyRow(name: "title", style: .title, sample: "Build calm, polished interfaces.")
                typographyRow(name: "heading", style: .heading, sample: "Section Heading This is a heading for a section")
                typographyRow(name: "body", style: .body, sample: "Body copy should feel open, readable, and neutral across longer passages.")
                typographyRow(name: "action", style: .action, sample: "BUTTON LABEL")
                typographyRow(name: "bodySmall", style: .bodySmall, sample: "Supporting metadata and compact annotations.")
            }
        }
    }

    private var colorSection: some View {
        sectionCard(title: "Color", subtitle: "Core semantic tokens used for text, surfaces, borders, and actions.") {
            VStack(alignment: .leading, spacing: .spacing(.sp4)) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: .spacing(.sp4)) {
                    colorSwatch(name: "text", color: Color.ds.text)
                    colorSwatch(name: "textMuted", color: Color.ds.textMuted)
                    colorSwatch(name: "accentBg", color: Color.ds.accentBg)
                    colorSwatch(name: "accentFg", color: Color.ds.accentFg)
                    colorSwatch(name: "surface", color: Color.ds.surface)
                    colorSwatch(name: "border", color: Color.ds.border)
                    colorSwatch(name: "danger", color: Color.ds.danger)
                    colorSwatch(name: "bg", color: Color.ds.bg, border: Color.ds.border)
                }
            }
        }
    }

    private var spacingSection: some View {
        sectionCard(title: "Spacing", subtitle: "Scale preview from `sp0` through `sp10` to verify rhythm and density.") {
            VStack(alignment: .leading, spacing: .spacing(.sp3)) {
                ForEach(spacingTokens, id: \.self) { spacing in
                    HStack(spacing: .spacing(.sp3)) {
                        Text(label(for: spacing))
                            .typography(.bodySmall)
                            .foregroundStyle(Color.ds.textMuted)
                            .frame(width: 48, alignment: .leading)

                        RoundedRectangle(cornerRadius: .spacing(.sp1))
                            .fill(Color.ds.accentBg)
                            .frame(width: spacing.value == 0 ? 1 : spacing.value, height: 12)

                        Text("\(Int(spacing.value))pt")
                            .typography(.bodySmall)
                            .foregroundStyle(Color.ds.text)
                    }
                }
            }
        }
    }

    private var buttonSection: some View {
        sectionCard(title: "Buttons", subtitle: "Current button styles with matching type and spacing rules.") {
            VStack(alignment: .leading, spacing: .spacing(.sp4)) {
                HStack(spacing: .spacing(.sp3)) {
                    Button("Primary") {}
                        .buttonStyle(.primary)

                    Button("Secondary") {}
                        .buttonStyle(.secondary)

                    Button("Tertiary") {}
                        .buttonStyle(.tertiary)
                }

                HStack(spacing: .spacing(.sp3)) {
                    Button(action: {}) {
                        Label("Share Link", systemImage: "paperplane.fill")
                    }
                    .buttonStyle(.primary)

                    Button(action: {}) {
                        Label("Archive", systemImage: "tray")
                    }
                    .buttonStyle(.secondary)
                }
            }
        }
    }

    private var demoSection: some View {
        sectionCard(title: "Demo UI", subtitle: "A compact composition that uses the tokens together instead of showing them in isolation.") {
            VStack(alignment: .leading, spacing: .spacing(.sp5)) {
                HStack(alignment: .top, spacing: .spacing(.sp4)) {
                    RoundedRectangle(cornerRadius: .spacing(.sp3))
                        .fill(Color.ds.accentBg.opacity(0.18))
                        .frame(width: 56, height: 56)
                        .overlay {
                            Image(systemName: "sparkles")
                                .font(.system(size: 22, weight: .medium))
                                .foregroundStyle(Color.ds.accentFg)
                        }

                    VStack(alignment: .leading, spacing: .spacing(.sp2)) {
                        Text("Spring Campaign")
                            .typography(.heading)
                            .foregroundStyle(Color.ds.text)

                        Text("Launch assets are nearly ready. Review the final copy, approve the visual set, and schedule publishing.")
                            .typography(.body)
                            .foregroundStyle(Color.ds.textMuted)
                    }
                }

                HStack(spacing: .spacing(.sp3)) {
                    statCard(value: "84%", label: "Approved")
                    statCard(value: "12", label: "Assets")
                    statCard(value: "2", label: "Risks", tint: Color.ds.danger)
                }

                Divider()
                    .overlay(Color.ds.border)

                HStack {
                    VStack(alignment: .leading, spacing: .spacing(.sp1)) {
                        Text("Next review")
                            .typography(.bodySmall)
                            .foregroundStyle(Color.ds.textMuted)

                        Text("Today, 4:30 PM")
                            .typography(.body)
                            .foregroundStyle(Color.ds.text)
                    }

                    Spacer()

                    HStack(spacing: .spacing(.sp3)) {
                        Button("Later") {}
                            .buttonStyle(.secondary)

                        Button("Approve") {}
                            .buttonStyle(.primary)
                    }
                }
            }
        }
    }

    private func sectionCard<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: .spacing(.sp5)) {
            VStack(alignment: .leading, spacing: .spacing(.sp2)) {
                Text(title)
                    .typography(.heading)
                    .foregroundStyle(Color.ds.text)

                Text(subtitle)
                    .typography(.bodySmall)
                    .foregroundStyle(Color.ds.textMuted)
            }

            content()
        }
        .padding(.sp6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.ds.surface)
        .overlay(
            RoundedRectangle(cornerRadius: .spacing(.sp4))
                .stroke(Color.ds.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp4)))
    }

    private func typographyRow(name: String, style: Typography, sample: String) -> some View {
        VStack(alignment: .leading, spacing: .spacing(.sp1)) {
            Text(name)
                .typography(.bodySmall)
                .foregroundStyle(Color.ds.textMuted)

            Text(sample)
                .typography(style)
                .foregroundStyle(Color.ds.text)
        }
    }

    private func colorSwatch(name: String, color: Color, border: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: .spacing(.sp2)) {
            RoundedRectangle(cornerRadius: .spacing(.sp3))
                .fill(color)
                .frame(height: 72)
                .overlay {
                    if let border {
                        RoundedRectangle(cornerRadius: .spacing(.sp3))
                            .stroke(border, lineWidth: 1)
                    }
                }

            Text(name)
                .typography(.bodySmall)
                .foregroundStyle(Color.ds.text)
        }
    }

    private func pill(text: String, foreground: Color, background: Color, border: Color? = nil) -> some View {
        Text(text)
            .typography(.bodySmall)
            .foregroundStyle(foreground)
            .padding(.horizontal, .sp3)
            .padding(.vertical, .sp2)
            .background(background)
            .overlay {
                if let border {
                    Capsule()
                        .stroke(border, lineWidth: 1)
                }
            }
            .clipShape(Capsule())
    }

    private func statCard(value: String, label: String, tint: Color = Color.ds.accentFg) -> some View {
        VStack(alignment: .leading, spacing: .spacing(.sp1)) {
            Text(value)
                .typography(.heading)
                .foregroundStyle(tint)

            Text(label)
                .typography(.bodySmall)
                .foregroundStyle(Color.ds.textMuted)
        }
        .padding(.sp4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.ds.bg)
        .overlay(
            RoundedRectangle(cornerRadius: .spacing(.sp3))
                .stroke(Color.ds.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp3)))
    }

    private func label(for spacing: Spacing) -> String {
        switch spacing {
        case .sp0: return "sp0"
        case .sp1: return "sp1"
        case .sp2: return "sp2"
        case .sp3: return "sp3"
        case .sp4: return "sp4"
        case .sp5: return "sp5"
        case .sp6: return "sp6"
        case .sp7: return "sp7"
        case .sp8: return "sp8"
        case .sp9: return "sp9"
        case .sp10: return "sp10"
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
