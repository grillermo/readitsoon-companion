import AppKit
import ReadItSoonCore

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var poller: Poller?
    private var statusWindow: StatusPanelController!
    private var savePath = ""
    private var statusText = "Monitoring"
    private var pendingTitles: [String] = []
    private var lastDownloadedTitle: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let icon = Icons.appIcon {
            NSApp.applicationIconImage = icon
        }
        setupStatusItem()
        setupStatusPanel()
        statusWindow.showWindow()

        if let config = Config.load(), !config.savePath.isEmpty {
            savePath = config.savePath
            refreshPanel()
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
            button.target = self
            button.action = #selector(handleStatusItemClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    private func setupStatusPanel() {
        statusWindow = StatusPanelController()
        statusWindow.onChooseFolder = { [weak self] in
            self?.chooseSaveFolder()
        }
        statusWindow.onQuit = {
            NSApp.terminate(nil)
        }
        refreshPanel()
    }

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        refreshPanel()

        guard let event = NSApp.currentEvent else {
            statusWindow.showWindow()
            return
        }

        if isContextClick(event) {
            showContextMenu()
            return
        }

        statusWindow.showWindow()
    }

    private func isContextClick(_ event: NSEvent) -> Bool {
        switch event.type {
        case .rightMouseUp:
            return true
        case .leftMouseUp:
            return event.modifierFlags.contains(.control)
        default:
            return false
        }
    }

    private func showContextMenu() {
        let menu = buildContextMenu()
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func buildContextMenu() -> NSMenu {
        let menu = NSMenu()

        func addInfoItem(_ title: String) {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        addInfoItem("ReadItSoon Companion")
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Open main window", action: #selector(openMainWindow), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitFromMenu), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }

        return menu
    }

    @objc private func openMainWindow() {
        refreshPanel()
        statusWindow.showWindow()
    }

    @objc private func quitFromMenu() {
        NSApp.terminate(nil)
    }

    private func refreshPanel() {
        statusWindow?.setContent(
            email: Credentials.userEmail,
            savePath: savePath,
            statusText: statusText,
            pendingTitles: pendingTitles,
            lastDownloaded: lastDownloadedTitle
        )
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
        self.savePath = savePath
        Config.save(Config(savePath: savePath))
        refreshPanel()

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

        poller = Poller(client: client, savePath: savePath) { [weak self] update in
            DispatchQueue.main.async { self?.applyPollerUpdate(update) }
        }
        poller?.start()
    }

    private func applyPollerUpdate(_ update: PollerUpdate) {
        pendingTitles = update.pendingTitles
        lastDownloadedTitle = update.lastDownloadedTitle

        switch update.state {
        case .idle:
            statusText = "Monitoring \(Credentials.userEmail)"
        case .downloading:
            statusText = "Downloading files..."
        case .done:
            statusText = "Downloads complete"
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                guard let self else { return }
                self.statusText = "Monitoring \(Credentials.userEmail)"
                self.refreshPanel()
            }
        case .error:
            statusText = "Error while syncing"
        }

        refreshPanel()
    }
}
