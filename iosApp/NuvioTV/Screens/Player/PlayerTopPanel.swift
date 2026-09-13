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
    init<V: View>(@ViewBuilder content: () -> V) {
        self.content = AnyView(content())
    }
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
            LinearGradient(stops: [.init(color: .clear, location: 0),
                                   .init(color: .black.opacity(0.88), location: 0.36),
                                   .init(color: .black.opacity(0.97), location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 760)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            if shown {
                panel
                    .onAppear { DispatchQueue.main.async { focusedTab = tab } }
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .ignoresSafeArea()
        .onAppear {
            withAnimation(reduceMotion ? nil : PlayerChipStyle.animation) { shown = true }
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
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .focusSection()
        }
        .padding(24)
        .frame(width: 1640, height: 460, alignment: .topLeading)
        .padding(.horizontal, 24)
        .padding(.bottom, 60)
    }

    private var tabRow: some View {
        GlassEffectContainer(spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.md) {
                ForEach(tabs) { item in
                    Button(item.title) { tab = item }
                        .buttonStyle(.glass)
                        .font(Theme.Font.body)
                        .controlSize(.small)
                        .focused($focusedTab, equals: item)
                        .accessibilityIdentifier("player.panel.tab.\(item.rawValue)")
                        .accessibilityValue(Text(verbatim: item == tab ? "selected" : ""))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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

/// Short settings lists size to their content; long lists keep remote scrolling within the panel.
struct PlayerPanelScroll<Content: View>: View {
    var maximumHeight: CGFloat = 320
    var showsIndicators = false
    @ViewBuilder var content: () -> Content
    @State private var contentHeight: CGFloat = 120

    var body: some View {
        ScrollView(.vertical, showsIndicators: showsIndicators) {
            content()
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(8)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    if abs(contentHeight - height) > 0.5 { contentHeight = height }
                }
        }
        .frame(height: min(max(contentHeight, 1), maximumHeight))
        .scrollBounceBehavior(.basedOnSize)
    }
}
