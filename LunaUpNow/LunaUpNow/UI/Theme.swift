//
//  Theme.swift
//  LunaUpNow
//
//  Dark, ember-orange look per the WakeProof mockups.
//

import SwiftUI

enum Theme {
    static let accent = Color(red: 1.00, green: 0.45, blue: 0.10)
    static let accentSoft = Color(red: 1.00, green: 0.62, blue: 0.25)
    static let background = Color(red: 0.05, green: 0.05, blue: 0.06)
    static let card = Color(red: 0.10, green: 0.10, blue: 0.12)
    static let cardElevated = Color(red: 0.14, green: 0.13, blue: 0.14)
    static let stroke = Color.white.opacity(0.07)
    static let success = Color(red: 0.30, green: 0.85, blue: 0.45)
    static let warning = Color(red: 1.00, green: 0.72, blue: 0.20)
    static let danger = Color(red: 1.00, green: 0.33, blue: 0.30)

    static let sunriseGradient = LinearGradient(
        colors: [Color(red: 0.20, green: 0.08, blue: 0.02), Color(red: 0.45, green: 0.16, blue: 0.03)],
        startPoint: .top, endPoint: .bottom)
}

struct CardStyle: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: 18).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.stroke))
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View { modifier(CardStyle(padding: padding)) }
}

struct Chip: View {
    var text: String
    var icon: String?
    var color: Color = Theme.accent
    var filled = false

    var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.caption2) }
            Text(text).font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(filled ? color.opacity(0.18) : .clear))
        .overlay(Capsule().stroke(color.opacity(0.6), lineWidth: 1))
        .foregroundStyle(color)
    }
}

func formatDuration(_ interval: TimeInterval) -> String {
    let total = max(0, Int(interval))
    let h = total / 3600, m = (total % 3600) / 60, s = total % 60
    if h > 0 { return String(format: "%dh %02dm", h, m) }
    if m > 0 { return String(format: "%dm %02ds", m, s) }
    return "\(s)s"
}
