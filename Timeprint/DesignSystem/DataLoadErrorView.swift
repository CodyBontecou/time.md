import SwiftUI

/// Error banner with Liquid Glass styling.
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

                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(BrutalTheme.textSecondary)
            }
            .padding(12)
        }
        .buttonStyle(.glass)
        .tint(BrutalTheme.warning)
    }

    private var genericBanner: some View {
        HStack(spacing: 12) {
            Text("ERR")
                .font(.system(size: 11, weight: .black, design: .monospaced))
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(BrutalTheme.danger, in: RoundedRectangle(cornerRadius: 4))

            Text(ScreenTimeDataError.message(for: error))
                .font(BrutalTheme.captionMono)
                .foregroundColor(BrutalTheme.textSecondary)
                .lineLimit(3)

            Spacer()
        }
        .padding(12)
        
    }

    private func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
