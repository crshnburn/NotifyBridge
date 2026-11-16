import AppKit
import Network

/// Settings come from UserDefaults, so they can be set either persistently:
///   defaults write com.local.notifybridge port -int 9000
/// or per launch:
///   open NotifyBridge.app --args -port 9000
struct Config {
    let host: String
    let port: UInt16
    let token: String?

    static func load() -> Config {
        let defaults = UserDefaults.standard
        let port = defaults.integer(forKey: "port")
        let token = defaults.string(forKey: "token")
        return Config(
            host: defaults.string(forKey: "host") ?? "127.0.0.1",
            port: (1...65_535).contains(port) ? UInt16(port) : 8787,
            token: (token?.isEmpty ?? true) ? nil : token
        )
    }

    var baseURL: String { "http://\(host == "0.0.0.0" ? "127.0.0.1" : host):\(port)" }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let config = Config.load()
    private let notifier = Notifier()
    private var server: HTTPServer?
    private var statusItem: NSStatusItem!
    private let statusLine = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        notifier.requestAuthorization()
        startServer()
    }

    private func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "bell.badge", accessibilityDescription: "NotifyBridge")

        let menu = NSMenu()
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Send Test Notification", action: #selector(sendTest), keyEquivalent: "t").target = self
        menu.addItem(withTitle: "Copy curl Example", action: #selector(copyCurl), keyEquivalent: "c").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit NotifyBridge", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    private func startServer() {
        do {
            let server = try HTTPServer(host: config.host, port: config.port) { [weak self] request, respond in
                guard let self else { return respond(.error(503, "shutting down")) }
                self.handle(request, respond: respond)
            }
            self.server = server
            server.start { [weak self] state in
                DispatchQueue.main.async { self?.listenerStateChanged(state) }
            }
        } catch {
            statusLine.title = "Failed to start: \(error.localizedDescription)"
        }
    }

    private func listenerStateChanged(_ state: NWListener.State) {
        switch state {
        case .ready:
            statusLine.title = "Listening on \(config.baseURL)"
        case .failed(let error):
            statusLine.title = "Server failed: \(error.localizedDescription)"
            NSLog("Listener failed on \(config.host):\(config.port): \(error)")
        case .waiting(let error):
            statusLine.title = "Waiting: \(error.localizedDescription)"
        default:
            break
        }
    }

    // MARK: - Routing

    private func handle(_ request: HTTPRequest, respond: @escaping (HTTPResponse) -> Void) {
        switch request.path {
        case "/health":
            notifier.deliverySettings { settings in
                respond(.ok(["status": "ok", "notifications": settings]))
            }
        case "/notify":
            guard request.method == "POST" else { return respond(.error(405, "use POST")) }
            if let token = config.token, request.headers["authorization"] != "Bearer \(token)" {
                return respond(.error(401, "missing or invalid bearer token"))
            }
            switch Self.message(from: request) {
            case .failure(let error):
                respond(.error(400, error.reason))
            case .success(let message):
                notifier.post(message) { error in
                    respond(error.map { .error(503, $0) } ?? .ok())
                }
            }
        default:
            respond(.error(404, "not found; POST to /notify"))
        }
    }

    private struct BadRequest: Error { let reason: String }

    /// Accepts a JSON object ({"title", "subtitle", "message", "sound"}) or a plain-text body
    /// used as the message. `title` and `subtitle` may also be passed as query parameters.
    private static func message(from request: HTTPRequest) -> Result<NotificationMessage, BadRequest> {
        var title = request.query["title"]
        var subtitle = request.query["subtitle"]
        var text: String?
        var sound = true

        if (request.headers["content-type"] ?? "").lowercased().contains("json") {
            guard let object = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any] else {
                return .failure(BadRequest(reason: "body must be a JSON object"))
            }
            title = object["title"] as? String ?? title
            subtitle = object["subtitle"] as? String ?? subtitle
            text = object["message"] as? String ?? object["body"] as? String
            sound = object["sound"] as? Bool ?? true
        } else {
            guard let body = String(data: request.body, encoding: .utf8) else {
                return .failure(BadRequest(reason: "body must be UTF-8 text"))
            }
            text = body
        }

        guard let message = text?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty else {
            return .failure(BadRequest(reason: "a non-empty message is required"))
        }
        return .success(NotificationMessage(
            title: title ?? "NotifyBridge",
            subtitle: subtitle,
            message: message,
            sound: sound
        ))
    }

    // MARK: - Menu actions

    @objc private func sendTest() {
        let message = NotificationMessage(title: "NotifyBridge", message: "Test notification — it works.")
        notifier.post(message) { error in
            guard let error else { return }
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Could not send notification"
                alert.informativeText = error
                NSApp.activate(ignoringOtherApps: true)
                alert.runModal()
            }
        }
    }

    @objc private func copyCurl() {
        let auth = config.token.map { " -H 'Authorization: Bearer \($0)'" } ?? ""
        let command = "curl -X POST \(config.baseURL)/notify\(auth) -H 'Content-Type: application/json' "
            + "-d '{\"title\": \"Hello\", \"message\": \"Sent from curl\"}'"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
