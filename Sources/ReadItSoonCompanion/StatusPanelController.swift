import AppKit

final class StatusPanelController: NSWindowController, NSTableViewDataSource {
    enum Mode {
        case emailEntry
        case otpEntry(email: String)
        case loading(message: String)
        case dashboard
    }

    private let statusLabel = NSTextField(labelWithString: "")
    private let cadenceLabel = NSTextField(labelWithString: "Checks every 60 seconds")
    private let folderLabel = NSTextField(labelWithString: "")
    private let emptyStateLabel = NSTextField(labelWithString: "No pending files")
    private let pendingCountLabel = NSTextField(labelWithString: "Pending downloads (0)")
    private let tableView = NSTableView()
    private var pendingTitles: [String] = []

    private let authTitleLabel = NSTextField(labelWithString: "Sign in")
    private let authDescriptionLabel = NSTextField(labelWithString: "")
    private let emailField = NSTextField(string: "")
    private let otpField = NSTextField(string: "")
    private let emailSubmitButton = NSButton(title: "Send OTP", target: nil, action: nil)
    private let otpSubmitButton = NSButton(title: "Verify OTP", target: nil, action: nil)
    private let backButton = NSButton(title: "Use different email", target: nil, action: nil)
    private let authMessageLabel = NSTextField(labelWithString: "")
    private let authSpinner = NSProgressIndicator()

    private let authStack = NSStackView()
    private let dashboardStack = NSStackView()

    private var currentMode: Mode = .emailEntry
    private var currentEmail: String = ""

    var onChooseFolder: (() -> Void)?
    var onQuit: (() -> Void)?
    var onSubmitEmail: ((String) -> Void)?
    var onSubmitOTP: ((String) -> Void)?
    var onBackToEmail: (() -> Void)?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 470),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "ReadItSoon Companion"
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 380, height: 470))
        window.center()
        window.isOpaque = false
        window.backgroundColor = NSColor(calibratedWhite: 0.1, alpha: 0.98)
        window.hasShadow = true
        window.isMovableByWindowBackground = false

        super.init(window: window)
        buildUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setContent(email: String, savePath: String, statusText: String, pendingTitles: [String], lastDownloaded: String?) {
        currentEmail = email
        folderLabel.stringValue = savePath.isEmpty ? "No save folder selected" : savePath
        statusLabel.stringValue = statusText
        pendingCountLabel.stringValue = "Pending downloads (\(pendingTitles.count))"
        self.pendingTitles = pendingTitles
        tableView.reloadData()
        emptyStateLabel.isHidden = !pendingTitles.isEmpty

        if let lastDownloaded, !lastDownloaded.isEmpty, pendingTitles.isEmpty {
            statusLabel.stringValue = "Last downloaded: \(lastDownloaded)"
        }
    }

    func showEmailForm(prefill: String = "", message: String? = nil, isError: Bool = false) {
        currentMode = .emailEntry
        currentEmail = prefill.trimmingCharacters(in: .whitespacesAndNewlines)
        emailField.stringValue = currentEmail
        otpField.stringValue = ""
        authTitleLabel.stringValue = "Sign in"
        authDescriptionLabel.stringValue = "Use your @kindle.com email to receive a one-time passcode."
        showAuthMessage(message, isError: isError)
        renderAuthState(isLoading: false)
    }

    func showOTPForm(email: String, message: String? = nil, isError: Bool = false) {
        currentMode = .otpEntry(email: email)
        currentEmail = email
        otpField.stringValue = ""
        authTitleLabel.stringValue = "Enter OTP"
        authDescriptionLabel.stringValue = "We sent a one-time passcode to \(email)."
        showAuthMessage(message, isError: isError)
        renderAuthState(isLoading: false)
    }

    func showLoading(message: String) {
        currentMode = .loading(message: message)
        showAuthMessage(message, isError: false)
        renderAuthState(isLoading: true)
    }

    func showSuccess(message: String) {
        showAuthMessage(message, isError: false)
    }

    func showDashboard() {
        currentMode = .dashboard
        authStack.isHidden = true
        dashboardStack.isHidden = false
    }

    func toggle() {
        guard let window else { return }

        if window.isVisible {
            window.orderOut(nil)
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func showWindow() {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func closeWindow() {
        window?.orderOut(nil)
    }

    override func cancelOperation(_ sender: Any?) {
        closeWindow()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        pendingTitles.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("PendingCell")

        let textField: NSTextField
        if let reusable = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField {
            textField = reusable
        } else {
            textField = NSTextField(labelWithString: "")
            textField.identifier = identifier
            textField.textColor = NSColor.white
            textField.font = NSFont.systemFont(ofSize: 12, weight: .regular)
            textField.lineBreakMode = .byTruncatingTail
        }

        textField.stringValue = pendingTitles[row]
        return textField
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        let root = NSView(frame: contentView.bounds)
        root.translatesAutoresizingMaskIntoConstraints = false
        root.wantsLayer = true
        root.layer?.cornerRadius = 16
        root.layer?.masksToBounds = true
        contentView.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            root.topAnchor.constraint(equalTo: contentView.topAnchor),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        let background = NSVisualEffectView(frame: .zero)
        background.material = .hudWindow
        background.blendingMode = .withinWindow
        background.state = .active
        background.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(background)

        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            background.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            background.topAnchor.constraint(equalTo: root.topAnchor),
            background.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])

        let titleLabel = NSTextField(labelWithString: "ReadItSoon Companion")
        titleLabel.font = NSFont.systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textColor = NSColor.white

        setupAuthControls()
        setupDashboardControls()

        let quitButton = NSButton(title: "Quit (⌘ Q)", target: self, action: #selector(quitTapped))
        quitButton.bezelStyle = .rounded
        quitButton.keyEquivalent = "q"
        quitButton.keyEquivalentModifierMask = [.command]

        let stack = NSStackView(views: [
            titleLabel,
            separatorView(),
            authStack,
            dashboardStack,
            separatorView(),
            quitButton
        ])
        stack.orientation = NSUserInterfaceLayoutOrientation.vertical
        stack.alignment = NSLayoutConstraint.Attribute.leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        stack.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            stack.topAnchor.constraint(equalTo: background.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: background.bottomAnchor)
        ])

        authStack.isHidden = true
        dashboardStack.isHidden = true
    }

    private func setupAuthControls() {
        authTitleLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        authTitleLabel.textColor = NSColor.white

        authDescriptionLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        authDescriptionLabel.textColor = NSColor(calibratedWhite: 0.86, alpha: 1)
        authDescriptionLabel.maximumNumberOfLines = 3
        authDescriptionLabel.lineBreakMode = .byWordWrapping

        emailField.placeholderString = "you@kindle.com"
        emailField.font = NSFont.systemFont(ofSize: 13)
        emailField.delegate = self
        emailField.action = #selector(emailSubmitTapped)
        emailField.target = self

        otpField.placeholderString = "One-time passcode"
        otpField.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        otpField.delegate = self
        otpField.action = #selector(otpSubmitTapped)
        otpField.target = self

        emailSubmitButton.target = self
        emailSubmitButton.action = #selector(emailSubmitTapped)

        otpSubmitButton.target = self
        otpSubmitButton.action = #selector(otpSubmitTapped)

        backButton.target = self
        backButton.action = #selector(backTapped)
        backButton.bezelStyle = .rounded

        authSpinner.style = .spinning
        authSpinner.controlSize = .small
        authSpinner.isDisplayedWhenStopped = false

        authMessageLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        authMessageLabel.textColor = NSColor(calibratedWhite: 0.86, alpha: 1)
        authMessageLabel.maximumNumberOfLines = 3
        authMessageLabel.lineBreakMode = .byWordWrapping

        authStack.orientation = .vertical
        authStack.alignment = .leading
        authStack.spacing = 8
        authStack.translatesAutoresizingMaskIntoConstraints = false

        let buttonRow = NSStackView(views: [emailSubmitButton, otpSubmitButton, backButton, authSpinner])
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 8

        authStack.addArrangedSubview(authTitleLabel)
        authStack.addArrangedSubview(authDescriptionLabel)
        authStack.addArrangedSubview(emailField)
        authStack.addArrangedSubview(otpField)
        authStack.addArrangedSubview(buttonRow)
        authStack.addArrangedSubview(authMessageLabel)

        emailField.widthAnchor.constraint(equalToConstant: 320).isActive = true
        otpField.widthAnchor.constraint(equalToConstant: 320).isActive = true
    }

    private func setupDashboardControls() {
        statusLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        statusLabel.textColor = NSColor(calibratedRed: 0.45, green: 0.86, blue: 0.67, alpha: 1)

        cadenceLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        cadenceLabel.textColor = NSColor(calibratedWhite: 0.75, alpha: 1)

        let folderTitleLabel = NSTextField(labelWithString: "Save folder")
        folderTitleLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        folderTitleLabel.textColor = NSColor(calibratedWhite: 0.86, alpha: 1)

        folderLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        folderLabel.textColor = NSColor(calibratedWhite: 0.82, alpha: 1)
        folderLabel.lineBreakMode = .byTruncatingMiddle
        folderLabel.maximumNumberOfLines = 2

        pendingCountLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        pendingCountLabel.textColor = NSColor(calibratedWhite: 0.86, alpha: 1)

        tableView.headerView = nil
        tableView.rowHeight = 20
        tableView.selectionHighlightStyle = .none
        tableView.backgroundColor = .clear
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("PendingColumn"))
        column.width = 320
        tableView.addTableColumn(column)
        tableView.delegate = self
        tableView.dataSource = self

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.documentView = tableView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.heightAnchor.constraint(equalToConstant: 130).isActive = true

        emptyStateLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        emptyStateLabel.textColor = NSColor(calibratedWhite: 0.62, alpha: 1)

        let folderButton = NSButton(title: "Change save folder", target: self, action: #selector(chooseFolderTapped))
        folderButton.bezelStyle = .rounded

        dashboardStack.orientation = .vertical
        dashboardStack.alignment = .leading
        dashboardStack.spacing = 8

        dashboardStack.addArrangedSubview(statusLabel)
        dashboardStack.addArrangedSubview(cadenceLabel)
        dashboardStack.addArrangedSubview(separatorView())
        dashboardStack.addArrangedSubview(pendingCountLabel)
        dashboardStack.addArrangedSubview(scrollView)
        dashboardStack.addArrangedSubview(emptyStateLabel)
        dashboardStack.addArrangedSubview(separatorView())
        dashboardStack.addArrangedSubview(folderTitleLabel)
        dashboardStack.addArrangedSubview(folderLabel)
        dashboardStack.addArrangedSubview(folderButton)
    }

    private func renderAuthState(isLoading: Bool) {
        let trimmedEmail = emailField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOTP = otpField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        authStack.isHidden = false
        dashboardStack.isHidden = true

        let isEmailMode: Bool
        let isOTPMode: Bool
        switch currentMode {
        case .emailEntry:
            isEmailMode = true
            isOTPMode = false
        case .otpEntry:
            isEmailMode = false
            isOTPMode = true
        case .loading:
            isEmailMode = false
            isOTPMode = false
        case .dashboard:
            return
        }

        emailField.isHidden = !isEmailMode
        emailSubmitButton.isHidden = !isEmailMode

        otpField.isHidden = !isOTPMode
        otpSubmitButton.isHidden = !isOTPMode
        backButton.isHidden = !isOTPMode

        emailField.isEnabled = !isLoading && isEmailMode
        otpField.isEnabled = !isLoading && isOTPMode

        emailSubmitButton.isEnabled = !isLoading && isValidEmail(trimmedEmail)
        otpSubmitButton.isEnabled = !isLoading && !trimmedOTP.isEmpty
        backButton.isEnabled = !isLoading

        if isLoading {
            authSpinner.startAnimation(nil)
        } else {
            authSpinner.stopAnimation(nil)
        }
    }

    private func showAuthMessage(_ message: String?, isError: Bool) {
        if let message, !message.isEmpty {
            authMessageLabel.stringValue = message
            authMessageLabel.isHidden = false
            authMessageLabel.textColor = isError
                ? NSColor(calibratedRed: 0.98, green: 0.52, blue: 0.52, alpha: 1)
                : NSColor(calibratedRed: 0.45, green: 0.86, blue: 0.67, alpha: 1)
        } else {
            authMessageLabel.stringValue = ""
            authMessageLabel.isHidden = true
        }
    }

    private func isValidEmail(_ email: String) -> Bool {
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        guard normalized.hasSuffix("@kindle.com") else { return false }
        return normalized.count > "@kindle.com".count
    }

    private func separatorView() -> NSView {
        let separator = NSBox(frame: .zero)
        separator.boxType = .separator
        return separator
    }

    @objc private func emailSubmitTapped() {
        let email = emailField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard isValidEmail(email) else {
            showAuthMessage("Enter a valid @kindle.com email.", isError: true)
            renderAuthState(isLoading: false)
            return
        }

        currentEmail = email
        onSubmitEmail?(email)
    }

    @objc private func otpSubmitTapped() {
        let otp = otpField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !otp.isEmpty else {
            showAuthMessage("OTP is required.", isError: true)
            renderAuthState(isLoading: false)
            return
        }

        onSubmitOTP?(otp)
    }

    @objc private func backTapped() {
        onBackToEmail?()
    }

    @objc private func chooseFolderTapped() {
        closeWindow()
        onChooseFolder?()
    }

    @objc private func quitTapped() {
        onQuit?()
    }
}

extension StatusPanelController: NSTableViewDelegate {}
extension StatusPanelController: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        switch currentMode {
        case .emailEntry, .otpEntry:
            showAuthMessage(nil, isError: false)
            renderAuthState(isLoading: false)
        case .loading, .dashboard:
            break
        }
    }
}
