// Last edited: 2026-09-29 10:50 PT

import SwiftUI

/// The Help tab of the Settings window: a section for each feature, then a table of every shortcut for each scope.
/// The text is long, so this tab scrolls in a fixed height. The other tabs fit their content.
struct HelpView: View {
    static let height: CGFloat = 560

    /// Changes each time the tab shows, so the body reads the hotkeys' keys again. `NSTabViewController` removes a
    /// tab's view when you go to another tab, so `onAppear` runs on each return, for example after a new recording on
    /// the Shortcuts tab.
    @State private var appearances = 0

    var body: some View {
        // Read the counter so that a change runs the body again.
        let _ = appearances // swiftlint:disable:this redundant_discardable_let
        Form {
            ForEach(HelpContent.sections) { section in
                Section(section.title) {
                    paragraphs(section.paragraphs)
                }
            }
            ForEach(HelpContent.shortcutGroups, id: \.scope) { group in
                Section("Shortcuts: \(group.scope.title)") {
                    shortcutGrid(group.shortcuts)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: SettingsWindowController.width, height: Self.height)
        .onAppear { appearances += 1 }
    }

    private func paragraphs(_ paragraphs: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(paragraphs, id: \.self) { paragraph in
                Text(paragraph)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func shortcutGrid(_ shortcuts: [ShortcutInfo]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            ForEach(shortcuts) { info in
                GridRow {
                    Text(info.keysText)
                        .fontWeight(.medium)
                        .gridColumnAlignment(.trailing)
                    Text(info.description)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
