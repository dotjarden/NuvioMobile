import SwiftUI

/// One horizontal scroll surface keeps all channels on the same time axis. Only visible channel
/// rows are materialized, so large playlists do not allocate a view for every programme.
struct LiveTVGuideView: View {
    @ObservedObject var store: LiveTVStore
    let channels: [LiveTVChannel]
    let onPlay: (LiveTVChannel) -> Void
    let onProgramme: (LiveTVProgramme) -> Void
    @State private var offset = 0
    private let hourWidth: CGFloat = 440
    private let labelWidth: CGFloat = 250
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let now = timeline.date
            let base = Date(timeIntervalSince1970: floor(now.timeIntervalSince1970 / 1800) * 1800)
            let start = base.addingTimeInterval(Double(offset) * 10800)
            let end = start.addingTimeInterval(10800)
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 20) {
                    Button("Earlier", systemImage: "chevron.left") { offset = max(-8, offset - 1) }.disabled(offset <= -8)
                    Button("Now") { offset = 0 }.disabled(offset == 0)
                    Button("Later", systemImage: "chevron.right") { offset = min(48, offset + 1) }.disabled(offset >= 48)
                    Spacer()
                    Text(start, format: .dateTime.weekday().month().day()).foregroundStyle(.secondary)
                }.buttonStyle(.glass)
                ScrollView(.horizontal) {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 0) {
                            Text("Channel").frame(width: labelWidth, alignment: .leading)
                            ForEach(0..<6) { index in
                                Text(start.addingTimeInterval(Double(index) * 1800), format: .dateTime.hour().minute())
                                    .frame(width: hourWidth / 2, alignment: .leading)
                            }
                        }.font(.caption).foregroundStyle(.secondary).padding(.bottom, 8)
                        ForEach(channels) { channel in
                            HStack(spacing: 0) {
                                Button { onPlay(channel) } label: {
                                    HStack(spacing: 12) {
                                        if store.favorites.contains(channel.id) { Image(systemName: "star.fill").font(.caption) }
                                        Text(channel.name).font(.headline).lineLimit(2)
                                    }.frame(width: labelWidth - 35, height: 90, alignment: .leading)
                                }.buttonStyle(.card).frame(width: labelWidth, alignment: .leading)
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.035))
                                    let programmes = store.schedule(for: channel, after: start).filter { $0.start < end }
                                    if programmes.isEmpty {
                                        Button { onPlay(channel) } label: { Text("No programme information · Watch live").foregroundStyle(.secondary).padding(20) }.buttonStyle(.glass)
                                    }
                                    ForEach(programmes) { programme in
                                        let left = max(programme.start, start)
                                        let right = min(programme.end, end)
                                        let width = CGFloat(right.timeIntervalSince(left) / 3600) * hourWidth
                                        Button {
                                            if programme.isCurrent(at: now) { onPlay(channel) } else { onProgramme(programme) }
                                        } label: {
                                            VStack(alignment: .leading, spacing: 8) {
                                                Text(programme.title).font(.callout).lineLimit(2)
                                                if width > 140 { Text(programme.start, format: .dateTime.hour().minute()).font(.caption).foregroundStyle(.secondary) }
                                            }.padding(14).frame(width: max(24, width - 10), height: 90, alignment: .leading)
                                                .background(programme.isCurrent(at: now) ? Color.blue.opacity(0.2) : Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                                        }.buttonStyle(.card)
                                            .offset(x: CGFloat(left.timeIntervalSince(start) / 3600) * hourWidth)
                                            .accessibilityLabel("\(channel.name), \(programme.title), \(programme.start.formatted(date: .omitted, time: .shortened))")
                                    }
                                    if start <= now && now < end {
                                        Rectangle().fill(.cyan.opacity(0.7)).frame(width: 2).offset(x: CGFloat(now.timeIntervalSince(start) / 3600) * hourWidth).allowsHitTesting(false)
                                    }
                                }.frame(width: hourWidth * 3, height: 90)
                            }
                        }
                    }.padding(12)
                }.scrollClipDisabled()
            }
        }
    }
}
