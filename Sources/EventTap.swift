import AppKit

private let keyCodeTab: Int64 = 48
private let keyCodeQ: Int64 = 12
private let keyCodeEscape: Int64 = 53
private let keyCodeLeftArrow: Int64 = 123
private let keyCodeRightArrow: Int64 = 124

final class EventTap {
    private var tap: CFMachPort?
    private let switcher: Switcher

    init?(switcher: Switcher) {
        self.switcher = switcher
        let mask = CGEventMask(
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)
        )
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let tap = Unmanaged<EventTap>.fromOpaque(refcon).takeUnretainedValue()
                return tap.handle(type: type, event: event)
            },
            userInfo: refcon
        ) else { return nil }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    deinit {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
    }

    // Runs on the main thread (the tap's run loop source is on the main run loop).
    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        let optionHeld = flags.contains(.maskAlternate)

        switch type {
        case .keyDown:
            if optionHeld && keyCode == keyCodeTab {
                if switcher.isActive {
                    switcher.advance(by: flags.contains(.maskShift) ? -1 : 1)
                } else {
                    switcher.open(backward: flags.contains(.maskShift))
                }
                return nil
            }
            if switcher.isActive {
                switch keyCode {
                case keyCodeEscape:
                    switcher.cancel()
                    return nil
                case keyCodeLeftArrow:
                    switcher.advance(by: -1)
                    return nil
                case keyCodeRightArrow:
                    switcher.advance(by: 1)
                    return nil
                case keyCodeQ where optionHeld:
                    // Ignore key repeat so holding ⌥Q doesn't quit app after app.
                    if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                        switcher.quitSelectedApp()
                    }
                    return nil
                default:
                    break
                }
            }
        case .keyUp:
            if switcher.isActive && (keyCode == keyCodeTab || keyCode == keyCodeQ) {
                return nil
            }
        case .flagsChanged:
            if switcher.isActive && !optionHeld {
                switcher.commit()
            }
        default:
            break
        }
        return Unmanaged.passUnretained(event)
    }
}
