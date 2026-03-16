import AppKit

extension NSImage {
    /// Универсальное извлечение CGImage:
    /// 1) Пытаемся через встроенный cgImage(forProposedRect:)
    /// 2) Если не вышло — берём TIFF и берём CGImage из NSBitmapImageRep
    func cgImage() -> CGImage? {
        var rect = CGRect(origin: .zero, size: self.size)
        if let cg = self.cgImage(forProposedRect: &rect, context: nil, hints: nil) {
            return cg
        }
        if let tiff = self.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let cg = rep.cgImage {
            return cg
        }
        return nil
    }
}
