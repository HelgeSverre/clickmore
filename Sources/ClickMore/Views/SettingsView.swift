import SwiftUI
import ClickMoreCore

struct SettingsView: View {
    @Bindable var controller: AppController
    @State private var confirmClear = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "cursorarrow.click.2")
                    .font(.system(size: 30)).foregroundStyle(.teal)
                VStack(alignment: .leading, spacing: 3) {
                    Text("ClickMore").font(.title2.bold())
                    Text("One click. Every connected spot.").foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Enabled", isOn: preference(\.enabled)).toggleStyle(.switch)
            }.padding(20)
            Divider()
            Form {
                Section("Click spots") {
                    HStack {
                        Text("\(controller.layout.spots.count) spots · \(controller.activeSpots.count) on connected displays")
                        Spacer()
                        Button("Add Spot", systemImage: "plus") { controller.addSpot() }
                    }
                    HStack {
                        Text(controller.editing ? "Drag the target rings onto your buttons." : "Right-click the trigger to add or arrange spots.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(controller.editing ? "Done" : "Arrange") { controller.setEditing(!controller.editing) }
                    }
                    if !controller.layout.spots.isEmpty {
                        ScrollView {
                            VStack(spacing: 6) {
                                ForEach(Array(controller.layout.spots.enumerated()), id: \.element.id) { index, spot in
                                    HStack {
                                        Text("\(index + 1)").monospacedDigit().frame(width: 22)
                                        Text("x \(coordinate(spot.position.x))   y \(coordinate(spot.position.y))")
                                            .font(.caption.monospaced()).foregroundStyle(.secondary)
                                        if !controller.activeSpots.contains(where: { $0.id == spot.id }) {
                                            Text("Offline").font(.caption).foregroundStyle(.orange)
                                        }
                                        Spacer()
                                        Button { controller.reorderSpot(spot.id, offset: -1) } label: { Image(systemName: "arrow.up") }
                                            .disabled(index == 0).help("Click earlier")
                                        Button { controller.reorderSpot(spot.id, offset: 1) } label: { Image(systemName: "arrow.down") }
                                            .disabled(index == controller.layout.spots.count - 1).help("Click later")
                                        Button { controller.removeSpot(spot.id) } label: { Image(systemName: "trash") }
                                            .help("Remove click spot")
                                    }.buttonStyle(.borderless)
                                }
                            }
                        }.frame(maxHeight: 110)
                        Button("Remove All Spots…", role: .destructive) { confirmClear = true }
                            .confirmationDialog("Remove all click spots?", isPresented: $confirmClear) {
                                Button("Remove All", role: .destructive) { controller.removeAllSpots() }
                            }
                    }
                }
                Section("Mouse access") {
                    Label(controller.permissionGranted ? "Accessibility access is ready" : "Accessibility access is required",
                          systemImage: controller.permissionGranted ? "checkmark.circle.fill" : "hand.raised")
                        .foregroundStyle(controller.permissionGranted ? Color.teal : Color.secondary)
                    if !controller.permissionGranted {
                        Text("Allow ClickMore in Privacy & Security → Accessibility so it can click buttons in other apps.")
                            .font(.callout).foregroundStyle(.secondary)
                        Button("Open Accessibility Settings…") { controller.requestPermission() }
                    }
                }
                Section("Dragging") {
                    Picker("Drag out a new spot with", selection: preference(\.spotCreationModifier)) {
                        ForEach(DragModifier.allCases.filter { $0 != controller.preferences.groupMoveModifier }, id: \.self) { modifier in
                            Text(modifier.displayName).tag(modifier)
                        }
                    }
                    Picker("Move all spots with the trigger", selection: preference(\.groupMoveModifier)) {
                        ForEach(DragModifier.allCases.filter { $0 != controller.preferences.spotCreationModifier }, id: \.self) { modifier in
                            Text(modifier.displayName).tag(modifier)
                        }
                    }
                    Text("\(controller.preferences.spotCreationModifier.spokenName)-drag creates a spot. \(controller.preferences.groupMoveModifier.spokenName)-drag moves the entire layout. Plain dragging moves only the trigger.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Clicks") {
                    Stepper(value: preference(\.delayMilliseconds), in: 1...250, step: 1) {
                        LabeledContent("Delay between clicks", value: "\(Int(controller.preferences.delayMilliseconds)) ms")
                    }
                    Toggle("Return pointer after clicking", isOn: preference(\.restorePointer))
                }
                Section("Overlay") {
                    Toggle("Show connecting lines", isOn: preference(\.showConnections))
                    LabeledContent("Trigger size") {
                        Slider(value: preference(\.triggerSize), in: 44...80, step: 2).frame(width: 180)
                    }
                    LabeledContent("Opacity") {
                        Slider(value: preference(\.overlayOpacity), in: 0.3...1, step: 0.05).frame(width: 180)
                    }
                    Button("Move Trigger to This Display") { controller.recenterTrigger() }
                }
                Section {
                    Button("Open Four-Button Test Board", systemImage: "square.grid.2x2") { controller.showTestBoard?() }
                    Text("Try one trigger click on four counters. Your saved layout returns when you close the board.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let message = controller.message {
                        Text(message).font(.callout).foregroundStyle(.red).textSelection(.enabled)
                        Button("Dismiss") { controller.message = nil }
                    }
                }
            }.formStyle(.grouped)
        }.frame(width: 520, height: 700)
    }

    private func preference<Value>(_ path: WritableKeyPath<Preferences, Value>) -> Binding<Value> {
        Binding(get: { controller.preferences[keyPath: path] },
                set: { value in controller.updatePreferences { $0[keyPath: path] = value } })
    }

    private func coordinate(_ value: Double) -> String {
        value.formatted(.number.grouping(.never).precision(.fractionLength(0)))
    }
}
