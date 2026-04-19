import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct ManageThemesView: View {
    @ObservedObject private var bridge: PreferencesBridge = .shared
    @State private var selectedThemeId: String?
    @State private var editingTheme: Theme?
    private let store = ThemeStore()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Import…", action: importTheme)
                Spacer()
                Button("Export…") { exportSelected() }
                    .disabled(selectedThemeId == nil)
                Button("Duplicate") { duplicateSelected() }
                    .disabled(selectedThemeId == nil)
                Button("Edit…") { editSelected() }
                    .disabled(selectedThemeId == nil || isBuiltinSelected)
                Button("Delete") { deleteSelected() }
                    .disabled(selectedThemeId == nil || isBuiltinSelected)
            }
            .padding()

            List(bridge.allThemes, id: \.id, selection: $selectedThemeId) { theme in
                HStack {
                    Text(theme.name)
                    if theme.isBuiltin {
                        Text("(builtin)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(width: 480, height: 400)
        .sheet(item: $editingTheme) { theme in
            ThemeEditorView(theme: theme) { saved in
                do {
                    try store.save(saved)
                    bridge.reloadThemes()
                } catch {
                    NSAlert(error: error).runModal()
                }
                editingTheme = nil
            } onCancel: {
                editingTheme = nil
            }
        }
    }

    private var isBuiltinSelected: Bool {
        guard let id = selectedThemeId else { return true }
        return bridge.allThemes.first(where: { $0.id == id })?.isBuiltin ?? true
    }

    private func importTheme() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if let type = UTType(filenameExtension: "justmd-theme") {
            panel.allowedContentTypes = [type]
        }
        if panel.runModal() == .OK, let url = panel.url {
            do {
                _ = try store.importTheme(from: url)
                bridge.reloadThemes()
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    private func exportSelected() {
        guard let id = selectedThemeId,
              let theme = bridge.allThemes.first(where: { $0.id == id }) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(theme.name).justmd-theme"
        if let type = UTType(filenameExtension: "justmd-theme") {
            panel.allowedContentTypes = [type]
        }
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try store.exportTheme(theme, to: url)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    private func duplicateSelected() {
        guard let id = selectedThemeId,
              let theme = bridge.allThemes.first(where: { $0.id == id }) else { return }
        let copy = Theme(
            id: "user.\(UUID().uuidString)",
            name: "\(theme.name) Copy",
            isBuiltin: false,
            light: theme.light,
            dark: theme.dark
        )
        do {
            try store.save(copy)
            bridge.reloadThemes()
            selectedThemeId = copy.id
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func editSelected() {
        guard let id = selectedThemeId,
              let theme = bridge.allThemes.first(where: { $0.id == id }) else { return }
        editingTheme = theme
    }

    private func deleteSelected() {
        guard let id = selectedThemeId,
              let theme = bridge.allThemes.first(where: { $0.id == id }) else { return }
        do {
            try store.delete(theme)
            selectedThemeId = nil
            bridge.reloadThemes()
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}

@MainActor
struct ThemeEditorView: View {
    @State var theme: Theme
    let onSave: (Theme) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading) {
            TextField("Name", text: $theme.name)
            Text("Light palette").font(.headline).padding(.top)
            paletteEditor(palette: Binding(
                get: { theme.light },
                set: { theme.light = $0 }
            ))

            Toggle("Add dark variant", isOn: Binding(
                get: { theme.dark != nil },
                set: { newVal in
                    if newVal && theme.dark == nil {
                        theme.dark = theme.light
                    } else if !newVal {
                        theme.dark = nil
                    }
                }
            )).padding(.top)

            if let darkBinding = darkPaletteBinding {
                Text("Dark palette").font(.headline).padding(.top)
                paletteEditor(palette: darkBinding)
            }

            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                Button("Save") { onSave(theme) }.keyboardShortcut(.defaultAction)
            }
            .padding(.top)
        }
        .padding()
        .frame(width: 460)
    }

    private var darkPaletteBinding: Binding<Palette>? {
        guard theme.dark != nil else { return nil }
        return Binding(
            get: { theme.dark ?? theme.light },
            set: { theme.dark = $0 }
        )
    }

    @ViewBuilder
    private func paletteEditor(palette: Binding<Palette>) -> some View {
        Grid(alignment: .trailing) {
            colorRow("Background", hex: Binding(
                get: { palette.wrappedValue.background },
                set: { palette.wrappedValue.background = $0 }
            ))
            colorRow("Text", hex: Binding(
                get: { palette.wrappedValue.text },
                set: { palette.wrappedValue.text = $0 }
            ))
            colorRow("Accent", hex: Binding(
                get: { palette.wrappedValue.accent },
                set: { palette.wrappedValue.accent = $0 }
            ))
            colorRow("Secondary", hex: Binding(
                get: { palette.wrappedValue.secondary },
                set: { palette.wrappedValue.secondary = $0 }
            ))
            colorRow("Code background", hex: Binding(
                get: { palette.wrappedValue.codeBackground },
                set: { palette.wrappedValue.codeBackground = $0 }
            ))
            colorRow("Selection", hex: Binding(
                get: { palette.wrappedValue.selection },
                set: { palette.wrappedValue.selection = $0 }
            ))
        }
    }

    @ViewBuilder
    private func colorRow(_ label: String, hex: Binding<String>) -> some View {
        GridRow {
            Text(label)
            ColorPicker("", selection: Binding(
                get: { Color(nsColor: NSColor.fromHex(hex.wrappedValue) ?? .black) },
                set: { newColor in
                    let nsColor = NSColor(newColor)
                    hex.wrappedValue = nsColor.hexString
                }
            ))
            .labelsHidden()
        }
    }
}

@MainActor
final class ManageThemesWindowController: NSWindowController {
    static let shared = ManageThemesWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 400),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Manage Themes"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.contentView = NSHostingView(rootView: ManageThemesView())
    }

    required init?(coder: NSCoder) { fatalError() }
}
