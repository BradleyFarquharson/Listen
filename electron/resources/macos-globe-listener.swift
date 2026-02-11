import Cocoa

// Globe (fn) key listener for macOS.
// Uses a CGEvent tap to detect fn key press/release events.
// Outputs "FN_DOWN" or "FN_UP" to stdout for the parent process.
// Requires Accessibility permission.

var fnDown = false

func callback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if type == .flagsChanged {
        let flags = event.flags
        let containsFn = flags.contains(.maskSecondaryFn)

        // Filter out modifier-only combos: if any other modifier is held
        // alongside fn, ignore it (user is doing cmd+fn, shift+fn, etc.)
        let otherModifiers: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]
        let hasOtherModifier = !flags.intersection(otherModifiers).isEmpty

        if containsFn && !hasOtherModifier && !fnDown {
            fnDown = true
            print("FN_DOWN")
            fflush(stdout)
        } else if !containsFn && fnDown {
            fnDown = false
            print("FN_UP")
            fflush(stdout)
        }
    }

    // If the tap is disabled by the system (timeout), re-enable it
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let refcon = refcon {
            let tap = Unmanaged<CFMachPort>.fromOpaque(refcon).takeUnretainedValue()
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    return Unmanaged.passRetained(event)
}

// Create event tap for flagsChanged events (modifier key changes)
let eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)

guard let eventTap = CGEvent.tapCreate(
    tap: .cghidEventTap,
    place: .headInsertEventTap,
    options: .listenOnly,
    eventsOfInterest: eventMask,
    callback: callback,
    userInfo: nil
) else {
    fputs("ERROR: Could not create event tap. Grant Accessibility permission in System Settings.\n", stderr)
    exit(1)
}

// Pass the tap reference so we can re-enable it if it times out
let tapPointer = Unmanaged.passUnretained(eventTap).toOpaque()

// Re-create with the userInfo pointer
guard let eventTapWithInfo = CGEvent.tapCreate(
    tap: .cghidEventTap,
    place: .headInsertEventTap,
    options: .listenOnly,
    eventsOfInterest: eventMask,
    callback: callback,
    userInfo: tapPointer
) else {
    fputs("ERROR: Could not create event tap.\n", stderr)
    exit(1)
}

let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTapWithInfo, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
CGEvent.tapEnable(tap: eventTapWithInfo, enable: true)

// Signal ready
print("READY")
fflush(stdout)

CFRunLoopRun()
