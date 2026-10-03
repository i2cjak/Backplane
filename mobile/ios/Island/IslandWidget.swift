import ActivityKit
import SwiftUI
import WidgetKit

@main
struct IslandBundle: WidgetBundle {
    var body: some Widget {
        IslandWidget()
    }
}

private struct Mark: View {
    let running: Int

    var body: some View {
        Image(systemName: running > 0 ? "cpu" : "checkmark.circle.fill")
            .foregroundStyle(running > 0 ? Color.green : Color.secondary)
    }
}

// a thread to open, or with pick the app asks which (a tap can only open
// the app; the island expands on a long press)
private func link(_ thread: String, pick: Bool = false) -> URL? {
    var c = URLComponents()
    c.scheme = "backplane"
    c.host = "open"
    c.queryItems = [pick ? URLQueryItem(name: "pick", value: "1") : URLQueryItem(name: "thread", value: thread)]
    return c.url
}

// a tap anywhere: the thread when one works, else the app asks which (the
// expanded island and the lock screen open one by its row)
private func tap(_ s: IslandAttributes.ContentState) -> URL? {
    s.lines.count == 1 ? link(s.lines[0].thread) : link("", pick: true)
}

// each thread its own row, a tap on it opens that thread
private struct Lines: View {
    let lines: [IslandAttributes.Line]
    let titles: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(lines, id: \.thread) { l in
                if let u = link(l.thread) {
                    Link(destination: u) { Row(line: l, title: titles) }
                } else {
                    Row(line: l, title: titles)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct Row: View {
    let line: IslandAttributes.Line
    let title: Bool

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                if title { Text(line.title).font(.caption.weight(.semibold)).lineLimit(1) }
                Text(line.doing).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if title { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
        }
        .contentShape(.rect)
    }
}

// what is not shown: "+ N more"
private struct More: View {
    let n: Int

    var body: some View {
        if n > 0 { Text("+ \(n) more").font(.caption2).foregroundStyle(.secondary) }
    }
}

// no word from the hubs for hours: this may no longer be so (open the app)
private struct Stale: View {
    let stale: Bool

    var body: some View {
        if stale { Text("Not updated lately: open Backplane").font(.caption2).foregroundStyle(.secondary) }
    }
}

struct IslandWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: IslandAttributes.self) { ctx in
            let s = ctx.state
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Mark(running: s.running)
                    Text(s.headline).font(.headline).lineLimit(1)
                    Spacer()
                    if s.running > 1 { Text("\(s.running)").font(.headline.monospacedDigit()) }
                }
                Lines(lines: Array(s.lines.prefix(4)), titles: s.running > 1)
                More(n: s.lines.count - 4)
                Stale(stale: ctx.isStale)
            }
            .opacity(ctx.isStale ? 0.5 : 1)
            .padding()
            .widgetURL(tap(s))
        } dynamicIsland: { ctx in
            let s = ctx.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Mark(running: s.running).font(.title3).padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(s.running)").font(.title3.monospacedDigit().bold()).padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(s.headline).font(.headline).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Lines(lines: Array(s.lines.prefix(4)), titles: s.running > 1)
                        More(n: s.lines.count - 4)
                        Stale(stale: ctx.isStale)
                    }
                }
            } compactLeading: {
                Mark(running: s.running).opacity(ctx.isStale ? 0.4 : 1)
            } compactTrailing: {
                Text(ctx.isStale ? "?" : "\(s.running)").monospacedDigit()
            } minimal: {
                Mark(running: s.running).opacity(ctx.isStale ? 0.4 : 1)
            }
            .widgetURL(tap(s))
        }
    }
}
