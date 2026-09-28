// Last edited: 2026-09-24 20:16 PT

import SwiftUI

/// The General tab of the Settings window: Launch at login.
struct GeneralSettingsView: View {
    let launchAtLogin: LaunchAtLoginModel

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { launchAtLogin.isOn }, set: { launchAtLogin.setOn($0) })) {
                    Text("Launch at login")
                    Text("TickTick opens in the menu bar when you log in to your Mac.")
                }
                if launchAtLogin.needsApproval {
                    approvalHint
                }
                if let errorText = launchAtLogin.errorText {
                    Label(errorText, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: SettingsWindowController.width)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var approvalHint: some View {
        HStack {
            Text("Allow TickTick in System Settings → General → Login Items.")
                .foregroundStyle(.secondary)
            Spacer()
            Button("Open Login Items…") {
                launchAtLogin.openLoginItemsSettings()
            }
        }
    }
}
