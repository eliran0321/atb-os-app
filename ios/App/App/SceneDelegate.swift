import UIKit
import WebKit
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
