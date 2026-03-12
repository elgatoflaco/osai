import Foundation
import CoreGraphics
import AppKit
import CryptoKit

// MARK: - Vision Driver (Screenshots with Intelligent Caching)

final class VisionDriver {

    /// Maximum width for screenshots sent to the AI (to save tokens/cost)
    var maxWidth: Int = 1280

    // MARK: - Screenshot Cache

    /// Cache entry: stores the last screenshot for a given region
    private struct CacheEntry {
        let jpegData: Data
        let base64: String
        let description: String
        let pixelHash: String       // SHA-256 of downsampled pixel grid for change detection
        let timestamp: Date
        let sizeKB: Int
    }

    /// Region-keyed cache (nil key = full screen)
    private var cache: [String: CacheEntry] = [:]
    private let cacheLock = NSLock()

    /// Cache TTL — screenshots older than this are always recaptured
    var cacheTTL: TimeInterval = 2.0

    /// Pixel sampling grid size for change detection (lower = faster hash, less precise)
    /// A 32x32 grid samples 1024 pixels — enough to detect meaningful UI changes
    private let hashGridSize = 32

    /// Cache statistics
    private(set) var cacheHits: Int = 0
    private(set) var cacheMisses: Int = 0

    var cacheHitRate: Double {
        let total = cacheHits + cacheMisses
        return total > 0 ? Double(cacheHits) / Double(total) * 100.0 : 0
    }

    /// Invalidate cache (call after actions that change screen: click, type, scroll)
    func invalidateCache() {
        cacheLock.lock()
        cache.removeAll()
        cacheLock.unlock()
    }

    // MARK: - Screenshot Capture

    func takeScreenshot(region: ScreenRegion? = nil) -> ToolResult {
        let displayID = CGMainDisplayID()

        let rect: CGRect
        if let region = region {
            rect = CGRect(x: region.x, y: region.y, width: region.width, height: region.height)
        } else {
            rect = CGRect(
                x: 0, y: 0,
                width: CGDisplayPixelsWide(displayID),
                height: CGDisplayPixelsHigh(displayID)
            )
        }

        guard let image = CGDisplayCreateImage(displayID, rect: rect) else {
            return ToolResult(success: false, output: "Failed to capture screenshot. Ensure Screen Recording permission is granted in System Settings > Privacy & Security > Screen Recording.", screenshot: nil)
        }

        // Compute pixel hash for change detection (fast: samples a small grid)
        let currentHash = computePixelHash(image)
        let cacheKey = region.map { "\($0.x),\($0.y),\($0.width),\($0.height)" } ?? "full"

        // Check cache: if hash matches and TTL hasn't expired, return cached version
        cacheLock.lock()
        if let cached = cache[cacheKey],
           cached.pixelHash == currentHash,
           Date().timeIntervalSince(cached.timestamp) < cacheTTL {
            cacheHits += 1
            cacheLock.unlock()
            return ToolResult(
                success: true,
                output: "\(cached.description) [cached — screen unchanged, saved ~\(cached.sizeKB)KB of tokens]",
                screenshot: cached.jpegData
            )
        }
        cacheMisses += 1
        cacheLock.unlock()

        // Downscale if needed
        let nsImage: NSImage
        if image.width > maxWidth {
            let scale = Double(maxWidth) / Double(image.width)
            let newHeight = Int(Double(image.height) * scale)
            nsImage = NSImage(size: NSSize(width: maxWidth, height: newHeight))
            nsImage.lockFocus()
            NSGraphicsContext.current?.imageInterpolation = .high
            let fromRect = NSRect(x: 0, y: 0, width: image.width, height: image.height)
            let toRect = NSRect(x: 0, y: 0, width: maxWidth, height: newHeight)
            let ciImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
            ciImage.draw(in: toRect, from: fromRect, operation: .copy, fraction: 1.0)
            nsImage.unlockFocus()
        } else {
            nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        }

        // Encode to JPEG — use CGImage → NSBitmapImageRep directly (skip TIFF round-trip)
        let jpegData: Data
        if let cgImg = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil),
           let bitmapRep = NSBitmapImageRep(cgImage: cgImg) as NSBitmapImageRep?,
           let data = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) {
            jpegData = data
        } else if let tiffData = nsImage.tiffRepresentation,
                  let bitmapRep = NSBitmapImageRep(data: tiffData),
                  let data = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) {
            // Fallback to TIFF round-trip if direct CGImage extraction fails
            jpegData = data
        } else {
            return ToolResult(success: false, output: "Failed to encode screenshot", screenshot: nil)
        }

        let sizeKB = jpegData.count / 1024
        let finalWidth = Int(nsImage.size.width)
        let finalHeight = Int(nsImage.size.height)
        let description = "Screenshot captured: \(finalWidth)x\(finalHeight) (\(sizeKB)KB) — original \(image.width)x\(image.height)"

        // Update cache
        let base64 = jpegData.base64EncodedString()
        let entry = CacheEntry(
            jpegData: jpegData,
            base64: base64,
            description: description,
            pixelHash: currentHash,
            timestamp: Date(),
            sizeKB: sizeKB
        )
        cacheLock.lock()
        cache[cacheKey] = entry
        cacheLock.unlock()

        return ToolResult(
            success: true,
            output: description,
            screenshot: jpegData
        )
    }

    func takeScreenshotBase64(region: ScreenRegion? = nil) -> (base64: String, description: String)? {
        let result = takeScreenshot(region: region)
        guard result.success, let data = result.screenshot else { return nil }

        // Use cached base64 if available (avoids redundant base64 encoding)
        let cacheKey = region.map { "\($0.x),\($0.y),\($0.width),\($0.height)" } ?? "full"
        cacheLock.lock()
        let cachedBase64 = cache[cacheKey]?.base64
        cacheLock.unlock()

        return (cachedBase64 ?? data.base64EncodedString(), result.output)
    }

    func saveScreenshot(to path: String, region: ScreenRegion? = nil) -> ToolResult {
        let result = takeScreenshot(region: region)
        guard result.success, let data = result.screenshot else {
            return result
        }

        do {
            try data.write(to: URL(fileURLWithPath: path))
            return ToolResult(success: true, output: "Screenshot saved to \(path)", screenshot: data)
        } catch {
            return ToolResult(success: false, output: "Failed to save screenshot: \(error.localizedDescription)", screenshot: nil)
        }
    }

    // MARK: - Pixel Hash (Fast Change Detection)

    /// Computes a SHA-256 hash of a downsampled pixel grid from the CGImage.
    /// Samples `hashGridSize x hashGridSize` evenly-spaced pixels → fast and sufficient
    /// to detect any meaningful screen change (UI updates, cursor moves, text changes).
    private func computePixelHash(_ image: CGImage) -> String {
        // Create a tiny bitmap context to downsample
        let sampleSize = hashGridSize
        guard let context = CGContext(
            data: nil,
            width: sampleSize,
            height: sampleSize,
            bitsPerComponent: 8,
            bytesPerRow: sampleSize * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            // Fallback: return timestamp to force cache miss
            return UUID().uuidString
        }

        // Draw the full image into the tiny context (hardware-accelerated downscale)
        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: sampleSize, height: sampleSize))

        // Hash the raw pixel buffer
        guard let data = context.data else {
            return UUID().uuidString
        }

        let bufferSize = sampleSize * sampleSize * 4
        let pixelData = Data(bytes: data, count: bufferSize)
        let digest = SHA256.hash(data: pixelData)

        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}
