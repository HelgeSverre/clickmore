import AppKit

/// Finish text editing on outside clicks without intercepting the destination control.
final class SettingsWindow: NSWindow {
    static let finishEditingNotification = Notification.Name("ClickMoreSettingsFinishEditing")

    func finishTextEditing() {
        // Commit the SwiftUI draft synchronously before another action or termination.
        NotificationCenter.default.post(name: Self.finishEditingNotification, object: self)
        makeFirstResponder(self)
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown,
           let editor = firstResponder as? NSTextView, editor.isFieldEditor {
            // The delegate is the owning text control; include its padding in the hit area.
            let control = (editor.delegate as? NSView) ?? editor
            let point = control.convert(event.locationInWindow, from: nil)
            if !control.bounds.contains(point) {
                finishTextEditing()
            }
        }
        super.sendEvent(event)
    }
}
