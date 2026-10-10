# ClickMore

ClickMore is a native macOS menu bar app with a movable floating trigger. Place click spots over buttons in a game or another app; one trigger click clicks every spot in order, with a default 10 ms delay between clicks.

## Run

Requires macOS 14 or later and Xcode command line tools with Swift 6.

```sh
./script/build_and_run.sh
```

The script builds and signs `dist/ClickMore.app`, then launches it. It uses an installed Apple Development signing identity when available, or an ad hoc signature otherwise. Set `CLICKMORE_SIGN_IDENTITY` to choose another identity. A consistent signature and app location help preserve Accessibility approval between builds.

ClickMore launches as a floating overlay with a menu bar icon and no Dock icon or main window. Open Settings using the cursor icon in the menu bar, or Command-comma while a ClickMore settings or test window is active. The overlay uses transparent, borderless, nonactivating macOS panels.

## Place and use click spots

1. Drag the floating trigger to a convenient gap between the buttons.
2. Hold **Option**, drag out from the trigger onto a button, and release to create a ready-to-use click spot. Repeat for each button. Change the modifier in **Settings → Dragging → Drag out a new spot with**.
3. For manual arrangement, right-click the trigger and choose **Add Click Spot** or **Arrange Click Spots**. Drag the target rings onto buttons, then click the checkmark on the trigger or choose **Finish Arranging**.
4. Left-click the trigger to click each spot once. Spots and connecting lines pass mouse input through to the underlying app outside placement mode.

Right-click a spot while arranging to remove it or change its click order. Plain dragging moves only the trigger. **Command-drag** moves the trigger and every spot together, keeping their relative positions; rebind this separately in **Settings → Dragging → Move all spots with the trigger**. The two gestures use distinct modifiers.

**Remove All Click Spots** is available from the trigger's context menu and the menu bar. The menu bar also provides an **Enabled** toggle that hides the overlay and cancels an active sequence. Option-drag follows the macOS [copy-by-dragging convention](https://support.apple.com/en-gb/guide/mac-help/mh35852/mac); Shift, Command, and their combinations are also available. Control-click keeps its normal context menu behavior.

The overlay uses an icon-only native material button, small target rings, and translucent circuit-style connections with rounded bends. Routing uses separate attachment points and 10-point lanes for crowded connections, inspired by [ELK's edge spacing](https://eclipse.dev/elk/reference/options/org-eclipse-elk-spacing-edgeEdge.html) and [port spacing](https://eclipse.dev/elk/reference/options/org-eclipse-elk-spacing-portPort.html). The click positions stay fixed; lines converge at targets that occupy the same position.

VoiceOver announces the trigger's state and each spot's order and position. Its Actions menu provides adding, arranging, moving the trigger or whole layout, reordering, and removing spots. The overlay respects Reduce Transparency and Increase Contrast. While Settings has focus, the overlay passes mouse input through so it cannot cover a Settings control.

In Settings, choose **Open Accessibility Settings** and allow **ClickMore** under **Privacy & Security → Accessibility**. macOS requires this approval to post clicks into other apps. The app checks permission again automatically; a grey trigger indicates access is still missing.

Settings also control the delay from 1–250 ms, trigger size, opacity, connecting lines, and pointer restoration. Each click has a 2 ms press before release, so the default four-click batch takes roughly 38 ms plus operating-system scheduling. The pointer returns after the sequence if it has stayed at the last target.

Layouts and preferences are saved automatically to `~/Library/Application Support/ClickMore/layout.json`. Targets use absolute screen positions in points. Rearrange them if the game moves or changes size. Targets on a disconnected display are skipped, and the trigger is recovered onto a connected display.

## Try the four-button board

Open **Four-Button Test Board** from the menu bar, click **Place Trigger & Four Spots**, then click the floating trigger. Ice, Sugar, Glass, and Lemon should each increment once. Closing the board restores the layout you were using before the test. This test layout is temporary and does not overwrite your saved game layout.

## Verify and develop

```sh
swift test
./script/test_runtime.sh
./script/test_runtime.sh --integration-test
```

The unit tests cover press/release ordering, timing, cancellation, concurrent triggers, permission checks, persistence, display coordinates, group translation, and crowded connector routing. The local runtime test delivers AppKit events to the live test board without requiring Accessibility. The integration test requires Accessibility and launches a separate test-target app. It verifies system clicks into that process, a left-click routed through the floating trigger, preservation of the target app's focus, both rebindable drag gestures, plain dragging, clear-all, and Settings pass-through. Reports go to `test-results/`.

The build script supports `--build`, `--verify`, `--debug`, `--logs`, and `--telemetry`. The Codex Run action invokes the same script. Regenerate the app icon with:

```sh
swift script/generate_icon.swift .build/ClickMore.iconset
iconutil -c icns .build/ClickMore.iconset -o Resources/ClickMore.icns
```

`ClickMoreCore` owns the layout, persistence, screen geometry, and cancellable click sequencer. `ClickMore` uses SwiftUI for Settings and AppKit for the menu bar, nonactivating overlay panels, and test board. Clicks use the [Core Graphics event API](https://developer.apple.com/documentation/coregraphics/cgevent); its [posting permission check](https://developer.apple.com/documentation/coregraphics/cgpreflightposteventaccess()) controls the permission indicator.

This is a local development build. Some games reject synthetic input or require a longer delay; adjust the delay in Settings if necessary.
