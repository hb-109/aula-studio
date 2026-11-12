import AulaCore
import SwiftUI

@main
struct AulaStudioApp: App {
    @StateObject private var app = AppModel()

    var body: some Scene {
        Window("AULA Studio", id: "studio") {
            RootView(app: app)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)

        MenuBarExtra("AULA Studio", systemImage: "keyboard") {
            MenuBarContent(app: app)
        }
    }
}

struct MenuBarContent: View {
    @ObservedObject var app: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ForEach(KeyboardModel.allCases) { model in
            Text("\(model.name): \(StatusText.short(app.status(of: model)))")
        }
        Divider()
        Menu("F75 Pro effect") {
            ForEach(AppEffect.allCases) { effect in
                Button {
                    app.setF75Effect(effect)
                } label: {
                    if app.profile(for: .f75Pro).lighting.appEffect == effect { Label(effect.title, systemImage: "checkmark") }
                    else { Text(effect.title) }
                }
            }
        }
        Divider()
        Button("Open AULA Studio…") {
            openWindow(id: "studio")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Quit AULA Studio") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
