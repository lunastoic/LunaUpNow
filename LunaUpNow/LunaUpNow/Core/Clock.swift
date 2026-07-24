//
//  Clock.swift
//  LunaUpNow
//
//  Injectable time source so the Wake Guard engine is fully testable and the
//  simulator dev controls can advance virtual time.
//

import Foundation

protocol ClockProviding: AnyObject, Sendable {
    var now: Date { get }
}

final class SystemClock: ClockProviding, @unchecked Sendable {
    var now: Date { Date() }
}

/// A clock that only moves when told to. Used by unit tests and the
/// in-simulator test controls ("advance virtual time").
final class VirtualClock: ClockProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(now: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        self.current = now
    }

    var now: Date {
        lock.lock(); defer { lock.unlock() }
        return current
    }

    func advance(by interval: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        current = current.addingTimeInterval(interval)
    }

    func set(to date: Date) {
        lock.lock(); defer { lock.unlock() }
        current = date
    }
}
