import SwiftUI

struct PermissionPromptView: View {
    @Bindable var service: PermissionService

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Mouthpiece 需要权限")
                .font(.title2).bold()

            permissionRow(
                title: "麦克风",
                description: "用于将你说的话转为文字",
                granted: service.microphone == .granted,
                action: {
                    if service.microphone == .notDetermined {
                        Task { await service.requestMicrophone() }
                    } else {
                        service.openMicrophoneSettings()
                    }
                }
            )

            permissionRow(
                title: "辅助功能",
                description: "用于自动粘贴文字到光标位置",
                granted: service.accessibility == .granted,
                action: { service.openAccessibilitySettings() }
            )
        }
        .padding(24)
        .frame(width: 480)
    }

    @ViewBuilder
    private func permissionRow(title: String, description: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(granted ? .green : .secondary)
                .font(.title2)
            VStack(alignment: .leading) {
                Text(title).font(.headline)
                Text(description).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted {
                Button("授权", action: action).buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    PermissionPromptView(service: PermissionService())
}
