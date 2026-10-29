import SwiftUI

/// Programme guide: a three-hour window that fits the screen, paged with Earlier / Later. Each
/// channel is one row (fixed channel label, then its programmes laid out on the time axis) in a
/// single lazy vertical stack, so only the rows on screen are built even for very large
/// playlists. The time header stays pinned while rows scroll.
struct LiveTVGuideView: View {
    @ObservedObject var store: LiveTVStore
    let channels: [LiveTVChannel]
    let now: Date
    var labelWidth: CGFloat = 300
    var hourWidth: CGFloat = 480
    let onPlay: (LiveTVChannel) -> Void
    let onProgramme: (LiveTVProgramme) -> Void
    @State private var offset = 0
    private let labelGap: CGFloat = 16
    private let rowHeight: CGFloat = 96
    private let window: TimeInterval = 10800
    /// Pages back to 3 hours ago and ahead to 3 days, the span `XMLTVParser` keeps.
    private let pages = -1...24
    var body: some View {
        let base = Date(timeIntervalSince1970: floor(now.timeIntervalSince1970 / 1800) * 1800)
        let start = base.addingTimeInterval(Double(offset) * window)
        let end = start.addingTimeInterval(window)
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 20) {
                Button("Earlier", systemImage: "chevron.left") { offset = max(pages.lowerBound, offset - 1) }.disabled(offset <= pages.lowerBound)
                Button("Now") { offset = 0 }.disabled(offset == 0)
                Button("Later", systemImage: "chevron.right") { offset = min(pages.upperBound, offset + 1) }.disabled(offset >= pages.upperBound)
                Spacer()
                Text("\(start.formatted(.dateTime.weekday(.wide).month().day())) · \(start.formatted(date: .omitted, time: .shortened)) – \(end.formatted(date: .omitted, time: .shortened))")
                    .font(.callout).foregroundStyle(.secondary)
            }.buttonStyle(.glass).focusSection()
            LazyVStack(alignment: .leading, spacing: 14, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(channels) { channel in row(channel, start: start, end: end) }
                } header: {
                    timeHeader(start: start, end: end)
                }
            }
        }
    }

    private func x(_ date: Date, from start: Date) -> CGFloat { CGFloat(date.timeIntervalSince(start) / 3600) * hourWidth }

    private func timeHeader(start: Date, end: Date) -> some View {
        HStack(spacing: labelGap) {
            Text("Channels").frame(width: labelWidth, alignment: .leading)
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    ForEach(0..<Int(window / 1800), id: \.self) { index in
                        Text(start.addingTimeInterval(Double(index) * 1800), format: .dateTime.hour().minute())
                            .frame(width: hourWidth / 2, alignment: .leading)
                    }
                }
                if start <= now && now < end {
                    Text("Now").font(.caption2.bold()).padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Theme.Palette.accent, in: Capsule()).foregroundStyle(Theme.Palette.accentText)
                        .offset(x: max(0, x(now, from: start) - 20), y: -30)
                }
            }
        }
        .font(.caption).foregroundStyle(.secondary)
        .frame(height: 44, alignment: .bottomLeading)
        .padding(.top, 20)
        .background(Theme.Palette.background)
    }

    private func row(_ channel: LiveTVChannel, start: Date, end: Date) -> some View {
        let programmes = Array(store.schedule(for: channel, after: start).prefix { $0.start < end })
        return HStack(spacing: labelGap) {
            Button { onPlay(channel) } label: {
                HStack(spacing: 14) {
                    LiveTVLogo(channel: channel).frame(width: 56, height: 40)
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
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.035))
                if programmes.isEmpty {
                    Button { onPlay(channel) } label: {
                        Text("No programme information · Watch live").foregroundStyle(.secondary).padding(.horizontal, 20)
                            .frame(height: rowHeight - 16)
                    }.buttonStyle(.card).padding(.leading, 8)
                } else {
                    // Laid out left to right with real gaps (not offsets), so focus moves between
                    // programmes in on-screen order.
                    HStack(spacing: 0) {
                        ForEach(Array(programmes.enumerated()), id: \.element.id) { index, programme in
                            let left = max(programme.start, start)
                            let previousEnd = index == 0 ? start : min(max(programmes[index - 1].end, start), end)
                            Color.clear.frame(width: max(0, x(left, from: start) - x(previousEnd, from: start)))
                            cell(programme, channel: channel, width: x(min(programme.end, end), from: start) - x(left, from: start))
                        }
                    }
                }
                if start <= now && now < end {
                    Rectangle().fill(Theme.Palette.accent.opacity(0.8)).frame(width: 2).offset(x: x(now, from: start)).allowsHitTesting(false)
                }
            }
            .frame(width: hourWidth * window / 3600, height: rowHeight, alignment: .leading)
        }
        .onAppear { store.requestGuide(for: channel) }
    }

    private func cell(_ programme: LiveTVProgramme, channel: LiveTVChannel, width: CGFloat) -> some View {
        let isCurrent = programme.isCurrent(at: now)
        return Button {
            if isCurrent { onPlay(channel) } else { onProgramme(programme) }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(programme.title).font(.callout.weight(isCurrent ? .semibold : .regular)).lineLimit(2)
                if width > 160 {
                    Text("\(programme.start.formatted(date: .omitted, time: .shortened)) – \(programme.end.formatted(date: .omitted, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(.horizontal, width > 60 ? 14 : 4)
            .frame(width: max(8, width - 8), height: rowHeight, alignment: .leading)
            .background(isCurrent ? Theme.Palette.accent.opacity(0.28) : Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.card)
        .frame(width: max(8, width), alignment: .leading)
        .accessibilityLabel("\(channel.name), \(programme.title), \(programme.start.formatted(date: .omitted, time: .shortened))")
    }
}
