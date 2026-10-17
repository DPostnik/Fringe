import AppKit
import Combine
import SwiftUI
import UserNotifications
import FringeCore

/// What the panel view renders; owned by the controller.
@MainActor final class NotchState: ObservableObject {
    @Published var notch = NotchGeometry(width: 185, height: 32)
    @Published var mode = NotchMode.hidden
    @Published var tab: FringeTab
    @Published var peek: PeekEvent?
    /// The last announcement; the buddy jumps when it changes.
    @Published var celebratedAt: Date?
    let look = NotchLook()
    let hub: NotchHub
    let modules: [FringeTab: any FringeTabModule]
    var onSelectTab: (FringeTab) -> Void = { _ in }
    var onOpenSettings: () -> Void = {}

    init(hub: NotchHub, modules: [any FringeTabModule], tab: FringeTab) {
        self.hub = hub
        self.modules = Dictionary(modules.map { ($0.tab, $0) }, uniquingKeysWith: { first, _ in first })
        self.tab = tab
    }

    var tabs: [FringeTab] { FringeTab.allCases.filter { modules[$0] != nil } }
}

/// A transparent panel over the MacBook notch. Only the built-in display with a cut-out gets it;
/// external screens are left alone. Adapted from Switchboard (Context Desk); window level, space
/// behaviour and the click-through switch follow Coucou (MIT, github.com/Louis-CFM/coucou).
@MainActor public final class NotchController {
    static let panelSize = CGSize(width: 560, height: 480)
    static let wing: CGFloat = 40
    static let expandedSize = CGSize(width: 480, height: 420)

    private let state: NotchState
    private let panel: NotchPanel
    private var preferences: FringePreferences
    private var queue = PeekQueue()
    private var observers: [AnyCancellable] = []
    private var monitors: [Any] = []
    private var hovering = false
    private var hoverTask: Task<Void, Never>?
    private var peekTask: Task<Void, Never>?
    private var pinnedOpen = false
    /// The tab to return to after an agent request switched to Agents.
    private var tabBeforeRequest: FringeTab?
    private var requestWaitsForHoverExit = false
    private var visibleTab: FringeTab?
    private var screen: NSScreen?
    private var hotKey: HotKey?

    public let hub: NotchHub
    public var onOpenSettings: () -> Void = {}

    public init(modules: [any FringeTabModule], hub: NotchHub = NotchHub()) {
        self.hub = hub
        let preferences = FringePreferences.load()
        self.preferences = preferences
        let initialTab = modules.contains { $0.tab == preferences.lastTab } ? preferences.lastTab : (modules.first?.tab ?? .agents)
        state = NotchState(hub: hub, modules: modules, tab: initialTab)
        panel = NotchPanel(contentRect: NSRect(origin: .zero, size: Self.panelSize),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.becomesKeyOnlyIfNeeded = true
        panel.ignoresMouseEvents = true
        panel.acceptsMouseMovedEvents = true
        panel.isReleasedWhenClosed = false
        let root = NotchView(state: state)
            .environment(\.colorScheme, .dark)
            .environment(\.locale, L10n.locale)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(origin: .zero, size: Self.panelSize)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        panel.onEscape = { [weak self] in self?.collapse() }

        state.onSelectTab = { [weak self] tab in self?.select(tab, remember: true) }
        state.onOpenSettings = { [weak self] in self?.collapse(); self?.onOpenSettings() }
        hub.onPost = { [weak self] in self?.post($0) }
        hub.onRetract = { [weak self] in self?.retract($0) }
        hub.onClose = { [weak self] in self?.collapse() }
        hub.onOpenSettings = { [weak self] in self?.collapse(); self?.onOpenSettings() }
    }

    public func start() {
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.placePanel() }
            .store(in: &observers)
        hub.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyMode() }
            .store(in: &observers)
        // Mouse moves need no special permission; global covers other apps, local covers our panel.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.trackMouse() }
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved], handler: { [weak self] event in
            self?.trackMouse(); return event
        }) { monitors.append(local) }
        // A click in another app closes an open panel, including one held open for typing.
        if let clicks = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated { if self?.state.mode == .expanded { self?.collapse() } }
        }) { monitors.append(clicks) }
        state.modules.values.forEach { $0.start(hub: hub) }
        registerShortcut()
        placePanel()
        applyMode()
    }

    /// Settings changed in the Settings window.
    public func reloadPreferences() {
        preferences = FringePreferences.load()
        registerShortcut()
        applyMode()
    }

    /// Opens the panel on a tab and keeps it open until Esc or a click elsewhere.
    public func open(_ tab: FringeTab, focus: Bool) {
        guard screen != nil, state.modules[tab] != nil else { return }
        select(tab, remember: true)
        pinnedOpen = true
        applyMode()
        if focus {
            panel.makeKeyAndOrderFront(nil)
            hub.requestFocus()
        }
    }

    private func registerShortcut() {
        hotKey?.unregister()
        hotKey = preferences.translateShortcut.flatMap { HotKey($0) { [weak self] in self?.toggleTranslate() } }
    }

    private func toggleTranslate() {
        if state.mode == .expanded, state.tab == .translate, pinnedOpen { collapse() } else { open(.translate, focus: true) }
    }

    private func select(_ tab: FringeTab, remember: Bool) {
        guard state.tab != tab else { return }
        state.tab = tab
        if remember {
            tabBeforeRequest = nil
            preferences.lastTab = tab
            var saved = FringePreferences.load()
            saved.lastTab = tab
            saved.save()
        }
        updateVisibility()
    }

    // MARK: Announcements

    private func post(_ event: PeekEvent) {
        if preferences.sound { NSSound(named: event.kind == .agentRequest ? "Ping" : event.kind == .agentDone ? "Glass" : "Pop")?.play() }
        if preferences.systemNotifications { notify(event) }
        state.celebratedAt = event.kind == .mail ? state.celebratedAt : Date()
        if queue.push(event) { showCurrent() }
    }

    private func retract(_ id: String) {
        let wasRequest = queue.current?.id == id && queue.current?.kind == .agentRequest
        if wasRequest { endRequest() }
        if queue.remove(id: id) { showCurrent() }
    }

    private func showCurrent() {
        peekTask?.cancel()
        guard let event = queue.current else {
            if state.peek != nil { state.peek = nil }
            applyMode()
            return
        }
        if event.kind == .agentRequest {
            state.peek = nil
            // Typing in another tab is not interrupted; the strip still counts the request.
            if !isEditing {
                if tabBeforeRequest == nil, state.tab != .agents { tabBeforeRequest = state.tab }
                select(.agents, remember: false)
                pinnedOpen = true
            }
        } else if hovering || pinnedOpen {
            // The open panel hides the peek line; the announcement waits until it closes.
            applyMode()
            return
        } else {
            state.peek = event
        }
        applyMode()
        peekTask = Task { [weak self] in
            try? await Task.sleep(for: event.kind.duration)
            guard let self, !Task.isCancelled else { return }
            self.finishCurrent()
        }
    }

    private func finishCurrent() {
        if queue.current?.kind == .agentRequest {
            // The user is reading the request: switch back only after the pointer leaves.
            if hovering { requestWaitsForHoverExit = true; return }
            endRequest()
        }
        state.peek = nil
        queue.advance()
        showCurrent()
    }

    private func endRequest() {
        requestWaitsForHoverExit = false
        pinnedOpen = false
        if let previous = tabBeforeRequest { select(previous, remember: false) }
        tabBeforeRequest = nil
    }

    private func notify(_ event: PeekEvent) {
        Task {
            let center = UNUserNotificationCenter.current()
            guard (try? await center.requestAuthorization(options: [.alert])) == true else { return }
            let content = UNMutableNotificationContent()
            content.title = event.title
            content.body = event.detail
            try? await center.add(UNNotificationRequest(identifier: event.id, content: content, trigger: nil))
        }
    }

    // MARK: Mode and hit testing

    /// Typing in the panel keeps it open when the pointer leaves.
    private var isEditing: Bool { panel.isKeyWindow && panel.firstResponder is NSText }

    private func applyMode() {
        let resting = NotchPolicy.restingMode(agents: hub.agents, unreadMail: hub.unreadMail, autoHide: preferences.autoHide)
        let mode = NotchPolicy.mode(resting: resting, hovering: hovering, pinnedOpen: pinnedOpen, peeking: state.peek != nil)
        if state.mode != mode {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) { state.mode = mode }
            if mode != .expanded, panel.isKeyWindow {
                // Give the keyboard back to the app the user was in.
                panel.orderOut(nil)
                panel.orderFrontRegardless()
            }
            updateVisibility()
        }
        updateClickThrough()
    }

    private func updateVisibility() {
        let visible = state.mode == .expanded ? state.tab : nil
        guard visible != visibleTab else { return }
        if let visibleTab { state.modules[visibleTab]?.visibilityChanged(false) }
        visibleTab = visible
        if let visible { state.modules[visible]?.visibilityChanged(true) }
    }

    private func collapse() {
        let hadRequest = queue.current?.kind == .agentRequest
        pinnedOpen = false
        hovering = false; hoverTask?.cancel()
        if hadRequest { endRequest(); queue.advance(); showCurrent() }
        applyMode()
        // A peek that waited behind the open panel is shown now.
        if !hadRequest, queue.current != nil, state.peek == nil { showCurrent() }
    }

    /// The panel's area in screen coordinates for the current mode.
    private func islandRect(for mode: NotchMode) -> NSRect {
        let notch = state.notch, frame = panel.frame
        let size: CGSize = switch mode {
        case .hidden: CGSize(width: notch.width, height: notch.height)
        case .compact: CGSize(width: notch.width + Self.wing * 2, height: notch.height)
        case .peek: CGSize(width: notch.width + Self.wing * 2 + 120, height: notch.height + 30)
        case .expanded: Self.expandedSize
        }
        return NSRect(x: frame.midX - size.width / 2, y: frame.maxY - size.height, width: size.width, height: size.height)
    }

    private func trackMouse() {
        guard screen != nil else { return }
        let mouse = NSEvent.mouseLocation
        // Quantized so ordinary pointer motion redraws the buddy only when its gaze really moves.
        let gaze = (max(-1, min(1, (mouse.x - panel.frame.midX) / 320)) * 8).rounded() / 8
        if state.look.x != gaze { state.look.x = gaze }
        if pointerInside() != hovering { scheduleHover() }
        updateClickThrough()
    }

    /// Once open, the panel stays open while the pointer is over it.
    private func pointerInside() -> Bool {
        islandRect(for: hovering || pinnedOpen ? .expanded : state.mode).insetBy(dx: -4, dy: -4).contains(NSEvent.mouseLocation)
    }

    private func scheduleHover() {
        let inside = pointerInside()
        hoverTask?.cancel()
        hoverTask = Task { [weak self] in
            // A short delay keeps a pointer crossing the top edge from flashing the panel open.
            try? await Task.sleep(for: .milliseconds(inside ? 120 : 350))
            guard let self, !Task.isCancelled else { return }
            self.hoverChanged()
        }
    }

    private func hoverChanged() {
        // Decide from where the pointer is now, not where it was when the delay started: over our own
        // panel macOS sends no mouse-moved events, so a quick return inside would otherwise go unnoticed.
        let inside = pointerInside()
        guard inside != hovering else { return }
        // A drag or text selection that leaves the panel is decided after the button is released.
        if !inside, NSEvent.pressedMouseButtons != 0 { scheduleHover(); return }
        hovering = inside
        if !inside {
            if requestWaitsForHoverExit {
                endRequest(); queue.advance(); showCurrent()
            } else if queue.current?.kind != .agentRequest {
                // Typing keeps the panel open until Esc or a click elsewhere.
                pinnedOpen = !NotchPolicy.closesOnHoverExit(editing: isEditing)
            }
            // A peek that waited behind the open panel is shown now.
            if queue.current != nil, queue.current?.kind != .agentRequest, state.peek == nil, !pinnedOpen { showCurrent(); return }
        }
        applyMode()
    }

    /// The transparent panel lets clicks through everywhere except over the visible panel.
    private func updateClickThrough() {
        let accepts = state.mode != .hidden && islandRect(for: state.mode).contains(NSEvent.mouseLocation)
        if panel.ignoresMouseEvents == accepts { panel.ignoresMouseEvents = !accepts }
    }

    private func placePanel() {
        let builtIn = NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
        guard let builtIn, let notch = NotchGeometry(screenWidth: builtIn.frame.width, safeAreaTop: builtIn.safeAreaInsets.top,
                                                    auxiliaryLeftWidth: builtIn.auxiliaryTopLeftArea?.width,
                                                    auxiliaryRightWidth: builtIn.auxiliaryTopRightArea?.width) else {
            // Lid closed or no notch: the panel waits for the built-in display to return.
            screen = nil; panel.orderOut(nil); return
        }
        screen = builtIn
        state.notch = notch
        let frame = builtIn.frame
        panel.setFrame(NSRect(x: frame.midX - Self.panelSize.width / 2, y: frame.maxY - Self.panelSize.height,
                              width: Self.panelSize.width, height: Self.panelSize.height), display: true)
        panel.orderFrontRegardless()
    }
}

final class NotchPanel: NSPanel {
    var onEscape: () -> Void = {}
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    /// Keep the panel in the menu-bar band instead of letting AppKit push it below.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    override func cancelOperation(_ sender: Any?) { onEscape() }
}
