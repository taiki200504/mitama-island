import AppKit
import WebKit
import OpenIslandCore

@MainActor
final class MitamaOSWindowController: NSObject, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate {
    private var window: NSWindow?
    private var webView: WKWebView?
    private var baseURL = MitamaOSURL.defaultURL

    func show(path: String = "/") {
        baseURL = MitamaOSURL.baseURL(UserDefaults.standard.string(forKey: "mitamaOS.url"))
        if window == nil {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .default()
            let webView = WKWebView(frame: .zero, configuration: configuration)
            webView.navigationDelegate = self
            webView.uiDelegate = self
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false
            )
            window.title = "mitama OS"
            window.minSize = NSSize(width: 420, height: 600)
            window.isReleasedWhenClosed = false
            window.contentView = webView
            window.delegate = self
            window.center()
            window.setFrameAutosaveName("mitamaOS.window")
            self.window = window
            self.webView = webView
        }
        let destination = MitamaOSURL.url(base: baseURL, path: path)
        if webView?.url != destination {
            webView?.load(URLRequest(url: destination))
        }
        window?.deminiaturize(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        guard MitamaOSURL.isInternal(url, base: baseURL) else {
            // Never dispatch executable URLs (javascript:, data:, file:) to the OS.
            if ["https", "http", "mailto", "tel"].contains(url.scheme?.lowercased() ?? "") {
                NSWorkspace.shared.open(url)
            }
            decisionHandler(.cancel)
            return
        }
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
            decisionHandler(.cancel)
        } else {
            decisionHandler(.allow)
        }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // Navigation policy routes target=_blank into this web view.
        nil
    }
}
