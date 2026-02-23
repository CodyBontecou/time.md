import SwiftUI

/// Brutalist error banner — sharp, monospace, high-contrast.
struct DataLoadErrorView: View {
    let error: Error

    private var isPermissionError: Bool {
        if let dataError = error as? ScreenTimeDataError {
            if case .permissionDenied = dataError {
                return true
            }
        }
        return false
    }

    var body: some View {
        if isPermissionError {
            permissionBanner
        } else {
            genericBanner
        }
    }

    private var permissionBanner: some View {
        Button {
            openFullDiskAccessSettings()
        } label: {
            HStack(spacing: 12) {
                Text("⚠")
                    .font(.system(size: 18, weight: .black, design: .monospaced))
                    .foregroundStyle(BrutalTheme.warning)

                VStack(alignment: .leading, spacing: 2) {
                    Text("FULL DISK ACCESS REQUIRED")
                        .font(BrutalTheme.headingFont)
                        .foregroundColor(BrutalTheme.textPrimary)
                        .tracking(1)
                    Text("Click to open System Settings and grant access.")
                        .font(BrutalTheme.captionMono)
                        .foregroundColor(BrutalTheme.textSecondary)
                }

                Spacer()

                Text("→")
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundColor(BrutalTheme.textSecondary)
            }
            .padding(12)
            .background(BrutalTheme.warning.opacity(0.08))
            .overlay(
                Rectangle()
                    .strokeBorder(BrutalTheme.warning.opacity(0.5), lineWidth: BrutalTheme.borderWidth)
            )
        }
        .buttonStyle(.plain)
    }

    private var genericBanner: some View {
        HStack(spacing: 12) {
            Text("ERR")
                .font(.system(size: 11, weight: .black, design: .monospaced))
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(BrutalTheme.danger)

            Text(ScreenTimeDataError.message(for: error))
                .font(BrutalTheme.captionMono)
                .foregroundColor(BrutalTheme.textSecondary)
                .lineLimit(3)

            Spacer()
        }
        .padding(12)
        .background(BrutalTheme.danger.opacity(0.04))
        .overlay(
            Rectangle()
                .strokeBorder(BrutalTheme.danger.opacity(0.3), lineWidth: BrutalTheme.borderWidth)
        )
    }

    private func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
