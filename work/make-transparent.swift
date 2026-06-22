import AppKit
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    fputs("Usage: swift make-transparent.swift input.png output.png\n", stderr)
    exit(2)
}

let inputURL = URL(fileURLWithPath: arguments[1])
let outputURL = URL(fileURLWithPath: arguments[2])

guard let image = NSImage(contentsOf: inputURL),
      let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fputs("Could not load input image.\n", stderr)
    exit(1)
}

let width = cgImage.width
let height = cgImage.height
let bytesPerPixel = 4
let bytesPerRow = width * bytesPerPixel
var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

guard let context = CGContext(
    data: &pixels,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: bytesPerRow,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fputs("Could not create bitmap context.\n", stderr)
    exit(1)
}

context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

func offset(_ x: Int, _ y: Int) -> Int {
    y * bytesPerRow + x * bytesPerPixel
}

func colorDistanceToBackground(_ index: Int) -> Double {
    let r = Double(pixels[index])
    let g = Double(pixels[index + 1])
    let b = Double(pixels[index + 2])

    // Border-sampled warm studio background from the provided image.
    let br = 246.0
    let bg = 243.0
    let bb = 238.0
    let dr = r - br
    let dg = g - bg
    let db = b - bb
    return sqrt(dr * dr + dg * dg + db * db)
}

func looksLikeConnectedStudioBackground(_ index: Int, threshold: Double) -> Bool {
    colorDistanceToBackground(index) < threshold
}

var background = [Bool](repeating: false, count: width * height)
var queue: [(Int, Int)] = []
var head = 0

func enqueueIfBackground(_ x: Int, _ y: Int, threshold: Double) {
    guard x >= 0, x < width, y >= 0, y < height else { return }
    let maskIndex = y * width + x
    guard !background[maskIndex] else { return }
    let pixelIndex = offset(x, y)
    guard looksLikeConnectedStudioBackground(pixelIndex, threshold: threshold) else { return }
    background[maskIndex] = true
    queue.append((x, y))
}

for x in 0..<width {
    enqueueIfBackground(x, 0, threshold: 46)
    enqueueIfBackground(x, height - 1, threshold: 46)
}

for y in 0..<height {
    enqueueIfBackground(0, y, threshold: 46)
    enqueueIfBackground(width - 1, y, threshold: 46)
}

while head < queue.count {
    let (x, y) = queue[head]
    head += 1
    enqueueIfBackground(x + 1, y, threshold: 52)
    enqueueIfBackground(x - 1, y, threshold: 52)
    enqueueIfBackground(x, y + 1, threshold: 52)
    enqueueIfBackground(x, y - 1, threshold: 52)
}

let featherRadius = 8
var alpha = [UInt8](repeating: 255, count: width * height)

for y in 0..<height {
    for x in 0..<width {
        let maskIndex = y * width + x
        if background[maskIndex] {
            alpha[maskIndex] = 0
            continue
        }

        var nearestBackground = featherRadius + 1
        for dy in -featherRadius...featherRadius {
            for dx in -featherRadius...featherRadius {
                let nx = x + dx
                let ny = y + dy
                guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                if background[ny * width + nx] {
                    let distance = Int(sqrt(Double(dx * dx + dy * dy)))
                    nearestBackground = min(nearestBackground, distance)
                }
            }
        }

        if nearestBackground <= featherRadius {
            let value = max(0.0, min(1.0, Double(nearestBackground) / Double(featherRadius)))
            alpha[maskIndex] = UInt8(value * 255)
        }
    }
}

for y in 0..<height {
    for x in 0..<width {
        let pixelIndex = offset(x, y)
        let maskIndex = y * width + x
        pixels[pixelIndex + 3] = alpha[maskIndex]
    }
}

guard let outputContext = CGContext(
    data: &pixels,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: bytesPerRow,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
), let outputImage = outputContext.makeImage(),
   let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fputs("Could not prepare output image.\n", stderr)
    exit(1)
}

CGImageDestinationAddImage(destination, outputImage, nil)
guard CGImageDestinationFinalize(destination) else {
    fputs("Could not write output image.\n", stderr)
    exit(1)
}

print("Wrote \(outputURL.path)")
