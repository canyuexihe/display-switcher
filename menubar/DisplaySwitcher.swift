import AppKit
import ServiceManagement

let baseDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".display-switcher")
let layoutsDir = baseDir.appendingPathComponent("layouts")
let layoutScript = baseDir.appendingPathComponent("layout.sh").path
let dpBinary = baseDir.appendingPathComponent("bin/displayplacer").path
let stateFile = baseDir.appendingPathComponent("state.json").path

func run(_ path: String, _ args: [String]) -> (status: Int32, output: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    do { try p.run() } catch { return (-1, error.localizedDescription) }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
}

struct Preset {
    let name: String
    let screenIDs: [String]
    let screenNames: [String]
    let configs: [String]
}

func loadPresets() -> [Preset] {
    let files = ((try? FileManager.default.contentsOfDirectory(atPath: layoutsDir.path)) ?? [])
        .filter { $0.hasSuffix(".json") }.sorted()
    return files.compactMap { fn in
        let url = layoutsDir.appendingPathComponent(fn)
        guard let data = try? Data(contentsOf: url),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let screens = obj["screens"] as? [[String: Any]] else { return nil }
        let ids = screens.compactMap { $0["id"] as? String }
        let configs = screens.compactMap { $0["config"] as? String }
        guard !ids.isEmpty, ids.count == configs.count else { return nil }
        let names = screens.map { ($0["name"] as? String) ?? ($0["id"] as? String) ?? "未知显示器" }
        return Preset(name: String(fn.dropLast(5)), screenIDs: ids, screenNames: names, configs: configs)
    }
}

func configValue(_ config: String, _ key: String) -> String? {
    guard let r = config.range(of: key + ":") else { return nil }
    return String(config[r.upperBound...].prefix { !$0.isWhitespace })
}

func screenSummary(_ preset: Preset) -> String {
    zip(preset.screenNames, preset.configs).map { name, config in
        let res = configValue(config, "res") ?? "?"
        let hz = configValue(config, "hz").map { "@\($0)Hz" } ?? ""
        return "\(name) \(res)\(hz)"
    }.joined(separator: " · ")
}

func groupTitle(_ names: [String]) -> String {
    var counts: [String: Int] = [:]
    for n in names { counts[n, default: 0] += 1 }
    return counts.keys.sorted().map { counts[$0]! > 1 ? "\($0) ×\(counts[$0]!)" : $0 }
        .joined(separator: " + ")
}

func arrangementLabel(_ configs: [String]) -> String {
    var centers: [(Double, Double)] = []
    for c in configs {
        guard let res = configValue(c, "res"), let origin = configValue(c, "origin") else { continue }
        let wh = res.split(separator: "x")
        let xy = origin.dropFirst().dropLast().split(separator: ",")
        guard wh.count == 2, xy.count == 2,
              let w = Double(wh[0]), let h = Double(wh[1]),
              let x = Double(xy[0]), let y = Double(xy[1]) else { continue }
        centers.append((x + w / 2, y + h / 2))
    }
    if centers.count < 2 { return "单屏" }
    if centers.count > 2 { return "多屏排列" }
    let dx = abs(centers[0].0 - centers[1].0)
    let dy = abs(centers[0].1 - centers[1].1)
    return dx >= dy ? "左右排列" : "上下排列"
}

func displayplacerList() -> String {
    run(dpBinary, ["list"]).output
}

func connectedScreenIDs() -> Set<String> {
    var ids = Set<String>()
    for line in displayplacerList().split(separator: "\n") {
        if line.hasPrefix("Persistent screen id: ") {
            ids.insert(line.dropFirst("Persistent screen id: ".count).trimmingCharacters(in: .whitespaces))
        }
    }
    return ids
}

func currentScreenConfigs() -> [String] {
    guard let line = displayplacerList().split(separator: "\n").last(where: { $0.hasPrefix("displayplacer ") }) else { return [] }
    let regex = try! NSRegularExpression(pattern: "\"[^\"]*\"")
    let s = String(line)
    return regex.matches(in: s, range: NSRange(s.startIndex..., in: s))
        .map { String(s[Range($0.range, in: s)!]).replacingOccurrences(of: "\"", with: "") }
        .sorted()
}

func lastUsedPreset(forScreenSet ids: Set<String>) -> String? {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: stateFile)),
          let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          let lastUsed = obj["lastUsed"] as? [String: String] else { return nil }
    return lastUsed[ids.sorted().joined(separator: "|")]
}

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    let menu = NSMenu()
    var lastConnectedSet = Set<String>()
    var pendingCheck: DispatchWorkItem?
    var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "display.2", accessibilityDescription: "显示器布局")
            button.image?.isTemplate = true
        }
        menu.delegate = self
        statusItem.menu = menu
        lastConnectedSet = connectedScreenIDs()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.scheduleDisplayCheck()
        }
    }

    func scheduleDisplayCheck() {
        pendingCheck?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.handleDisplayChange()
        }
        pendingCheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
    }

    func handleDisplayChange() {
        let current = connectedScreenIDs()
        guard current != lastConnectedSet else { return }
        lastConnectedSet = current
        guard let name = lastUsedPreset(forScreenSet: current) else { return }
        let exists = loadPresets().contains { $0.name == name }
        guard exists else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            _ = run(layoutScript, ["apply", name])
        }
        if settingsWindow?.isVisible == true { rebuildSettings() }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let connected = connectedScreenIDs()
        let current = currentScreenConfigs()
        let available = loadPresets().filter { Set($0.screenIDs).isSubset(of: connected) }
        if available.isEmpty {
            let item = NSMenuItem(title: "当前显示器组合没有可用预设", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        for preset in available {
            let item = NSMenuItem(title: preset.name, action: #selector(applyPreset(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset.name
            if preset.configs.sorted() == current { item.state = .on }
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let manage = NSMenuItem(title: "管理预设…", action: #selector(openSettings), keyEquivalent: "")
        manage.target = self
        menu.addItem(manage)
        let save = NSMenuItem(title: "保存当前布局…", action: #selector(saveCurrent), keyEquivalent: "")
        save.target = self
        menu.addItem(save)
        let login = NSMenuItem(title: "登录时启动", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    @objc func applyPreset(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            _ = run(layoutScript, ["apply", name])
        }
    }

    @objc func saveCurrent() {
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        let alert = NSAlert()
        alert.messageText = "保存当前布局"
        alert.informativeText = "输入预设名称（将记录当前所有接入显示器的排列和分辨率）："
        alert.accessoryView = field
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")
        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        guard !name.isEmpty else { return }
        let result = run(layoutScript, ["save", name])
        if result.status != 0 {
            let err = NSAlert()
            err.messageText = "保存失败"
            err.informativeText = result.output
            err.runModal()
        }
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered, defer: false)
            w.title = "管理预设"
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 420, height: 300)
            w.center()
            settingsWindow = w
        }
        rebuildSettings()
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func rebuildSettings() {
        guard let window = settingsWindow else { return }
        let connected = connectedScreenIDs()
        let current = currentScreenConfigs()
        let presets = loadPresets()

        var groups: [String: (title: String, online: Bool, presets: [Preset])] = [:]
        for p in presets {
            let key = p.screenIDs.sorted().joined(separator: "|")
            let title = groupTitle(p.screenNames)
            let online = Set(p.screenIDs).isSubset(of: connected)
            if groups[key] == nil { groups[key] = (title, online, []) }
            groups[key]!.presets.append(p)
        }

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false

        func fullWidth(_ v: NSView) {
            v.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(v)
            v.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32).isActive = true
        }

        if presets.isEmpty {
            let empty = NSTextField(wrappingLabelWithString: "还没有保存任何预设。在菜单栏点「保存当前布局…」即可创建。")
            empty.textColor = .secondaryLabelColor
            fullWidth(empty)
        }

        for key in groups.keys.sorted(by: { groups[$0]!.title < groups[$1]!.title }) {
            let group = groups[key]!
            let header = NSTextField(labelWithString: group.title + (group.online ? "" : "（未接入）"))
            header.font = .boldSystemFont(ofSize: 13)
            header.textColor = group.online ? .labelColor : .secondaryLabelColor
            fullWidth(header)

            for p in group.presets {
                let isActive = group.online && p.configs.sorted() == current
                let info = NSStackView()
                info.orientation = .vertical
                info.alignment = .leading
                info.spacing = 2

                let titleLine = NSStackView()
                titleLine.orientation = .horizontal
                titleLine.spacing = 8
                let nameLabel = NSTextField(labelWithString: p.name)
                nameLabel.font = .systemFont(ofSize: 13, weight: isActive ? .semibold : .medium)
                titleLine.addArrangedSubview(nameLabel)
                if isActive {
                    let badge = NSTextField(labelWithString: "✓ 当前生效")
                    badge.font = .systemFont(ofSize: 11)
                    badge.textColor = .systemGreen
                    titleLine.addArrangedSubview(badge)
                }
                if lastUsedPreset(forScreenSet: Set(p.screenIDs)) == p.name {
                    let badge = NSTextField(labelWithString: "插拔自动恢复")
                    badge.font = .systemFont(ofSize: 11)
                    badge.textColor = .systemBlue
                    titleLine.addArrangedSubview(badge)
                }
                info.addArrangedSubview(titleLine)

                let detail = NSTextField(wrappingLabelWithString: arrangementLabel(p.configs) + " · " + screenSummary(p))
                detail.font = .systemFont(ofSize: 11)
                detail.textColor = .secondaryLabelColor
                detail.preferredMaxLayoutWidth = 350
                info.addArrangedSubview(detail)

                let rename = NSButton(title: "重命名", target: self, action: #selector(renamePreset(_:)))
                rename.bezelStyle = .rounded
                rename.identifier = NSUserInterfaceItemIdentifier(p.name)
                rename.setContentHuggingPriority(.required, for: .horizontal)

                let del = NSButton(title: "删除", target: self, action: #selector(deletePreset(_:)))
                del.bezelStyle = .rounded
                del.identifier = NSUserInterfaceItemIdentifier(p.name)

                let row = NSStackView()
                row.orientation = .horizontal
                row.alignment = .centerY
                row.spacing = 10
                row.addArrangedSubview(info)
                row.addArrangedSubview(rename)
                row.addArrangedSubview(del)
                info.setContentHuggingPriority(.defaultLow, for: .horizontal)
                del.setContentHuggingPriority(.required, for: .horizontal)
                row.translatesAutoresizingMaskIntoConstraints = false

                let container = NSView()
                container.wantsLayer = true
                container.layer?.cornerRadius = 8
                if isActive {
                    container.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.12).cgColor
                    container.layer?.borderColor = NSColor.systemGreen.withAlphaComponent(0.5).cgColor
                    container.layer?.borderWidth = 1
                }
                container.addSubview(row)
                NSLayoutConstraint.activate([
                    row.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
                    row.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6),
                    row.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
                    row.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
                ])
                fullWidth(container)
            }
        }

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = stack
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
        ])
        window.contentView = scroll
    }

    @objc func renamePreset(_ sender: NSButton) {
        guard let oldName = sender.identifier?.rawValue else { return }
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = oldName
        let alert = NSAlert()
        alert.messageText = "重命名预设"
        alert.informativeText = "为预设「\(oldName)」输入新名称："
        alert.accessoryView = field
        alert.addButton(withTitle: "重命名")
        alert.addButton(withTitle: "取消")
        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let newName = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        guard !newName.isEmpty, newName != oldName else { return }
        if loadPresets().contains(where: { $0.name.lowercased() == newName.lowercased() }) {
            let err = NSAlert()
            err.messageText = "名称已存在"
            err.informativeText = "已有名为「\(newName)」的预设，请换一个名称。"
            err.alertStyle = .warning
            err.runModal()
            return
        }
        let newURL = layoutsDir.appendingPathComponent(newName + ".json")
        do {
            try FileManager.default.moveItem(at: layoutsDir.appendingPathComponent(oldName + ".json"), to: newURL)
        } catch {
            let err = NSAlert()
            err.messageText = "重命名失败"
            err.informativeText = error.localizedDescription
            err.runModal()
            return
        }
        if let data = try? Data(contentsOf: newURL),
           var obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            obj["name"] = newName
            if let out = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) {
                try? out.write(to: newURL)
            }
        }
        if let data = try? Data(contentsOf: URL(fileURLWithPath: stateFile)),
           var obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let lastUsed = obj["lastUsed"] as? [String: String] {
            obj["lastUsed"] = lastUsed.mapValues { $0 == oldName ? newName : $0 }
            if let out = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) {
                try? out.write(to: URL(fileURLWithPath: stateFile))
            }
        }
        rebuildSettings()
    }

    @objc func deletePreset(_ sender: NSButton) {
        guard let name = sender.identifier?.rawValue else { return }
        let alert = NSAlert()
        alert.messageText = "删除预设「\(name)」？"
        alert.informativeText = "将删除该布局预设及其插拔自动恢复记录，操作不可恢复。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        try? FileManager.default.removeItem(at: layoutsDir.appendingPathComponent(name + ".json"))
        if let data = try? Data(contentsOf: URL(fileURLWithPath: stateFile)),
           var obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let lastUsed = obj["lastUsed"] as? [String: String] {
            obj["lastUsed"] = lastUsed.filter { $0.value != name }
            if let out = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) {
                try? out.write(to: URL(fileURLWithPath: stateFile))
            }
        }
        rebuildSettings()
    }

    @objc func toggleLogin(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let err = NSAlert()
            err.messageText = "设置登录启动失败"
            err.informativeText = error.localizedDescription
            err.runModal()
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()