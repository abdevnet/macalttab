import AppKit
import ScreenCaptureKit

enum Thumbnailer {
    // Serves last-known thumbnails instantly while fresh captures arrive.
    private static var cache: [CGWindowID: NSImage] = [:]

    static func capture(for windows: [WindowInfo], update: @escaping (CGWindowID, NSImage) -> Void) {
        let wanted = Set(windows.map { $0.windowID })
        cache = cache.filter { wanted.contains($0.key) }
        for window in windows {
            if let cached = cache[window.windowID] {
                update(window.windowID, cached)
            }
        }

        SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: false) { content, _ in
            guard let content else { return }
            var scWindows: [CGWindowID: SCWindow] = [:]
            for scWindow in content.windows {
                scWindows[scWindow.windowID] = scWindow
            }
            for window in windows {
                guard let scWindow = scWindows[window.windowID] else { continue }
                let frame = scWindow.frame
                guard frame.width > 1, frame.height > 1 else { continue }

                // Up to 2x (retina), capped so huge windows don't produce huge captures.
                let scale = min(2.0, 2048.0 / max(frame.width, frame.height))
                let config = SCStreamConfiguration()
                config.width = Int(frame.width * scale)
                config.height = Int(frame.height * scale)
                config.showsCursor = false
                config.ignoreShadowsSingleWindow = true

                let filter = SCContentFilter(desktopIndependentWindow: scWindow)
                SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) { cgImage, _ in
                    guard let cgImage else { return }
                    let size = NSSize(width: cgImage.width / 2, height: cgImage.height / 2)
                    let image = NSImage(cgImage: cgImage, size: size)
                    DispatchQueue.main.async {
                        cache[window.windowID] = image
                        update(window.windowID, image)
                    }
                }
            }
        }
    }
}
