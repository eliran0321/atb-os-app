# ההתאמות של פרויקט האייפון אחרי "cap add ios": חתימה, הרשאות, שפה וצבעים.
# כל החלפה חלה פעם אחת, והרצה חוזרת לא משנה כלום.
# הרצה מתיקיית השורש: python scripts/configure-ios.py
import io

TEAM = '8BTVG2Q5P7'
PROFILE = 'ATB-OS App Store'
T4 = '\t\t\t\t'


def load(path):
    return io.open(path, encoding='utf-8', newline='').read()


def save(path, text):
    io.open(path, 'w', encoding='utf-8', newline='').write(text)


def once(text, old, new, start=0):
    i = text.index(old, start)
    return text[:i] + new + text[i + len(old):]


p = 'ios/App/App.xcodeproj/project.pbxproj'
s = load(p)
if 'PROVISIONING_PROFILE_SPECIFIER' not in s:
    style = T4 + 'CODE_SIGN_STYLE = Automatic;\n'
    entitlements = T4 + 'CODE_SIGN_ENTITLEMENTS = App/App.entitlements;\n'
    team = T4 + 'DEVELOPMENT_TEAM = %s;\n' % TEAM
    debug = s.index('504EC3171FED79650016851F /* Debug */ = {')
    s = once(s, style, entitlements + style + team, debug)
    release = s.index('504EC3181FED79650016851F /* Release */ = {')
    s = once(s, style,
             entitlements
             + T4 + 'CODE_SIGN_IDENTITY = "Apple Distribution";\n'
             + T4 + 'CODE_SIGN_STYLE = Manual;\n'
             + team
             + T4 + 'PROVISIONING_PROFILE_SPECIFIER = "%s";\n' % PROFILE, release)
    assert s.count('MARKETING_VERSION = 1.0;') == 2
    s = s.replace('MARKETING_VERSION = 1.0;', 'MARKETING_VERSION = 1.0.0;')
    s = once(s, 'developmentRegion = en;', 'developmentRegion = he;')
    s = once(s, 'knownRegions = (\n' + T4 + 'en,\n', 'knownRegions = (\n' + T4 + 'he,\n' + T4 + 'en,\n')
    save(p, s)
    print('project configured')

p = 'ios/App/App/Info.plist'
s = load(p)
if 'ITSAppUsesNonExemptEncryption' not in s:
    s = once(s, '<key>CFBundleDevelopmentRegion</key>\n\t<string>en</string>',
             '<key>CFBundleDevelopmentRegion</key>\n\t<string>he</string>')
    pairs = [
        ('CFBundleLocalizations', '<array>\n\t\t<string>he</string>\n\t</array>'),
        ('ITSAppUsesNonExemptEncryption', '<false/>'),
        ('NSFaceIDUsageDescription', '<string>זיהוי הפנים משמש לכניסה למערכת בלי סיסמה.</string>'),
        ('NSCameraUsageDescription', '<string>המצלמה משמשת לסריקת שוברים וברקודים ולצילום תמונות שמעלים למערכת.</string>'),
        ('NSMicrophoneUsageDescription', '<string>המיקרופון משמש רק כשמצלמים סרטון שמעלים למערכת.</string>'),
        ('NSPhotoLibraryAddUsageDescription', '<string>שמירת תמונה מהמערכת לגלריה, למשל שובר.</string>'),
        ('UIStatusBarStyle', '<string>UIStatusBarStyleLightContent</string>'),
    ]
    extra = ''.join('\t<key>%s</key>\n\t%s\n' % kv for kv in pairs)
    i = s.rindex('</dict>\n</plist>')
    s = s[:i] + extra + s[i:]
    save(p, s)
    print('plist configured')

p = 'ios/App/App/Base.lproj/LaunchScreen.storyboard'
s = load(p)
old = '<color key="backgroundColor" systemColor="systemBackgroundColor"/>'
if old in s:
    s = once(s, old, '<color key="backgroundColor" red="0.16470588" green="0.07058824" blue="0.27843137" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>')
    save(p, s)
    print('launch screen configured')

p = 'ios/App/App/AppDelegate.swift'
s = load(p)
if 'capacitorDidRegisterForRemoteNotifications' not in s:
    anchor = '    func application(_ application: UIApplication,\n                     configurationForConnecting'
    push = (
        '    // The device token for push notifications goes to the Capacitor plugin, which hands it to the page.\n'
        '    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {\n'
        '        NotificationCenter.default.post(name: .capacitorDidRegisterForRemoteNotifications, object: deviceToken)\n'
        '    }\n\n'
        '    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {\n'
        '        NotificationCenter.default.post(name: .capacitorDidFailToRegisterForRemoteNotifications, object: error)\n'
        '    }\n\n'
    )
    s = once(s, anchor, push + anchor)
    save(p, s)
    print('app delegate configured')
