import SwiftUI
import AppKit

@main
struct NotchPrompterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(viewModel: appDelegate.viewModel)
                .frame(minWidth: 600, minHeight: 400)
        }

        MenuBarExtra("NotchPrompter", systemImage: "text.justify") {
            Button {
                appDelegate.viewModel.togglePlayPause()
            } label: {
                Label(appDelegate.viewModel.isPlaying ? "Pause" : "Play",
                      systemImage: appDelegate.viewModel.isPlaying ? "pause.fill" : "play.fill")
            };

            Divider()

            SettingsLink {
                Label("Settings", systemImage: "gearshape")
            }
            .keyboardShortcut(",", modifiers: [.command])

            Divider()

            Button(role: .destructive) {
                NSApp.terminate(nil)
            } label: {
                Label("Exit", systemImage: "xmark.circle")
            }
            .keyboardShortcut("q", modifiers: [.command])
        }
        .menuBarExtraStyle(.menu)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let viewModel = PrompterViewModel()
    private var prompterWindow: PrompterWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        prompterWindow = PrompterWindow(viewModel: viewModel)
        prompterWindow.show()

        // Accessory app (no Dock icon)
        NSApp.setActivationPolicy(.accessory)
    }
}
