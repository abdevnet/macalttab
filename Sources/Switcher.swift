import AppKit

final class Switcher {
    private(set) var isActive = false
    private var windows: [WindowInfo] = []
    private var selection = 0
    private lazy var panel: SwitcherPanel = {
        let panel = SwitcherPanel()
        panel.onHover = { [weak self] in self?.hover(windowID: $0) }
        panel.onClick = { [weak self] in self?.click(windowID: $0) }
        panel.onQuit = { [weak self] in self?.quitApp(windowID: $0) }
        return panel
    }()

    func open(backward: Bool) {
        windows = WindowEnumerator.list()
        guard !windows.isEmpty else { return }
        isActive = true
        selection = windows.count > 1 ? (backward ? windows.count - 1 : 1) : 0
        panel.present(windows: windows, selected: selection)
        Thumbnailer.capture(for: windows) { [weak self] windowID, image in
            self?.panel.updateThumbnail(windowID: windowID, image: image)
        }
    }

    func advance(by delta: Int) {
        guard isActive, !windows.isEmpty else { return }
        let count = windows.count
        selection = ((selection + delta) % count + count) % count
        panel.select(index: selection)
    }

    func commit() {
        guard isActive else { return }
        let target = windows.indices.contains(selection) ? windows[selection] : nil
        close()
        // Deferred so focus (and any synthetic Space-switch key events) runs after
        // the event tap callback that triggered the commit has returned.
        if let target {
            DispatchQueue.main.async { target.focus() }
        }
    }

    func cancel() {
        close()
    }

    func quitSelectedApp() {
        guard isActive, windows.indices.contains(selection) else { return }
        quitApp(at: selection)
    }

    private func hover(windowID: CGWindowID) {
        guard isActive, let index = index(of: windowID), index != selection else { return }
        selection = index
        panel.select(index: index)
    }

    private func click(windowID: CGWindowID) {
        guard isActive, let index = index(of: windowID) else { return }
        selection = index
        commit()
    }

    private func quitApp(windowID: CGWindowID) {
        guard isActive, let index = index(of: windowID) else { return }
        quitApp(at: index)
    }

    // Quits the app owning the window at `index` and drops all its tiles, keeping
    // the switcher open so more apps can be quit or switched to.
    private func quitApp(at index: Int) {
        let pid = windows[index].pid
        let selectedID = windows.indices.contains(selection) ? windows[selection].windowID : nil
        NSRunningApplication(processIdentifier: pid)?.terminate()
        windows.removeAll { $0.pid == pid }
        guard !windows.isEmpty else {
            cancel()
            return
        }
        selection = windows.firstIndex { $0.windowID == selectedID } ?? min(index, windows.count - 1)
        panel.reload(windows: windows, selected: selection)
    }

    private func index(of windowID: CGWindowID) -> Int? {
        windows.firstIndex { $0.windowID == windowID }
    }

    private func close() {
        isActive = false
        panel.orderOut(nil)
        windows = []
    }
}
