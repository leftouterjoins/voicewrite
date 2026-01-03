import SwiftUI

/// Color schemes for the listening overlay border
enum OverlayColor: String, CaseIterable, Identifiable {
    case redOrange = "Red/Orange"
    case blueCyan = "Blue/Cyan"
    case greenTeal = "Green/Teal"
    case purplePink = "Purple/Pink"

    var id: String { rawValue }

    /// Colors for the rotating gradient
    var colors: [Color] {
        switch self {
        case .redOrange: return [.red, .orange, .red, .orange, .red]
        case .blueCyan: return [.blue, .cyan, .blue, .cyan, .blue]
        case .greenTeal: return [.green, .teal, .green, .teal, .green]
        case .purplePink: return [.purple, .pink, .purple, .pink, .purple]
        }
    }

    /// Primary color for the reactive pulse layer
    var primaryColor: Color {
        switch self {
        case .redOrange: return .red
        case .blueCyan: return .blue
        case .greenTeal: return .green
        case .purplePink: return .purple
        }
    }
}
