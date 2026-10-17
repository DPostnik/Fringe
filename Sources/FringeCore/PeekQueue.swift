import Foundation

/// One announcement over the notch. Lower `priority` values are more urgent.
public struct PeekEvent: Identifiable, Equatable, Sendable {
    public enum Kind: Int, Comparable, Sendable {
        /// An agent asks the user: the panel opens on the Agents tab.
        case agentRequest = 0
        /// An agent finished a turn.
        case agentDone = 1
        /// A new mail message.
        case mail = 2
        public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

        /// How long the announcement stays before the next one.
        public var duration: Duration {
            switch self {
            case .agentRequest: .seconds(8)
            case .agentDone: .seconds(4)
            case .mail: .seconds(5)
            }
        }
    }

    public var id: String
    public var kind: Kind
    public var title: String
    public var detail: String
    public init(id: String, kind: Kind, title: String, detail: String) {
        self.id = id; self.kind = kind; self.title = title; self.detail = detail
    }
}

/// Orders announcements by priority. A more urgent event interrupts a less urgent one, which is
/// shown again afterwards; a less urgent one waits while a more urgent one is shown.
public struct PeekQueue: Sendable {
    public private(set) var current: PeekEvent?
    public private(set) var pending: [PeekEvent] = []
    /// Bursts (a mailbox sync) must not queue minutes of peeks; the oldest of a kind are dropped.
    public let limitPerKind: Int

    public init(limitPerKind: Int = 3) { self.limitPerKind = limitPerKind }

    /// Returns true when `current` changed, so the caller restarts its timer.
    @discardableResult
    public mutating func push(_ event: PeekEvent) -> Bool {
        guard current?.id != event.id, !pending.contains(where: { $0.id == event.id }) else { return false }
        guard let shown = current else { current = event; return true }
        if event.kind < shown.kind {
            insert(shown, atFront: true)
            current = event
            return true
        }
        insert(event, atFront: false)
        return false
    }

    /// The current event ended; returns the next one, if any.
    @discardableResult
    public mutating func advance() -> PeekEvent? {
        current = nil
        guard let index = pending.indices.min(by: { pending[$0].kind < pending[$1].kind || (pending[$0].kind == pending[$1].kind && $0 < $1) }) else { return nil }
        current = pending.remove(at: index)
        return current
    }

    /// Drops an event that no longer applies (a request answered elsewhere). Returns true when `current` changed.
    @discardableResult
    public mutating func remove(id: String) -> Bool {
        pending.removeAll { $0.id == id }
        guard current?.id == id else { return false }
        advance()
        return true
    }

    private mutating func insert(_ event: PeekEvent, atFront: Bool) {
        let index = atFront ? (pending.firstIndex { $0.kind == event.kind } ?? pending.endIndex) : pending.endIndex
        pending.insert(event, at: index)
        let sameKind = pending.indices.filter { pending[$0].kind == event.kind }
        guard sameKind.count > limitPerKind else { return }
        // Keep the newest; an interrupted event put back at the front is kept as well.
        let candidates = sameKind.filter { !(atFront && pending[$0].id == event.id) }
        for index in candidates.prefix(sameKind.count - limitPerKind).reversed() { pending.remove(at: index) }
    }
}
