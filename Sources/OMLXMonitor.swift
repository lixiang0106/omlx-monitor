import AppKit
import Foundation

// The activity endpoint is local and read-only. Credentials are read directly
// from oMLX's own configuration and are never stored in this application.
struct ActivityEnvelope: Decodable {
    let active_models: Activity
}

struct Activity: Decodable {
    let models: [ModelActivity]?
    let memory_pressure: MemoryPressure?
    let total_active_requests: Int?
    let total_waiting_requests: Int?
}

struct MemoryPressure: Decodable {
    let enabled: Bool?
    let current_formatted: String?
    let soft_formatted: String?
    let hard_formatted: String?
    let pressure_level: String?
}

struct ModelActivity: Decodable {
    let id: String
    let is_loading: Bool?
    let actual_size_formatted: String?
    let estimated_size_formatted: String?
    let active_requests: Int?
    let waiting_requests: Int?
    let generating: [Generating]?
    let prefilling: [Prefilling]?
}

struct Generating: Decodable {
    let generated_tokens: Int?
    let tokens_per_second: Double?
    let elapsed_seconds: Double?
}

struct Prefilling: Decodable {
    let processed: Int?
    let total: Int?
    let speed: Double?
    let elapsed: Double?
}

enum InterfaceLanguage: String, CaseIterable {
    case automatic, chinese, english
}

enum L {
    static var language: InterfaceLanguage = .automatic

    static var isChinese: Bool {
        switch language {
        case .chinese: return true
        case .english: return false
        case .automatic:
            return Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") ?? false
        }
    }

    static func t(_ zh: String, _ en: String) -> String { isChinese ? zh : en }

    static func count(_ zh: String, _ en: String, _ value: Int) -> String {
        String(format: t(zh, en), value)
    }
}

enum MonitorError: Error {
    case settingsUnavailable
    case invalidSettings
    case connection
    case unauthorized
    case server(Int)
    case invalidResponse

    var message: String {
        switch self {
        case .settingsUnavailable:
            return L.t("无法读取 oMLX 设置", "Cannot read the oMLX settings file")
        case .invalidSettings:
            return L.t("oMLX 设置格式不可用", "oMLX settings format is not usable")
        case .connection:
            return L.t("oMLX 未连接，正在重试", "oMLX not reachable — retrying")
        case .unauthorized:
            return L.t("身份验证失败，请检查 oMLX 设置",
                       "Authentication failed — check the oMLX settings file")
        case .server(let status):
            return L.t("oMLX 接口不可用（HTTP \(status)）",
                       "oMLX request failed (HTTP \(status))")
        case .invalidResponse:
            return L.t("oMLX 状态数据格式不可用", "Unexpected oMLX status payload")
        }
    }
}

final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        // Never forward the local API key to a redirect destination.
        completionHandler(nil)
    }
}

final class ActivityClient {
    private let redirectDelegate = NoRedirects()
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3.0
        config.timeoutIntervalForResource = 5.0
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpShouldSetCookies = false
        return URLSession(configuration: config, delegate: redirectDelegate, delegateQueue: nil)
    }()

    func fetch(_ completion: @escaping (Result<Activity, MonitorError>) -> Void) {
        let fileURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".omlx/settings.json")
        guard let data = try? Data(contentsOf: fileURL) else {
            completion(.failure(.settingsUnavailable)); return
        }
        guard let config = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            completion(.failure(.invalidSettings)); return
        }
        let server = config["server"] as? [String: Any] ?? [:]
        let port = server["port"] as? Int ?? 8000
        guard (1...65535).contains(port),
              let url = URL(string: "http://127.0.0.1:\(port)/admin/api/activity") else {
            completion(.failure(.invalidSettings)); return
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: 3.0)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let auth = config["auth"] as? [String: Any],
           let key = auth["api_key"] as? String, !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        session.dataTask(with: request) { data, response, error in
            guard error == nil, let http = response as? HTTPURLResponse else {
                completion(.failure(.connection)); return
            }
            guard http.statusCode == 200 else {
                completion(.failure(http.statusCode == 401 || http.statusCode == 403
                                    ? .unauthorized : .server(http.statusCode)))
                return
            }
            guard let data = data,
                  let envelope = try? JSONDecoder().decode(ActivityEnvelope.self, from: data) else {
                completion(.failure(.invalidResponse)); return
            }
            completion(.success(envelope.active_models))
        }.resume()
    }
}

struct DisplayModel {
    let title: String
    let detail: String
    let size: String
}

struct DisplayState {
    let connected: Bool
    let headline: String
    let counts: String
    let models: [DisplayModel]
    let memory: String
    let hasPressure: Bool

    static func failure(_ error: MonitorError) -> DisplayState {
        DisplayState(connected: false,
                     headline: L.t("oMLX 状态不可用", "oMLX status unavailable"),
                     counts: L.t("离线", "OFFLINE"),
                     models: [DisplayModel(title: error.message,
                                           detail: L.t("连接恢复后自动刷新",
                                                       "Refreshes automatically when reconnected"),
                                           size: "")],
                     memory: L.t("内存及请求数暂不可用",
                                 "Memory and request counts unavailable"),
                     hasPressure: false)
    }

    static func from(_ activity: Activity) -> DisplayState {
        let all = activity.models ?? []
        let sorted = all.enumerated().sorted { lhs, rhs in
            let left = (lhs.element.active_requests ?? 0) + (lhs.element.waiting_requests ?? 0)
            let right = (rhs.element.active_requests ?? 0) + (rhs.element.waiting_requests ?? 0)
            return left == right ? lhs.offset < rhs.offset : left > right
        }.map { $0.element }
        var models = sorted.map { model -> DisplayModel in
            let requests = L.t("活跃 \(model.active_requests ?? 0) · 等待 \(model.waiting_requests ?? 0)",
                               "\(model.active_requests ?? 0) active · \(model.waiting_requests ?? 0) waiting")
            let generating = model.generating ?? []
            let prefilling = model.prefilling ?? []
            let detail: String
            if model.is_loading == true {
                detail = L.t("加载中…   ·   \(requests)", "Loading…   ·   \(requests)")
            } else if let item = generating.first {
                var parts = [L.t("生成中", "Generating")]
                if let tokens = item.generated_tokens { parts.append("\(tokens) tok") }
                if let speed = item.tokens_per_second { parts.append(String(format: "%.1f tok/s", speed)) }
                if let elapsed = item.elapsed_seconds { parts.append(String(format: "%.1f s", elapsed)) }
                if generating.count > 1 {
                    parts.append(L.t("另 \(generating.count - 1) 条生成",
                                     "+\(generating.count - 1) generating"))
                }
                if !prefilling.isEmpty {
                    parts.append(L.t("预填 \(prefilling.count)", "\(prefilling.count) prefilling"))
                }
                detail = parts.joined(separator: "  ·  ")
            } else if let item = prefilling.first {
                var parts = [L.t("预填充", "Prefilling")]
                if let processed = item.processed, let total = item.total {
                    parts.append("\(processed) / \(total) tok")
                }
                if let speed = item.speed, speed > 0 { parts.append(String(format: "%.1f tok/s", speed)) }
                if let elapsed = item.elapsed { parts.append(String(format: "%.1f s", elapsed)) }
                if prefilling.count > 1 {
                    parts.append(L.t("另 \(prefilling.count - 1) 条预填",
                                     "+\(prefilling.count - 1) prefilling"))
                }
                detail = parts.joined(separator: "  ·  ")
            } else if (model.active_requests ?? 0) > 0 {
                detail = L.t("处理中   ·   \(requests)", "Running   ·   \(requests)")
            } else if (model.waiting_requests ?? 0) > 0 {
                detail = L.t("等待中   ·   \(requests)", "Queued   ·   \(requests)")
            } else {
                detail = L.t("已加载 · 空闲", "Loaded · Idle")
            }
            let actual = model.actual_size_formatted.map {
                L.t("\($0) 实测", "\($0) actual")
            } ?? L.t("实测未提供", "actual n/a")
            let estimate = model.estimated_size_formatted.map {
                L.t("\($0) 估算", "\($0) estimated")
            } ?? L.t("估算未提供", "estimated n/a")
            return DisplayModel(title: model.id, detail: detail, size: "\(actual)  /  \(estimate)")
        }
        if models.isEmpty {
            models = [DisplayModel(title: L.t("暂无已加载的模型", "No model loaded"),
                                   detail: L.t("等待 oMLX 加载模型",
                                               "Waiting for oMLX to load a model"),
                                   size: "")]
        }
        let counts = L.t("活跃 \(activity.total_active_requests ?? 0) · 等待 \(activity.total_waiting_requests ?? 0)",
                         "\(activity.total_active_requests ?? 0) active · \(activity.total_waiting_requests ?? 0) waiting")
        let pressure = activity.memory_pressure
        let memory: String
        if pressure?.enabled == true {
            memory = L.t("进程内存  \(pressure?.current_formatted ?? "—")  /  软限 \(pressure?.soft_formatted ?? "—")  /  硬限 \(pressure?.hard_formatted ?? "—")",
                         "Process \(pressure?.current_formatted ?? "—")  /  soft \(pressure?.soft_formatted ?? "—")  /  hard \(pressure?.hard_formatted ?? "—")")
        } else {
            memory = L.t("进程内存保护未启用或数据不可用",
                         "Memory guard disabled or data unavailable")
        }
        let level = pressure?.pressure_level ?? "ok"
        return DisplayState(connected: true,
                            headline: L.t("oMLX 实时状态", "oMLX Live Status"),
                            counts: counts, models: models, memory: memory,
                            hasPressure: level != "ok")
    }
}

final class DragLabel: NSTextField {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

final class DragBackground: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

final class MonitorPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

struct MonitorPreferences {
    static let widthValues = [340, 448, 560, 680]
    static let fontValues = [10, 12, 14, 16]
    static let defaultWidth = 448
    static let defaultFont = 12

    static func widthTitle(_ value: Int) -> String {
        switch value {
        case 340: return L.t("紧凑", "Compact")
        case 560: return L.t("宽", "Wide")
        case 680: return L.t("更宽", "Wider")
        default: return L.t("标准", "Standard")
        }
    }

    static func fontTitle(_ value: Int) -> String {
        switch value {
        case 10: return L.t("小", "Small")
        case 14: return L.t("大", "Large")
        case 16: return L.t("特大", "X-Large")
        default: return L.t("标准", "Standard")
        }
    }

    static func savedValue(_ key: String, options: [Int], fallback: Int) -> Int {
        let value = UserDefaults.standard.object(forKey: key) as? Int ?? fallback
        return options.contains(value) ? value : fallback
    }
}

final class MonitorApp: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let client = ActivityClient()
    private var panel: NSPanel!
    private var root: DragBackground!
    private var rootStack: NSStackView!
    private var bodyStack: NSStackView!
    private var headerLabel: DragLabel!
    private var countsLabel: DragLabel!
    private var memoryLabel: DragLabel!
    private var menuButton: NSButton!
    private var quitButton: NSButton!
    private var headerHeight: NSLayoutConstraint!
    private var memoryHeight: NSLayoutConstraint!
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var pending = false
    private var currentState = DisplayState.failure(.connection)
    private var lastActivity: Activity?
    private var lastError: MonitorError = .connection
    private var adjustingFrame = false
    private var darkText = UserDefaults.standard.bool(forKey: "darkText")
    private var showBackdrop = UserDefaults.standard.bool(forKey: "showBackdrop")
    private var compactMode = UserDefaults.standard.bool(forKey: "compactMode")
    private var languagePreference = UserDefaults.standard.string(forKey: "language")
        .flatMap(InterfaceLanguage.init(rawValue:)) ?? .automatic
    private var windowWidth = MonitorPreferences.savedValue(
        "windowWidth", options: MonitorPreferences.widthValues,
        fallback: MonitorPreferences.defaultWidth)
    private var fontSize = MonitorPreferences.savedValue(
        "fontSize", options: MonitorPreferences.fontValues,
        fallback: MonitorPreferences.defaultFont)
    private let maxVisibleModels = 4

    private var textScale: CGFloat { CGFloat(fontSize) / 12.0 }
    private func scaled(_ value: CGFloat) -> CGFloat { ceil(value * textScale) }

    private func contentHeight(modelCount: Int, hasMore: Bool) -> CGFloat {
        let groupHeight = scaled(19) + scaled(18) + (compactMode ? 0 : scaled(16) + 2) + 2
        let bodyHeight = CGFloat(modelCount) * groupHeight
            + CGFloat(max(0, modelCount - 1)) * 6
            + (hasMore ? 6 + scaled(16) : 0)
        return 18 + max(22, scaled(22)) + 12 + bodyHeight + scaled(20)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        L.language = languagePreference
        buildWindow()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "oMLX"
        statusItem.button?.toolTip = L.t("oMLX 状态浮窗", "oMLX status HUD")
        refreshMenu()
        render()
        restorePosition()
        if CommandLine.arguments.contains("--gui-diagnostic") {
            print("after positioning: frame=\(panel.frame) screens=\(NSScreen.screens.map { $0.visibleFrame })")
            print("controls: key=\(panel.canBecomeKey) menu=\(menu().items.map { $0.title })")
            if !testLayoutLevels() { print("FAIL: size and layout diagnostics"); exit(2) }
            print("PASS: size options, font scaling, layout and menus")
        }
        panel.orderFrontRegardless()
        if CommandLine.arguments.contains("--gui-diagnostic") {
            print("after show: frame=\(panel.frame) visible=\(panel.isVisible)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                if let self = self { print("after refresh: frame=\(self.panel.frame) visible=\(self.panel.isVisible)") }
                NSApp.terminate(nil)
            }
        }
        poll()
        timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
        if let timer = timer { RunLoop.main.add(timer, forMode: .common) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        if let item = statusItem { NSStatusBar.system.removeStatusItem(item) }
    }

    private func buildWindow() {
        panel = MonitorPanel(contentRect: NSRect(x: 0, y: 0, width: CGFloat(windowWidth), height: 130),
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        panel.delegate = self
        panel.title = L.t("oMLX 状态浮窗", "oMLX Status HUD")
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none

        root = DragBackground(frame: panel.contentView!.bounds)
        root.wantsLayer = true
        root.layer?.cornerRadius = 10
        panel.contentView = root
        rootStack = NSStackView()
        rootStack.orientation = .vertical
        rootStack.alignment = .width
        rootStack.spacing = 6
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(rootStack)
        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            rootStack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10),
            rootStack.topAnchor.constraint(equalTo: root.topAnchor, constant: 9),
            rootStack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -9)
        ])

        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 7
        headerHeight = header.heightAnchor.constraint(equalToConstant: 22)
        headerHeight.isActive = true
        headerLabel = makeLabel(size: 13, weight: .semibold)
        headerLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        headerLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        countsLabel = makeLabel(size: 12, weight: .medium)
        countsLabel.alignment = .right
        countsLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        menuButton = makeButton(title: "⋯", action: #selector(showMenu(_:)))
        quitButton = makeButton(title: "×", action: #selector(quit(_:)))
        menuButton.toolTip = L.t("浮窗选项", "HUD options")
        quitButton.toolTip = L.t("退出浮窗", "Quit")
        header.addArrangedSubview(headerLabel)
        header.addArrangedSubview(countsLabel)
        header.addArrangedSubview(menuButton)
        header.addArrangedSubview(quitButton)
        rootStack.addArrangedSubview(header)
        bodyStack = NSStackView()
        bodyStack.orientation = .vertical
        bodyStack.alignment = .width
        bodyStack.spacing = 6
        rootStack.addArrangedSubview(bodyStack)
        memoryLabel = makeLabel(size: 12, weight: .medium)
        memoryHeight = memoryLabel.heightAnchor.constraint(equalToConstant: 20)
        memoryHeight.isActive = true
        rootStack.addArrangedSubview(memoryLabel)
    }

    private func makeButton(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.isBordered = false
        button.font = .systemFont(ofSize: 17, weight: .medium)
        button.widthAnchor.constraint(equalToConstant: 23).isActive = true
        button.heightAnchor.constraint(equalToConstant: 22).isActive = true
        return button
    }

    private func makeLabel(size: CGFloat, weight: NSFont.Weight) -> DragLabel {
        let label = DragLabel(labelWithString: "")
        label.font = .systemFont(ofSize: size * textScale, weight: weight)
        label.lineBreakMode = .byTruncatingMiddle
        label.maximumNumberOfLines = 1
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.isSelectable = false
        return label
    }

    private func setText(_ text: String, on label: NSTextField, secondary: Bool = false,
                         warning: Bool = false) {
        let color: NSColor
        if warning {
            color = darkText ? NSColor(calibratedRed: 0.65, green: 0.14, blue: 0.05, alpha: 1)
                             : NSColor(calibratedRed: 1.0, green: 0.72, blue: 0.43, alpha: 1)
        } else {
            color = (darkText ? NSColor.black : NSColor.white)
                .withAlphaComponent(secondary ? 0.84 : 1.0)
        }
        let shadow = NSShadow()
        shadow.shadowColor = (darkText ? NSColor.white : NSColor.black).withAlphaComponent(0.9)
        shadow.shadowBlurRadius = 3
        shadow.shadowOffset = NSSize(width: 0, height: darkText ? -0.5 : 0.5)
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingMiddle
        style.alignment = label.alignment
        label.attributedStringValue = NSAttributedString(string: text, attributes: [
            .font: label.font ?? NSFont.systemFont(ofSize: 12),
            .foregroundColor: color, .shadow: shadow, .paragraphStyle: style
        ])
    }

    private func render() {
        guard panel != nil else { return }
        root.layer?.backgroundColor = showBackdrop
            ? (darkText ? NSColor.white.withAlphaComponent(0.72).cgColor
                        : NSColor.black.withAlphaComponent(0.56).cgColor)
            : NSColor.clear.cgColor
        let buttonColor = darkText ? NSColor.black : NSColor.white
        menuButton.contentTintColor = buttonColor
        quitButton.contentTintColor = buttonColor
        headerLabel.font = .systemFont(ofSize: 13 * textScale, weight: .semibold)
        countsLabel.font = .systemFont(ofSize: 12 * textScale, weight: .medium)
        memoryLabel.font = .systemFont(ofSize: 12 * textScale, weight: .medium)
        headerHeight.constant = max(22, scaled(22))
        memoryHeight.constant = scaled(20)
        setText((currentState.connected ? "●  " : "○  ") + currentState.headline,
                on: headerLabel)
        setText(currentState.counts, on: countsLabel, secondary: true)
        setText(currentState.memory, on: memoryLabel, secondary: true,
                warning: currentState.hasPressure)
        for view in bodyStack.arrangedSubviews {
            bodyStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        let visible = Array(currentState.models.prefix(maxVisibleModels))
        for model in visible {
            let group = NSStackView()
            group.orientation = .vertical
            group.alignment = .width
            group.spacing = 2
            let name = makeLabel(size: 13, weight: .semibold)
            name.heightAnchor.constraint(equalToConstant: scaled(19)).isActive = true
            setText(model.title, on: name)
            let detail = makeLabel(size: 12, weight: .medium)
            detail.heightAnchor.constraint(equalToConstant: scaled(18)).isActive = true
            setText(model.detail, on: detail)
            group.addArrangedSubview(name)
            group.addArrangedSubview(detail)
            if !compactMode {
                let size = makeLabel(size: 11, weight: .regular)
                size.heightAnchor.constraint(equalToConstant: scaled(16)).isActive = true
                setText(model.size, on: size, secondary: true)
                group.addArrangedSubview(size)
            }
            bodyStack.addArrangedSubview(group)
        }
        let extra = currentState.models.count - visible.count
        if extra > 0 {
            let more = makeLabel(size: 11, weight: .regular)
            more.heightAnchor.constraint(equalToConstant: scaled(16)).isActive = true
            setText(L.t("另有 \(extra) 个模型未展开", "+\(extra) more models"), on: more, secondary: true)

            bodyStack.addArrangedSubview(more)
        }
        let height = contentHeight(modelCount: visible.count, hasMore: extra > 0)
        let old = panel.frame
        let desired = NSRect(x: old.origin.x, y: old.maxY - height,
                             width: CGFloat(windowWidth), height: height)
        // Resize only when dimensions change; otherwise borderless panels can drift.
        if abs(old.height - height) > 0.5 || abs(old.width - desired.width) > 0.5 {
            adjustingFrame = true
            panel.setFrame(clampedToScreen(desired), display: true)
            adjustingFrame = false
        }
    }

    private func clampedToScreen(_ frame: NSRect) -> NSRect {
        guard let screen = panel.screen ?? NSScreen.screens.first else { return frame }
        let area = screen.visibleFrame
        var result = frame
        result.size.width = min(frame.width, area.width)
        result.origin.x = min(max(frame.minX, area.minX), area.maxX - result.width)
        // Content height is based on visible rows; it is not scaled or clipped.
        result.origin.y = max(area.minY, min(frame.minY, area.maxY - frame.height))
        return result
    }

    func windowDidMove(_ notification: Notification) {
        guard panel.isVisible, !adjustingFrame else { return }
        let topLeft = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
        UserDefaults.standard.set([Double(topLeft.x), Double(topLeft.y)], forKey: "windowTopLeft")
    }

    private func restorePosition() {
        guard let coords = UserDefaults.standard.array(forKey: "windowTopLeft") as? [Double],
              coords.count == 2, coords.allSatisfy({ $0.isFinite }) else {
            resetPosition(nil)
            return
        }
        let proposed = NSRect(x: coords[0], y: coords[1] - panel.frame.height,
                              width: panel.frame.width, height: panel.frame.height)
        let screens = NSScreen.screens
        if let screen = screens.first(where: { $0.visibleFrame.intersects(proposed) }) {
            let area = screen.visibleFrame
            let x = min(max(proposed.minX, area.minX), area.maxX - proposed.width)
            let y = max(area.minY, min(proposed.minY, area.maxY - proposed.height))
            adjustingFrame = true
            panel.setFrameOrigin(NSPoint(x: x, y: y))
            adjustingFrame = false
        } else {
            resetPosition(nil)
        }
    }

    private func testLayoutLevels() -> Bool {
        let savedWidth = windowWidth
        let savedFont = fontSize
        let savedCompact = compactMode
        let savedState = currentState
        let savedFrame = panel.frame
        defer {
            windowWidth = savedWidth
            fontSize = savedFont
            compactMode = savedCompact
            currentState = savedState
            render()
            panel.setFrame(savedFrame, display: false)
        }
        let sample = DisplayModel(title: "Qwen3.8-Flash-Next-oQ3e-mtp",
                                  detail: "生成中 · 250 tok · 63.8 tok/s · 4.0 s",
                                  size: "56.85GB 实测 / 90.52GB 估算")
        currentState = DisplayState(connected: true, headline: "oMLX 实时状态",
                                    counts: "活跃 1 · 等待 1",
                                    models: Array(repeating: sample, count: 5),
                                    memory: "进程内存 72.6GB / 软限 90.0GB / 硬限 97.0GB",
                                    hasPressure: false)
        let currentMenu = menu()
        let submenus = currentMenu.items.compactMap { $0.submenu }
        guard submenus.count == 3,
              submenus.contains(where: { $0.items.count == 4 }),
              submenus.filter({ $0.items.count == 4 }).count == 2 else { return false }
        for compact in [false, true] {
            compactMode = compact
            for width in MonitorPreferences.widthValues {
                windowWidth = width
                for font in MonitorPreferences.fontValues {
                    fontSize = font
                    render()
                    root.layoutSubtreeIfNeeded()
                    let expectedHeight = contentHeight(modelCount: 4, hasMore: true)
                    guard abs(panel.frame.width - CGFloat(width)) < 1,
                          abs(panel.frame.height - expectedHeight) < 1,
                          abs((memoryLabel.font?.pointSize ?? 0) - CGFloat(font)) < 0.1,
                          !rootStack.hasAmbiguousLayout, !bodyStack.hasAmbiguousLayout,
                          bodyStack.arrangedSubviews.count == 5 else {
                        print("layout mismatch: width=\(width) font=\(font) compact=\(compact) frame=\(panel.frame) expectedHeight=\(expectedHeight) actualFont=\(memoryLabel.font?.pointSize ?? 0) ambiguous=\(rootStack.hasAmbiguousLayout)/\(bodyStack.hasAmbiguousLayout) rows=\(bodyStack.arrangedSubviews.count)")
                        return false
                    }
                    for group in bodyStack.arrangedSubviews.prefix(4) {
                        guard let stack = group as? NSStackView,
                              stack.arrangedSubviews.count == (compact ? 2 : 3) else {
                            print("row mismatch: width=\(width) font=\(font) compact=\(compact)")
                            return false
                        }
                    }
                }
            }
        }
        return true
    }

    private func poll() {
        guard !pending else { return }
        pending = true
        client.fetch { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.pending = false
                switch result {
                case .success(let activity):
                    self.lastActivity = activity
                    self.currentState = .from(activity)
                case .failure(let error):
                    self.lastActivity = nil
                    self.lastError = error
                    self.currentState = .failure(error)
                }
                self.render()
            }
        }
    }

    private func menu() -> NSMenu {
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        let setDefaults = NSMenuItem(title: L.t("设为紧凑小字", "Compact preset"),
                                     action: #selector(setCompactPreset(_:)), keyEquivalent: "")
        setDefaults.target = self
        menu.addItem(setDefaults)
        let widthMenu = NSMenu(title: L.t("浮窗宽度", "Width"))
        for value in MonitorPreferences.widthValues {
            let item = NSMenuItem(title: "\(MonitorPreferences.widthTitle(value))  ·  \(value) pt",
                                  action: #selector(setWindowWidth(_:)), keyEquivalent: "")
            item.target = self
            item.tag = value
            item.state = value == windowWidth ? .on : .off
            widthMenu.addItem(item)
        }
        let widthItem = NSMenuItem(title: L.t("浮窗宽度", "Width"), action: nil, keyEquivalent: "")
        widthItem.submenu = widthMenu
        menu.addItem(widthItem)

        let fontMenu = NSMenu(title: L.t("字体大小", "Text size"))
        for value in MonitorPreferences.fontValues {
            let item = NSMenuItem(title: "\(MonitorPreferences.fontTitle(value))  ·  \(L.t("正文", "body")) \(value) pt",
                                  action: #selector(setFontSize(_:)), keyEquivalent: "")
            item.target = self
            item.tag = value
            item.state = value == fontSize ? .on : .off
            fontMenu.addItem(item)
        }
        let fontItem = NSMenuItem(title: L.t("字体大小", "Text size"), action: nil, keyEquivalent: "")
        fontItem.submenu = fontMenu
        menu.addItem(fontItem)
        add(compactMode ? L.t("显示模型内存明细", "Show model memory rows")
                        : L.t("精简显示（隐藏模型内存明细）", "Compact rows (hide model memory)"),
            #selector(toggleCompactMode(_:)))
        add(L.t("恢复默认尺寸和字体", "Reset size & text"),
            #selector(resetDisplaySize(_:)))
        menu.addItem(.separator())
        add(showBackdrop ? L.t("关闭半透明底色", "Turn backdrop off")
                         : L.t("启用半透明底色", "Turn backdrop on"),
            #selector(toggleBackdrop(_:)))
        add(darkText ? L.t("切换为浅色文字", "Switch to light text")
                      : L.t("切换为深色文字", "Switch to dark text"),
            #selector(toggleText(_:)))

        let languageMenu = NSMenu(title: L.t("语言", "Language"))
        for (mode, title) in [(InterfaceLanguage.automatic, L.t("自动（跟随系统）", "Auto (system)")),
                              (InterfaceLanguage.chinese, "中文"),
                              (InterfaceLanguage.english, "English")] {
            let item = NSMenuItem(title: title, action: #selector(setLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = mode == languagePreference ? .on : .off
            languageMenu.addItem(item)
        }
        let languageItem = NSMenuItem(title: L.t("语言", "Language"), action: nil, keyEquivalent: "")
        languageItem.submenu = languageMenu
        menu.addItem(languageItem)

        add(L.t("移回屏幕左上角", "Move to top-left"),
            #selector(resetPosition(_:)))
        menu.addItem(.separator())
        add(L.t("退出浮窗", "Quit"), #selector(quit(_:)))
        return menu
    }

    private func refreshMenu() {
        statusItem?.menu = menu()
        root?.menu = menu()
    }

    @objc private func showMenu(_ sender: NSButton) {
        let popup = menu()
        popup.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.minY), in: sender)
    }

    @objc private func setLanguage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = InterfaceLanguage(rawValue: raw) else { return }
        languagePreference = mode
        L.language = mode
        UserDefaults.standard.set(raw, forKey: "language")
        statusItem?.button?.toolTip = L.t("oMLX 状态浮窗", "oMLX status HUD")
        if let activity = lastActivity {
            currentState = .from(activity)
        } else {
            currentState = .failure(lastError)
        }
        refreshMenu(); render()
    }

    @objc private func setCompactPreset(_ sender: Any?) {
        windowWidth = 340
        fontSize = 10
        compactMode = true
        UserDefaults.standard.set(windowWidth, forKey: "windowWidth")
        UserDefaults.standard.set(fontSize, forKey: "fontSize")
        UserDefaults.standard.set(compactMode, forKey: "compactMode")
        refreshMenu(); render()
    }

    @objc private func setWindowWidth(_ sender: NSMenuItem) {
        guard MonitorPreferences.widthValues.contains(sender.tag) else { return }
        windowWidth = sender.tag
        UserDefaults.standard.set(windowWidth, forKey: "windowWidth")
        refreshMenu(); render()
    }

    @objc private func setFontSize(_ sender: NSMenuItem) {
        guard MonitorPreferences.fontValues.contains(sender.tag) else { return }
        fontSize = sender.tag
        UserDefaults.standard.set(fontSize, forKey: "fontSize")
        refreshMenu(); render()
    }

    @objc private func toggleCompactMode(_ sender: Any?) {
        compactMode.toggle()
        UserDefaults.standard.set(compactMode, forKey: "compactMode")
        refreshMenu(); render()
    }

    @objc private func resetDisplaySize(_ sender: Any?) {
        windowWidth = MonitorPreferences.defaultWidth
        fontSize = MonitorPreferences.defaultFont
        compactMode = false
        UserDefaults.standard.set(windowWidth, forKey: "windowWidth")
        UserDefaults.standard.set(fontSize, forKey: "fontSize")
        UserDefaults.standard.set(compactMode, forKey: "compactMode")
        refreshMenu(); render()
    }

    @objc private func toggleBackdrop(_ sender: Any?) {
        showBackdrop.toggle()
        UserDefaults.standard.set(showBackdrop, forKey: "showBackdrop")
        refreshMenu(); render()
    }

    @objc private func toggleText(_ sender: Any?) {
        darkText.toggle()
        UserDefaults.standard.set(darkText, forKey: "darkText")
        refreshMenu(); render()
    }

    @objc private func resetPosition(_ sender: Any?) {
        guard let screen = NSScreen.screens.first else { return }
        let area = screen.visibleFrame
        let topLeft = NSPoint(x: area.minX + 12, y: area.maxY - 12)
        adjustingFrame = true
        panel.setFrameTopLeftPoint(topLeft)
        adjustingFrame = false
        UserDefaults.standard.set([Double(topLeft.x), Double(topLeft.y)], forKey: "windowTopLeft")
    }

    @objc private func quit(_ sender: Any?) {
        NSApp.terminate(nil)
    }
}

func runSelfTests() -> Bool {
    L.language = .chinese
    let json = """
    {"active_models":{"models":[{"id":"demo-model","is_loading":false,"actual_size_formatted":"56.85GB","estimated_size_formatted":"90.52GB","active_requests":1,"waiting_requests":1,"generating":[{"generated_tokens":62,"tokens_per_second":63.8,"elapsed_seconds":1.0}],"prefilling":[]}],"memory_pressure":{"enabled":true,"current_formatted":"72.6GB","soft_formatted":"90.0GB","hard_formatted":"97.0GB","pressure_level":"ok"},"total_active_requests":1,"total_waiting_requests":1}}
    """
    guard let envelope = try? JSONDecoder().decode(ActivityEnvelope.self, from: Data(json.utf8)) else {
        print("FAIL: generating JSON"); return false
    }
    let state = DisplayState.from(envelope.active_models)
    guard state.connected, state.models.first?.detail.contains("63.8 tok/s") == true,
          state.counts.contains("等待 1"), state.memory.contains("软限 90.0GB"),
          state.memory.contains("硬限 97.0GB") else {
        print("FAIL: generating display"); return false
    }
    let loading = "{\"active_models\":{\"models\":[{\"id\":\"demo\",\"is_loading\":true}]}}"
    let idle = "{\"active_models\":{\"models\":[{\"id\":\"demo\"}]}}"
    guard let load = try? JSONDecoder().decode(ActivityEnvelope.self, from: Data(loading.utf8)),
          DisplayState.from(load.active_models).models.first?.detail.contains("加载中") == true,
          let idleValue = try? JSONDecoder().decode(ActivityEnvelope.self, from: Data(idle.utf8)),
          DisplayState.from(idleValue.active_models).models.first?.detail.contains("空闲") == true else {
        print("FAIL: loading/idle display"); return false
    }
    let prefill = """
    {"active_models":{"models":[{"id":"demo","prefilling":[{"processed":500,"total":1000,"speed":250.0}],"generating":[]}],"memory_pressure":{"enabled":false},"total_active_requests":1,"total_waiting_requests":0}}
    """
    guard let pre = try? JSONDecoder().decode(ActivityEnvelope.self, from: Data(prefill.utf8)),
          DisplayState.from(pre.active_models).models.first?.detail.contains("500 / 1000 tok") == true,
          DisplayState.from(pre.active_models).memory.contains("未启用") else {
        print("FAIL: prefill display"); return false
    }
    let empty = "{\"active_models\":{\"models\":[]}}"
    guard let blank = try? JSONDecoder().decode(ActivityEnvelope.self, from: Data(empty.utf8)),
          DisplayState.from(blank.active_models).models.first?.title == "暂无已加载的模型",
          !DisplayState.failure(.connection).connected,
          DisplayState.failure(.unauthorized).models.first?.title.contains("身份验证失败") == true,
          (try? JSONDecoder().decode(ActivityEnvelope.self, from: Data("not JSON".utf8))) == nil else {
        print("FAIL: empty/offline/auth/invalid display"); return false
    }
    print("PASS: generating, prefill, loading, idle, memory limits, empty, offline, authentication, invalid data")

    L.language = .english
    guard let englishEnvelope = try? JSONDecoder().decode(ActivityEnvelope.self, from: Data(json.utf8)) else {
        print("FAIL: english JSON"); return false
    }
    let english = DisplayState.from(englishEnvelope.active_models)
    guard english.headline == "oMLX Live Status",
          english.counts.contains("1 active"), english.counts.contains("1 waiting"),
          english.models.first?.detail.contains("Generating") == true,
          english.models.first?.detail.contains("63.8 tok/s") == true,
          english.models.first?.size.contains("actual") == true,
          english.memory.contains("Process 72.6GB"),
          DisplayState.failure(.connection).headline == "oMLX status unavailable",
          DisplayState.failure(.unauthorized).models.first?.title.contains("Authentication failed") == true else {
        print("FAIL: english display"); return false
    }
    L.language = .chinese
    print("PASS: English UI strings and error states")
    return true
}

if CommandLine.arguments.contains("--self-test") {
    exit(runSelfTests() ? 0 : 1)
} else if CommandLine.arguments.contains("--probe") {
    let client = ActivityClient()
    let done = DispatchSemaphore(value: 0)
    var succeeded = false
    client.fetch { result in
        switch result {
        case .success(let activity):
            let state = DisplayState.from(activity)
            print("CONNECTED: models=\((activity.models ?? []).count), \(state.counts), \(state.memory)")
            succeeded = true
        case .failure(let error):
            print("UNAVAILABLE: \(error.message)")
        }
        done.signal()
    }
    if done.wait(timeout: .now() + 8) == .timedOut { print("UNAVAILABLE: timed out") }
    exit(succeeded ? 0 : 1)
} else {
    let app = NSApplication.shared
    let delegate = MonitorApp()
    app.delegate = delegate
    app.run()
}
