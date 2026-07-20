import AppKit

final class Switcher {
    private(set) var isActive = false
    private var windows: [WindowInfo] = []
    private var selection = 0
    private lazy var panel = SwitcherPanel()

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

    private func close() {
        isActive = false
        panel.orderOut(nil)
        windows = []
    }
}
