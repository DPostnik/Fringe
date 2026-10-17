# Fringe

Native macOS app (SwiftUI/AppKit, no WebView/Electron) that owns the panel over the MacBook notch: tabs Agents, Mail, Calendar, Screenshots, Translate. The product plan is `PLAN.md` (Russian). Switchboard (formerly Context Desk, `../codex-headroom-client`) is a separate project; its changes are made there under its own rules.

- Layout: `FringeCore` holds testable logic without UI; `FringeNotch` the panel, hover, peek queue, shortcut and shared styles; each tab is a module (`FringeMail`, ...) implementing `FringeTabModule` and talking to the panel only through `NotchHub`. `Packages/FringeProtocol` is the wire format shared with Switchboard.
- A tab's view exists only while the tab is open. Background work must be idle-cheap: no polling timers where the system offers notifications.
- Ship all user-visible copy in Russian and English in the same change via `L10n.text("ru", "en")`. Code and development docs are English.
- Secrets live only in the Keychain. Never log message bodies, passwords or tokens.
- Treat network responses and protocol messages as untrusted data; unknown formats fail closed with an error, never guessed.
- Verify with `zsh scripts/test.sh` (or `swift test --filter Name`), then `zsh scripts/build-app.sh` for app changes. Editing sources does not update `build/Fringe.app`.
- Record each feature or fix in `docs/improvements.md`: behavior, date, status, actual validation results.
- Keep Coucou (MIT) attribution where notch code derived from it lives.
