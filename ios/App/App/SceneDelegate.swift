import UIKit
import WebKit
import Capacitor

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        window = UIWindow(windowScene: windowScene)
        window?.rootViewController = MainViewController()
        window?.makeKeyAndVisible()

        SceneDelegateProxy.shared.scene(scene, willConnectTo: session, options: connectionOptions)
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        SceneDelegateProxy.shared.scene(scene, openURLContexts: URLContexts)
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        SceneDelegateProxy.shared.scene(scene, continue: userActivity)
    }
}

/// The only screen of the app: the Capacitor web view around the live system, plus the
/// things a browser gives for free and a bare web view does not.
class MainViewController: CAPBridgeViewController {
    /// The ink of the top bar of the system (#2a1247).
    private let ink = UIColor(red: 42 / 255, green: 18 / 255, blue: 71 / 255, alpha: 1)
    private var windowOpener: SameAppWindowOpener?

    override func capacitorDidLoad() {
        super.capacitorDidLoad()
        guard let webView = webView else { return }

        // There is no back button in the shell: an edge swipe goes back, as in the browser.
        webView.allowsBackForwardNavigationGestures = true

        // A link of the system that opens in a new tab loads here, where the session is.
        // Capacitor alone would send every new tab to Safari, signed out.
        if let original = webView.uiDelegate {
            let opener = SameAppWindowOpener(original: original, appHost: bridge?.config.serverURL.host)
            windowOpener = opener
            webView.uiDelegate = opener
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // An ink strip behind the clock and the battery. The status bar text is white on
        // every screen, and some pages of the system are light: without the strip the
        // clock would disappear on them, and scrolled content would show through it.
        let strip = UIView()
        strip.backgroundColor = ink
        strip.isUserInteractionEnabled = false
        strip.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(strip)
        NSLayoutConstraint.activate([
            strip.topAnchor.constraint(equalTo: view.topAnchor),
            strip.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            strip.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            strip.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor)
        ])
    }
}

/// Stands in front of the UI delegate of Capacitor and changes one answer: what happens
/// when a page asks for a new window. Everything else is forwarded to Capacitor untouched.
final class SameAppWindowOpener: NSObject {
    private weak var original: WKUIDelegate?
    private let appHost: String?

    init(original: WKUIDelegate, appHost: String?) {
        self.original = original
        self.appHost = appHost
        super.init()
    }

    override func responds(to aSelector: Selector!) -> Bool {
        if super.responds(to: aSelector) { return true }
        return original?.responds(to: aSelector) ?? false
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        return original
    }
}

// The conformance lives in an extension on purpose: only this method runs on the main
// actor, and the two forwarding overrides above keep the isolation of NSObject.
extension SameAppWindowOpener: WKUIDelegate {
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let url = navigationAction.request.url else { return nil }
        if let host = url.host, host == appHost {
            webView.load(navigationAction.request)
        } else {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
        return nil
    }
}
