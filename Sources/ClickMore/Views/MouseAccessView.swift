import SwiftUI

struct MouseAccessView: View {
    var controller: AppController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var highlighted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(controller.permissionGranted ? "Accessibility access is ready" : "Accessibility access is required",
                  systemImage: controller.permissionGranted ? "checkmark.circle.fill" : "hand.raised")
                .foregroundStyle(controller.permissionGranted ? Color.teal : Color.secondary)
            if !controller.permissionGranted {
                Text("Allow ClickMore in Privacy & Security → Accessibility so it can click buttons in other apps.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Open Accessibility Settings…") { controller.requestPermission() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.accentColor.opacity(highlighted ? 1 : 0), lineWidth: 2)
                .padding(-6)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .task(id: controller.permissionGranted ? 0 : controller.permissionAttentionRequest) {
            guard controller.permissionAttentionRequest > 0, !controller.permissionGranted else { return }
            defer { highlighted = false }
            do {
                if reduceMotion {
                    highlighted = true
                    try await Task.sleep(for: .seconds(3))
                } else {
                    for _ in 0..<3 {
                        withAnimation(.easeInOut(duration: 0.25)) { highlighted = true }
                        try await Task.sleep(for: .milliseconds(500))
                        withAnimation(.easeInOut(duration: 0.25)) { highlighted = false }
                        try await Task.sleep(for: .milliseconds(500))
                    }
                }
            } catch is CancellationError {
                // A repeated request restarts the cue; disappearing cancels it.
            } catch {
                highlighted = false
            }
        }
    }
}
