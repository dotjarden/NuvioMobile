import SwiftUI
import AVKit

struct LiveTVView: View {
    @StateObject private var store: LiveTVStore
    @State private var query = ""
    @State private var guideMode = true
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
                Color(red: 0.035, green: 0.045, blue: 0.06).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        HStack(spacing: 20) {
                            TextField("Search channels", text: $query)
                                .textFieldStyle(.plain).padding(20)
                                .glassEffect(.regular, in: Capsule())
                            Button { Task { await store.refresh() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                                .buttonStyle(.glass).disabled(store.loading)
                            Button { showingSources = true } label: { Label("Sources", systemImage: "plus") }.buttonStyle(.glass)
                        }
                        Picker("View", selection: $guideMode) {
                            Text("Guide").tag(true)
                            Text("Channels").tag(false)
                        }.pickerStyle(.segmented)
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
                            ScrollView(.horizontal) {
                                HStack(spacing: 16) {
                                    ForEach(["All channels", "Favorites", "Recent"] + store.groups, id: \.self) { name in
                                        Button { group = name } label: {
                                            HStack { if group == name { Image(systemName: "checkmark") }; Text(name) }
                                        }.buttonStyle(.glass)
                                    }
                                }.padding(.vertical, 12)
                            }.scrollClipDisabled()
                            if visibleChannels.isEmpty && !store.loading {
                                ContentUnavailableView("No matching channels", systemImage: "tv", description: Text("Try another category or search, or check your source connection."))
                            }
                            if guideMode {
                                LiveTVGuideView(store: store, channels: visibleChannels, onPlay: { focusedChannel = $0.id; playing = $0 }, onProgramme: { selectedProgramme = $0 })
                            } else {
                            TimelineView(.periodic(from: .now, by: 60)) { timeline in
                                LazyVStack(alignment: .leading, spacing: 18) {
                                    HStack {
                                        Text("On now").font(.title2.bold())
                                        Spacer()
                                        Text(timeline.date, style: .time).foregroundStyle(.secondary)
                                    }
                                    ForEach(visibleChannels) { channel in
                                        channelRow(channel, now: timeline.date)
                                    }
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
        .sheet(item: $selectedProgramme) { programme in
            VStack(alignment: .leading, spacing: 24) {
                Text(programme.title).font(.largeTitle.bold())
                Text("\(programme.start.formatted(date: .abbreviated, time: .shortened)) – \(programme.end.formatted(date: .omitted, time: .shortened))").foregroundStyle(.secondary)
                Text(programme.summary).font(.body)
                Button("Done") { selectedProgramme = nil }.buttonStyle(.glassProminent)
            }.padding(70)
        }
    }
    private func channelRow(_ channel: LiveTVChannel, now: Date) -> some View {
        let schedule = store.schedule(for: channel, after: now)
        let current = schedule.first(where: { $0.isCurrent(at: now) })
        let next = schedule.first(where: { $0.start > now })
        return HStack(spacing: 24) {
            Button { focusedChannel = channel.id; playing = channel } label: {
                HStack(spacing: 20) {
                    AsyncImage(url: channel.logo) { image in image.resizable().scaledToFit() } placeholder: { Image(systemName: "tv").font(.title) }
                        .frame(width: 80, height: 60)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(channel.name).font(.headline).lineLimit(1)
                        Text(current?.title ?? "Watch live").font(.callout).lineLimit(1)
                        if let current {
                            ProgressView(value: now.timeIntervalSince(current.start), total: current.end.timeIntervalSince(current.start)).tint(.white)
                            Text("\(current.start.formatted(date: .omitted, time: .shortened)) – \(current.end.formatted(date: .omitted, time: .shortened))").font(.caption)
                        } else { Text("Programme information unavailable").font(.caption).foregroundStyle(.secondary) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.padding(20)
            }.buttonStyle(.card).focused($focusedChannel, equals: channel.id)
            .contextMenu {
                Button { store.toggleFavorite(channel) } label: {
                    Label(store.favorites.contains(channel.id) ? "Remove favorite" : "Add favorite", systemImage: "star")
                }
            }
            if let next {
                Button { selectedProgramme = next } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Up next · \(next.start.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                        Text(next.title).font(.callout).lineLimit(2)
                    }.frame(width: 290, alignment: .leading).padding(20)
                }.buttonStyle(.card)
            }
            Button { store.toggleFavorite(channel) } label: {
                Image(systemName: store.favorites.contains(channel.id) ? "star.fill" : "star")
            }.buttonStyle(.glass).accessibilityLabel(store.favorites.contains(channel.id) ? "Remove \(channel.name) from favorites" : "Favorite \(channel.name)")
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
        NavigationStack {
            List {
                Section {
                    ForEach(store.sources) { source in
                        HStack {
                            Button { editing = source } label: {
                                VStack(alignment: .leading) { Text(source.name); Text(source.kind.title).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            Button(role: .destructive) { deleting = source } label: { Label("Remove", systemImage: "trash") }
                        }
                    }
                    Button { editing = LiveTVSource(name: "", kind: .m3u, address: "") } label: { Label("Add source", systemImage: "plus") }
                } footer: { Text("Sources are saved securely on this Apple TV for the active profile. Your existing Stremio addons remain available in Add-ons.") }
                if let error { Text(error).foregroundStyle(.red) }
                Button("Done") { dismiss() }
            }.navigationTitle("Live TV sources")
            .fullScreenCover(item: $editing) { source in LiveTVSourceEditor(store: store, source: source) }
            .alert("Remove source?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("Cancel", role: .cancel) { deleting = nil }
                Button("Remove", role: .destructive) {
                    if let source = deleting {
                        Task { do { try await store.remove(source) } catch { self.error = "Could not remove this source. Please try again." } }
                    }
                    deleting = nil
                }
            } message: { Text("Its channels will be removed from this profile’s guide and favorites.") }
        }
    }
}

struct LiveTVSourceEditor: View {
    @ObservedObject var store: LiveTVStore
    @State var source: LiveTVSource
    @Environment(\.dismiss) private var dismiss
    @State private var saving = false
    @State private var error: String?
    var valid: Bool {
        !source.name.trimmingCharacters(in: .whitespaces).isEmpty && LiveTVURL.parse(source.address) != nil
        && (source.guideAddress.isEmpty || LiveTVURL.parse(source.guideAddress) != nil)
        && (source.kind != .xtream || !source.username.isEmpty && !source.password.isEmpty)
    }
    var body: some View {
        NavigationStack {
            List {
                TextField("Source name", text: $source.name)
                Picker("Source type", selection: $source.kind) { ForEach(LiveTVSource.Kind.allCases) { kind in Text(kind.title).tag(kind) } }
                TextField(source.kind == .m3u ? "Playlist URL" : "Server URL", text: $source.address).textContentType(.URL).autocorrectionDisabled()
                if source.kind == .xtream {
                    TextField("Username", text: $source.username).textContentType(.username).autocorrectionDisabled()
                    SecureField("Password", text: $source.password).textContentType(.password)
                }
                Section { TextField("XMLTV URL (optional)", text: $source.guideAddress).textContentType(.URL).autocorrectionDisabled() }
                footer: { Text("Leave blank to use the guide supplied by your playlist or Xtream provider.") }
                if let error { Text(error).foregroundStyle(.red) }
                Button(saving ? "Connecting…" : "Save and connect") {
                    saving = true
                    Task {
                        do { try await store.save(source); dismiss() }
                        catch { self.error = "Could not save the source securely. Please try again." }
                        saving = false
                    }
                }.disabled(!valid || saving)
                Button("Cancel") { dismiss() }.disabled(saving)
            }.frame(maxWidth: 1200)
                .frame(maxWidth: .infinity)
        }.interactiveDismissDisabled(saving)
    }
}
