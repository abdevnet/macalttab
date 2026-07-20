import AppKit
import ApplicationServices

// Private but stable APIs, the same ones AltTab relies on. _AXUIElementGetWindow maps an
// AX window to its CGWindowID; the SkyLight pair forces focus onto a specific window,
// which public API can no longer do reliably under macOS 14+ cooperative activation.
@_silgen_name("_AXUIElementGetWindow")
@discardableResult
func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: inout CGWindowID) -> AXError

@_silgen_name("_SLPSSetFrontProcessWithOptions")
@discardableResult
func _SLPSSetFrontProcessWithOptions(_ psn: inout ProcessSerialNumber, _ windowID: CGWindowID, _ mode: UInt32) -> CGError

@_silgen_name("SLPSPostEventRecordTo")
@discardableResult
func SLPSPostEventRecordTo(_ psn: inout ProcessSerialNumber, _ bytes: UnsafeMutablePointer<UInt8>) -> CGError

// GetProcessForPID is Carbon-era and marked unavailable in Swift, but still exported.
@_silgen_name("GetProcessForPID")
func processSerialNumber(for pid: pid_t, _ psn: inout ProcessSerialNumber) -> OSStatus

// CGS Spaces APIs: the only way to enumerate windows on other Spaces — both
// kCGWindowListOptionOnScreenOnly and kAXWindowsAttribute are current-Space only.
typealias CGSConnectionID = UInt32

@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> CGSConnectionID

@_silgen_name("CGSCopyManagedDisplaySpaces")
func CGSCopyManagedDisplaySpaces(_ cid: CGSConnectionID) -> CFArray

@_silgen_name("CGSCopyWindowsWithOptionsAndTags")
func CGSCopyWindowsWithOptionsAndTags(_ cid: CGSConnectionID, _ owner: Int, _ spaces: CFArray, _ options: Int, _ setTags: inout UInt64, _ clearTags: inout UInt64) -> CFArray

private let kCPSUserGenerated: UInt32 = 0x200

struct SpaceLocation {
    let spaceID: UInt64
    let displayUUID: String
}

struct WindowInfo {
    let windowID: CGWindowID
    let pid: pid_t
    let appName: String
    let title: String
    let axWindow: AXUIElement?  // nil for windows on other Spaces (AX can't see them)
    let isMinimized: Bool
    let icon: NSImage?
    let bounds: CGRect  // CG coordinates (top-left origin)
    let space: SpaceLocation?

    var displayTitle: String { title.isEmpty ? appName : title }

    func focus() {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return }
        if app.isHidden { app.unhide() }
        if isMinimized, let axWindow {
            AXUIElementSetAttributeValue(axWindow, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        switchToSpaceIfNeeded()
        var psn = ProcessSerialNumber()
        if processSerialNumber(for: pid, &psn) == noErr {
            _SLPSSetFrontProcessWithOptions(&psn, windowID, kCPSUserGenerated)
            makeKeyWindow(psn: &psn)
        }
        if let axWindow {
            AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(axWindow, kAXMainAttribute as CFString, kCFBooleanTrue)
        }
    }

    // The SkyLight focus calls don't switch Spaces on their own, so jump to the
    // window's Space first when it isn't the current one.
    private func switchToSpaceIfNeeded() {
        guard let space else { return }
        for display in CGSCopyManagedDisplaySpaces(CGSMainConnectionID()) as? [[String: Any]] ?? [] {
            guard let uuid = display["Display Identifier"] as? String, uuid == space.displayUUID
            else { continue }
            let ordered = (display["Spaces"] as? [[String: Any]] ?? [])
                .compactMap { ($0["id64"] as? NSNumber)?.uint64Value }
            guard let current = ((display["Current Space"] as? [String: Any])?["id64"] as? NSNumber)?.uint64Value,
                  current != space.spaceID,
                  let fromIndex = ordered.firstIndex(of: current),
                  let toIndex = ordered.firstIndex(of: space.spaceID)
            else { return }
            moveSpaces(by: toIndex - fromIndex)
            return
        }
    }

    // Drives the real Mission Control shortcut (^← / ^→) so the Dock performs the
    // switch. CGSManagedDisplaySetCurrentSpace only flips the logical Space on
    // modern macOS and leaves the display showing the old desktop. The symbolic
    // hotkey only fires for the full sequence: a real Control press wrapping the
    // arrow, not just an arrow event carrying the Control flag.
    private func moveSpaces(by delta: Int) {
        guard delta != 0, let source = CGEventSource(stateID: .hidSystemState) else { return }
        let arrowKey: CGKeyCode = delta > 0 ? 124 : 123
        let controlKey: CGKeyCode = 59
        let controlDown = CGEvent(keyboardEventSource: source, virtualKey: controlKey, keyDown: true)
        controlDown?.flags = .maskControl
        controlDown?.post(tap: .cghidEventTap)
        // Real arrow-key hardware events carry Fn + numeric-pad flags; the symbolic
        // hotkey matcher won't recognize the shortcut without them.
        let arrowFlags: CGEventFlags = [.maskControl, .maskSecondaryFn, .maskNumericPad]
        for _ in 0 ..< abs(delta) {
            let down = CGEvent(keyboardEventSource: source, virtualKey: arrowKey, keyDown: true)
            down?.flags = arrowFlags
            let up = CGEvent(keyboardEventSource: source, virtualKey: arrowKey, keyDown: false)
            up?.flags = arrowFlags
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
            usleep(120_000)
        }
        let controlUp = CGEvent(keyboardEventSource: source, virtualKey: controlKey, keyDown: false)
        controlUp?.post(tap: .cghidEventTap)
    }

    // Posts synthetic focus events straight to the target process so the chosen
    // window (not just the app) becomes key.
    private func makeKeyWindow(psn: inout ProcessSerialNumber) {
        var windowID = self.windowID
        var bytes = [UInt8](repeating: 0, count: 0xf8)
        bytes[0x04] = 0xf8
        bytes[0x3a] = 0x10
        withUnsafeBytes(of: &windowID) { widBytes in
            for (offset, byte) in widBytes.enumerated() {
                bytes[0x3c + offset] = byte
            }
        }
        for offset in 0x20 ..< 0x30 {
            bytes[offset] = 0xff
        }
        bytes[0x08] = 0x01
        SLPSPostEventRecordTo(&psn, &bytes)
        bytes[0x08] = 0x02
        SLPSPostEventRecordTo(&psn, &bytes)
    }
}

enum WindowEnumerator {
    private struct AXEntry {
        let element: AXUIElement
        let title: String
        let isMinimized: Bool
    }

    static func list() -> [WindowInfo] {
        let myPid = getpid()
        var axEntries: [pid_t: [CGWindowID: AXEntry]] = [:]
        var appInfo: [pid_t: (name: String, icon: NSImage?)] = [:]

        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            let pid = app.processIdentifier
            guard pid != myPid else { continue }
            if !Settings.includeFinderWindows, app.bundleIdentifier == "com.apple.finder" { continue }
            appInfo[pid] = (app.localizedName ?? "", app.icon)

            let axApp = AXUIElementCreateApplication(pid)
            var windowsRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                  let axWindows = windowsRef as? [AXUIElement] else { continue }

            var entries: [CGWindowID: AXEntry] = [:]
            for axWindow in axWindows {
                var windowID = CGWindowID(0)
                guard _AXUIElementGetWindow(axWindow, &windowID) == .success, windowID != 0 else { continue }

                var subroleRef: CFTypeRef?
                AXUIElementCopyAttributeValue(axWindow, kAXSubroleAttribute as CFString, &subroleRef)
                if let subrole = subroleRef as? String,
                   subrole != kAXStandardWindowSubrole as String,
                   subrole != kAXDialogSubrole as String {
                    continue
                }

                var titleRef: CFTypeRef?
                AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef)
                var minimizedRef: CFTypeRef?
                AXUIElementCopyAttributeValue(axWindow, kAXMinimizedAttribute as CFString, &minimizedRef)

                entries[windowID] = AXEntry(
                    element: axWindow,
                    title: titleRef as? String ?? "",
                    isMinimized: (minimizedRef as? Bool) ?? false
                )
            }
            axEntries[pid] = entries
        }

        var result: [WindowInfo] = []
        var seen = Set<CGWindowID>()
        let spacesByWindow = windowSpaces()

        // On-screen windows first, in z-order (front to back = most recently used).
        let cgList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        for entry in cgList {
            guard let pidNumber = entry[kCGWindowOwnerPID as String] as? NSNumber,
                  let widNumber = entry[kCGWindowNumber as String] as? NSNumber,
                  (entry[kCGWindowLayer as String] as? NSNumber)?.intValue == 0
            else { continue }
            let pid = pid_t(pidNumber.int32Value)
            let windowID = CGWindowID(widNumber.uint32Value)
            guard let info = appInfo[pid],
                  let ax = axEntries[pid]?[windowID],
                  !seen.contains(windowID)
            else { continue }
            seen.insert(windowID)
            let bounds = (entry[kCGWindowBounds as String] as? NSDictionary).flatMap {
                CGRect(dictionaryRepresentation: $0 as CFDictionary)
            } ?? .zero
            result.append(WindowInfo(windowID: windowID, pid: pid, appName: info.name, title: ax.title,
                                     axWindow: ax.element, isMinimized: ax.isMinimized, icon: info.icon,
                                     bounds: bounds, space: spacesByWindow[windowID]))
        }

        // Then windows on other Spaces: the all-windows list intersected with the ids
        // the CGS Spaces API reports as belonging to a Space. The intersection filters
        // out invisible helper windows (CGWindowListCreateDescriptionFromArray would be
        // the direct route but returns nothing on macOS 26). Titles come from CG
        // (needs Screen Recording) since AX can't see other-Space windows.
        let allWindows = CGWindowListCopyWindowInfo([.excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        for entry in allWindows {
            guard let pidNumber = entry[kCGWindowOwnerPID as String] as? NSNumber,
                  let widNumber = entry[kCGWindowNumber as String] as? NSNumber,
                  (entry[kCGWindowLayer as String] as? NSNumber)?.intValue == 0
            else { continue }
            let pid = pid_t(pidNumber.int32Value)
            let windowID = CGWindowID(widNumber.uint32Value)
            guard let space = spacesByWindow[windowID],
                  let info = appInfo[pid], !seen.contains(windowID) else { continue }
            let bounds = (entry[kCGWindowBounds as String] as? NSDictionary).flatMap {
                CGRect(dictionaryRepresentation: $0 as CFDictionary)
            } ?? .zero
            let ax = axEntries[pid]?[windowID]
            let title = ax?.title ?? (entry[kCGWindowName as String] as? String ?? "")
            guard ax != nil || (bounds.width >= 100 && bounds.height >= 72) else { continue }
            seen.insert(windowID)
            result.append(WindowInfo(windowID: windowID, pid: pid, appName: info.name, title: title,
                                     axWindow: ax?.element, isMinimized: ax?.isMinimized ?? false,
                                     icon: info.icon, bounds: bounds, space: space))
        }

        // Finally, minimized / hidden windows AX knows about that CGS didn't report.
        var extras: [WindowInfo] = []
        for (pid, entries) in axEntries {
            guard let info = appInfo[pid] else { continue }
            for (windowID, ax) in entries where !seen.contains(windowID) {
                extras.append(WindowInfo(windowID: windowID, pid: pid, appName: info.name, title: ax.title,
                                         axWindow: ax.element, isMinimized: ax.isMinimized, icon: info.icon,
                                         bounds: axRect(of: ax.element), space: spacesByWindow[windowID]))
            }
        }
        extras.sort {
            ($0.appName, $0.title, $0.windowID) < ($1.appName, $1.title, $1.windowID)
        }
        result.append(contentsOf: extras)
        return result
    }

    private static func windowSpaces() -> [CGWindowID: SpaceLocation] {
        let cid = CGSMainConnectionID()
        var result: [CGWindowID: SpaceLocation] = [:]
        for display in CGSCopyManagedDisplaySpaces(cid) as? [[String: Any]] ?? [] {
            guard let uuid = display["Display Identifier"] as? String else { continue }
            for space in display["Spaces"] as? [[String: Any]] ?? [] {
                guard let spaceID = (space["id64"] as? NSNumber)?.uint64Value else { continue }
                var setTags: UInt64 = 0
                var clearTags: UInt64 = 0
                let ids = CGSCopyWindowsWithOptionsAndTags(cid, 0, [spaceID] as CFArray, 2, &setTags, &clearTags)
                    as? [NSNumber] ?? []
                for id in ids {
                    let windowID = CGWindowID(id.uint32Value)
                    if result[windowID] == nil {
                        result[windowID] = SpaceLocation(spaceID: spaceID, displayUUID: uuid)
                    }
                }
            }
        }
        return result
    }

    private static func axRect(of element: AXUIElement) -> CGRect {
        var rect = CGRect.zero
        var positionRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) == .success,
           let positionRef, CFGetTypeID(positionRef) == AXValueGetTypeID() {
            AXValueGetValue(positionRef as! AXValue, .cgPoint, &rect.origin)
        }
        var sizeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
           let sizeRef, CFGetTypeID(sizeRef) == AXValueGetTypeID() {
            AXValueGetValue(sizeRef as! AXValue, .cgSize, &rect.size)
        }
        return rect
    }
}
