import AppKit
import SwiftUI

final class PrompterWindow {
    private var window: NSWindow!
    private let viewModel: PrompterViewModel

    init(viewModel: PrompterViewModel) {
        self.viewModel = viewModel

        let contentView = PrompterView(viewModel: viewModel)
            .frame(width: 400, height: 150)
            .clipShape( UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 16,
                bottomTrailingRadius: 16,
                topTrailingRadius: 0
            ))


        let hosting = NSHostingView(rootView: contentView)
        hosting.wantsLayer = true
        hosting.layer?.masksToBounds = true

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 150),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.hasShadow = true
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = false
        window.contentView = hosting
    }

    func show() {
        guard let screen = NSScreen.main else {
            window.center()
            window.makeKeyAndOrderFront(nil)
            return
        }

        let screenFrame = screen.frame
        let windowSize = window.frame.size

        let x = screenFrame.midX - windowSize.width / 2
        let y = screenFrame.maxY - windowSize.height + 2 // hide borders on top

        window.setFrameOrigin(NSPoint(x: x, y: y))

        window.level = .statusBar // <<< stick to top

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

}
