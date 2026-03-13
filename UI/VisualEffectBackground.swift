import SwiftUI
import AppKit

/// Обёртка над NSVisualEffectView для полупрозрачного фона
struct VisualEffectBackground: NSViewRepresentable {
    enum Material {
        case menu, hud, sidebar

        var nsMaterial: NSVisualEffectView.Material {
            switch self {
            case .menu: return .menu
            case .hud: return .hudWindow
            case .sidebar: return .sidebar
            }
        }
    }

    var material: Material = .hud
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var emphasized: Bool = false

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.state = .active
        v.material = material.nsMaterial
        v.blendingMode = blendingMode
        v.isEmphasized = emphasized
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.state = .active
        nsView.material = material.nsMaterial
        nsView.blendingMode = blendingMode
        nsView.isEmphasized = emphasized
    }
}
