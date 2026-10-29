import SwiftUI

/// Programme guide. The channel column stays put while the programme grid scrolls sideways, and
/// both columns share row heights so they stay aligned inside the page's vertical scroll. Only
/// visible rows are materialized, so large playlists do not allocate a view for every programme.
struct LiveTVGuideView: View {
    @ObservedObject var store: LiveTVStore
    let channels: [LiveTVChannel]
    let onPlay: (LiveTVChannel) -> Void
    let onProgramme: (LiveTVProgramme) -> Void
    @State private var offset = 0
    private let hourWidth: CGFloat = 480
    private let labelWidth: CGFloat = 320
    private let rowHeight: CGFloat = 96
    private let headerHeight: CGFloat = 44
    private let rowSpacing: CGFloat = 14
    private let window: TimeInterval = 10800
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let now = timeline.date
            let base = Date(timeIntervalSince1970: floor(now.timeIntervalSince1970 / 1800) * 1800)
            let start = base.addingTimeInterval(Double(offset) * window)
            let end = start.addingTimeInterval(window)
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 20) {
                    Button("Earlier", systemImage: "chevron.left") { offset = max(-8, offset - 1) }.disabled(offset <= -8)
                    Button("Now") { offset = 0 }.disabled(offset == 0)
                    Button("Later", systemImage: "chevron.right") { offset = min(48, offset + 1) }.disabled(offset >= 48)
                    Spacer()
                    Text("\(start.formatted(.dateTime.weekday(.wide).month().day())) · \(start.formatted(date: .omitted, time: .shortened)) – \(end.formatted(date: .omitted, time: .shortened))")
                        .font(.callout).foregroundStyle(.secondary)
                }.buttonStyle(.glass).focusSection()
                HStack(alignment: .top, spacing: 16) {
                    LazyVStack(alignment: .leading, spacing: rowSpacing) {
                        Text("Channels").font(.caption).foregroundStyle(.secondary)
                            .frame(height: headerHeight, alignment: .bottomLeading)
                        ForEach(channels) { channel in channelLabel(channel) }
                    }
                    .frame(width: labelWidth)
                    .focusSection()
                    ScrollView(.horizontal) {
                        LazyVStack(alignment: .leading, spacing: rowSpacing) {
                            timeHeader(start: start, end: end, now: now)
                            ForEach(channels) { channel in programmeRow(channel, start: start, end: end, now: now) }
                        }.padding(.horizontal, 8)
                    }
                    .scrollClipDisabled()
                    .focusSection()
                }
            }
        }
    }

    private func x(_ date: Date, from start: Date) -> CGFloat { CGFloat(date.timeIntervalSince(start) / 3600) * hourWidth }

    private func timeHeader(start: Date, end: Date, now: Date) -> some View {
        ZStack(alignment: .bottomLeading) {
            HStack(spacing: 0) {
                ForEach(0..<Int(window / 1800), id: \.self) { index in
                    Text(start.addingTimeInterval(Double(index) * 1800), format: .dateTime.hour().minute())
                        .frame(width: hourWidth / 2, alignment: .leading)
                }
            }.font(.caption).foregroundStyle(.secondary)
            if start <= now && now < end {
                Text("Now").font(.caption2.bold()).padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Theme.Palette.accent, in: Capsule()).foregroundStyle(Theme.Palette.accentText)
                    .offset(x: x(now, from: start) - 20, y: -24)
            }
        }.frame(width: hourWidth * window / 3600, height: headerHeight, alignment: .bottomLeading)
    }

    private func channelLabel(_ channel: LiveTVChannel) -> some View {
        Button { onPlay(channel) } label: {
            HStack(spacing: 16) {
                LiveTVLogo(channel: channel).frame(width: 64, height: 44)
                Text(channel.name).font(.callout.weight(.semibold)).lineLimit(2)
                Spacer(minLength: 0)
                if store.favorites.contains(channel.id) { Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow) }
            }
            .padding(.horizontal, 16)
            .frame(width: labelWidth, height: rowHeight, alignment: .leading)
            .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.card)
        .accessibilityLabel(channel.name)
    }

    private func programmeRow(_ channel: LiveTVChannel, start: Date, end: Date, now: Date) -> some View {
        let programmes = store.schedule(for: channel, after: start).filter { $0.start < end }
        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.035))
            if programmes.isEmpty {
                Button { onPlay(channel) } label: {
                    Text("No programme information · Watch live").foregroundStyle(.secondary).padding(.horizontal, 20)
                        .frame(height: rowHeight - 16)
                }.buttonStyle(.card).padding(.leading, 8)
            }
            ForEach(programmes) { programme in
                let left = max(programme.start, start)
                let right = min(programme.end, end)
                let width = CGFloat(right.timeIntervalSince(left) / 3600) * hourWidth
                let isCurrent = programme.isCurrent(at: now)
                Button {
                    if isCurrent { onPlay(channel) } else { onProgramme(programme) }
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(programme.title).font(.callout.weight(isCurrent ? .semibold : .regular)).lineLimit(2)
                        if width > 160 {
                            Text("\(programme.start.formatted(date: .omitted, time: .shortened)) – \(programme.end.formatted(date: .omitted, time: .shortened))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 14)
                    .frame(width: max(24, width - 8), height: rowHeight, alignment: .leading)
                    .background(isCurrent ? Theme.Palette.accent.opacity(0.28) : Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.card)
                .offset(x: x(left, from: start))
                .accessibilityLabel("\(channel.name), \(programme.title), \(programme.start.formatted(date: .omitted, time: .shortened))")
            }
            if start <= now && now < end {
                Rectangle().fill(Theme.Palette.accent.opacity(0.8)).frame(width: 2).offset(x: x(now, from: start)).allowsHitTesting(false)
            }
        }
        .frame(width: hourWidth * window / 3600, height: rowHeight)
    }
}
