import ActivityKit
import Foundation

private func hex(_ d: Data) -> String { d.map { String(format: "%02x", $0) }.joined() }

// Runs the one Live Activity (lock screen + Dynamic Island) from the
// screen's island. It can only start while the app is in front; after
// that the hub keeps it current with pushes to its token.
@MainActor
final class IslandController {
    private var activity: Activity<IslandAttributes>?
    private var last: IslandAttributes.ContentState?
    private let register: (String, String) -> Void
    // with no word for this long iOS marks it stale (the hubs push at least
    // hourly while any thread works: push.bend's Island.fresh)
    private var stale: Date { Date().addingTimeInterval(3 * 3600) }

    // register(kind, token): "activity" for this activity, "start" for
    // starting one by push (iOS 17.2+)
    init(register: @escaping (String, String) -> Void) {
        self.register = register
        activity = Activity<IslandAttributes>.activities.first
        if let a = activity { watch(a) }
        if #available(iOS 17.2, *) {
            Task {
                for await t in Activity<IslandAttributes>.pushToStartTokenUpdates { register("start", hex(t)) }
            }
        }
    }

    private func watch(_ a: Activity<IslandAttributes>) {
        Task {
            for await t in a.pushTokenUpdates { register("activity", hex(t)) }
        }
    }

    func show(_ s: IslandAttributes.ContentState, foreground: Bool) {
        if let a = activity, a.activityState == .ended || a.activityState == .dismissed { activity = nil }
        if activity == nil, s.running > 0 {
            guard foreground, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
            do {
                let a = try Activity.request(attributes: IslandAttributes(), content: .init(state: s, staleDate: stale), pushType: .token)
                activity = a
                last = s
                watch(a)
            } catch {
                NSLog("live activity: %@", error.localizedDescription)
            }
            return
        }
        // against what the activity shows now (a hub's push may have changed
        // it since), and again whenever its stale date draws near
        guard let a = activity else { return }
        let due = (a.content.staleDate ?? .distantFuture) < Date().addingTimeInterval(2 * 3600)
        guard s != a.content.state || due else { return }
        last = s
        if s.running > 0 {
            Task { await a.update(.init(state: s, staleDate: stale)) }
        } else {
            activity = nil
            Task { await a.end(.init(state: s, staleDate: nil), dismissalPolicy: .after(.now + 15 * 60)) }
        }
    }
}
