public enum IIGSEventKind: Int, Sendable {
    case videoScanline = 10
    case verticalBlankStart = 20
    case verticalBlankEnd = 30
    case videoFrame = 40
    case paddleTimeout = 50
    case docOscillator = 60
    case disk = 70
    case scc = 80
    case clockTick = 90
    case custom = 255
}

public struct IIGSScheduledEvent: Equatable, Identifiable, Sendable {
    public let id: UInt64
    public let cycle: UInt64
    public let kind: IIGSEventKind
    public let payload: UInt32
    public let interval: UInt64?

    public init(id: UInt64, cycle: UInt64, kind: IIGSEventKind, payload: UInt32 = 0, interval: UInt64? = nil) {
        self.id = id
        self.cycle = cycle
        self.kind = kind
        self.payload = payload
        self.interval = interval
    }
}

public struct IIGSFiredEvent: Equatable, Sendable {
    public let id: UInt64
    public let cycle: UInt64
    public let kind: IIGSEventKind
    public let payload: UInt32

    public init(id: UInt64, cycle: UInt64, kind: IIGSEventKind, payload: UInt32 = 0) {
        self.id = id
        self.cycle = cycle
        self.kind = kind
        self.payload = payload
    }
}

public final class IIGSEventScheduler {
    public private(set) var currentCycle: UInt64 = 0

    private var nextID: UInt64 = 1
    private var sequence: UInt64 = 0
    private var events: [QueuedEvent] = []
    private var firedEvents: [IIGSFiredEvent] = []

    public init() {}

    @discardableResult
    public func schedule(
        kind: IIGSEventKind,
        at cycle: UInt64,
        payload: UInt32 = 0,
        repeatingEvery interval: UInt64? = nil
    ) -> UInt64 {
        precondition(interval == nil || interval! > 0)
        let id = nextID
        nextID += 1
        enqueue(
            IIGSScheduledEvent(id: id, cycle: cycle, kind: kind, payload: payload, interval: interval)
        )
        return id
    }

    public func cancel(id: UInt64) {
        events.removeAll { $0.event.id == id }
    }

    public func advance(by cycles: UInt64) {
        advance(to: currentCycle &+ cycles)
    }

    public func advance(to targetCycle: UInt64) {
        guard targetCycle >= currentCycle else {
            return
        }

        while let next = events.first, next.event.cycle <= targetCycle {
            events.removeFirst()
            currentCycle = next.event.cycle
            firedEvents.append(
                IIGSFiredEvent(
                    id: next.event.id,
                    cycle: next.event.cycle,
                    kind: next.event.kind,
                    payload: next.event.payload
                )
            )

            if let interval = next.event.interval {
                enqueue(
                    IIGSScheduledEvent(
                        id: next.event.id,
                        cycle: next.event.cycle &+ interval,
                        kind: next.event.kind,
                        payload: next.event.payload,
                        interval: interval
                    )
                )
            }
        }

        currentCycle = targetCycle
    }

    public func pendingEvents() -> [IIGSScheduledEvent] {
        events.map(\.event)
    }

    public func peekFiredEvents() -> [IIGSFiredEvent] {
        firedEvents
    }

    public func drainFiredEvents() -> [IIGSFiredEvent] {
        let drained = firedEvents
        firedEvents.removeAll(keepingCapacity: true)
        return drained
    }

    public func reset(to cycle: UInt64 = 0) {
        currentCycle = cycle
        nextID = 1
        sequence = 0
        events.removeAll(keepingCapacity: true)
        firedEvents.removeAll(keepingCapacity: true)
    }

    private func enqueue(_ event: IIGSScheduledEvent) {
        sequence += 1
        events.append(QueuedEvent(event: event, sequence: sequence))
        events.sort()
    }
}

private struct QueuedEvent: Comparable {
    let event: IIGSScheduledEvent
    let sequence: UInt64

    static func < (lhs: QueuedEvent, rhs: QueuedEvent) -> Bool {
        if lhs.event.cycle != rhs.event.cycle {
            return lhs.event.cycle < rhs.event.cycle
        }
        if lhs.event.kind.rawValue != rhs.event.kind.rawValue {
            return lhs.event.kind.rawValue < rhs.event.kind.rawValue
        }
        return lhs.sequence < rhs.sequence
    }
}
