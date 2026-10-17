import Testing
@testable import FringeCore

private func event(_ id: String, _ kind: PeekEvent.Kind) -> PeekEvent { PeekEvent(id: id, kind: kind, title: id, detail: "") }

@Test func firstEventIsShownAtOnce() {
    var queue = PeekQueue()
    let r1 = queue.push(event("m1", .mail))
    #expect(r1)
    #expect(queue.current?.id == "m1")
}

@Test func lessUrgentEventWaits() {
    var queue = PeekQueue()
    queue.push(event("done", .agentDone))
    let r2 = queue.push(event("m1", .mail))
    #expect(!r2)
    #expect(queue.current?.id == "done")
    let r3 = queue.advance()
    #expect(r3?.id == "m1")
    let r4 = queue.advance()
    #expect(r4 == nil)
}

@Test func moreUrgentEventInterruptsAndTheInterruptedOneReturns() {
    var queue = PeekQueue()
    queue.push(event("m1", .mail))
    queue.push(event("m2", .mail))
    let r5 = queue.push(event("req", .agentRequest))
    #expect(r5)
    #expect(queue.current?.id == "req")
    queue.push(event("done", .agentDone))
    let r6 = queue.advance()
    #expect(r6?.id == "done")
    let r7 = queue.advance()
    #expect(r7?.id == "m1")
    let r8 = queue.advance()
    #expect(r8?.id == "m2")
}

@Test func duplicatesAreIgnored() {
    var queue = PeekQueue()
    queue.push(event("m1", .mail))
    let r9 = queue.push(event("m1", .mail))
    #expect(!r9)
    queue.push(event("m2", .mail))
    let r10 = queue.push(event("m2", .mail))
    #expect(!r10)
    #expect(queue.pending.count == 1)
}

@Test func burstKeepsOnlyTheNewestOfAKind() {
    var queue = PeekQueue(limitPerKind: 2)
    queue.push(event("done", .agentDone))
    for index in 1...5 { queue.push(event("m\(index)", .mail)) }
    #expect(queue.pending.map(\.id) == ["m4", "m5"])
}

@Test func interruptedEventSurvivesTheLimit() {
    var queue = PeekQueue(limitPerKind: 1)
    queue.push(event("m1", .mail))
    queue.push(event("req", .agentRequest))
    #expect(queue.pending.map(\.id) == ["m1"])
}

@Test func removingTheCurrentEventAdvances() {
    var queue = PeekQueue()
    queue.push(event("req", .agentRequest))
    queue.push(event("m1", .mail))
    let r11 = queue.remove(id: "req")
    #expect(r11)
    #expect(queue.current?.id == "m1")
    let r12 = queue.remove(id: "missing")
    #expect(!r12)
}
