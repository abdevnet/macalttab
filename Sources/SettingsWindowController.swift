import AppKit
import ServiceManagement

final class SettingsWindowController: NSWindowController {
    private let finderCheckbox = NSButton(checkboxWithTitle: "Include Finder windows", target: nil, action: nil)
    private let loginCheckbox = NSButton(checkboxWithTitle: "Start at login", target: nil, action: nil)

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 108),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "MyAltTab Settings"
        window.isReleasedWhenClosed = false
        self.init(window: window)

        finderCheckbox.target = self
        finderCheckbox.action = #selector(toggleFinder(_:))
        loginCheckbox.target = self
        loginCheckbox.action = #selector(toggleLogin(_:))

        let stack = NSStackView(views: [finderCheckbox, loginCheckbox])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        if let content = window.contentView {
            content.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.topAnchor.constraint(equalTo: content.topAnchor),
                stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                stack.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor),
                stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor),
            ])
        }
    }

    func show() {
        guard let window else { return }
        finderCheckbox.state = Settings.includeFinderWindows ? .on : .off
        loginCheckbox.state = SMAppService.mainApp.status == .enabled ? .on : .off
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func toggleFinder(_ sender: NSButton) {
        Settings.includeFinderWindows = sender.state == .on
    }

    @objc private func toggleLogin(_ sender: NSButton) {
        do {
            if sender.state == .on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            sender.state = sender.state == .on ? .off : .on
            NSAlert(error: error).runModal()
        }
    }
}
