import AppKit

// Génère un PNG 1024×1024 pour l'icône de l'app : squircle violet (dégradé)
// avec un pictogramme de livres blanc centré. Sortie : chemin passé en argument.

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

NSColor.clear.set()
NSRect(x: 0, y: 0, width: size, height: size).fill()

// Squircle légèrement encastré, comme les icônes macOS depuis Big Sur.
let inset: CGFloat = size * 0.085
let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let radius = rect.width * 0.2237
let squircle = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

let violetTop = NSColor(red: 139 / 255.0, green: 92 / 255.0, blue: 246 / 255.0, alpha: 1)
let violet = NSColor(red: 109 / 255.0, green: 40 / 255.0, blue: 217 / 255.0, alpha: 1)
let violetBottom = NSColor(red: 76 / 255.0, green: 29 / 255.0, blue: 149 / 255.0, alpha: 1)
if let gradient = NSGradient(colors: [violetTop, violet, violetBottom]) {
    gradient.draw(in: squircle, angle: -90)
} else {
    violet.set()
    squircle.fill()
}

// Pictogramme « books.vertical.fill » en blanc, centré.
let config = NSImage.SymbolConfiguration(pointSize: rect.width * 0.42, weight: .semibold)
if let base = NSImage(systemSymbolName: "books.vertical.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(config) {
    let symSize = base.size
    let tinted = NSImage(size: symSize)
    tinted.lockFocus()
    base.draw(at: .zero, from: NSRect(origin: .zero, size: symSize), operation: .sourceOver, fraction: 1)
    NSColor.white.set()
    NSRect(origin: .zero, size: symSize).fill(using: .sourceAtop)
    tinted.unlockFocus()

    tinted.draw(in: NSRect(x: rect.midX - symSize.width / 2, y: rect.midY - symSize.height / 2,
                           width: symSize.width, height: symSize.height))
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("Échec de la génération PNG\n".data(using: .utf8)!)
    exit(1)
}
do {
    try png.write(to: URL(fileURLWithPath: outPath))
    print("Icône écrite : \(outPath)")
} catch {
    FileHandle.standardError.write("Échec d'écriture : \(error)\n".data(using: .utf8)!)
    exit(1)
}
