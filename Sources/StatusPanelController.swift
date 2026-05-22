import AppKit

final class StatusPanelController: NSWindowController, NSTableViewDataSource {
    private let statusLabel = NSTextField(labelWithString: "")
    private let cadenceLabel = NSTextField(labelWithString: "Checks every 60 seconds")
    private let folderLabel = NSTextField(labelWithString: "")
    private let emptyStateLabel = NSTextField(labelWithString: "No pending files")
    private let pendingCountLabel = NSTextField(labelWithString: "Pending downloads (0)")
    private let tableView = NSTableView()
    private var pendingTitles: [String] = []

    var onChooseFolder: (() -> Void)?
    var onQuit: (() -> Void)?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 430),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "ReadItSoon Companion"
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 380, height: 430))
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

        let quitButton = NSButton(title: "Quit", target: self, action: #selector(quitTapped))
        quitButton.bezelStyle = .rounded

        let stack = NSStackView(views: [
            titleLabel,
            separatorView(),
            statusLabel,
            cadenceLabel,
            separatorView(),
            pendingCountLabel,
            scrollView,
            emptyStateLabel,
            separatorView(),
            folderTitleLabel,
            folderLabel,
            folderButton,
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
    }

    private func separatorView() -> NSView {
        let separator = NSBox(frame: .zero)
        separator.boxType = .separator
        return separator
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
