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

    // The curtain over the first seconds (LaunchCurtain below), and when it goes.
    private var curtain: LaunchCurtain?
    private var curtainSince: CFTimeInterval = 0
    private var pageBegan = false
    private var pageLoading: NSKeyValueObservation?
    /// The message with which the first page says that it has drawn itself.
    private static let drawnMessage = "atbPageDrawn"

    override func capacitorDidLoad() {
        super.capacitorDidLoad()
        // The sign-in key of this device, for the page to use (BiometricKeyPlugin below).
        bridge?.registerPluginInstance(BiometricKeyPlugin())
        // A file of the system (an Excel export, a PDF), shown by the device (FileViewerPlugin below).
        bridge?.registerPluginInstance(FileViewerPlugin())
        // A sign-in page of another service, in the sheet of the system (WebAuthPlugin below).
        bridge?.registerPluginInstance(WebAuthPlugin())

        guard let webView = webView else { return }

        // The first page says when it is there to look at: its content is in place, its
        // images are decoded, what it brings in when it opens (a rise, a fade) has ended,
        // and two frames have been drawn since. Each of these was missing once, and each
        // time the curtain left a hole behind it: a blank page, a page without its logo,
        // a page caught in the middle of its entrance. It does not wait for the end of
        // the whole load: on a slow network the scripts of a page keep coming long after
        // it is on screen, and the curtain stood in front of a finished page.
        // The curtain over the launch goes then (coverLaunch below). Once it is gone
        // nobody listens, and the script finds no listener and does nothing.
        let drawn = """
        (function () {
          var handlers = window.webkit && window.webkit.messageHandlers;
          var listener = handlers && handlers.\(Self.drawnMessage);
          if (!listener) return;
          function within(ms, promise) {
            return Promise.race([promise, new Promise(function (resolve) { setTimeout(resolve, ms); })]);
          }
          function images() {
            var now = Array.prototype.filter.call(document.images, function (img) {
              return img.loading !== 'lazy';
            });
            return Promise.all(now.map(function (img) {
              return img.decode ? img.decode().catch(function () {}) : null;
            }));
          }
          function entrance() {
            var all = document.getAnimations ? document.getAnimations() : [];
            var entering = all.filter(function (a) {
              var timing = a.effect && a.effect.getComputedTiming ? a.effect.getComputedTiming() : null;
              return timing && isFinite(timing.endTime) && a.playState !== 'finished';
            });
            return Promise.all(entering.map(function (a) {
              return a.finished.catch(function () {});
            }));
          }
          function frames() {
            return new Promise(function (resolve) {
              requestAnimationFrame(function () { requestAnimationFrame(resolve); });
            });
          }
          function settle() {
            within(4000, images())
              .then(function () { return within(3000, entrance()); })
              .then(frames)
              .then(function () { listener.postMessage(location.pathname); });
          }
          if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', settle, { once: true });
          } else {
            settle();
          }
        })();
        """
        let scripts = webView.configuration.userContentController
        scripts.addUserScript(WKUserScript(source: drawn, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        scripts.add(PageListener { [weak self] path in self?.firstPageDrawn(path) }, name: Self.drawnMessage)

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

        coverLaunch()
    }

    /// The web view starts empty, and the first page comes over the network. Until it
    /// is on screen the curtain stands in front of the web view.
    private func coverLaunch() {
        guard let webView = webView else { return }
        let curtain = LaunchCurtain(frame: view.bounds)
        curtain.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(curtain)
        self.curtain = curtain
        curtainSince = CACurrentMediaTime()

        // The load has already begun by now (super.viewDidLoad starts it), hence .initial.
        pageLoading = webView.observe(\.isLoading, options: [.initial, .new]) { [weak self] webView, _ in
            let loading = webView.isLoading
            DispatchQueue.main.async { self?.pageIsLoading(loading) }
        }
        // Whatever happens to the page, the curtain does not stay for ever. But it does
        // stay through a slow network: when it went after 12 seconds, and then after 30,
        // a page that took longer left the blank screen in between. A load that gets
        // nowhere is given up by the web view after a minute, and then the offline page
        // reports like any other; this is only for what nobody thought of.
        DispatchQueue.main.asyncAfter(deadline: .now() + 75) { [weak self] in
            self?.uncover()
        }
    }

    /// The page is all there (the script in capacitorDidLoad), and the curtain can go.
    private func firstPageDrawn(_ path: String) {
        liftCurtain(after: 0.1)
    }

    /// The end of the load is the second sign, for a page that did not report. It comes
    /// before the page is on screen, so it is only a net: a few seconds later, and only
    /// if the web view is still at rest then. A failed load is followed at once by the
    /// offline page, and a redirect by the next page, and each of them reports again.
    private func pageIsLoading(_ loading: Bool) {
        if loading {
            pageBegan = true
            return
        }
        guard pageBegan, curtain != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self = self, self.webView?.isLoading == false else { return }
            self.liftCurtain(after: 0)
        }
    }

    /// Not before the opening had time to play, also when the page is already there.
    /// `-curtainHold <seconds>` at launch keeps the curtain longer, to look at it in the
    /// simulator (.github/workflows/ios-check.yml). Nobody else passes it.
    private func liftCurtain(after settle: CFTimeInterval) {
        guard curtain != nil else { return }
        let least = max(1.0, UserDefaults.standard.double(forKey: "curtainHold"))
        let left = least - (CACurrentMediaTime() - curtainSince)
        DispatchQueue.main.asyncAfter(deadline: .now() + max(settle, left)) { [weak self] in
            self?.uncover()
        }
    }

    private func uncover() {
        guard let curtain = curtain else { return }
        self.curtain = nil
        pageLoading = nil
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: Self.drawnMessage)
        curtain.lift()
    }
}

/// Hands a message of the page to a closure. The web view holds its listeners strongly,
/// so the screen itself is not one.
final class PageListener: NSObject, WKScriptMessageHandler {
    private let hear: (String) -> Void

    init(_ hear: @escaping (String) -> Void) {
        self.hear = hear
        super.init()
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        hear(message.body as? String ?? "")
    }
}

/// The first seconds of the app. The web view starts empty, and until the first page of
/// the system arrived the app was a blank ink screen. The curtain covers that time: the
/// logo starts exactly where the launch screen of iOS drew it and rises, the elephant
/// of ATB comes up under it, and a bowling ball rolls by for as long as the page takes.
///
/// It is the opening page of the system (/start) without its two tiles, measured the
/// way the page measures itself, so for someone who is not signed in the tiles simply
/// appear under the elephant. Someone who is signed in goes from it to the home screen.
final class LaunchCurtain: UIView {
    /// The logo on the launch image: 720 px on a 2732 px square that fills the screen
    /// (scripts/make-assets.mjs).
    private static let launchLogoShare: CGFloat = 720.0 / 2732.0
    private static let ink = UIColor(red: 42 / 255, green: 18 / 255, blue: 71 / 255, alpha: 1)
    /// The faint balls at the edges of the opening page: the middle in percent of the
    /// page, the size in percent of the short side of the screen, and the turn of the holes.
    private static let edgeBalls: [(x: CGFloat, y: CGFloat, size: CGFloat, turn: CGFloat)] = [
        (-5, 31, 36, 20), (103, 15, 24, 140), (99, 60, 13, 260)
    ]

    /// What the page draws behind everything, cut at the edges of the page as there.
    private let backdrop = CALayer()
    private let glowTop = CAGradientLayer()
    private let glowBottom = CAGradientLayer()
    private let balls = LaunchCurtain.edgeBalls.map { _ in BowlingBall(ink: LaunchCurtain.ink.cgColor) }
    private let logo = UIImageView(image: UIImage(named: "Logo"))
    /// The elephant and the light behind it: they come up together.
    private let stage = UIView()
    private let spotlight = CAGradientLayer()
    private let elephant = UIImageView(image: UIImage(named: "Elephant"))
    private let roller = BowlingBall(ink: LaunchCurtain.ink.cgColor)

    private var playing = false
    /// Where the rolling ball starts and ends, and how far it turns on the way.
    private var roll: (from: CGFloat, to: CGFloat, turn: CGFloat) = (0, 0, 0)

    private static func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
        return UIColor(red: red / 255, green: green / 255, blue: blue / 255, alpha: alpha).cgColor
    }

    /// A round light: the colors run from the middle of the layer to its edge.
    private static func light(_ layer: CAGradientLayer, _ colors: [CGColor], _ stops: [NSNumber]) {
        layer.type = .radial
        layer.startPoint = CGPoint(x: 0.5, y: 0.5)
        layer.endPoint = CGPoint(x: 1, y: 1)
        layer.colors = colors
        layer.locations = stops
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Self.ink
        clipsToBounds = true

        // The two purple lights in the corners of the page, and its faint balls.
        Self.light(glowTop, [Self.color(139, 92, 246, 0.42), Self.color(139, 92, 246, 0)], [0, 0.7])
        Self.light(glowBottom, [Self.color(124, 58, 237, 0.38), Self.color(124, 58, 237, 0)], [0, 0.7])
        backdrop.masksToBounds = true
        backdrop.addSublayer(glowTop)
        backdrop.addSublayer(glowBottom)
        for (ball, spec) in zip(balls, Self.edgeBalls) {
            ball.layer.opacity = 0.13
            ball.holes.setAffineTransform(CGAffineTransform(rotationAngle: spec.turn * .pi / 180))
            backdrop.addSublayer(ball.layer)
        }
        layer.addSublayer(backdrop)

        logo.contentMode = .scaleAspectFit
        addSubview(logo)

        Self.light(
            spotlight,
            [Self.color(196, 181, 253, 0.5), Self.color(139, 92, 246, 0.42),
             Self.color(109, 40, 217, 0.16), Self.color(109, 40, 217, 0)],
            [0, 0.38, 0.68, 1]
        )
        stage.layer.addSublayer(spotlight)
        elephant.contentMode = .scaleAspectFit
        // It breathes from its feet, which stay on the ground.
        elephant.layer.anchorPoint = CGPoint(x: 0.5, y: 1)
        elephant.layer.shadowColor = Self.color(10, 4, 20)
        elephant.layer.shadowOpacity = 0.6
        elephant.layer.shadowRadius = 9
        elephant.layer.shadowOffset = CGSize(width: 0, height: 16)
        stage.addSubview(elephant)
        addSubview(stage)

        roller.layer.shadowColor = Self.color(10, 4, 20)
        roller.layer.shadowOpacity = 0.5
        roller.layer.shadowRadius = 7
        roller.layer.shadowOffset = CGSize(width: 0, height: 6)
        layer.addSublayer(roller.layer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        setNeedsLayout()
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        setNeedsLayout()
    }

    /// The numbers are the numbers of the opening page (src/app/start/page.tsx in the
    /// system), measured the way the web view measures them: the page is the screen
    /// without the safe areas, "vw" and "vh" are the whole screen, and one "rem" is
    /// 15 points on a phone and 16 on anything wider (globals.css).
    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        let height = bounds.height
        guard width > 0, height > 0 else { return }
        let safe = safeAreaInsets
        let page = CGRect(x: safe.left, y: safe.top,
                          width: width - safe.left - safe.right,
                          height: height - safe.top - safe.bottom)
        // A wide screen has everything together in the middle; a tablet standing up has
        // the layout of a phone with larger pieces.
        let wide = page.width >= 1024
        let tablet = page.width >= 640 && !wide
        let rem: CGFloat = page.width < 640 ? 15 : 16
        // A phone on its side has no room for the elephant.
        let low = page.height <= 520

        let top = max(2 * rem, 0.06 * height)
        let foot = 1.75 * rem
        // A tile is as tall as what is in it: the badge, the word (28 points), the gaps.
        let tiles = tablet ? max(11 * rem, 9.5 * rem + 28) : max(9 * rem, 7.75 * rem + 28)
        // How far the elephant sits into the tiles.
        let sink = (tablet ? 2.5 : 2) * rem
        let elephantWidth = low ? 0
            : (tablet ? min(0.58 * width, 0.40 * height, 28 * rem) : min(0.76 * width, 0.38 * height, 21 * rem))
        let elephantHeight = elephantWidth * 841 / 720
        let elephantRoom = max(0, elephantHeight - sink)
        let logoHeight = tablet ? min(max(7 * rem, 0.16 * height), 12 * rem)
            : min(max(5.5 * rem, 0.17 * height), 9 * rem)
        let logoWidth = logoHeight * 1816 / 1159
        let lightSize = tablet ? min(0.96 * width, 0.58 * height, 44 * rem)
            : min(1.08 * width, 0.54 * height, 30 * rem)

        let tilesTop: CGFloat
        let logoMiddle: CGFloat
        if wide {
            let gap = 3 * rem
            let block = logoHeight + gap + elephantRoom + tiles
            let blockTop = page.minY + top + (page.height - top - foot - block) / 2
            logoMiddle = blockTop + logoHeight / 2
            tilesTop = blockTop + logoHeight + gap + elephantRoom
        } else {
            tilesTop = page.maxY - foot - tiles
            logoMiddle = (page.minY + top + tilesTop - elephantRoom) / 2
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backdrop.frame = page
        glowTop.frame = CGRect(x: page.width - 34 * rem, y: -26 * rem, width: 68 * rem, height: 52 * rem)
        glowBottom.frame = CGRect(x: -30 * rem, y: page.height - 24 * rem, width: 60 * rem, height: 48 * rem)
        for (ball, spec) in zip(balls, Self.edgeBalls) {
            ball.resize(spec.size / 100 * min(width, height))
            ball.layer.position = CGPoint(x: spec.x / 100 * page.width, y: spec.y / 100 * page.height)
        }

        logo.bounds = CGRect(x: 0, y: 0, width: logoWidth, height: logoHeight)
        logo.center = CGPoint(x: page.midX, y: logoMiddle)

        stage.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        stage.center = CGPoint(x: width / 2, y: height / 2)
        stage.isHidden = low
        elephant.bounds = CGRect(x: 0, y: 0, width: elephantWidth, height: elephantHeight)
        elephant.center = CGPoint(x: page.midX, y: tilesTop + sink)
        spotlight.frame = CGRect(x: page.midX - lightSize / 2,
                                 y: tilesTop - 0.06 * elephantRoom - lightSize,
                                 width: lightSize, height: lightSize)

        // The ball rolls where the two tiles of the page will be. Between two passes it
        // waits out of sight, on the right.
        let rollerSize: CGFloat = page.width < 640 ? 48 : 64
        roller.layer.isHidden = low
        roller.resize(rollerSize)
        roller.layer.position = CGPoint(x: width + rollerSize, y: tilesTop + tiles / 2)
        CATransaction.commit()

        roll = (width + rollerSize, -rollerSize, -(width + 2 * rollerSize) / (rollerSize / 2))
        if window != nil, !playing {
            playing = true
            play()
        }
    }

    /// The first frame is the launch screen of iOS: only the logo, in the middle, at
    /// its size there. From it the logo rises to its place and the rest comes in.
    private func play() {
        let launchWidth = Self.launchLogoShare * max(bounds.width, bounds.height)
        let grow = launchWidth / max(logo.bounds.width, 1)
        logo.transform = CGAffineTransform(translationX: bounds.midX - logo.center.x, y: bounds.midY - logo.center.y)
            .scaledBy(x: grow, y: grow)
        stage.alpha = 0
        stage.transform = CGAffineTransform(translationX: 0, y: 14).scaledBy(x: 0.97, y: 0.97)

        // `-curtainWait <seconds>` at launch holds the first frame, to look at it in the
        // simulator (.github/workflows/ios-check.yml). Nobody else passes it.
        let wait = max(0, UserDefaults.standard.double(forKey: "curtainWait"))

        // The curve of the opening page (start-rise).
        let rise = UICubicTimingParameters(
            controlPoint1: CGPoint(x: 0.23, y: 1), controlPoint2: CGPoint(x: 0.32, y: 1)
        )
        let logoUp = UIViewPropertyAnimator(duration: 0.62, timingParameters: rise)
        logoUp.addAnimations { self.logo.transform = .identity }
        logoUp.startAnimation(afterDelay: wait + 0.12)
        let stageUp = UIViewPropertyAnimator(duration: 0.56, timingParameters: rise)
        stageUp.addAnimations {
            self.stage.alpha = 1
            self.stage.transform = .identity
        }
        stageUp.startAnimation(afterDelay: wait + 0.26)

        let now = layer.convertTime(CACurrentMediaTime(), from: nil) + wait
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.7
        fade.beginTime = now + 0.1
        fade.fillMode = .backwards
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        backdrop.add(fade, forKey: "in")

        // With "Reduce Motion" on, things come in and then stand still.
        if UIAccessibility.isReduceMotionEnabled { return }

        // start-breathe of the opening page: 4.5 seconds for a breath in and out.
        let breath = CABasicAnimation(keyPath: "transform.scale")
        breath.fromValue = 1
        breath.toValue = 1.025
        breath.duration = 2.25
        breath.autoreverses = true
        breath.repeatCount = .infinity
        breath.beginTime = now + 0.9
        breath.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        elephant.layer.add(breath, forKey: "breath")

        // One pass from right to left, turning as far as a rolling ball turns, then a
        // short wait out of sight.
        let pass: CFTimeInterval = 1.7
        let ease = CAMediaTimingFunction(controlPoints: 0.45, 0.05, 0.55, 0.95)
        let move = CABasicAnimation(keyPath: "position.x")
        move.fromValue = roll.from
        move.toValue = roll.to
        let turn = CABasicAnimation(keyPath: "transform.rotation.z")
        turn.fromValue = 0
        turn.toValue = roll.turn
        let steps: [(CALayer, CABasicAnimation)] = [(roller.layer, move), (roller.holes, turn)]
        for (target, step) in steps {
            step.duration = pass
            step.timingFunction = ease
            let loop = CAAnimationGroup()
            loop.animations = [step]
            loop.duration = pass + 0.6
            loop.repeatCount = .infinity
            loop.beginTime = now + 0.85
            target.add(loop, forKey: "roll")
        }
    }

    /// The page is on: the curtain fades and leaves.
    func lift() {
        isUserInteractionEnabled = false
        UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseOut, .beginFromCurrentState], animations: {
            self.alpha = 0
        }, completion: { _ in
            self.removeFromSuperview()
        })
    }
}

/// The bowling ball of the system (clock/bowling-balls.tsx): a glossy purple ball with
/// three holes and a shine. The holes are a layer of their own, so that they can turn
/// while the shine stays on top.
final class BowlingBall {
    let layer = CALayer()
    let holes = CALayer()
    private let body = CAGradientLayer()
    private let spots = [CALayer(), CALayer(), CALayer()]
    private let shine = CAShapeLayer()

    init(ink: CGColor) {
        body.type = .radial
        body.startPoint = CGPoint(x: 0.34, y: 0.28)
        body.endPoint = CGPoint(x: 1.12, y: 1.06)
        body.colors = [
            UIColor(red: 237 / 255, green: 233 / 255, blue: 254 / 255, alpha: 1).cgColor,
            UIColor(red: 167 / 255, green: 139 / 255, blue: 250 / 255, alpha: 1).cgColor,
            UIColor(red: 124 / 255, green: 58 / 255, blue: 237 / 255, alpha: 1).cgColor,
            UIColor(red: 59 / 255, green: 7 / 255, blue: 100 / 255, alpha: 1).cgColor
        ]
        body.locations = [0, 0.3, 0.7, 1]
        body.masksToBounds = true
        layer.addSublayer(body)
        for spot in spots {
            spot.backgroundColor = ink
            holes.addSublayer(spot)
        }
        layer.addSublayer(holes)
        shine.fillColor = UIColor(white: 1, alpha: 0.4).cgColor
        layer.addSublayer(shine)
    }

    /// The drawing is on a 100 by 100 square: the body is a circle of radius 48, the
    /// holes are at (41, 32), (59, 32) and (50, 50), the shine at (32, 24).
    func resize(_ size: CGFloat) {
        let unit = size / 100
        layer.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        body.frame = CGRect(x: 2 * unit, y: 2 * unit, width: 96 * unit, height: 96 * unit)
        body.cornerRadius = 48 * unit
        holes.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        holes.position = CGPoint(x: size / 2, y: size / 2)
        let places: [(x: CGFloat, y: CGFloat, radius: CGFloat)] = [(41, 32, 5.5), (59, 32, 5.5), (50, 50, 6.8)]
        for (spot, place) in zip(spots, places) {
            let radius = place.radius * unit
            spot.bounds = CGRect(x: 0, y: 0, width: 2 * radius, height: 2 * radius)
            spot.position = CGPoint(x: place.x * unit, y: place.y * unit)
            spot.cornerRadius = radius
        }
        shine.bounds = CGRect(x: 0, y: 0, width: 26 * unit, height: 14 * unit)
        shine.position = CGPoint(x: 32 * unit, y: 24 * unit)
        shine.path = UIBezierPath(ovalIn: shine.bounds).cgPath
        shine.setAffineTransform(CGAffineTransform(rotationAngle: -32 * .pi / 180))
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
