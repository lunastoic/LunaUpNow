//
//  QuestionGenerator.swift
//  LunaUpNow
//
//  Deterministic (seedable) arithmetic question generation so a stage's
//  questions can be regenerated identically after relaunch and asserted in
//  unit tests.
//

import Foundation

/// SplitMix64 — tiny deterministic RNG; seeded per session+stage.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

enum QuestionGenerator {

    /// Stable seed derived from the session and stage so regeneration after a
    /// relaunch produces the same questions that were persisted.
    static func seed(sessionID: UUID, stageIndex: Int) -> UInt64 {
        let bytes = withUnsafeBytes(of: sessionID.uuid) { Array($0) }
        var s: UInt64 = 0xcbf29ce484222325
        for b in bytes { s = (s ^ UInt64(b)) &* 0x100000001b3 }
        return s &+ UInt64(stageIndex &* 7919)
    }

    static func questions(count: Int, difficulty: QuestionDifficulty, seed: UInt64) -> [Question] {
        var rng = SeededGenerator(seed: seed)
        return (0..<count).map { _ in question(difficulty: difficulty, rng: &rng) }
    }

    static func question(difficulty: QuestionDifficulty, rng: inout SeededGenerator) -> Question {
        let kind = Int.random(in: 0..<3, using: &rng)
        switch kind {
        case 0:
            let (a, b) = additionOperands(difficulty: difficulty, rng: &rng)
            return Question(id: uuid(&rng), prompt: "\(a) + \(b) = ?", answer: a + b)
        case 1:
            let (a, b) = additionOperands(difficulty: difficulty, rng: &rng)
            let (hi, lo) = a >= b ? (a, b) : (b, a)
            return Question(id: uuid(&rng), prompt: "\(hi) − \(lo) = ?", answer: hi - lo)
        default:
            // Keep multiplication factors small enough to be solvable in bed.
            let m = difficulty == .hard ? Int.random(in: 6...15, using: &rng) : Int.random(in: 3...9, using: &rng)
            let n = difficulty == .gentle ? Int.random(in: 2...6, using: &rng) : Int.random(in: 4...12, using: &rng)
            return Question(id: uuid(&rng), prompt: "\(m) × \(n) = ?", answer: m * n)
        }
    }

    /// Below `hard`, one operand is always a round number (multiple of 10) and
    /// the other is a multiple of 5 or an even number — sums like 10 + 85 or
    /// 34 + 20 that are solvable half-asleep. `hard` keeps arbitrary operands.
    private static func additionOperands(difficulty: QuestionDifficulty, rng: inout SeededGenerator) -> (Int, Int) {
        switch difficulty {
        case .gentle:
            let round = 10 * Int.random(in: 1...5, using: &rng)
            let friendly = 5 * Int.random(in: 1...8, using: &rng)
            return Bool.random(using: &rng) ? (round, friendly) : (friendly, round)
        case .balanced:
            let round = 10 * Int.random(in: 1...9, using: &rng)
            let friendly = Bool.random(using: &rng)
                ? 5 * Int.random(in: 1...19, using: &rng)   // multiple of 5, 5–95
                : 2 * Int.random(in: 6...24, using: &rng)   // even, 12–48
            return Bool.random(using: &rng) ? (round, friendly) : (friendly, round)
        case .hard:
            return (Int.random(in: 23...99, using: &rng), Int.random(in: 23...99, using: &rng))
        }
    }

    private static func uuid(_ rng: inout SeededGenerator) -> UUID {
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<16 { bytes[i] = UInt8(truncatingIfNeeded: rng.next()) }
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
