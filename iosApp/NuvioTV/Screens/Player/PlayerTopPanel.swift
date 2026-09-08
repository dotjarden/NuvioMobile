import SwiftUI

enum PlayerPanelTab: String, CaseIterable, Identifiable {
    case info, subtitles, audio
    /// Shared playback controls; each engine supplies its supported actions.
    case playback
    var id: String { rawValue }

    var title: String {
        switch self {
        case .info: return String(localized: "Details")
        case .subtitles: return String(localized: "Subtitles")
        case .audio: return String(localized: "Audio")
        case .playback: return String(localized: "Playback")
        }
    }
}

/// Engine-supported content for the shared Playback tab.
struct PlayerPanelExtraTab {
    let content: AnyView
    init<V: View>(@ViewBuilder content: () -> V) { self.content = AnyView(content()) }
}

/// Shared bottom drawer for native, MPV, and Live TV playback. Select commits a tab;
/// navigation focus alone does not rebuild the content. Back closes the drawer first.
struct PlayerTopPanel: View {
    @ObservedObject var model: PlayerTopPanelModel
    var extraTab: PlayerPanelExtraTab? = nil
    @State private var tab: PlayerPanelTab
    init(model: PlayerTopPanelModel, extraTab: PlayerPanelExtraTab? = nil, initialTab: PlayerPanelTab = .playback) {
        self.model = model
        self.extraTab = extraTab
        _tab = State(initialValue: initialTab)
    }
    @State private var shown = false
    @FocusState private var focusedTab: PlayerPanelTab?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottom) {
            // Full-screen clear layer so the hosting view fills the window (focus + gestures).
            Color.clear.ignoresSafeArea()
            if shown {
                panel
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .onAppear {
            withAnimation(reduceMotion ? nil : PlayerChipStyle.animation) { shown = true }
            focusedTab = tab
        }
        .onAppear { model.onPresentation?(); model.setDetailsVisible(tab == .info) }
        .onChange(of: tab) { _, value in model.setDetailsVisible(value == .info) }
        .onDisappear { model.setDetailsVisible(false) }
        .onExitCommand { model.onClose?() }
    }

    private var panel: some View {
        VStack(spacing: Theme.Spacing.md) {
            tabRow
                .focusSection()
            content
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(height: 440, alignment: .top)
                .clipped()
                .focusSection()
        }
        .padding(.horizontal, Theme.Spacing.screen)
        .padding(.top, Theme.Spacing.xl)
        .padding(.bottom, Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(Color(white: 0.055).opacity(0.98),
                    in: UnevenRoundedRectangle(topLeadingRadius: Theme.Radius.hero, topTrailingRadius: Theme.Radius.hero))
        .overlay(alignment: .top) { Capsule().fill(.white.opacity(0.2)).frame(width: 70, height: 5).padding(.top, 10).allowsHitTesting(false) }

    }

    private var tabRow: some View {
        HStack(spacing: Theme.Spacing.md) {
            ForEach(tabs) { item in
                Button(item.title) { tab = item }
                    .font(Theme.Font.sectionTitle)
                    .focused($focusedTab, equals: item)
                    .accessibilityIdentifier("player.panel.tab.\(item.rawValue)")
                    .accessibilityValue(Text(verbatim: item == tab ? "selected" : ""))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tabs: [PlayerPanelTab] {
        [.audio, .subtitles, .playback, .info]
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .info:
            PlayerInfoTab(info: model.info)
        case .subtitles:
            PlayerSubtitlesTab(model: model)
        case .audio:
            PlayerAudioTab(model: model)
        case .playback:
            if let extraTab { extraTab.content } else { Text("Playback controls are available below the video.") }
        }
    }
}

/// One checkmark row of the Subtitles / Audio tab. DEFAULT tvOS button style on purpose: it draws
/// the white focus platter (the classic panel's focused-row look) and recolors the label itself.
/// `.borderless` would only brighten the label — invisible on an already-bright label (BUG-58
/// lesson) — and no explicit foreground color is set here so the platter's dark text wins.
struct PlayerPanelOptionRow: View {
    let option: PlayerPanelOption
    let identifierPrefix: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.md) {
                Image(systemName: "checkmark")
                    .font(Theme.Font.body.weight(.semibold))
                    .opacity(option.isSelected ? 1 : 0)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title)
                        .font(Theme.Font.body)
                        .lineLimit(1)
                    if let detail = option.detail {
                        Text(detail)
                            .font(Theme.Font.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("\(identifierPrefix).\(option.id)")
        .accessibilityValue(Text(verbatim: option.isSelected ? "selected" : ""))
    }
}

/// Small uppercase column/section caption ("LANGUAGE", "SPEAKERS & HEADPHONES") — the classic
/// tvOS panel's column headers.
struct PlayerPanelSectionCaption: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(Theme.Font.caption.weight(.semibold))
            .foregroundStyle(Theme.Palette.textSecondary)
            .padding(.bottom, Theme.Spacing.xxs)
    }
}
