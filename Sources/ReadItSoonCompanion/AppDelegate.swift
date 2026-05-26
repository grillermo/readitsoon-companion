import AppKit
import ReadItSoonCore

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var poller: Poller?
    private var statusWindow: StatusPanelController!

    private var savePath = ""
    private var session: AuthSession?
    private var pendingAuthEmail: String?

    private var statusText = "Sign in required"
    private var pendingTitles: [String] = []
    private var lastDownloadedTitle: String?

    private let authClient = AuthAPIClient(baseURL: Credentials.baseURL)

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let icon = Icons.appIcon {
            NSApp.applicationIconImage = icon
        }

        loadConfig()
        setupStatusItem()
        setupStatusPanel()
        transitionAfterLaunch()
        statusWindow.showWindow()
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
        statusWindow.onSubmitEmail = { [weak self] email in
            self?.requestOTP(email: email)
        }
        statusWindow.onSubmitOTP = { [weak self] otp in
            self?.verifyOTP(otp: otp)
        }
        statusWindow.onBackToEmail = { [weak self] in
            guard let self else { return }
            self.pendingAuthEmail = nil
            self.statusWindow.showEmailForm()
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
        menu.addItem(NSMenuItem(title: "Logout", action: #selector(logoutFromMenu), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitFromMenu), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }

        if session == nil {
            menu.item(withTitle: "Logout")?.isEnabled = false
        }

        return menu
    }

    @objc private func openMainWindow() {
        refreshPanel()
        statusWindow.showWindow()
    }

    @objc private func quitFromMenu() {
        NSApp.terminate(nil)
    }

    @objc private func logoutFromMenu() {
        logout()
        statusWindow.showWindow()
    }

    private func refreshPanel() {
        statusWindow?.setContent(
            email: session?.email ?? "",
            savePath: savePath,
            statusText: statusText,
            pendingTitles: pendingTitles,
            lastDownloaded: lastDownloadedTitle
        )
    }

    // MARK: - Config

    private func loadConfig() {
        guard let config = Config.load() else { return }
        savePath = config.savePath
        session = config.session
    }

    private func persistConfig() {
        Config.save(Config(savePath: savePath, session: session))
    }

    private func persistSignedOutConfig() {
        Config.save(Config(savePath: savePath, session: session).signedOut())
    }

    // MARK: - Startup Flow

    private func transitionAfterLaunch() {
        guard let session else {
            statusText = "Sign in required"
            refreshPanel()
            statusWindow.showEmailForm()
            return
        }

        if savePath.isEmpty {
            statusText = "Choose a default save folder"
            refreshPanel()
            statusWindow.showDashboard()
            promptFolderAfterSignIn(quitOnCancel: true)
            return
        }

        statusText = "Monitoring \(session.email)"
        refreshPanel()
        statusWindow.showDashboard()
        startPolling(session: session, savePath: savePath)
    }

    // MARK: - Sign In

    private func requestOTP(email: String) {
        pendingAuthEmail = email
        statusWindow.showLoading(message: "Sending OTP...")

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await authClient.requestSignInOTP(email: email)
                self.statusWindow.showOTPForm(
                    email: email,
                    message: "OTP sent. Check your inbox and paste the code.",
                    isError: false
                )
            } catch {
                self.statusWindow.showEmailForm(
                    prefill: email,
                    message: self.userMessage(for: error, context: .requestOTP),
                    isError: true
                )
            }
        }
    }

    private func verifyOTP(otp: String) {
        guard let email = pendingAuthEmail else {
            statusWindow.showEmailForm(message: "Email is required before OTP verification.", isError: true)
            return
        }

        statusWindow.showLoading(message: "Verifying OTP...")

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let token = try await authClient.verifySignInOTP(email: email, otp: otp)
                self.session = AuthSession(email: email, token: token)
                self.pendingAuthEmail = nil
                self.statusText = "Signed in as \(email)"
                self.persistConfig()
                self.refreshPanel()
                self.statusWindow.showOTPForm(email: email, message: "Sign-in successful.", isError: false)
                self.promptFolderAfterSignIn(quitOnCancel: true)
            } catch {
                self.statusWindow.showOTPForm(
                    email: email,
                    message: self.userMessage(for: error, context: .verifyOTP),
                    isError: true
                )
            }
        }
    }

    private func logout() {
        poller = nil
        session = nil
        pendingAuthEmail = nil
        pendingTitles = []
        lastDownloadedTitle = nil
        statusText = "Sign in required"

        persistSignedOutConfig()
        refreshPanel()
        statusWindow.showEmailForm(message: "Signed out. Sign in to continue.", isError: false)
    }

    private enum AuthContext {
        case requestOTP
        case verifyOTP
    }

    private func userMessage(for error: Error, context: AuthContext) -> String {
        guard let authError = error as? AuthAPIClientError else {
            return "Unexpected error. Please try again."
        }

        switch authError {
        case .invalidEmail:
            return "Use a valid @kindle.com email address."
        case .invalidOTP:
            return "Invalid OTP. Check the code and try again."
        case .rateLimited:
            return "Too many attempts. Please wait a bit and retry."
        case .timeout:
            return "Request timed out. Check your connection and try again."
        case .network:
            return "Network error. Please check your connection and retry."
        case let .serverError(message):
            return message
        case .invalidResponse:
            switch context {
            case .requestOTP:
                return "Could not request OTP. Please try again."
            case .verifyOTP:
                return "Could not verify OTP. Please try again."
            }
        }
    }

    // MARK: - First Run / Choose Folder

    private func promptFolderAfterSignIn(quitOnCancel: Bool) {
        let alert = NSAlert()
        alert.messageText = "Choose Save Folder"
        alert.informativeText = "Select where to save downloaded articles."
        alert.addButton(withTitle: "Choose Folder")
        alert.addButton(withTitle: quitOnCancel ? "Quit" : "Cancel")

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        guard alert.runModal() == .alertFirstButtonReturn else {
            if quitOnCancel { NSApp.terminate(nil) }
            return
        }

        pickSaveFolder(quitOnCancel: quitOnCancel)
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

        savePath = url.path
        persistConfig()

        refreshPanel()
        statusWindow.showDashboard()

        poller = nil
        if let session {
            statusText = "Monitoring \(session.email)"
            refreshPanel()
            startPolling(session: session, savePath: savePath)
        }
    }

    // MARK: - Polling

    private func startPolling(session: AuthSession, savePath: String) {
        let client = APIClient(
            baseURL: Credentials.baseURL,
            email: session.email,
            token: session.token
        )

        poller = Poller(client: client, savePath: savePath) { [weak self] update in
            DispatchQueue.main.async { self?.applyPollerUpdate(update) }
        }
        poller?.start()
    }

    private func applyPollerUpdate(_ update: PollerUpdate) {
        guard session != nil else { return }

        pendingTitles = update.pendingTitles
        lastDownloadedTitle = update.lastDownloadedTitle

        switch update.state {
        case .idle:
            statusText = session.map { "Monitoring \($0.email)" } ?? "Monitoring"
        case .downloading:
            statusText = "Downloading files..."
        case .done:
            statusText = "Downloads complete"
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                guard let self else { return }
                self.statusText = self.session.map { "Monitoring \($0.email)" } ?? "Monitoring"
                self.refreshPanel()
            }
        case .error:
            statusText = "Error while syncing"
        }

        refreshPanel()
    }
}
