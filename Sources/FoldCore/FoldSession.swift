import Foundation

/// Angle updates are the only timeline. A generation token prevents late screen
/// captures from restoring an overlay after reopening, disabling, or sleep.
public struct FoldSession {
    public enum State: String { case idle, capturing, folding, closed, blocked }
    public enum Action: Equatable { case none, hide, capture(Int), render }
    public private(set) var state: State = .idle
    public private(set) var progress = 0.0
    public private(set) var generation = 0

    public init() {}

    public mutating func update(progress value: Double, allowed: Bool) -> Action {
        let next = value.isFinite ? min(1, max(0, value)) : 0
        guard allowed, next > 0 else {
            let wasActive = state != .idle
            reset()
            return wasActive ? .hide : .none
        }
        let changed = next != progress
        progress = next
        switch state {
        case .idle:
            generation += 1
            state = .capturing
            return .capture(generation)
        case .capturing, .blocked: return .none
        case .folding, .closed:
            state = next == 1 ? .closed : .folding
            return changed ? .render : .none
        }
    }

    public mutating func completeCapture(_ token: Int, succeeded: Bool) -> Bool {
        guard token == generation, state == .capturing, progress > 0 else { return false }
        state = succeeded ? (progress == 1 ? .closed : .folding) : .blocked
        return succeeded
    }

    public mutating func reset() {
        if state != .idle { generation += 1 }
        state = .idle
        progress = 0
    }

    public mutating func failRendering() {
        generation += 1
        state = .blocked
    }
}
