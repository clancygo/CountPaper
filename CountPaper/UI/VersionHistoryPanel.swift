import Cocoa

struct LedgerRecoveryVersion {
    let url: URL
    let date: Date
}

/// A focused, read-only browser for automatic ledger recovery snapshots.
/// Selecting a version immediately displays its plain-text contents; restoring
/// is deliberately a separate, explicit action supplied by the host app.
final class VersionHistoryPanelController: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    private let versions: [LedgerRecoveryVersion]
    private let chinese: Bool
    private let onRestore: (LedgerRecoveryVersion) -> Void
    private weak var parentWindow: NSWindow?
    private let tableView = NSTableView()
    private let preview = NSTextView()
    private let restoreButton = NSButton(title: "", target: nil, action: nil)
    private var windowController: NSWindowController?

    init(versions: [LedgerRecoveryVersion], chinese: Bool, onRestore: @escaping (LedgerRecoveryVersion) -> Void) {
        self.versions = versions
        self.chinese = chinese
        self.onRestore = onRestore
        super.init()
    }

    func present(asSheetFor parentWindow: NSWindow) {
        self.parentWindow = parentWindow
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 530),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = chinese ? "历史版本" : "Version History"
        window.isReleasedWhenClosed = false
        window.contentView = makeContentView()
        windowController = NSWindowController(window: window)
        parentWindow.beginSheet(window)
    }

    private func makeContentView() -> NSView {
        let content = NSView()
        let title = NSTextField(labelWithString: chinese ? "历史版本" : "Version History")
        title.font = .systemFont(ofSize: 22, weight: .bold)
        let detail = NSTextField(labelWithString: chinese ? "选择一个自动保存的版本以预览或恢复。恢复前会备份当前账本。" : "Select an automatic snapshot to preview or restore. Your current ledger is backed up first.")
        detail.textColor = .secondaryLabelColor
        detail.font = .systemFont(ofSize: 13)

        let listScroll = NSScrollView()
        listScroll.hasVerticalScroller = true
        listScroll.borderType = .noBorder
        tableView.frame = NSRect(x: 0, y: 0, width: 255, height: 360)
        tableView.autoresizingMask = [.width]
        tableView.headerView = nil
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.rowHeight = 38
        tableView.delegate = self
        tableView.dataSource = self
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("version"))
        column.width = 245
        tableView.addTableColumn(column)
        listScroll.documentView = tableView

        let previewScroll = NSScrollView()
        previewScroll.borderType = .lineBorder
        previewScroll.hasVerticalScroller = true
        preview.frame = NSRect(x: 0, y: 0, width: 470, height: 360)
        preview.minSize = NSSize(width: 0, height: 360)
        preview.isVerticallyResizable = true
        preview.autoresizingMask = [.width]
        preview.isEditable = false
        preview.isSelectable = true
        preview.drawsBackground = true
        preview.backgroundColor = .textBackgroundColor
        preview.font = .monospacedSystemFont(ofSize: 12.5, weight: .regular)
        preview.textColor = .labelColor
        preview.textContainerInset = NSSize(width: 14, height: 14)
        preview.textContainer?.widthTracksTextView = true
        previewScroll.documentView = preview

        let split = NSSplitView()
        split.isVertical = true
        split.dividerStyle = .thin
        split.addArrangedSubview(listScroll)
        split.addArrangedSubview(previewScroll)
        split.setPosition(255, ofDividerAt: 0)

        let cancel = NSButton(title: chinese ? "取消" : "Cancel", target: self, action: #selector(cancel(_:)))
        cancel.bezelStyle = .rounded
        restoreButton.title = chinese ? "恢复此版本" : "Restore This Version"
        restoreButton.target = self
        restoreButton.action = #selector(restore(_:))
        restoreButton.bezelStyle = .rounded
        restoreButton.keyEquivalent = "\r"
        restoreButton.isEnabled = false
        let buttons = NSStackView(views: [cancel, restoreButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.alignment = .centerY

        [title, detail, split, buttons].forEach { view in
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            title.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            detail.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            detail.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 5),
            split.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            split.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            split.topAnchor.constraint(equalTo: detail.bottomAnchor, constant: 20),
            split.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -18),
            buttons.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            buttons.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20)
        ])
        if !versions.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            showPreview(for: versions[0])
            restoreButton.isEnabled = true
        }
        return content
    }

    func numberOfRows(in tableView: NSTableView) -> Int { versions.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("versionCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? NSTableCellView()
        cell.identifier = identifier
        let label: NSTextField
        if let existing = cell.textField { label = existing }
        else {
            label = NSTextField(labelWithString: "")
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
            cell.textField = label
        }
        label.stringValue = versionTitle(for: versions[row].date)
        label.font = .systemFont(ofSize: 13.5, weight: .medium)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard versions.indices.contains(row) else {
            preview.string = ""
            restoreButton.isEnabled = false
            return
        }
        showPreview(for: versions[row])
        restoreButton.isEnabled = true
    }

    private func showPreview(for version: LedgerRecoveryVersion) {
        preview.string = (try? String(contentsOf: version.url, encoding: .utf8)) ?? (chinese ? "无法读取此历史版本。" : "This historical version could not be read.")
        preview.scrollRangeToVisible(NSRange(location: 0, length: 0))
    }

    private func versionTitle(for date: Date) -> String {
        let calendar = Calendar.current
        let time = DateFormatter()
        time.locale = chinese ? Locale(identifier: "zh_Hans_CN") : Locale(identifier: "en_US")
        time.dateFormat = chinese ? "HH:mm" : "h:mm a"
        if calendar.isDateInToday(date) { return "\(chinese ? "今天" : "Today") \(time.string(from: date))" }
        if calendar.isDateInYesterday(date) { return "\(chinese ? "昨天" : "Yesterday") \(time.string(from: date))" }
        let day = DateFormatter()
        day.locale = time.locale
        day.dateFormat = chinese ? "M月d日 HH:mm" : "MMM d, h:mm a"
        return day.string(from: date)
    }

    @objc private func cancel(_ sender: Any?) { dismiss() }

    @objc private func restore(_ sender: Any?) {
        let row = tableView.selectedRow
        guard versions.indices.contains(row) else { return }
        let version = versions[row]
        dismiss()
        onRestore(version)
    }

    private func dismiss() {
        guard let window = windowController?.window else { return }
        parentWindow?.endSheet(window)
        window.orderOut(nil)
        windowController = nil
    }
}
