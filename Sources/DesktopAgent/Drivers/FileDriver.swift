import Foundation

// MARK: - File Driver for analysis and operations

final class FileDriver {

    func readFile(path: String, maxLines: Int = 500) -> ToolResult {
        let expandedPath = NSString(string: path).expandingTildeInPath

        guard FileManager.default.fileExists(atPath: expandedPath) else {
            return ToolResult(success: false, output: "File not found: \(path)", screenshot: nil)
        }

        guard let data = FileManager.default.contents(atPath: expandedPath) else {
            return ToolResult(success: false, output: "Cannot read file: \(path)", screenshot: nil)
        }

        // Check if binary
        if let _ = data.range(of: Data([0x00]), in: data.startIndex..<min(data.startIndex + 512, data.endIndex)) {
            let size = ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
            return ToolResult(success: true, output: "[Binary file: \(size)]", screenshot: nil)
        }

        guard var text = String(data: data, encoding: .utf8) else {
            return ToolResult(success: false, output: "Cannot decode file as UTF-8", screenshot: nil)
        }

        // Truncate if too long
        let lines = text.components(separatedBy: "\n")
        if lines.count > maxLines {
            text = lines.prefix(maxLines).joined(separator: "\n")
            text += "\n\n... [truncated: showing \(maxLines) of \(lines.count) lines]"
        }

        return ToolResult(success: true, output: text, screenshot: nil)
    }

    func listDirectory(path: String, recursive: Bool = false, maxItems: Int = 100) -> ToolResult {
        let expandedPath = NSString(string: path).expandingTildeInPath
        let fm = FileManager.default

        guard fm.fileExists(atPath: expandedPath) else {
            return ToolResult(success: false, output: "Directory not found: \(path)", screenshot: nil)
        }

        do {
            let items: [String]
            if recursive {
                guard let enumerator = fm.enumerator(atPath: expandedPath) else {
                    return ToolResult(success: false, output: "Cannot enumerate: \(path)", screenshot: nil)
                }
                var all: [String] = []
                while let item = enumerator.nextObject() as? String {
                    all.append(item)
                    if all.count >= maxItems { break }
                }
                items = all
            } else {
                items = try fm.contentsOfDirectory(atPath: expandedPath)
            }

            let sorted = items.sorted()
            var output = "Directory: \(expandedPath) (\(sorted.count) items)\n"

            for item in sorted.prefix(maxItems) {
                let fullPath = (expandedPath as NSString).appendingPathComponent(item)
                var isDir: ObjCBool = false
                fm.fileExists(atPath: fullPath, isDirectory: &isDir)

                if isDir.boolValue {
                    output += "  📁 \(item)/\n"
                } else {
                    let attrs = try? fm.attributesOfItem(atPath: fullPath)
                    let size = attrs?[.size] as? Int64 ?? 0
                    let sizeStr = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
                    output += "  📄 \(item) (\(sizeStr))\n"
                }
            }

            if sorted.count > maxItems {
                output += "  ... and \(sorted.count - maxItems) more items"
            }

            return ToolResult(success: true, output: output, screenshot: nil)
        } catch {
            return ToolResult(success: false, output: "Error listing directory: \(error.localizedDescription)", screenshot: nil)
        }
    }

    func writeFile(path: String, content: String) -> ToolResult {
        let expandedPath = NSString(string: path).expandingTildeInPath
        do {
            try content.write(toFile: expandedPath, atomically: true, encoding: .utf8)
            return ToolResult(success: true, output: "File written: \(expandedPath) (\(content.count) chars)", screenshot: nil)
        } catch {
            return ToolResult(success: false, output: "Error writing file: \(error.localizedDescription)", screenshot: nil)
        }
    }

    func fileInfo(path: String) -> ToolResult {
        let expandedPath = NSString(string: path).expandingTildeInPath
        let fm = FileManager.default

        guard fm.fileExists(atPath: expandedPath) else {
            return ToolResult(success: false, output: "File not found: \(path)", screenshot: nil)
        }

        do {
            let attrs = try fm.attributesOfItem(atPath: expandedPath)
            let size = attrs[.size] as? Int64 ?? 0
            let modified = attrs[.modificationDate] as? Date
            let created = attrs[.creationDate] as? Date
            let type = attrs[.type] as? FileAttributeType

            var output = "Path: \(expandedPath)\n"
            output += "Type: \(type == .typeDirectory ? "Directory" : "File")\n"
            output += "Size: \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))\n"
            if let m = modified { output += "Modified: \(m)\n" }
            if let c = created { output += "Created: \(c)\n" }

            // For text files, show line count
            if type != .typeDirectory,
               let data = fm.contents(atPath: expandedPath),
               let text = String(data: data, encoding: .utf8) {
                let lines = text.components(separatedBy: "\n").count
                output += "Lines: \(lines)\n"
                output += "Encoding: UTF-8"
            }

            return ToolResult(success: true, output: output, screenshot: nil)
        } catch {
            return ToolResult(success: false, output: "Error: \(error.localizedDescription)", screenshot: nil)
        }
    }
}
