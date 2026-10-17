# Improvements

## 2026-10-17 - Stage 1: skeleton

Status: delivered.

- SwiftPM package with modules `FringeApp`, `FringeNotch`, `FringeCore`, five tab modules and the local `Packages/FringeProtocol`.
- Notch panel adapted from Switchboard (geometry, window level, click-through, hover delays 120/350 ms, built-in display only, screen changes; Coucou MIT). States hidden/compact/peek/expanded; compact strip shows the buddy and agent count on the left, unread mail on the right; expanded panel 480×420 with a tab bar, last tab remembered.
- Peek queue with priorities (agent request 8 s on the Agents tab, then the previous tab once the pointer leaves; agent done 4 s; mail 5 s). A more urgent event interrupts and the interrupted one returns; bursts keep the newest three per kind; peeks wait while the panel is open.
- Keyboard: the panel becomes key for text input, stays open while typing, closes on Esc or a click elsewhere. Global shortcut (Carbon, default ⌃⌥T, recordable, can be turned off) opens the Translate tab.
- Settings window (General + per-tab sections): open at login (`SMAppService.mainApp`), auto-hide, sounds, system notifications, shortcut, interface language RU/EN.
- `scripts/build-app.sh` builds `build/Fringe.app` (`local.daniil.fringe`, LSUIElement, macOS 15+), signed with the Apple Development identity.

Validation: `swift build` and `scripts/build-app.sh` succeeded; 14 FringeCore tests and 1 protocol test passed.
