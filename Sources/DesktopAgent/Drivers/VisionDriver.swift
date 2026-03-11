import Foundation
import CoreGraphics
import AppKit

// MARK: - Vision Driver (Screenshots)

final class VisionDriver {

    /// Maximum width for screenshots sent to the AI (to save tokens/cost)
    var maxWidth: Int = 1280

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

        guard let tiffData = nsImage.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) else {
            return ToolResult(success: false, output: "Failed to encode screenshot", screenshot: nil)
        }

        let sizeKB = jpegData.count / 1024
        let finalWidth = nsImage.size.width
        let finalHeight = nsImage.size.height

        return ToolResult(
            success: true,
            output: "Screenshot captured: \(Int(finalWidth))x\(Int(finalHeight)) (\(sizeKB)KB) — original \(image.width)x\(image.height)",
            screenshot: jpegData
        )
    }

    func takeScreenshotBase64(region: ScreenRegion? = nil) -> (base64: String, description: String)? {
        let result = takeScreenshot(region: region)
        guard result.success, let data = result.screenshot else { return nil }
        return (data.base64EncodedString(), result.output)
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
}
