// Last edited: 2026-09-24 20:16 PT

import KeyboardShortcuts
import SwiftUI

/// The Shortcuts tab of the Settings window: an on/off switch and a key recorder for each global hotkey, and an
/// on/off switch for the popover keys. Each change works at once.
struct ShortcutsSettingsView: View {
    @Bindable var preferences: Preferences

    var body: some View {
        Form {
            hotkeySection(
                title: "Quick add",
                info: ShortcutCatalog.quickAdd,
                name: .quickAdd,
                isOn: $preferences.quickAddHotkeyEnabled
            )
            hotkeySection(
                title: "Open the popover",
                info: ShortcutCatalog.togglePopover,
                name: .togglePopover,
                isOn: $preferences.togglePopoverHotkeyEnabled
            )
            popoverKeysSection
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: SettingsWindowController.width)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func hotkeySection(
        title: String,
        info: ShortcutInfo,
        name: KeyboardShortcuts.Name,
        isOn: Binding<Bool>
    ) -> some View {
        Section(title) {
            Toggle(isOn: isOn) {
                Text("Hotkey")
                Text("\(info.description).")
            }
            KeyboardShortcuts.Recorder("Keys", name: name)
                .disabled(!isOn.wrappedValue)
        }
    }

    private var popoverKeysSection: some View {
        Section("Popover keys") {
            Toggle(isOn: $preferences.popoverKeysEnabled) {
                Text("Popover keys")
                Text("Single keys that work while the popover is open and a timer is active.")
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                ForEach(ShortcutCatalog.popoverKeys) { info in
                    GridRow {
                        Text(info.keysText)
                            .fontWeight(.medium)
                            .gridColumnAlignment(.trailing)
                        Text(info.description)
                    }
                }
            }
            .font(.callout)
            .foregroundStyle(preferences.popoverKeysEnabled ? .secondary : .tertiary)
        }
    }
}
