import SwiftUI
import AVKit
import Combine

/// The channel the hero describes. Only the hero observes it, so moving focus between cards
/// redraws the hero alone instead of the whole screen of rows.
@MainActor private final class LiveTVFeatured: ObservableObject {
    @Published var channel: LiveTVChannel?
}

struct LiveTVView: View {
    @StateObject private var store: LiveTVStore
    @StateObject private var featured = LiveTVFeatured()
    @State private var query = ""
    @State private var guideMode = false
    @State private var group = LiveTVView.allChannels
    @State private var showingSources = false
    @State private var playing: LiveTVChannel?
    @State private var selectedProgramme: LiveTVProgramme?
    /// Progress bars and the guide's now line advance once a minute from this single clock.
    @State private var now = Date()
    /// Back from the rows or guide jumps to the filters first, instead of many Up presses.
    @FocusState private var toolbarFocused: Bool
    init(profile: String) { _store = StateObject(wrappedValue: LiveTVStore(profile: profile)) }

    private static let allChannels = "All channels"
    private static let favorites = "Favorites"
    private static let recent = "Recent"
    private let clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var visibleChannels: [LiveTVChannel] {
        let base: [LiveTVChannel]
        switch group {
        case Self.allChannels: base = store.channels
        case Self.favorites: base = store.favoriteChannels
        case Self.recent: base = store.recentChannels
        default: base = store.channelsByGroup[group] ?? []
        }
        return query.isEmpty ? base : base.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }
    /// Unfiltered browsing shows rows (Favorites, Recent, then one per category); a category or
    /// search shows a grid of matches.
    private var showsShelves: Bool { group == Self.allChannels && query.isEmpty }
    private var shelves: [(title: String, channels: [LiveTVChannel])] {
        var rows: [(title: String, channels: [LiveTVChannel])] = []
        let favorites = store.favoriteChannels
        if !favorites.isEmpty { rows.append(("Favorites", favorites)) }
        let recent = store.recentChannels
        if !recent.isEmpty { rows.append(("Recently watched", recent)) }
        for name in store.groups { if let channels = store.channelsByGroup[name] { rows.append((name, channels)) } }
        return rows
    }

    var body: some View {
        let visible = visibleChannels
        NavigationStack {
            ZStack(alignment: .top) {
                Theme.Palette.background.ignoresSafeArea()
                LinearGradient(colors: [Theme.Palette.accent.opacity(0.22), .clear], startPoint: .top, endPoint: .center)
                    .ignoresSafeArea().allowsHitTesting(false)
                if store.sources.isEmpty {
                    ScrollView { emptyState.padding(Theme.Spacing.screen) }
                        .reportsScrollToTabBar(tab: "Live TV")
                        .railMenuReveal()
                } else {
                    // The hero and filters stay pinned so the hero keeps describing the focused card
                    // while the rows scroll beneath it (the Stage Home pattern).
                    VStack(alignment: .leading, spacing: 20) {
                        if guideMode {
                            Text("Live TV").font(.title2.bold())
                        } else {
                            LiveTVHero(store: store, featured: featured, now: now)
                        }
                        toolbar(count: visible.count)
                        status
                        // Clipped so rows never draw over the pinned header; the negative margin
                        // keeps room at the screen edges for the focused card's lift.
                        ScrollView {
                            content(visible).padding(.vertical, 24).padding(.horizontal, Theme.Spacing.screen)
                        }
                        // Exit commands bubble from the focused card, so this only runs inside the rows.
                        .onExitCommand { toolbarFocused = true }
                        .padding(.horizontal, -Theme.Spacing.screen)
                        .reportsScrollToTabBar(tab: "Live TV")
                    }
                    .padding([.horizontal, .top], Theme.Spacing.screen)
                    .railMenuReveal()
                }
            }
        }
        .task { await store.start() }
        .onReceive(clock) { now = $0 }
        .fullScreenCover(isPresented: $showingSources) { LiveTVSourcesView(store: store) }
        .fullScreenCover(item: $playing) { channel in
            LiveTVPlayerView(store: store, initialChannel: channel, channels: visible, onShowGuide: { guideMode = true })
        }
        .fullScreenCover(item: $selectedProgramme) { programme in
            LiveTVProgrammeDetail(programme: programme,
                                  channel: store.channels.first { $0.guideID == programme.channelID },
                                  onWatch: { channel in selectedProgramme = nil; play(channel) },
                                  onClose: { selectedProgramme = nil })
        }
    }

    @ViewBuilder private func content(_ visible: [LiveTVChannel]) -> some View {
        if guideMode {
            LiveTVGuideView(store: store, channels: visible, now: now, onPlay: play, onProgramme: { selectedProgramme = $0 })
        } else if visible.isEmpty && !store.loading {
            ContentUnavailableView("No matching channels", systemImage: "tv", description: Text("Try another category or search, or check your source connection."))
        } else if showsShelves {
            LazyVStack(alignment: .leading, spacing: Theme.Spacing.sectionGap) {
                ForEach(shelves, id: \.title) { shelf in shelfRow(shelf.title, shelf.channels) }
            }
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: LiveTVChannelCard.width), spacing: Theme.Spacing.rowGap)], spacing: 40) {
                ForEach(visible) { channel in card(channel) }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Your channels belong here", systemImage: "tv")
        } description: { Text("Connect an M3U playlist or Xtream provider to watch Live TV.") }
        actions: { Button("Add a source") { showingSources = true }.buttonStyle(.glassProminent) }
            .frame(maxWidth: .infinity, minHeight: 700)
    }

    private func toolbar(count: Int) -> some View {
        HStack(spacing: 24) {
            HStack(spacing: 0) {
                modeButton("On Now", systemImage: "square.grid.2x2", selected: !guideMode) { guideMode = false }
                    .focused($toolbarFocused)
                modeButton("Guide", systemImage: "calendar.day.timeline.left", selected: guideMode) { guideMode = true }
            }
            TVSelectionMenu(title: "Category", value: group, options: [Self.allChannels, Self.favorites, Self.recent] + store.groups) { group = $0 }
            TextField("Search channels", text: $query).frame(minWidth: 240, maxWidth: 520)
            Spacer(minLength: 0)
            // Loading sits here, in place of the count, so the rows below never jump.
            if store.loading {
                HStack(spacing: 12) { ProgressView(); Text("Updating…") }
                    .font(.caption).foregroundStyle(.secondary).fixedSize()
            } else {
                Text(count == 1 ? "1 channel" : "\(count) channels")
                    .font(.caption).foregroundStyle(.secondary).fixedSize()
            }
            Button { Task { await store.refresh() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                .labelStyle(.iconOnly).disabled(store.loading).accessibilityLabel("Refresh")
            Button { showingSources = true } label: { Label("Sources", systemImage: "antenna.radiowaves.left.and.right") }
        }
        .buttonStyle(.glass)
        .focusSection()
    }

    @ViewBuilder private func modeButton(_ title: String, systemImage: String, selected: Bool, action: @escaping () -> Void) -> some View {
        let button = Button(action: action) { Label(title, systemImage: systemImage).fixedSize() }
            .accessibilityValue(selected ? "selected" : "")
        if selected { button.buttonStyle(.glassProminent).tint(Theme.Palette.accent) } else { button.buttonStyle(.glass) }
    }

    @ViewBuilder private var status: some View {
        if let error = store.error {
            Label(error, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.secondary)
                .lineLimit(2)
                .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
    }

    private func shelfRow(_ title: String, _ channels: [LiveTVChannel]) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(title).font(.title3.bold())
                Text("\(channels.count)").font(.callout).foregroundStyle(.secondary)
            }
            ScrollView(.horizontal) {
                LazyHStack(spacing: Theme.Spacing.rowGap) {
                    ForEach(channels) { channel in card(channel) }
                }.padding(.vertical, 20)
            }.scrollClipDisabled()
        }.focusSection()
    }

    private func card(_ channel: LiveTVChannel) -> some View {
        LiveTVCardButton(channel: channel, isFavorite: store.favorites.contains(channel.id),
                         programme: store.nowAndNext(for: channel, at: now).now, now: now, featured: featured,
                         onPlay: { play(channel) }, onToggleFavorite: { store.toggleFavorite(channel) })
            .equatable()
    }

    private func play(_ channel: LiveTVChannel) {
        featured.channel = channel
        playing = channel
    }
}

/// One focusable channel card. Equatable on what it draws, so a store update (a favorite, a
/// guide refresh) only redraws the cards it changes. Focus is reported to `featured` without
/// observing it.
private struct LiveTVCardButton: View, Equatable {
    let channel: LiveTVChannel
    let isFavorite: Bool
    let programme: LiveTVProgramme?
    let now: Date
    let featured: LiveTVFeatured
    let onPlay: () -> Void
    let onToggleFavorite: () -> Void
    @FocusState private var focused: Bool

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.channel.id == rhs.channel.id && lhs.isFavorite == rhs.isFavorite && lhs.programme == rhs.programme && lhs.now == rhs.now
    }

    var body: some View {
        Button(action: onPlay) {
            LiveTVChannelCard(channel: channel, isFavorite: isFavorite, programme: programme, now: now)
        }
        .buttonStyle(.card)
        .focused($focused)
        .onChange(of: focused) { _, isFocused in if isFocused { featured.channel = channel } }
        .contextMenu {
            Button(action: onToggleFavorite) { Label(isFavorite ? "Remove favorite" : "Add favorite", systemImage: "star") }
        }
    }
}

/// The large summary of the focused (or last watched) channel: what is on now and what is next.
private struct LiveTVHero: View {
    @ObservedObject var store: LiveTVStore
    @ObservedObject var featured: LiveTVFeatured
    let now: Date
    private var channel: LiveTVChannel? { featured.channel ?? store.recentChannels.first ?? store.channels.first }
    var body: some View {
        HStack(alignment: .center, spacing: 48) {
            if let channel {
                let (current, next) = store.nowAndNext(for: channel, at: now)
                LiveTVLogo(channel: channel)
                    .frame(width: 280, height: 180)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 24))
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 16) {
                        LiveTVBadge()
                        if store.favorites.contains(channel.id) { Image(systemName: "star.fill").foregroundStyle(.yellow) }
                        Text(channel.group.isEmpty ? "Live television" : channel.group).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Text(channel.name).font(.title2.bold()).lineLimit(1)
                    if let current {
                        Text(current.title).font(.title3).lineLimit(1)
                        HStack(spacing: 16) {
                            ProgressView(value: now.timeIntervalSince(current.start), total: current.end.timeIntervalSince(current.start))
                                .tint(Theme.Palette.accent).frame(width: 360)
                            Text("\(current.start.formatted(date: .omitted, time: .shortened)) – \(current.end.formatted(date: .omitted, time: .shortened))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if !current.summary.isEmpty {
                            Text(current.summary).font(.callout).foregroundStyle(.secondary).lineLimit(1).frame(maxWidth: 1000, alignment: .leading)
                        }
                    } else {
                        Text("No programme information").font(.title3).foregroundStyle(.secondary)
                    }
                    if let next {
                        Text("Up next at \(next.start.formatted(date: .omitted, time: .shortened)): \(next.title)")
                            .font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(height: 330, alignment: .center)
        .clipped()
        .accessibilityElement(children: .combine)
    }
}

private struct LiveTVChannelCard: View {
    static let width: CGFloat = 400
    let channel: LiveTVChannel
    let isFavorite: Bool
    let programme: LiveTVProgramme?
    let now: Date
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                Color.white.opacity(0.06)
                LiveTVLogo(channel: channel).padding(28)
                HStack {
                    LiveTVBadge()
                    Spacer()
                    if isFavorite { Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow) }
                }.padding(14)
            }
            .frame(height: 170)
            VStack(alignment: .leading, spacing: 6) {
                Text(channel.name).font(.headline).lineLimit(1)
                Text(programme?.title ?? (channel.group.isEmpty ? "Watch live" : channel.group))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if let programme {
                    ProgressView(value: now.timeIntervalSince(programme.start), total: programme.end.timeIntervalSince(programme.start))
                        .tint(Theme.Palette.accent).padding(.top, 4)
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
            .background(Theme.Palette.surface)
        }
        .frame(width: Self.width)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(programme.map { "\(channel.name), \($0.title)" } ?? channel.name)
    }
}

struct LiveTVLogo: View {
    let channel: LiveTVChannel
    private var initials: String {
        let words = channel.name.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        return String(words.prefix(2).compactMap(\.first)).uppercased()
    }
    var body: some View {
        if let logo = channel.logo {
            // Decoded at card size: provider logos are often large PNGs, and a row decodes many.
            CachedAsyncImage(string: logo.absoluteString, contentMode: .fit, decodeSize: .points(width: 280, height: 180)) {
                placeholder
            }
            .accessibilityHidden(true)
        } else {
            placeholder
        }
    }
    private var placeholder: some View {
        Text(initials)
            .font(.system(size: 54, weight: .bold, design: .rounded))
            .minimumScaleFactor(0.3)
            .foregroundStyle(.white.opacity(0.7))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct LiveTVBadge: View {
    var body: some View {
        Text("LIVE").font(.caption2.bold()).padding(.horizontal, 10).padding(.vertical, 4)
            .background(Color.red.opacity(0.85), in: Capsule()).foregroundStyle(.white)
    }
}

private struct LiveTVProgrammeDetail: View {
    let programme: LiveTVProgramme
    let channel: LiveTVChannel?
    let onWatch: (LiveTVChannel) -> Void
    let onClose: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 60) {
            if let channel {
                LiveTVLogo(channel: channel).frame(width: 300, height: 200)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 24))
            }
            VStack(alignment: .leading, spacing: 24) {
                if let channel { Text(channel.name).font(.callout).foregroundStyle(.secondary) }
                Text(programme.title).font(.largeTitle.bold())
                Text("\(programme.start.formatted(date: .abbreviated, time: .shortened)) – \(programme.end.formatted(date: .omitted, time: .shortened))").foregroundStyle(.secondary)
                if !programme.summary.isEmpty { Text(programme.summary).font(.body).frame(maxWidth: 1100, alignment: .leading) }
                HStack(spacing: 24) {
                    if let channel { Button { onWatch(channel) } label: { Label("Watch \(channel.name) live", systemImage: "play.fill") } }
                    Button("Done", action: onClose)
                }.buttonStyle(.glassProminent)
            }
        }
        .padding(80).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.Palette.background.ignoresSafeArea()).presentationBackground(Theme.Palette.background)
    }
}

struct LiveTVSourcesView: View {
    @ObservedObject var store: LiveTVStore
    @Environment(\.dismiss) private var dismiss
    @State private var editing: LiveTVSource?
    @State private var deleting: LiveTVSource?
    @State private var error: String?
    var body: some View {
        ZStack {
            Theme.Palette.background.ignoresSafeArea()
            if let source = editing {
                LiveTVSourceEditor(store: store, source: source) { editing = nil }.id(source.id)
            } else {
                VStack(alignment: .leading, spacing: 32) {
                    Text("Live TV sources").font(.title2.bold())
                    HStack(spacing: 24) {
                        Button { editing = LiveTVSource(name: "", kind: .m3u, address: "") } label: { Label("Add source", systemImage: "plus") }.buttonStyle(.glass)
                        Button("Done") { dismiss() }.buttonStyle(.glass)
                    }.focusSection()
                    if store.sources.isEmpty { Text("Add your playlist or provider to get started.").foregroundStyle(.secondary) }
                    ScrollView {
                        LazyVStack(spacing: 24) {
                            ForEach(store.sources) { source in
                                HStack(spacing: 24) {
                                    Button { editing = source } label: {
                                        HStack {
                                            Image(systemName: "tv")
                                            VStack(alignment: .leading, spacing: 8) { Text(source.name); Text(source.kind.title).font(.caption).foregroundStyle(.secondary) }
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                        }.padding(24).frame(maxWidth: .infinity)
                                    }.buttonStyle(.card)
                                    Button(role: .destructive) { deleting = source } label: { Label("Remove", systemImage: "trash") }.buttonStyle(.glass)
                                }
                            }
                        }.padding(16)
                    }
                    if let error { Text(error).foregroundStyle(.red) }
                    Text("Saved securely on this Apple TV for this profile.").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: 1200).padding(64)
            }
        }.preferredColorScheme(.dark).presentationBackground(Theme.Palette.background)
        .alert("Remove source?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Cancel", role: .cancel) { deleting = nil }
            Button("Remove", role: .destructive) {
                if let source = deleting { Task { do { try await store.remove(source) } catch { self.error = "Could not remove this source. Please try again." } } }
                deleting = nil
            }
        } message: { Text("Its channels will be removed from this profile’s guide and favorites.") }
    }
}

struct LiveTVSourceEditor: View {
    @ObservedObject var store: LiveTVStore
    @State var source: LiveTVSource
    let onClose: () -> Void
    @State private var saving = false
    @State private var error: String?
    @FocusState private var field: String?
    private var validation: String? {
        if LiveTVURL.parse(source.address.trimmingCharacters(in: .whitespacesAndNewlines)) == nil { return "Enter a complete playlist or server URL beginning with https:// or http://." }
        if !source.guideAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && LiveTVURL.parse(source.guideAddress.trimmingCharacters(in: .whitespacesAndNewlines)) == nil { return "Enter a valid XMLTV URL, or leave it blank." }
        if source.kind == .xtream && (source.username.isEmpty || source.password.isEmpty) { return "Enter the username and password supplied by your provider." }
        return nil
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            Text("Connect a source").font(.title2.bold())
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Picker("Source type", selection: $source.kind) { ForEach(LiveTVSource.Kind.allCases) { kind in Text(kind.title).tag(kind) } }.pickerStyle(.segmented)
                    entry("Source name (optional)") { TextField("Source name", text: $source.name) }
                    entry(source.kind == .m3u ? "Playlist URL" : "Server URL") {
                        TextField(source.kind == .m3u ? "Playlist URL" : "Server URL", text: $source.address).textContentType(.URL).autocorrectionDisabled().focused($field, equals: "address")
                    }
                    if source.kind == .xtream {
                        entry("Username") { TextField("Username", text: $source.username).textContentType(.username).autocorrectionDisabled() }
                        entry("Password") { SecureField("Password", text: $source.password).textContentType(.password) }
                    }
                    entry("Programme guide (optional)") { TextField("XMLTV URL (optional)", text: $source.guideAddress).textContentType(.URL).autocorrectionDisabled() }
                    Text("Leave the guide blank to use the one supplied by your provider.").font(.caption).foregroundStyle(.secondary)
                }.padding(20)
            }
            if let error { Text(error).font(.callout).foregroundStyle(.orange).accessibilityIdentifier("sourceValidation") }
            HStack(spacing: 24) {
            Button(saving ? "Connecting…" : "Save and connect") {
                if let validation { error = validation; return }
                source.address = source.address.trimmingCharacters(in: .whitespacesAndNewlines)
                source.guideAddress = source.guideAddress.trimmingCharacters(in: .whitespacesAndNewlines)
                if source.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { source.name = URL(string: source.address)?.host ?? "Live TV" }
                saving = true
                Task {
                    do { try await store.save(source); onClose() }
                    catch { self.error = "Could not save this source securely. Please try again." }
                    saving = false
                }
            }.buttonStyle(.glass).disabled(saving)
            Button("Cancel", action: onClose).buttonStyle(.glass).disabled(saving)
            }.focusSection()
        }.frame(maxWidth: 1200).padding(60)
        .background(Theme.Palette.background.ignoresSafeArea())
        .interactiveDismissDisabled(saving)
    }
    private func entry<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(label).font(.caption).foregroundStyle(.white.opacity(0.8))
            content().textFieldStyle(.plain)
        }
    }
}
