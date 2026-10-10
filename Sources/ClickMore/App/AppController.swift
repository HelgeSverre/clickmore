import AppKit
import Observation
import OSLog
import ClickMoreCore

@MainActor @Observable
final class AppController {
    var layout: Layout
    var preferences: Preferences
    private(set) var editing = false
    private(set) var firing = false
    private(set) var permissionGranted = CGPreflightPostEventAccess()
    var message: String?
    var showSettings: (() -> Void)?
    var showTestBoard: (() -> Void)?
    private(set) var settingsHasFocus = false

    @ObservationIgnored private let store: StateStore
    @ObservationIgnored private let poster = SystemClickPoster()
    @ObservationIgnored private lazy var sequencer = ClickSequencer(poster: poster)
    @ObservationIgnored private var fireTask: Task<Void, Never>?
    @ObservationIgnored private var permissionTimer: Timer?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var screenObserver: NSObjectProtocol?
    @ObservationIgnored private var accessibilityObserver: NSObjectProtocol?
    @ObservationIgnored private var boardBackup: SavedState?
    @ObservationIgnored private var unreadableSavedState = false
    @ObservationIgnored private let logger = Logger(subsystem: "no.liseth.clickmore", category: "actions")
    @ObservationIgnored lazy var overlays = OverlayCoordinator(controller: self)

    var activeSpots: [ClickSpot] { layout.activeSpots(on: Self.displays) }
    var hasTestLayout: Bool { boardBackup != nil }

    init(store: StateStore) {
        self.store = store
        let visible = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1000, height: 800)
        let initial = Layout(trigger: ScreenPoint(x: visible.midX, y: visible.midY))
        do {
            let saved = try store.load()
            layout = saved?.layout ?? initial
            preferences = saved?.preferences ?? Preferences()
        } catch {
            layout = initial
            preferences = Preferences()
            unreadableSavedState = true
            message = "The saved layout could not be loaded: \(error.localizedDescription)"
        }
        layout.recoverTrigger(on: Self.visibleDisplays, radius: preferences.triggerSize / 2)
    }

    static var displays: [ScreenBounds] { NSScreen.screens.map { bounds($0.frame) } }
    static var visibleDisplays: [ScreenBounds] { NSScreen.screens.map { bounds($0.visibleFrame) } }
    private static func bounds(_ frame: NSRect) -> ScreenBounds {
        ScreenBounds(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height)
    }

    func start() {
        overlays.refresh()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshPermission() }
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.cancelSequence()
                self.layout.recoverTrigger(on: Self.visibleDisplays, radius: self.preferences.triggerSize / 2)
                self.overlays.rebuildConnections()
                self.changed()
            }
        }
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.overlays.refresh() }
        }
    }

    func shutdown() {
        cancelSequence()
        sequencer.releaseHeldButton()
        permissionTimer?.invalidate()
        saveTask?.cancel()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        if let accessibilityObserver { NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver) }
        persist()
    }

    func refreshPermission() {
        let granted = CGPreflightPostEventAccess()
        if granted != permissionGranted {
            permissionGranted = granted
            overlays.refresh()
        }
    }

    func requestPermission() {
        _ = CGRequestPostEventAccess()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    func updatePreferences(_ update: (inout Preferences) -> Void) {
        update(&preferences)
        preferences.validate()
        if !preferences.enabled { cancelSequence(); editing = false }
        layout.recoverTrigger(on: Self.visibleDisplays, radius: preferences.triggerSize / 2)
        changed()
    }

    func setEditing(_ value: Bool) {
        cancelSequence()
        if value && !preferences.enabled { preferences.enabled = true }
        editing = value
        changed()
    }

    func addSpot() {
        let angle = Double(layout.spots.count) * .pi / 3
        var position = ScreenPoint(x: layout.trigger.x + cos(angle) * 110,
                                   y: layout.trigger.y + sin(angle) * 110)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: layout.trigger.x, y: layout.trigger.y)) }) {
            position = Self.bounds(screen.visibleFrame).clamped(position, inset: 20)
        }
        _ = addSpot(at: position)
    }

    @discardableResult
    func addSpot(at position: ScreenPoint) -> UUID? {
        guard layout.spots.count < 64 else { message = "A trigger supports up to 64 click spots."; return nil }
        setEditing(true)
        let spot = ClickSpot(position: position)
        layout.spots.append(spot)
        changed()
        return spot.id
    }

    func removeSpot(_ id: UUID) {
        layout.spots.removeAll { $0.id == id }
        changed()
    }

    func removeAllSpots() { cancelSequence(); layout.spots.removeAll(); changed() }

    func setSettingsHasFocus(_ focused: Bool) {
        settingsHasFocus = focused
        overlays.refresh()
    }

    func moveTrigger(to position: ScreenPoint) {
        layout.trigger = position
        layout.recoverTrigger(on: Self.visibleDisplays, radius: preferences.triggerSize / 2)
        changed()
    }

    func moveLayout(from original: Layout, triggerTo position: ScreenPoint) {
        layout = original.movingTogether(to: position, on: Self.visibleDisplays, radius: preferences.triggerSize / 2)
        changed()
    }

    func moveSpot(_ id: UUID, to position: ScreenPoint) {
        guard let index = layout.spots.firstIndex(where: { $0.id == id }) else { return }
        layout.spots[index].position = position
        changed()
    }

    func reorderSpot(_ id: UUID, offset: Int) {
        guard let index = layout.spots.firstIndex(where: { $0.id == id }),
              layout.spots.indices.contains(index + offset) else { return }
        layout.spots.swapAt(index, index + offset)
        changed()
    }

    func recenterTrigger() {
        let frame = NSScreen.main?.visibleFrame ?? .zero
        moveTrigger(to: ScreenPoint(x: frame.midX, y: frame.midY))
    }

    func fire() {
        guard preferences.enabled, !firing else { return }
        if editing { setEditing(false); return }
        guard !activeSpots.isEmpty else {
            if layout.spots.isEmpty { addSpot() }
            else { message = "The click spots are on disconnected displays. Arrange them on a connected display."; showSettings?() }
            return
        }
        refreshPermission()
        guard permissionGranted else { showSettings?(); return }
        // Snapshot the entire batch. Editing and disabling cancel it rather than
        // changing target coordinates halfway through a press/release pair.
        let points = activeSpots.map(\.position)
        let delay = preferences.delayMilliseconds
        poster.restorePointer = preferences.restorePointer
        firing = true
        overlays.refresh()
        fireTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.sequencer.run(points: points, delayMilliseconds: delay)
                self.logger.info("Completed \(points.count) clicks")
            } catch is CancellationError {
                self.logger.info("Click sequence cancelled")
            } catch {
                self.message = error.localizedDescription
            }
            self.firing = false
            self.fireTask = nil
            self.overlays.refresh()
        }
    }

    func cancelSequence() { fireTask?.cancel() }

    func useTestLayout(trigger: ScreenPoint, spots: [ScreenPoint]) {
        cancelSequence()
        if boardBackup == nil { boardBackup = SavedState(layout: layout, preferences: preferences) }
        layout = Layout(trigger: trigger, spots: spots.map { ClickSpot(position: $0) })
        preferences.enabled = true
        editing = false
        overlays.refresh()
    }

    func restoreFromTestLayout() {
        guard let backup = boardBackup else { return }
        cancelSequence()
        layout = backup.layout; preferences = backup.preferences
        boardBackup = nil
        editing = false
        changed()
    }

    func changed() {
        overlays.refresh()
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            self?.persist()
        }
    }

    private func persist() {
        do {
            if unreadableSavedState, FileManager.default.fileExists(atPath: store.url.path) {
                let backup = store.url.deletingLastPathComponent().appendingPathComponent("layout-backup-\(UUID().uuidString).json")
                try FileManager.default.copyItem(at: store.url, to: backup)
                unreadableSavedState = false
            }
            try store.save(boardBackup ?? SavedState(layout: layout, preferences: preferences))
        }
        catch { message = "Could not save the layout: \(error.localizedDescription)" }
    }
}
