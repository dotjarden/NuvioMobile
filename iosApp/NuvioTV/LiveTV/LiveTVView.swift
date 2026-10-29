import SwiftUI
import AVKit
import Combine

/// The channel the details panel describes. Only that panel observes it, so moving focus down
/// the channel list redraws one panel instead of the screen.
@MainActor private final class LiveTVFeatured: ObservableObject {
    @Published var channel: LiveTVChannel?
}

/// Live TV in the layout IPTV viewers expect, built for providers with tens of thousands of
/// channels: categories on the left, the category's channel list in the middle, and details for
/// the focused channel on the right. Guide swaps the list and details for the programme grid of
/// the selected category. Every column is a lazy stack, so only what is on screen is built.
struct LiveTVView: View {
    @StateObject private var store: LiveTVStore
    @StateObject private var featured = LiveTVFeatured()
    @State private var query = ""
    @State private var guideMode = false
    @State private var category = LiveTVView.allChannels
    @State private var showingSources = false
    @State private var playing: LiveTVChannel?
    @State private var selectedProgramme: LiveTVProgramme?
    /// Progress bars and the guide's now line advance once a minute from this single clock.
    @State private var now = Date()
    /// Focusing a category selects it after a short pause, so scrolling past many categories
    /// does not rebuild the channel list for each one.
    @FocusState private var focusedCategory: String?
    init(profile: String) { _store = StateObject(wrappedValue: LiveTVStore(profile: profile)) }

    private static let allChannels = "All channels"
    private static let favorites = "Favorites"
    private static let recent = "Recent"
    private let clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var visibleChannels: [LiveTVChannel] {
        if !query.isEmpty { return store.channels.filter { $0.name.localizedCaseInsensitiveContains(query) } }
        switch category {
        case Self.allChannels: return store.channels
        case Self.favorites: return store.favoriteChannels
        case Self.recent: return store.recentChannels
        default: return store.channelsByGroup[category] ?? []
        }
    }

    var body: some View {
        let visible = visibleChannels
        NavigationStack {
            ZStack(alignment: .top) {
                Theme.Palette.background.ignoresSafeArea()
                if store.sources.isEmpty {
                    emptyState
                } else {
                    VStack(alignment: .leading, spacing: 24) {
                        header
                        status
                        HStack(alignment: .top, spacing: 32) {
                            categories
                            if guideMode {
                                ScrollView {
                                    LiveTVGuideView(store: store, channels: visible, now: now, labelWidth: 240,
                                                    hourWidth: 370, onPlay: play, onProgramme: { selectedProgramme = $0 })
                                        .padding(.vertical, 12)
                                }
                                .id("guide|\(category)|\(query)")
                                .focusSection()
                            } else {
                                channelList(visible)
                                LiveTVDetailsPanel(store: store, featured: featured, now: now)
                            }
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.screen)
                    .padding(.top, 30)
                    .railMenuReveal()
                }
            }
        }
        .task { await store.start() }
        .task(id: focusedCategory) {
            guard let focusedCategory, focusedCategory != category else { return }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            category = focusedCategory
        }
        .onReceive(clock) { now = $0 }
        .fullScreenCover(isPresented: $showingSources) { LiveTVSourcesView(store: store) }
        .fullScreenCover(item: $playing) { channel in
            LiveTVPlayerView(store: store, initialChannel: channel, channels: visible, onShowGuide: { guideMode = true })
        }
        .fullScreenCover(item: $selectedProgramme) { programme in
            LiveTVProgrammeDetail(programme: programme,
                                  channel: store.channels.first { LiveTVStore.guideKey($0) == programme.channelID },
                                  onWatch: { channel in selectedProgramme = nil; play(channel) },
                                  onClose: { selectedProgramme = nil })
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Your channels belong here", systemImage: "tv")
        } description: { Text("Connect an M3U playlist or Xtream provider to watch Live TV.") }
        actions: { Button("Add a source") { showingSources = true }.buttonStyle(.glassProminent) }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .railMenuReveal()
    }

    private var header: some View {
        HStack(spacing: 24) {
            Text("Live TV").font(.title2.bold()).fixedSize()
            HStack(spacing: 0) {
                modeButton("Channels", systemImage: "list.bullet", selected: !guideMode) { guideMode = false }
                modeButton("Guide", systemImage: "calendar.day.timeline.left", selected: guideMode) { guideMode = true }
            }
            TextField("Search all channels", text: $query).frame(minWidth: 240, maxWidth: 560)
            Spacer(minLength: 0)
            if store.loading {
                HStack(spacing: 12) { ProgressView(); Text("Updating…") }
                    .font(.caption).foregroundStyle(.secondary).fixedSize()
            } else {
                Text(store.channels.count == 1 ? "1 channel" : "\(store.channels.count.formatted()) channels")
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
            Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    // MARK: Categories

    private var categories: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                categoryRow(Self.favorites, systemImage: "star.fill", count: store.favoriteChannels.count)
                categoryRow(Self.recent, systemImage: "clock.arrow.circlepath", count: store.recentChannels.count)
                categoryRow(Self.allChannels, systemImage: "square.grid.2x2", count: store.channels.count)
                Divider().padding(.vertical, 10)
                ForEach(store.groups, id: \.self) { group in
                    categoryRow(group, systemImage: nil, count: store.channelsByGroup[group]?.count ?? 0)
                }
            }
            .padding(.vertical, 12)
        }
        .frame(width: 400)
        .focusSection()
    }

    private func categoryRow(_ name: String, systemImage: String?, count: Int) -> some View {
        let isSelected = query.isEmpty && category == name
        return Button { category = name; query = "" } label: {
            HStack(spacing: 14) {
                if let systemImage { Image(systemName: systemImage).font(.callout).frame(width: 28) }
                Text(name).font(.callout.weight(isSelected ? .semibold : .regular)).lineLimit(1)
                Spacer(minLength: 8)
                Text(count.formatted()).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20).frame(height: 62)
            .background(isSelected ? Theme.Palette.accent.opacity(0.22) : .clear, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(LiveTVRowButtonStyle())
        .focused($focusedCategory, equals: name)
        .accessibilityLabel("\(name), \(count) channels")
        .accessibilityValue(isSelected ? "selected" : "")
    }

    // MARK: Channels

    private func channelList(_ channels: [LiveTVChannel]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                Text(query.isEmpty ? category : "Results for “\(query)”").font(.headline)
                    .padding(.horizontal, 20).padding(.bottom, 6)
                if channels.isEmpty && !store.loading {
                    Text(query.isEmpty ? "No channels in this category." : "No channels match your search.")
                        .foregroundStyle(.secondary).padding(20)
                }
                ForEach(channels) { channel in
                    LiveTVChannelRow(channel: channel, number: store.channelNumbers[channel.id] ?? 0,
                                     isFavorite: store.favorites.contains(channel.id),
                                     programme: store.nowAndNext(for: channel, at: now).now, now: now, featured: featured,
                                     onAppear: { store.requestGuide(for: channel) },
                                     onPlay: { play(channel) }, onToggleFavorite: { store.toggleFavorite(channel) })
                        .equatable()
                }
            }
            .padding(.vertical, 12)
        }
        .id("channels|\(category)|\(query)")
        .frame(width: 720)
        .focusSection()
    }

    private func play(_ channel: LiveTVChannel) {
        featured.channel = channel
        playing = channel
    }
}

/// Row focus: a soft fill and slight lift, quieter than the card style for long lists.
private struct LiveTVRowButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isFocused ? Color.black : Color.white)
            .background(isFocused ? Color.white : Color.clear, in: RoundedRectangle(cornerRadius: 14))
            .scaleEffect(configuration.isPressed ? 0.98 : (isFocused ? 1.03 : 1))
            .animation(.easeOut(duration: 0.12), value: isFocused)
    }
}

/// One channel in the list. Equatable on what it draws, so store updates only redraw the rows
/// they change. Focus is reported to `featured` without observing it.
private struct LiveTVChannelRow: View, Equatable {
    let channel: LiveTVChannel
    let number: Int
    let isFavorite: Bool
    let programme: LiveTVProgramme?
    let now: Date
    let featured: LiveTVFeatured
    let onAppear: () -> Void
    let onPlay: () -> Void
    let onToggleFavorite: () -> Void
    @FocusState private var focused: Bool

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.channel.id == rhs.channel.id && lhs.number == rhs.number && lhs.isFavorite == rhs.isFavorite
            && lhs.programme == rhs.programme && lhs.now == rhs.now
    }

    var body: some View {
        Button(action: onPlay) {
            HStack(spacing: 18) {
                Text(number > 0 ? "\(number)" : "").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                    .frame(width: 84, alignment: .trailing)
                LiveTVLogo(channel: channel).frame(width: 96, height: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text(channel.name).font(.callout.weight(.semibold)).lineLimit(1)
                    Text(programme?.title ?? " ").font(.caption).opacity(0.7).lineLimit(1)
                    if let programme {
                        ProgressView(value: now.timeIntervalSince(programme.start), total: programme.end.timeIntervalSince(programme.start))
                            .tint(Theme.Palette.accent).scaleEffect(x: 1, y: 0.6)
                    }
                }
                Spacer(minLength: 0)
                if isFavorite { Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow) }
            }
            .padding(.horizontal, 20).frame(height: 92)
        }
        .buttonStyle(LiveTVRowButtonStyle())
        .focused($focused)
        .onChange(of: focused) { _, isFocused in if isFocused { featured.channel = channel; onAppear() } }
        .onAppear(perform: onAppear)
        .contextMenu {
            Button(action: onToggleFavorite) { Label(isFavorite ? "Remove favorite" : "Add favorite", systemImage: "star") }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(programme.map { "\(channel.name), \($0.title)" } ?? channel.name)
        .accessibilityAddTraits(.isButton)
    }
}

/// What is on the focused channel now and next.
private struct LiveTVDetailsPanel: View {
    @ObservedObject var store: LiveTVStore
    @ObservedObject var featured: LiveTVFeatured
    let now: Date
    private var channel: LiveTVChannel? { featured.channel ?? store.recentChannels.first ?? store.channels.first }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let channel {
                let upcoming = Array(store.schedule(for: channel, after: now).prefix(4))
                let current = upcoming.first.flatMap { $0.isCurrent(at: now) ? $0 : nil }
                LiveTVLogo(channel: channel)
                    .frame(width: 260, height: 150)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
                HStack(spacing: 12) {
                    Text("LIVE").font(.caption2.bold()).padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color.red.opacity(0.85), in: Capsule()).foregroundStyle(.white)
                    if store.favorites.contains(channel.id) { Image(systemName: "star.fill").foregroundStyle(.yellow) }
                    Text(channel.group).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Text(channel.name).font(.title3.bold()).lineLimit(2)
                if let current {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(current.title).font(.headline).lineLimit(2)
                        ProgressView(value: now.timeIntervalSince(current.start), total: current.end.timeIntervalSince(current.start))
                            .tint(Theme.Palette.accent)
                        Text("\(current.start.formatted(date: .omitted, time: .shortened)) – \(current.end.formatted(date: .omitted, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                        if !current.summary.isEmpty {
                            Text(current.summary).font(.caption).foregroundStyle(.secondary).lineLimit(5)
                        }
                    }
                } else {
                    Text("No programme information").font(.callout).foregroundStyle(.secondary)
                }
                let later = upcoming.filter { !$0.isCurrent(at: now) }.prefix(3)
                if !later.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Up next").font(.caption.bold()).foregroundStyle(.secondary)
                        ForEach(Array(later)) { programme in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(programme.start.formatted(date: .omitted, time: .shortened)).font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
                                Text(programme.title).font(.caption).lineLimit(1)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
                Text("Select to watch · Hold Select to favorite").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.Palette.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 24))
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
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
