import SwiftUI
import AVKit
import Combine

/// The channel being previewed and described at the top. Only the preview and its info observe
/// it, so moving focus through the guide never redraws the guide itself.
@MainActor private final class LiveTVFeatured: ObservableObject {
    @Published var channel: LiveTVChannel?
}

/// Low-buffer AVPlayer for the top preview. Tuning waits for focus to settle, so
/// scrolling through the guide never opens a stream per row.
@MainActor private final class LiveTVPreview: ObservableObject {
    let player = AVPlayer()
    @Published private(set) var channelID: String?
    @Published private(set) var failed = false
    @Published private(set) var ready = false
    private var status: NSKeyValueObservation?
    private var pending: Task<Void, Never>?
    private var suspended = false

    init() { player.automaticallyWaitsToMinimizeStalling = true }

    func focus(_ channel: LiveTVChannel?) {
        pending?.cancel()
        guard let channel, !suspended else { return }
        guard channel.id != channelID else { return }
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            self?.tune(channel)
        }
    }
    private func tune(_ channel: LiveTVChannel) {
        channelID = channel.id; failed = false; ready = false
        status = nil
        // Raw MPEG-TS cannot play in AVPlayer; the full-screen player handles it with mpv.
        guard !["ts", "mpeg", "mpg"].contains(channel.url.pathExtension.lowercased()) else {
            player.replaceCurrentItem(with: nil); failed = true; return
        }
        let asset = AVURLAsset(url: channel.url, options: channel.headers.isEmpty ? nil : ["AVURLAssetHTTPHeaderFieldsKey": channel.headers])
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 2
        item.preferredPeakBitRate = 6_000_000
        status = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self, self.player.currentItem === item else { return }
                if item.status == .failed { self.failed = true }
                if item.status == .readyToPlay { self.ready = true }
            }
        }
        player.replaceCurrentItem(with: item)
        player.play()
    }
    /// Full-screen playback, another tab or the background: release the stream entirely
    /// (providers often allow one connection per account).
    func suspend() {
        suspended = true; pending?.cancel()
        player.pause(); player.replaceCurrentItem(with: nil)
        status = nil; channelID = nil; ready = false
    }
    func resume(_ channel: LiveTVChannel?) { suspended = false; focus(channel) }
}

private struct LiveTVPreviewSurface: UIViewRepresentable {
    let player: AVPlayer
    func makeUIView(context: Context) -> PlayerVideoView {
        let view = PlayerVideoView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
        return view
    }
    func updateUIView(_ view: PlayerVideoView, context: Context) {}
}

/// Live TV in the style of Pluto TV and other live apps: the focused channel plays in a preview
/// at the top beside what is on, and the programme guide for the selected category fills the
/// bottom. Categories sit to the left of the guide. Every list is lazy, so providers with tens
/// of thousands of channels stay smooth.
struct LiveTVView: View {
    @StateObject private var store: LiveTVStore
    @StateObject private var featured = LiveTVFeatured()
    @StateObject private var preview = LiveTVPreview()
    @State private var query = ""
    @State private var category = LiveTVView.allChannels
    @State private var showingSources = false
    @State private var playing: LiveTVChannel?
    @State private var selectedProgramme: LiveTVProgramme?
    /// The guide's now line and progress advance once a minute from this single clock.
    @State private var now = Date()
    @FocusState private var focusedCategory: String?
    @Environment(\.scenePhase) private var scenePhase
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
                    VStack(alignment: .leading, spacing: 12) {
                        LiveTVStage(store: store, featured: featured, preview: preview, now: now, controls: AnyView(header))
                        HStack(alignment: .top, spacing: 24) {
                            categories
                            ScrollView {
                                LiveTVGuideView(store: store, channels: visible, now: now, labelWidth: 280, hourWidth: 385,
                                                onPlay: play, onProgramme: { selectedProgramme = $0 },
                                                onFocus: { featured.channel = $0 }, compact: true)
                                    .padding(.vertical, 8)
                            }
                            .id("guide|\(category)|\(query)")
                            .focusSection()
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.screen)
                    .padding(.top, 8)
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
        .onReceive(featured.$channel) { preview.focus($0) }
        .onAppear { preview.resume(featured.channel ?? store.recentChannels.first) }
        .onDisappear { preview.suspend() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { preview.resume(featured.channel) } else { preview.suspend() }
        }
        .onChange(of: store.channels.isEmpty) { _, empty in
            if !empty, featured.channel == nil { featured.channel = store.recentChannels.first ?? store.channels.first }
        }
        .fullScreenCover(isPresented: $showingSources) { LiveTVSourcesView(store: store) }
        .fullScreenCover(item: $playing, onDismiss: { preview.resume(featured.channel) }) { channel in
            LiveTVPlayerView(store: store, initialChannel: channel, channels: visible, onShowGuide: {})
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
            TextField("Search all channels", text: $query).font(.caption).frame(minWidth: 240, maxWidth: 440)
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
        .controlSize(.mini)
        .font(.caption)
        .focusSection()
    }

    private var categories: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                categoryRow(Self.favorites, systemImage: "star.fill", count: store.favoriteChannels.count)
                categoryRow(Self.recent, systemImage: "clock.arrow.circlepath", count: store.recentChannels.count)
                categoryRow(Self.allChannels, systemImage: "square.grid.2x2", count: store.channels.count)
                Divider().padding(.vertical, 8)
                ForEach(store.groups, id: \.self) { group in
                    categoryRow(group, systemImage: nil, count: store.channelsByGroup[group]?.count ?? 0)
                }
            }
            .padding(.vertical, 8)
        }
        .frame(width: 320)
        .focusSection()
    }

    private func categoryRow(_ name: String, systemImage: String?, count: Int) -> some View {
        let isSelected = query.isEmpty && category == name
        return Button { category = name; query = "" } label: {
            HStack(spacing: 12) {
                if let systemImage { Image(systemName: systemImage).font(.caption).frame(width: 24) }
                Text(name).font(.caption.weight(isSelected ? .semibold : .regular)).lineLimit(1)
                Spacer(minLength: 6)
                Text(count.formatted()).font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16).frame(height: 52)
            .background(isSelected ? Theme.Palette.accent.opacity(0.22) : .clear, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(LiveTVRowButtonStyle())
        .focused($focusedCategory, equals: name)
        .accessibilityLabel("\(name), \(count) channels")
        .accessibilityValue(isSelected ? "selected" : "")
    }

    private func play(_ channel: LiveTVChannel) {
        featured.channel = channel
        preview.suspend()
        playing = channel
    }
}

/// Row focus: a white fill and slight lift, quieter than the card style for long lists.
private struct LiveTVRowButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isFocused ? Color.black : Color.white)
            .background(isFocused ? Color.white : Color.clear, in: RoundedRectangle(cornerRadius: 12))
            .scaleEffect(configuration.isPressed ? 0.98 : (isFocused ? 1.03 : 1))
            .animation(.easeOut(duration: 0.12), value: isFocused)
    }
}

/// The top of the screen: what is on the focused channel, and the channel itself playing.
private struct LiveTVStage: View {
    @ObservedObject var store: LiveTVStore
    @ObservedObject var featured: LiveTVFeatured
    @ObservedObject var preview: LiveTVPreview
    let now: Date
    /// Search, refresh and sources, kept under the info so the guide gets the rest of the screen.
    let controls: AnyView
    var body: some View {
        HStack(alignment: .top, spacing: 40) {
            VStack(alignment: .leading, spacing: 12) {
                info.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                controls
            }
            ZStack {
                Color.black
                if let channel = featured.channel {
                    LiveTVPreviewSurface(player: preview.player)
                    if preview.channelID != channel.id || !preview.ready || preview.failed {
                        LiveTVLogo(channel: channel).padding(50).background(Color.black)
                            .overlay(alignment: .bottom) {
                                Group {
                                    if preview.failed { Text("Preview unavailable · Select to watch") }
                                    else { ProgressView() }
                                }
                                .font(.caption).foregroundStyle(.secondary).padding(.bottom, 20)
                            }
                    }
                }
            }
            .frame(width: 480, height: 270)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(alignment: .topLeading) {
                Text("LIVE").font(.caption2.bold()).padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Color.red.opacity(0.9), in: Capsule()).foregroundStyle(.white).padding(16)
            }
            .accessibilityHidden(true)
        }
        .frame(height: 270)
    }

    @ViewBuilder private var info: some View {
        if let channel = featured.channel {
            let upcoming = Array(store.schedule(for: channel, after: now).prefix(3))
            let current = upcoming.first.flatMap { $0.isCurrent(at: now) ? $0 : nil }
            let next = upcoming.first { !$0.isCurrent(at: now) }
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 16) {
                    LiveTVLogo(channel: channel).frame(width: 96, height: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(channel.number(in: store)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        Text(channel.name).font(.callout.weight(.semibold)).lineLimit(1)
                    }
                    if store.favorites.contains(channel.id) { Image(systemName: "star.fill").foregroundStyle(.yellow) }
                }
                if let current {
                    Text(current.title).font(.title3.bold()).lineLimit(1)
                    HStack(spacing: 16) {
                        Text("\(current.start.formatted(date: .omitted, time: .shortened)) – \(current.end.formatted(date: .omitted, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                        ProgressView(value: now.timeIntervalSince(current.start), total: current.end.timeIntervalSince(current.start))
                            .tint(Theme.Palette.accent).frame(width: 260)
                    }
                    if !current.summary.isEmpty {
                        Text(current.summary).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                    }
                } else {
                    Text(channel.group).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    Text("No programme information").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if let next {
                    Text("Next · \(next.start.formatted(date: .omitted, time: .shortened))  \(next.title)")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
        } else {
            Text("Live TV").font(.title2.bold())
        }
    }
}

private extension LiveTVChannel {
    @MainActor func number(in store: LiveTVStore) -> String { store.channelNumbers[id].map { "CH \($0)" } ?? "" }
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
