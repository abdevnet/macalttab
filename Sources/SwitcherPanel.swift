import AppKit

private let tilePadding: CGFloat = 10
private let headerHeight: CGFloat = 24
private let panelPadding: CGFloat = 24
private let tileGap: CGFloat = 14

final class SwitcherPanel: NSPanel {
    private var tiles: [TileView] = []
    private var tilesByWindowID: [CGWindowID: TileView] = [:]
    private var windows: [WindowInfo] = []
    private var images: [CGWindowID: NSImage] = [:]
    private var selectedIndex = 0
    private let effectView = NSVisualEffectView()
    private let preview = PreviewWindow()

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none

        effectView.material = .popover
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 26
        effectView.layer?.masksToBounds = true
        contentView = effectView
    }

    func present(windows: [WindowInfo], selected: Int) {
        self.windows = windows
        images = [:]
        for tile in tiles { tile.removeFromSuperview() }
        tiles = windows.map { TileView(window: $0) }
        tilesByWindowID = [:]
        for tile in tiles {
            tilesByWindowID[tile.windowID] = tile
            effectView.addSubview(tile)
        }

        let screen = NSScreen.main ?? NSScreen.screens.first!
        let visible = screen.visibleFrame
        let maxContentWidth = visible.width * 0.63

        func layout(forTileWidth tileWidth: CGFloat)
        -> (tileHeight: CGFloat, perRow: Int, contentWidth: CGFloat, panelWidth: CGFloat, panelHeight: CGFloat) {
            let thumbHeight = (tileWidth - tilePadding * 2) * 0.62
            let tileHeight = thumbHeight + headerHeight + 6 + tilePadding * 2
            let perRow = max(1, min(windows.count, Int((maxContentWidth + tileGap) / (tileWidth + tileGap))))
            let rows = (windows.count + perRow - 1) / perRow
            let contentWidth = CGFloat(perRow) * tileWidth + CGFloat(perRow - 1) * tileGap
            return (tileHeight, perRow, contentWidth,
                    contentWidth + panelPadding * 2,
                    CGFloat(rows) * tileHeight + CGFloat(rows - 1) * tileGap + panelPadding * 2)
        }

        // AltTab-like sizing: tiles ~28% of a panel capped at 63% screen width,
        // shrinking if the rows would overflow 87% of screen height.
        var tileWidth = min(max(maxContentWidth * 0.28, 280), 700)
        var metrics = layout(forTileWidth: tileWidth)
        while metrics.panelHeight > visible.height * 0.87 && tileWidth > 220 {
            tileWidth *= 0.9
            metrics = layout(forTileWidth: tileWidth)
        }

        for (index, tile) in tiles.enumerated() {
            let row = index / metrics.perRow
            let col = index % metrics.perRow
            let tilesInRow = min(metrics.perRow, windows.count - row * metrics.perRow)
            let rowWidth = CGFloat(tilesInRow) * tileWidth + CGFloat(tilesInRow - 1) * tileGap
            let x = panelPadding + (metrics.contentWidth - rowWidth) / 2 + CGFloat(col) * (tileWidth + tileGap)
            let y = metrics.panelHeight - panelPadding - CGFloat(row + 1) * metrics.tileHeight - CGFloat(row) * tileGap
            tile.frame = NSRect(x: x, y: y, width: tileWidth, height: metrics.tileHeight)
            tile.layoutContents()
        }

        let panelFrame = NSRect(
            x: visible.midX - metrics.panelWidth / 2,
            y: visible.midY - metrics.panelHeight / 2,
            width: metrics.panelWidth,
            height: metrics.panelHeight
        )
        setFrame(panelFrame, display: true)
        orderFrontRegardless()
        select(index: selected)
    }

    func select(index: Int) {
        selectedIndex = index
        for (i, tile) in tiles.enumerated() {
            tile.setSelected(i == index)
        }
        updatePreview()
    }

    func updateThumbnail(windowID: CGWindowID, image: NSImage) {
        images[windowID] = image
        tilesByWindowID[windowID]?.setThumbnail(image)
        if windows.indices.contains(selectedIndex), windows[selectedIndex].windowID == windowID {
            updatePreview()
        }
    }

    override func orderOut(_ sender: Any?) {
        preview.orderOut(nil)
        super.orderOut(sender)
    }

    // AltTab-style: the selected window is previewed full-size at its real
    // position behind the panel, so you see what you're switching to.
    private func updatePreview() {
        guard isVisible, windows.indices.contains(selectedIndex) else {
            preview.orderOut(nil)
            return
        }
        let window = windows[selectedIndex]
        guard !window.isMinimized,
              window.bounds.width > 10, window.bounds.height > 10,
              let image = images[window.windowID] else {
            preview.orderOut(nil)
            return
        }
        preview.show(image: image, frame: cocoaRect(fromCGRect: window.bounds), below: self)
    }
}

// CG window coordinates have a top-left origin; Cocoa's are bottom-left on the primary screen.
private func cocoaRect(fromCGRect rect: CGRect) -> NSRect {
    let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
    return NSRect(x: rect.origin.x,
                  y: primaryHeight - rect.origin.y - rect.height,
                  width: rect.width,
                  height: rect.height)
}

final class PreviewWindow: NSWindow {
    private let imageView = NSImageView()

    init() {
        super.init(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isReleasedWhenClosed = false
        animationBehavior = .none

        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 12
        container.layer?.masksToBounds = true
        container.layer?.borderWidth = 4
        imageView.imageScaling = .scaleAxesIndependently
        container.addSubview(imageView)
        contentView = container
    }

    func show(image: NSImage, frame: NSRect, below panel: NSWindow) {
        imageView.image = image
        setFrame(frame, display: false)
        if let container = contentView {
            container.layer?.borderColor = NSColor.controlAccentColor.cgColor
            imageView.frame = container.bounds
        }
        order(.below, relativeTo: panel.windowNumber)
    }
}

final class TileView: NSView {
    let windowID: CGWindowID
    private let iconView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let thumbView = NSImageView()
    private let placeholderView = NSImageView()
    private var thumbArea: NSRect = .zero

    init(window: WindowInfo) {
        self.windowID = window.windowID
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 14

        iconView.image = window.icon
        iconView.imageScaling = .scaleProportionallyUpOrDown

        titleField.stringValue = window.displayTitle
        titleField.font = .systemFont(ofSize: 14, weight: .medium)
        titleField.textColor = .labelColor
        titleField.lineBreakMode = .byTruncatingTail
        titleField.maximumNumberOfLines = 1

        thumbView.imageScaling = .scaleAxesIndependently
        thumbView.wantsLayer = true
        thumbView.layer?.cornerRadius = 8
        thumbView.layer?.masksToBounds = true

        placeholderView.image = window.icon
        placeholderView.imageScaling = .scaleProportionallyUpOrDown

        addSubview(thumbView)
        addSubview(placeholderView)
        addSubview(iconView)
        addSubview(titleField)
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    func layoutContents() {
        let pad = tilePadding
        let iconSize: CGFloat = 22
        let headerY = bounds.height - pad - headerHeight
        iconView.frame = NSRect(x: pad + 2, y: headerY + (headerHeight - iconSize) / 2,
                                width: iconSize, height: iconSize)
        let titleX = pad + 2 + iconSize + 7
        titleField.frame = NSRect(x: titleX, y: headerY + (headerHeight - 18) / 2,
                                  width: bounds.width - titleX - pad, height: 18)
        thumbArea = NSRect(x: pad, y: pad, width: bounds.width - pad * 2,
                           height: bounds.height - pad * 2 - headerHeight - 6)
        thumbView.frame = thumbArea
        let side = min(128, max(64, thumbArea.height * 0.35))
        placeholderView.frame = NSRect(x: thumbArea.midX - side / 2, y: thumbArea.midY - side / 2,
                                       width: side, height: side)
        fitThumbnail()
    }

    func setSelected(_ selected: Bool) {
        layer?.borderWidth = selected ? 3 : 0
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        layer?.backgroundColor = selected
            ? NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
            : NSColor.clear.cgColor
    }

    func setThumbnail(_ image: NSImage) {
        thumbView.image = image
        placeholderView.isHidden = true
        fitThumbnail()
    }

    // Size the image view to the aspect-fitted rect so its rounded corners hug the image.
    private func fitThumbnail() {
        guard let image = thumbView.image,
              image.size.width > 0, image.size.height > 0,
              thumbArea.width > 0, thumbArea.height > 0 else { return }
        let scale = min(thumbArea.width / image.size.width, thumbArea.height / image.size.height, 1)
        let width = image.size.width * scale
        let height = image.size.height * scale
        thumbView.frame = NSRect(x: thumbArea.midX - width / 2, y: thumbArea.midY - height / 2,
                                 width: width, height: height)
    }
}
