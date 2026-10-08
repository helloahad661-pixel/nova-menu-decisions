# nova-menu-decisions

Swift menu-bar app for macOS: press Ctrl+Option+Cmd+N, and whatever is on the
clipboard is sent to a local AI decision engine, with the answer posted as a
notification.

Deliberately uses a Carbon hot key instead of a key-event tap — taps need
Accessibility permission, which macOS ties to the binary's code hash, so every
rebuild silently breaks the grant. A hot key needs no permission and cannot
break that way.

```bash
swiftc -O -o NovaMenu.app/Contents/MacOS/NovaMenu NovaMenu.swift
codesign --force --sign - --identifier com.nova.menu NovaMenu.app
```

Needs Xcode command-line tools and a decision endpoint (Nova uses Laya on
port 8767). Part of [Nova](https://github.com/helloahad661-pixel/Nova), my macOS assistant system — `laya_agent` looks after this piece.
