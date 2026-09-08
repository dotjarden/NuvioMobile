import SwiftUI
import AVKit

struct LiveTVView: View {
    @StateObject private var store: LiveTVStore
    @State private var query = ""
    @State private var guideMode = false
    @State private var group = "All channels"
    @State private var showingSources = false
    @State private var playing: LiveTVChannel?
    @State private var selectedProgramme: LiveTVProgramme?
    @FocusState private var focusedChannel: String?
    init(profile: String) { _store = StateObject(wrappedValue: LiveTVStore(profile: profile)) }

    private var visibleChannels: [LiveTVChannel] {
        var channels = store.channels.filter { channel in
            (group == "All channels" || group == "Favorites" && store.favorites.contains(channel.id)
             || group == "Recent" && store.recent.contains(channel.id) || group == channel.group)
            && (query.isEmpty || channel.name.localizedCaseInsensitiveContains(query))
        }
        if group == "Recent" { channels.sort { (store.recent.firstIndex(of: $0.id) ?? 999) < (store.recent.firstIndex(of: $1.id) ?? 999) } }
        return channels
    }
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Palette.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        if !store.sources.isEmpty {
                        HStack(spacing: 20) {
                            TextField("Search channels", text: $query)
                                .textFieldStyle(.plain).padding(20)
                                .glassEffect(.regular, in: Capsule())
                            Button { Task { await store.refresh() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                                .buttonStyle(.glass).disabled(store.loading)
                            Button { showingSources = true } label: { Label("Sources", systemImage: "plus") }.buttonStyle(.glass)
                        }
                        }
                        if !store.sources.isEmpty {
                            HStack(spacing: 24) {
                                TVSelectionMenu(title: "View", value: guideMode ? "Programme guide" : "On now", options: ["On now", "Programme guide"]) { guideMode = $0 == "Programme guide" }
                                TVSelectionMenu(title: "Category", value: group, options: ["All channels", "Favorites", "Recent"] + store.groups) { group = $0 }
                                Spacer()
                                Text("\(visibleChannels.count) channels").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        if store.loading { ProgressView("Updating channels and guide…") }
                        if let error = store.error {
                            Text(error).font(.callout).foregroundStyle(.secondary)
                                .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
                        }
                        if store.sources.isEmpty {
                            ContentUnavailableView {
                                Label("Your channels belong here", systemImage: "tv")
                            } description: { Text("Connect an M3U playlist or Xtream provider to watch Live TV.") }
                            actions: { Button("Add a source") { showingSources = true }.buttonStyle(.glassProminent) }
                        } else {
                            if visibleChannels.isEmpty && !store.loading {
                                ContentUnavailableView("No matching channels", systemImage: "tv", description: Text("Try another category or search, or check your source connection."))
                            }
                            if guideMode {
                                LiveTVGuideView(store: store, channels: visibleChannels, onPlay: { focusedChannel = $0.id; playing = $0 }, onProgramme: { selectedProgramme = $0 })
                            } else {
                            TimelineView(.periodic(from: .now, by: 60)) { timeline in
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 440), spacing: 30)], spacing: 30) {
                                    ForEach(visibleChannels) { channel in channelRow(channel, now: timeline.date) }
                                }
                            }
                            }
                        }
                    }.padding(56)
                }.scrollClipDisabled()
                .reportsScrollToTabBar(tab: "Live TV")
                .sidebarMenuReveal()
            }
        }
        .task { await store.start() }
        .fullScreenCover(isPresented: $showingSources) { LiveTVSourcesView(store: store) }
        .fullScreenCover(item: $playing, onDismiss: { if let id = focusedChannel { focusedChannel = id } }) { channel in
            LiveTVPlayerView(store: store, initialChannel: channel, channels: visibleChannels)
        }
        .fullScreenCover(item: $selectedProgramme) { programme in
            VStack(alignment: .leading, spacing: 24) {
                Text(programme.title).font(.largeTitle.bold())
                Text("\(programme.start.formatted(date: .abbreviated, time: .shortened)) – \(programme.end.formatted(date: .omitted, time: .shortened))").foregroundStyle(.secondary)
                Text(programme.summary).font(.body)
                Button("Done") { selectedProgramme = nil }.buttonStyle(.glassProminent)
            }.padding(70).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .background(Theme.Palette.background.ignoresSafeArea()).presentationBackground(Theme.Palette.background)
        }
    }
    private func channelRow(_ channel: LiveTVChannel, now: Date) -> some View {
        let schedule = store.schedule(for: channel, after: now)
        let current = schedule.first(where: { $0.isCurrent(at: now) })
        return Button { focusedChannel = channel.id; playing = channel } label: {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    AsyncImage(url: channel.logo) { image in image.resizable().scaledToFit() } placeholder: { Image(systemName: "tv").font(.title) }
                        .frame(width: 80, height: 55)
                    Spacer()
                    if store.favorites.contains(channel.id) { Image(systemName: "star.fill") }
                    Text("LIVE").font(.caption.bold()).padding(.horizontal, 10).padding(.vertical, 5).background(Color.red.opacity(0.8), in: Capsule())
                }
                Text(channel.name).font(.headline).lineLimit(1)
                Text(current?.title ?? "Watch live").font(.callout).lineLimit(2).frame(height: 65, alignment: .topLeading)
                if let current {
                    ProgressView(value: now.timeIntervalSince(current.start), total: current.end.timeIntervalSince(current.start)).tint(.white)
                    Text("Until \(current.end.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(channel.group.isEmpty ? "Live television" : channel.group).font(.caption).foregroundStyle(.secondary)
                }
            }.padding(28).frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 300).background(Color(white: 0.10), in: RoundedRectangle(cornerRadius: 20))
        }.buttonStyle(.card).focused($focusedChannel, equals: channel.id)
        .contextMenu {
            Button { store.toggleFavorite(channel) } label: { Label(store.favorites.contains(channel.id) ? "Remove favorite" : "Add favorite", systemImage: "star") }
        }
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
