import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var statusMenuItem: NSMenuItem!
    private var poller: Poller?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()

        if let config = Config.load(), !config.savePath.isEmpty {
            startPolling(savePath: config.savePath)
        } else {
            promptFirstRun()
        }
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            if let image = Icons.menuBarIcon {
                button.image = image
            } else {
                button.title = "RS"
            }
        }

        buildMenu()
    }

    private func buildMenu() {
        let menu = NSMenu()

        statusMenuItem = NSMenuItem(
            title: "Monitoring \(Credentials.userEmail)",
            action: nil,
            keyEquivalent: ""
        )
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Choose where to save downloaded articles...",
            action: #selector(chooseSaveFolder),
            keyEquivalent: ""
        )
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        statusItem.menu = menu
    }

    // MARK: - First Run / Choose Folder

    private func promptFirstRun() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "ReadItSoon Companion Setup"
            alert.informativeText = "Choose where to save downloaded articles."
            alert.addButton(withTitle: "Choose Folder")
            alert.addButton(withTitle: "Quit")

            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)

            guard alert.runModal() == .alertFirstButtonReturn else {
                NSApp.terminate(nil)
                return
            }

            self.pickSaveFolder(quitOnCancel: true)
        }
    }

    @objc private func chooseSaveFolder() {
        pickSaveFolder(quitOnCancel: false)
    }

    private func pickSaveFolder(quitOnCancel: Bool) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Select"
        panel.message = "Select folder for downloaded articles"

        let result = panel.runModal()
        NSApp.setActivationPolicy(.accessory)

        guard result == .OK, let url = panel.url else {
            if quitOnCancel { NSApp.terminate(nil) }
            return
        }

        let savePath = url.path
        Config.save(Config(savePath: savePath))

        // Restart poller with new path
        poller = nil
        startPolling(savePath: savePath)
    }

    // MARK: - Polling

    private func startPolling(savePath: String) {
        let client = APIClient(
            baseURL: Credentials.baseURL,
            email: Credentials.userEmail,
            token: Credentials.authToken
        )

        poller = Poller(client: client, savePath: savePath) { [weak self] state in
            DispatchQueue.main.async { self?.updateStatus(state) }
        }
        poller?.start()
    }

    private func updateStatus(_ state: PollerState) {
        switch state {
        case .idle:
            statusMenuItem.title = "Monitoring \(Credentials.userEmail)"
        case .downloading:
            statusMenuItem.title = "⬇️ Downloading..."
        case .done:
            statusMenuItem.title = "✅ Downloads complete"
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                self?.statusMenuItem.title = "Monitoring \(Credentials.userEmail)"
            }
        }
    }
}
