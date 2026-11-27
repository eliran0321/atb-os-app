import UIKit
import WebKit
import QuickLook
import AuthenticationServices
import LocalAuthentication
import Security
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
        // The sign-in key of this device, for the page to use (BiometricKeyPlugin below).
        bridge?.registerPluginInstance(BiometricKeyPlugin())
        // A file of the system (an Excel export, a PDF), shown by the device (FileViewerPlugin below).
        bridge?.registerPluginInstance(FileViewerPlugin())
        // A sign-in page of another service, in the sheet of the system (WebAuthPlugin below).
        bridge?.registerPluginInstance(WebAuthPlugin())

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

/// The sign-in key of this device. The private key is created inside the Secure Enclave
/// and never leaves it; it signs only after the system has matched the face or the
/// fingerprint that are enrolled right now. The page asks for a signature over a login
/// challenge from the server, and the server checks it against the public key it stored
/// when the user turned this on. No password and no token are kept on the device.
///
/// The plugin knows nothing about the login itself: it creates a key, hands out the
/// public half, and signs bytes. Everything else lives in the web app, where it can be
/// tested and fixed without shipping a new build.
@objc(BiometricKeyPlugin)
public class BiometricKeyPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "BiometricKeyPlugin"
    public let jsName = "BiometricKey"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "status", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "create", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "sign", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "remove", returnType: CAPPluginReturnPromise)
    ]

    private let tag = Data("il.co.all4fun.atb.sign-in-key".utf8)

    private func query(_ extra: [String: Any] = [:]) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom
        ]
        for (name, value) in extra { query[name] = value }
        return query
    }

    /// Finding the key never asks for the face; only signing with it does.
    private func storedKey(using context: LAContext? = nil) -> SecKey? {
        var extra: [String: Any] = [kSecReturnRef as String: true]
        if let context = context { extra[kSecUseAuthenticationContext as String] = context }
        var item: CFTypeRef?
        guard SecItemCopyMatching(query(extra) as CFDictionary, &item) == errSecSuccess,
              let found = item else { return nil }
        // swiftlint:disable:next force_cast
        return (found as! SecKey)
    }

    /// The public half as the uncompressed point: 04, X, Y.
    private func publicKey(of key: SecKey) -> String? {
        guard let publicKey = SecKeyCopyPublicKey(key),
              let data = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else { return nil }
        return data.base64EncodedString()
    }

    /// Whether the device can do this at all, and the key it already holds, if any.
    @objc func status(_ call: CAPPluginCall) {
        var result: [String: Any] = [
            "available": LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        ]
        if let key = storedKey(), let publicKey = publicKey(of: key) {
            result["publicKey"] = publicKey
        }
        call.resolve(result)
    }

    /// A new key replaces the previous one. biometryCurrentSet: enrolling another face or
    /// finger later makes the key unusable, and the user turns sign-in on again.
    @objc func create(_ call: CAPPluginCall) {
        SecItemDelete(query() as CFDictionary)
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
            [.privateKeyUsage, .biometryCurrentSet],
            nil
        ) else {
            call.reject("access control", "FAILED")
            return
        }
        let privateKey: [String: Any] = [
            kSecAttrIsPermanent as String: true,
            kSecAttrApplicationTag as String: tag,
            kSecAttrAccessControl as String: access
        ]
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs as String: privateKey
        ]
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, nil),
              let publicKey = publicKey(of: key) else {
            call.reject("key generation", "FAILED")
            return
        }
        call.resolve(["publicKey": publicKey])
    }

    /// Signs the given bytes (ECDSA over SHA-256, DER). This is where the system shows
    /// Face ID or Touch ID; it blocks, so it runs off the main thread.
    @objc func sign(_ call: CAPPluginCall) {
        guard let text = call.getString("data"), let data = Data(base64Encoded: text) else {
            call.reject("data", "FAILED")
            return
        }
        let context = LAContext()
        context.localizedReason = call.getString("reason") ?? ""
        guard let key = storedKey(using: context) else {
            call.reject("no key", "NO_KEY")
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            var failure: Unmanaged<CFError>?
            guard let signature = SecKeyCreateSignature(
                key, .ecdsaSignatureMessageX962SHA256, data as CFData, &failure
            ) as Data? else {
                let code = failure.map { CFErrorGetCode($0.takeRetainedValue()) } ?? 0
                let canceled = code == Int(errSecUserCanceled)
                    || code == LAError.Code.userCancel.rawValue
                    || code == LAError.Code.appCancel.rawValue
                    || code == LAError.Code.systemCancel.rawValue
                call.reject("not signed", canceled ? "CANCELED" : "FAILED")
                return
            }
            call.resolve(["signature": signature.base64EncodedString()])
        }
    }

    @objc func remove(_ call: CAPPluginCall) {
        SecItemDelete(query() as CFDictionary)
        call.resolve()
    }
}

/// A file of the system, shown on the device: an Excel export, a quote as a PDF. A web
/// view has no downloads of its own, so a tap on such a file led nowhere. The page
/// fetches the file with the session it already has and hands the bytes over; the
/// system preview shows it, and its share button is where saving to Files, printing
/// and sending live.
///
/// As with the sign-in key, the plugin knows nothing about the file: it gets a name and
/// bytes. Which taps lead here is decided in the web app, where it can be tested and
/// fixed without shipping a new build.
@objc(FileViewerPlugin)
public class FileViewerPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "FileViewerPlugin"
    public let jsName = "FileViewer"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "open", returnType: CAPPluginReturnPromise)
    ]

    private let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("files", isDirectory: true)
    private var shown: URL?

    /// The files of the previous run go when the app starts. Within a run they stay:
    /// a share that is still copying a file must not lose it.
    override public func load() {
        try? FileManager.default.removeItem(at: folder)
    }

    @objc func open(_ call: CAPPluginCall) {
        guard let text = call.getString("data"), let data = Data(base64Encoded: text) else {
            call.reject("data", "FAILED")
            return
        }
        // A name, never a path: nothing the page sends can point outside the folder.
        var name = (call.getString("name") ?? "").replacingOccurrences(of: "/", with: "-")
        if name.isEmpty || name == "." || name == ".." { name = "file" }
        // A folder for each file, so that the name on screen is exactly the name the
        // page gave, also when the same export is opened twice.
        let url = folder
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try data.write(to: url)
        } catch {
            call.reject(error.localizedDescription, "FAILED")
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self = self, var top = self.bridge?.viewController else {
                call.reject("no screen", "FAILED")
                return
            }
            while let above = top.presentedViewController, !above.isBeingDismissed {
                top = above
            }
            self.shown = url
            let preview = QLPreviewController()
            preview.dataSource = self
            top.present(preview, animated: true) { call.resolve() }
        }
    }
}

// The conformance lives in an extension, as with the window opener above: only these
// two methods run on the main actor, and open(_:) stays callable from the bridge queue.
extension FileViewerPlugin: QLPreviewControllerDataSource {
    public func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        return shown == nil ? 0 : 1
    }

    public func previewController(_ controller: QLPreviewController,
                                  previewItemAt index: Int) -> QLPreviewItem {
        return (shown ?? folder) as NSURL
    }
}

/// The sign-in page of another service, shown by the device above the app: Google's
/// consent screen when a user connects a calendar. Google refuses to show it inside a
/// web view, and a jump to Safari leaves the session of the system behind. The sheet of
/// the system is a real browser, with the Google accounts that are already signed in on
/// the phone, and it hands the answer back to the page that asked.
///
/// As with the other two, the plugin knows nothing about Google or calendars: it opens
/// an address and returns the address the visit ended on. Which address, and what to do
/// with the answer, is decided in the web app.
@objc(WebAuthPlugin)
public class WebAuthPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "WebAuthPlugin"
    public let jsName = "WebAuth"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "start", returnType: CAPPluginReturnPromise)
    ]

    /// Held while the sheet is up: the system closes a sheet that nothing holds.
    private var session: ASWebAuthenticationSession?
    private var round = 0

    /// `url`: the page to open, https only. `scheme`: the visit ends when the page is
    /// sent to an address of this scheme, and that address is the answer.
    @objc func start(_ call: CAPPluginCall) {
        guard let text = call.getString("url"), let url = URL(string: text),
              url.scheme == "https",
              let scheme = call.getString("scheme"), !scheme.isEmpty else {
            call.reject("url", "FAILED")
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                call.reject("no screen", "FAILED")
                return
            }
            // One sheet at a time: a new one closes the previous, which answers CANCELED.
            self.session?.cancel()
            self.round += 1
            let round = self.round
            let session = ASWebAuthenticationSession(
                url: url, callbackURLScheme: scheme
            ) { [weak self] back, error in
                DispatchQueue.main.async {
                    if let self = self, self.round == round { self.session = nil }
                }
                if let back = back {
                    call.resolve(["url": back.absoluteString])
                    return
                }
                // The number tells a closed sheet (1) from a sheet that could not open.
                let canceled = (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin
                let number = (error as NSError?)?.code ?? 0
                call.reject("not finished \(number)", canceled ? "CANCELED" : "FAILED")
            }
            session.presentationContextProvider = self
            self.session = session
            if !session.start() {
                self.session = nil
                call.reject("not started", "FAILED")
            }
        }
    }
}

// The conformance lives in an extension, as with the two above: only this method runs
// on the main actor, and start(_:) stays callable from the bridge queue.
extension WebAuthPlugin: ASWebAuthenticationPresentationContextProviding {
    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return bridge?.viewController?.view.window ?? ASPresentationAnchor()
    }
}
