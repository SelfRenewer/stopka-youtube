// Стопка: окно приложения-контейнера.
// build.sh подставляет __EXTENSION_BUNDLE_ID__ и __PRIVACY_URL__.

import Cocoa
import SafariServices
import WebKit

let extensionBundleIdentifier = "__EXTENSION_BUNDLE_ID__"
let privacyPolicyURL = URL(string: "__PRIVACY_URL__")!

class ViewController: NSViewController, WKNavigationDelegate, WKScriptMessageHandler {

    @IBOutlet var webView: WKWebView!

    override func viewDidLoad() {
        super.viewDidLoad()
        self.webView.navigationDelegate = self
        self.webView.configuration.userContentController.add(self, name: "controller")
        self.webView.loadFileURL(Bundle.main.url(forResource: "Main", withExtension: "html")!,
                                 allowingReadAccessTo: Bundle.main.resourceURL!)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        SFSafariExtensionManager.getStateOfSafariExtension(withIdentifier: extensionBundleIdentifier) { state, error in
            guard let state = state, error == nil else { return }
            DispatchQueue.main.async {
                webView.evaluateJavaScript("show(\(state.isEnabled))")
            }
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.body as? String {
        case "open-preferences":
            SFSafariApplication.showPreferencesForExtension(withIdentifier: extensionBundleIdentifier) { _ in
                DispatchQueue.main.async { NSApplication.shared.terminate(nil) }
            }
        case "open-privacy":
            NSWorkspace.shared.open(privacyPolicyURL)
        default:
            break
        }
    }
}
