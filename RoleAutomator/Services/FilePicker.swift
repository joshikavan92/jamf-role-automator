import SwiftUI
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

struct FilePicker: View {
    @Binding var selectedFileURL: URL?
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        #if os(macOS)
        VStack(spacing: 24) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)
            Text("Select Script")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Choose a Bash, Shell, or Python script to analyze for required Jamf Pro API roles.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button(action: chooseFile) {
                Label("Choose Script File", systemImage: "folder.badge.plus")
                    .font(.headline)
                    .frame(minWidth: 220, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            Text("Supports: .sh, .bash, .py, .txt")
                .font(.caption)
                .foregroundColor(Color(NSColor.tertiaryLabelColor))
        }
        .frame(minWidth: 420, minHeight: 320)
        .padding(32)
        #else
        Text("File picker not supported on this platform.")
        #endif
    }

    #if os(macOS)
    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if #available(macOS 12.0, *) {
            panel.allowedContentTypes = [
                .plainText,
                UTType(filenameExtension: "sh")!,
                UTType(filenameExtension: "py")!,
                UTType(filenameExtension: "bash")!
            ]
        } else {
            panel.allowedFileTypes = ["sh", "py", "bash", "txt"]
        }
        panel.message = "Select a script to analyze"
        panel.prompt = "Select"
        panel.setContentSize(NSSize(width: 560, height: 380))
        if panel.runModal() == .OK, let url = panel.url {
            selectedFileURL = url
            presentationMode.wrappedValue.dismiss()
        }
    }
    #endif
}

extension UTType {
    static let shellScript = UTType(filenameExtension: "sh")!
    static let pythonScript = UTType(filenameExtension: "py")!
}
