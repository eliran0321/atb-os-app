// הטקסטים של דף האפליקציה בחנות של אפל (עברית). אורכים: כותרת משנה עד 30,
// מילות מפתח עד 100, טקסט קידום עד 170
export const LISTING = {
  subtitle: 'השוברים והאירועים שלך ב-ATB',
  privacyPolicyUrl: 'https://atb-os.all4fun.co.il/privacy',
  supportUrl: 'https://www.all4fun.co.il/contact',
  marketingUrl: 'https://www.all4fun.co.il',
  copyright: '2026 ATB באולינג',
  primaryCategory: 'ENTERTAINMENT',
  secondaryCategory: 'SPORTS',
  // המדינות שבהן האפליקציה זמינה (קוד של אפל). רק ישראל: עסק מקומי בעברית
  territories: ['ISR'],
  keywords: 'באולינג,שוברים,יום הולדת,אירועים,כרטיסייה,חדרה,בילוי,מסלולים,all4fun,משמרות',
  promotionalText: 'השוברים, הצעות המחיר ופרטי האירוע שלך ב-ATB באולינג, תמיד בטלפון.',
  description: [
    'האפליקציה של ATB באולינג, מרכז פנאי ובילוי בחדרה.',
    '',
    'ללקוחות',
    '• כל השוברים שלך במקום אחד: מציגים את הברקוד בקבלה ומשחקים.',
    '• רואים כמה משחקים נשארו ועד מתי השובר בתוקף.',
    '• מעבירים שובר לחבר או לבן משפחה בכמה לחיצות.',
    '• הצעות המחיר שלך: קוראים, חותמים ומשריינים את התאריך מהטלפון.',
    '• דף האירוע: שעות, לוח זמנים, מה כלול ואיך מגיעים.',
    '',
    'לצוות של ATB',
    '• סידור עבודה, הגשת זמינות והחלפת משמרות.',
    '• אירועי היום, משימות וצ\'קליסטים.',
    '• סריקת שוברים במצלמה.',
    '• התראות לטלפון וכניסה בזיהוי פנים.',
    '',
    'הכניסה ללקוחות היא במספר הטלפון ובקוד חד פעמי שנשלח בוואטסאפ. הכניסה לצוות היא בחשבון שמקבלים מההנהלה.',
  ].join('\n'),
}
// ההערות לבודק של אפל (באנגלית), עם הוראות הכניסה לחשבון ההדגמה. שם המשתמש הוא
// מספר ההדגמה; הסיסמה היא הקוד מהכרטיס "גישה לבודקי החנויות" במערכת (הגדרות ›
// מערכת › כתובת), ובעל החשבון מעתיק אותה לשדה Sign-In Information. פרטי הקשר
// ממולאים בממשק, ואחרי שנוצרו אפל מקבלת עדכון של ההערות רק יחד איתם
export const DEMO_PHONE = '0500000003'
export const REVIEW_NOTES = [
  'ATB-OS is the app of ATB Bowling, an entertainment center in Hadera, Israel. The interface is in Hebrew (right to left).',
  '',
  'SIGN-IN: the user name and password above work for both entrances of the first screen.',
  '',
  `1. Customers (the lime tile on the right, "לקוחות"): enter the phone number ${DEMO_PHONE} and continue. Then type the password as the 6-digit one-time code. Real customers receive this code by WhatsApp; the demo number does not need a message. The demo account shows sample vouchers: tap "הצגת ברקוד" to show the QR code that the front desk scans. Transferring vouchers is disabled for the demo account.`,
  '',
  `2. Staff (the purple tile on the left, "צוות"): enter the phone number ${DEMO_PHONE} and the password. Staff screens depend on the permissions of each role (shifts, tasks, checklists, voucher scanning, events). The demo staff account has a minimal role with no access to customer or business data, so it shows the personal screens only: home, my tasks, my clock-in badge and profile (photo, notifications, Face ID sign-in).`,
  '',
  'To switch between the two entrances, sign out first: customers with the "יציאה" button at the top, staff with the sign-out icon in the menu at the top ("התנתקות"). Each sign-in screen has a back button to the first screen.',
  '',
  'Native features: push notifications (APNs), Face ID sign-in backed by a key in the Secure Enclave, camera scanning of vouchers, and Quick Look preview with share for exported files (PDF, Excel).',
  '',
  'Vouchers are redeemed in person at the venue for bowling games. Nothing is sold inside the app.',
  '',
  'Accounts are not created in the app. Staff accounts are opened by the management of the venue, and a customer area exists once the venue issues vouchers to a phone number. Requests to delete personal data are handled through the contact details on the privacy policy page, which is linked from the forms in the app.',
].join('\n')
