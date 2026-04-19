import SwiftUI

@MainActor
struct PreferencesView: View {
    @ObservedObject private var prefsBridge: PreferencesBridge

    init() {
        self.prefsBridge = PreferencesBridge.shared
    }

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $prefsBridge.themeId) {
                    ForEach(prefsBridge.allThemes, id: \.id) { theme in
                        Text(theme.name).tag(theme.id)
                    }
                }
                HStack {
                    Text("Custom themes")
                    Spacer()
                    Button("Manage Presets…") {
                        ManageThemesWindowController.shared.showWindow(nil)
                    }
                }
            }
            Section("Typography") {
                Picker("Font", selection: $prefsBridge.fontFamily) {
                    Text("Serif").tag(PreferencesStore.FontFamily.serif)
                    Text("Sans").tag(PreferencesStore.FontFamily.sans)
                    Text("Mono").tag(PreferencesStore.FontFamily.mono)
                }
                .pickerStyle(.segmented)

                HStack {
                    Text("Size")
                    Slider(value: $prefsBridge.fontSize, in: 12...24, step: 1)
                    Text("\(Int(prefsBridge.fontSize))")
                        .frame(width: 30, alignment: .trailing)
                        .monospacedDigit()
                }

                HStack {
                    Text("Line height")
                    Slider(value: $prefsBridge.lineHeight, in: 1.2...2.0, step: 0.1)
                    Text(String(format: "%.1f", prefsBridge.lineHeight))
                        .frame(width: 30, alignment: .trailing)
                        .monospacedDigit()
                }
            }
            Section("Editor") {
                HStack {
                    Text("Reading width")
                    Slider(value: $prefsBridge.readingWidth, in: 480...1000, step: 20)
                    Text("\(Int(prefsBridge.readingWidth))")
                        .frame(width: 50, alignment: .trailing)
                        .monospacedDigit()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 480)
    }
}
