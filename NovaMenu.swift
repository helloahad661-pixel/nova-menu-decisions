// Nova Menu: a status-bar item that runs Laya on the clipboard.
//
// Why not the hold-Enter-3s listener in launchd/nova_hold_listener.c:
// tapping raw keystrokes needs Accessibility, and TCC identifies an ad-hoc
// signed app by its code hash. This machine has zero code-signing identities,
// so every rebuild produced a new hash and silently invalidated the grant.
// A status-bar item and a Carbon hot key need NO permission at all, so they
// cannot break that way.
//
// Trigger:  click "Decide now", or press Ctrl+Option+Cmd+N from anywhere.
//
// The decide+notify work stays in python (core/nova_hold.py --print). This
// process only owns the menu, the hot key, and posting the notification under
// Nova's own name.

import AppKit
import Carbon.HIToolbox
import UserNotifications

let PY = "/Users/noor/Nova/venv/bin/python"
let SCRIPT = "/Users/noor/Nova/core/nova_hold.py"

var hotKeyRef: EventHotKeyRef?

// A trigger that fires but shows nothing is indistinguishable from a broken
// one, so every attempt is recorded whether or not the notification lands.
func trace(_ s: String) {
    let line = "\(Date().description) \(s)\n"
    if let h = FileHandle(forWritingAtPath: "/tmp/nova_menu.log") {
        h.seekToEndOfFile()
        h.write(line.data(using: .utf8)!)
        try? h.close()
    } else {
        try? line.write(toFile: "/tmp/nova_menu.log", atomically: true, encoding: .utf8)
    }
}

// AppleScript string literal. The decision text is model output, so it can and
// does contain quotes and backslashes.
func asScriptString(_ s: String) -> String {
    let e = s.replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
    return "\"\(e)\""
}

// Fallback path. UNUserNotificationCenter already refused us once (a bundle
// missing CFBundleVersion never registers with the notification daemon), and
// when it is not authorized it drops the request with no error at all. So check
// the status first and use the auth-free path when it is not authorized.
func deliverViaScript(_ subtitle: String, _ body: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    p.arguments = ["-e", "display notification \(asScriptString(body)) "
                        + "with title \"Nova\" subtitle \(asScriptString(subtitle))"]
    do {
        try p.run()
        p.waitUntilExit()
        trace("delivered via osascript '\(subtitle)'")
    } catch {
        trace("osascript fallback FAILED: \(error)")
    }
}

func notify(_ subtitle: String, _ body: String) {
    let center = UNUserNotificationCenter.current()
    center.getNotificationSettings { s in
        let ok = s.authorizationStatus == .authorized || s.authorizationStatus == .provisional
        guard ok else {
            trace("not authorized (status \(s.authorizationStatus.rawValue)) -> falling back")
            deliverViaScript(subtitle, body)
            return
        }
        let c = UNMutableNotificationContent()
        c.title = "Nova"
        c.subtitle = subtitle
        c.body = body
        let req = UNNotificationRequest(
            identifier: "nova-\(UUID().uuidString)", content: c, trigger: nil)
        center.add(req) { err in
            trace("notify '\(subtitle)' err=\(err.map { "\($0)" } ?? "none")")
        }
    }
}

func decide() {
    trace("trigger fired")
    let p = Process()
    p.executableURL = URL(fileURLWithPath: PY)
    p.arguments = [SCRIPT, "--print"]
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    do {
        try p.run()
    } catch {
        notify("could not start", "\(error)")
        return
    }
    p.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    var out = String(data: data, encoding: .utf8) ?? ""
    out = out.trimmingCharacters(in: .whitespacesAndNewlines)
    if out.isEmpty {
        notify("no answer", "Laya returned nothing")
        return
    }
    // First line is the preset, the rest is the decision.
    let parts = out.split(separator: "\n", maxSplits: 1).map(String.init)
    notify(parts[0], parts.count > 1 ? parts[1] : out)
}

func hotKeyHandler(_ next: EventHandlerCallRef?, _ event: EventRef?, _ user: UnsafeMutableRawPointer?) -> OSStatus {
    DispatchQueue.main.async { decide() }
    return noErr
}

var eventHandlerRef: EventHandlerRef?

func installHotKey() {
    let target = GetEventDispatcherTarget()

    // Swift's Carbon overlay takes a dispatcher target, not a proc, so the
    // handler has to be installed on the dispatcher and the hot key linked to
    // it via the shared EventHotKeyID.
    var spec = EventTypeSpec(
        eventClass: OSType(kEventClassKeyboard),
        eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(
        target, hotKeyHandler, 1, &spec, nil, &eventHandlerRef)

    let id = EventHotKeyID(signature: OSType(0x4E4F5641), id: 1)  // 'NOVA'
    RegisterEventHotKey(
        UInt32(kVK_ANSI_N),
        UInt32(controlKey | optionKey | cmdKey),
        id, target, 0, &hotKeyRef)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)  // no Dock icon, menu bar only

// Without this the notification is silently dropped. He approves once and it
// never asks again.
UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) {
    granted, err in
    trace("notification auth granted=\(granted) err=\(err.map { "\($0)" } ?? "none")")
}

let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
item.button?.title = "Nova"

let menu = NSMenu()

final class Target: NSObject {
    @objc func fire() { decide() }
    @objc func quit() { NSApp.terminate(nil) }
}
let target = Target()

let d = NSMenuItem(title: "Decide on clipboard  ⌃⌥⌘N", action: #selector(Target.fire),
                   keyEquivalent: "")
d.target = target
let q = NSMenuItem(title: "Quit Nova", action: #selector(Target.quit), keyEquivalent: "q")
q.target = target
menu.addItem(d)
menu.addItem(.separator())
menu.addItem(q)
item.menu = menu

installHotKey()
app.run()
