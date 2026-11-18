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
        return Preset(name: String(fn.dropLast(5)), screenIDs: ids, configs: configs)
    }
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