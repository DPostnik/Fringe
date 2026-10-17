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

## 2026-10-17 - Stage 2: Screenshots tab

Status: implemented; live Spotlight results, the Desktop permission prompt and the actions still need a manual check.

- Latest 30 captures from the `com.apple.screencapture` `location` folder (fallback `~/Desktop`), newest first, 4-column grid with QuickLookThumbnailing thumbnails cached in memory.
- `NSMetadataQuery` on `kMDItemIsScreenCapture == 1`, only direct children of the folder, running only while the tab is visible; no polling. Screen recordings get a video badge.
- Click opens, drag to another app, copy (file URL plus PNG/TIFF data), show in Finder, move to Trash; hover buttons and a context menu. States: loading, empty, no Desktop access, folder missing, Spotlight failure with Retry.

Validation: 12 FringeScreenshotsTests passed; the tab rendered on the real notch (loading state while macOS asked for Desktop access).

## 2026-10-17 - Stage 3: Calendar tab

Status: implemented; the permission prompt, the `ical://` deep link and live refresh still need a manual check.

- Read-only EventKit agenda for 7 days: Today / Tomorrow / dated groups, time or "all day", calendar color; current event highlighted, next one counts down (`TimelineView(.everyMinute)`, only while visible).
- Full access requested on first show; states for not determined, denied (button to Privacy → Calendars) and restricted.
- Refresh on `EKEventStoreChanged`, `NSCalendarDayChanged` and wake; changes while hidden mark the list stale. Cancelled and declined events hidden.
- Join button for Meet, Zoom `/j/`, Teams meetup-join and teams.live.com links (strict host/path match); a row opens the event in Calendar.

Validation: 27 FringeCalendarTests passed; the tab rendered on the real notch in the "requesting access" state.

## 2026-10-17 - Stage 4: Translate tab

Status: implemented; typing, focus by shortcut and Apple Translation success need a manual check.

- Source/target pickers with detection, swap, multi-line input focused when opened by the shortcut, result with Copy and engine/detected-language labels. Translation 400 ms after typing stops, cancelling in-flight requests; last pair remembered.
- Google's unofficial `gtx` endpoint (POST form body, 5000-character cap), parsed fail-closed. Network, HTTP or format errors fall back to Apple Translation with installed languages (macOS 26 direct session, macOS 15 `.translationTask` bridge). Settings: engine, clipboard prefill (off by default), note that text goes to Google.
- Hidden the legacy scroller that macOS draws in the input with a mouse attached.

Validation: 28 FringeTranslateTests passed (no network); a real Google response is the multi-sentence fixture; Apple "not installed" path confirmed on macOS 26.6.2; the tab rendered on the real notch.

## 2026-10-17 - Stage 5: Mail tab (Gmail)

Status: implemented; not yet validated with a real account (needs a Google app password).

- Built-in IMAP client (Network.framework, TLS to imap.gmail.com:993): app password in the Keychain (`local.daniil.fringe.gmail`), read-only `EXAMINE INBOX`, `UID SEARCH UNSEEN X-GM-RAW "category:primary"`, `BODY.PEEK` headers for the newest 20, IDLE renewed every 20 minutes. Messages are never marked read.
- Peek for new messages, unread counter on the strip and the tab, click opens Gmail by `X-GM-MSGID` (default browser or Chrome). Reconnect after wake, network change or error with 2 s / 10 s / 1 min / 5 min backoff; a rejected login waits for new credentials.
- Not-configured state has an "Open Settings" button (`NotchHub.openSettings()`).

Validation: 21 FringeMailTests passed; live Gmail greeting and CAPABILITY (IDLE, X-GM-EXT-1) checked; login rejection of an unknown account maps to the auth error; the tab rendered on the real notch.

## 2026-10-17 - Stage 6-7: protocol, Agents tab, answers from the panel

Status: Fringe side delivered and checked against a simulated Switchboard; the Switchboard side is on its branch `fringe-link`, not yet merged or run.

- `FringeProtocol` v1: newline-delimited JSON with `version`; hello / snapshot / announce / answerResult from Switchboard, hello / openChat / answer from Fringe. Another version, an unknown type, a malformed payload or a line over 1 MiB closes the session. `FringePeer` checks the peer's signature by audit token (bundle id plus the same Team ID).
- Agents tab: up to 8 chats with activity and duration, request cards with reason and details. Approvals show Decline / Allow once when Switchboard announces the `answer` capability; an answer is sent once, a dropped connection shows "check the chat" and never resends. Other requests open the chat. "Switchboard is not running" with Open; reconnects on launch, wake and with 1/2/5/15 s retries.
- A request announcement opens the panel on Agents for 8 s, then returns to the previous tab once the pointer leaves; the strip shows the waiting count.

Validation: 9 protocol tests and 4 FringeAgentsTests passed. End-to-end against a Python stand-in on the real socket path: hello exchanged, snapshot rendered (waiting chat with an approval card, working chat with "3 min"), the announcement opened the panel and it collapsed to the compact strip after 8 s, disconnect hid the strip. Answer buttons were not clicked (no synthetic input available).

## 2026-10-17 - Fix: stale unread mail counter, calendar access and Google hint

Status: delivered.

- Mail: Gmail does not always report a message read elsewhere during IDLE, so the strip kept counting it until the 20-minute renewal. The unseen list is now re-checked when the Mail tab opens, when the user leaves a browser (Chrome, Safari, Arc, Firefox, Edge, Brave; at most every 5 s), and at least every 5 minutes (IDLE renewal shortened from 20). A nudge ends the IDLE wait without dropping buffered responses. Session snapshots and failures are logged (counts only).
- Calendar: an event store created before access was granted returned no events; the store is recreated after the grant (also when access is turned on in System Settings while Fringe runs). If no Google calendar is visible to macOS, the tab shows a hint with a button to System Settings → Internet Accounts. Reloads log calendar and event counts.

Validation: full test suite passed (23 mail tests incl. two nudge tests, 28 calendar tests); after a rebuild the app logged "Mail snapshot: 0 unseen" (the message read in the browser no longer counted) and "Calendar reload: 6 calendars, Google: true, 1 events", and the tab listed the event.

## 2026-10-17 - Fix: the open panel closed on its own

Status: delivered; needs the user's hover check (no synthetic input here).

- The close delay (350 ms) used the pointer position from when it started. Over Fringe's own panel macOS sends no mouse-moved events, so a pointer that slipped past the edge and came back was never noticed and the panel closed under it. Open/close is now decided from the pointer position when the delay ends.
- Typing kept the panel open only when it was opened by the shortcut; opened by hover, it closed as soon as the pointer left during typing. Leaving while a text field is focused now pins the panel until Esc or a click elsewhere.
- A drag or text selection that leaves the panel is decided after the mouse button is released.

Validation: full test suite passed; app rebuilt and relaunched.

## 2026-10-17 - Live hand-off with Switchboard

Status: delivered.

- Switchboard `main` now carries the server side (FringeLinkServer, vendored FringeProtocol). After the rename Switchboard is `local.daniil.switchboard` with data in `~/Library/Application Support/Switchboard`; Fringe finds it by either id (commit 62a064b, from the rename work).

Validation: after rebuilding Fringe and restarting Switchboard, Switchboard logged "Fringe connected; the island is handed off" and its island window left the screen; quitting Fringe brought it back, relaunching handed it off again.

## 2026-10-17 - Tabs in a left column, one page template for every tab

Status: delivered.

- The tab bar became a column of icons on the left (name on hover, badges on the icon). Every tab now sits in the same page: a title row (tab name on the left, the tab's own controls on the right via `FringeTabModule.makeHeaderAccessory()`) and a fixed content area, so switching tabs no longer changes sizes and margins.
- Shared `FringeMetrics` (spacing, row padding, corner radius, fonts) and a `fringeRow()` modifier; Mail and Screenshots moved their header controls into the title row; rows in Agents, Mail and Calendar use the same padding.

Validation: full test suite passed; all five tabs captured on the real notch with the new layout (Agents showed a live chat from Switchboard).

## 2026-10-17 - Calendar list in Settings; why Google events were missing

Status: delivered.

- Settings → Calendar lists every calendar macOS shares with Fringe (account, name, color, events in the shown window) with a switch to hide it; hidden calendars are remembered. Buttons open Google's CalDAV sync page (`calendar.google.com/calendar/syncselect`) and Internet Accounts. The Settings window opens taller (820 pt) and is resizable.
- Diagnosis for the user's setup: Notion Calendar reads Google directly, but macOS syncs only the primary `d.postnik1@gmail.com` calendar, and with 0 events in the week, while Google holds events there (an interview on 2026-10-19) and in the secondary "AI" calendar (agent runs) and a shared calendar, none of which macOS lists. The fix is on the macOS/Google side: re-check the account in Internet Accounts and select the calendars on the sync page.

Validation: full test suite passed; the Settings list on the real app showed d.postnik1@gmail.com (Google, 0 events), Birthdays, Holidays in Belarus (1 event) and daniil.postnik@gmail.com (0); events were compared with the Notion Calendar connector.
