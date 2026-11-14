import Cocoa

// Configuration
let size = 1024
let backgroundColor = NSColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1.0) // Dark Gray
let keyColor = NSColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1.0) // Off-white
let keyShadowColor = NSColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.5)

// Create Image
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

// Draw Background (Rounded Square)
let bgPath = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: size, height: size), xRadius: CGFloat(size) * 0.22, yRadius: CGFloat(size) * 0.22)
backgroundColor.setFill()
bgPath.fill()

// Draw "Key" shape
let keySize = CGFloat(size) * 0.6
let keyX = (CGFloat(size) - keySize) / 2
let keyY = (CGFloat(size) - keySize) / 2

// Shadow for 3D effect
let shadowPath = NSBezierPath(roundedRect: NSRect(x: keyX, y: keyY - 20, width: keySize, height: keySize), xRadius: keySize * 0.15, yRadius: keySize * 0.15)
keyShadowColor.setFill()
shadowPath.fill()

// Key Cap
let keyPath = NSBezierPath(roundedRect: NSRect(x: keyX, y: keyY, width: keySize, height: keySize), xRadius: keySize * 0.15, yRadius: keySize * 0.15)
keyColor.setFill()
keyPath.fill()

// Draw Text "KS"
let text = "KS" as NSString
let fontSize = keySize * 0.5
let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
let textColor = NSColor.black

let attributes: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: textColor
]

let textSize = text.size(withAttributes: attributes)
let textRect = NSRect(
    x: keyX + (keySize - textSize.width) / 2,
    y: keyY + (keySize - textSize.height) / 2,
    width: textSize.width,
    height: textSize.height
)

text.draw(in: textRect, withAttributes: attributes)

image.unlockFocus()

// Save to PNG
if let tiffData = image.tiffRepresentation,
   let bitmap = NSBitmapImageRep(data: tiffData),
   let pngData = bitmap.representation(using: .png, properties: [:]) {
    let url = URL(fileURLWithPath: "icon_1024x1024.png")
    try? pngData.write(to: url)
    print("Icon generated at \(url.path)")
}
