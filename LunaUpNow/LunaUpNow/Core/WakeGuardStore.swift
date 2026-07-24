//
//  WakeGuardStore.swift
//  LunaUpNow
//
//  Persistence for alarms and Wake Guard sessions. An unresolved session must
//  survive app termination and be restored on relaunch, so everything the spec
//  requires (session UUID, alarm UUID, times, stages, questions, escalations,
//  outcome) round-trips through Codable JSON.
//

import Foundation

struct PersistedState: Codable, Sendable {
    var alarms: [AlarmConfig] = []
    var sessions: [WakeGuardSession] = []
}

protocol WakeGuardPersisting: AnyObject {
    func load() -> PersistedState
    func save(_ state: PersistedState)
}

final class JSONFileStore: WakeGuardPersisting {
    private let url: URL
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init(url: URL? = nil) {
        if let url {
            self.url = url
        } else {
            let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("WakeGuard", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.url = dir.appendingPathComponent("state.json")
        }
    }

    func load() -> PersistedState {
        guard let data = try? Data(contentsOf: url),
              let state = try? decoder.decode(PersistedState.self, from: data) else {
            return PersistedState()
        }
        return state
    }

    func save(_ state: PersistedState) {
        guard let data = try? encoder.encode(state) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

final class InMemoryStore: WakeGuardPersisting {
    private var state = PersistedState()
    func load() -> PersistedState { state }
    func save(_ state: PersistedState) { self.state = state }
}
