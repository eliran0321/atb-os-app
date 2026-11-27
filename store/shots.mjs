// צילומי המסך לדף החנות: צילום של המסך האמיתי (נתוני הדוגמה של המערכת, והשם
// במסך הבית מוחלף) בתוך מסגרת של מכשיר עם כיתוב. צריך את שרת הפיתוח של ATB-OS.
// הרצה: node store/shots.mjs [תיקיית פלט] [phone|pad|all] [חלק משם של צילום]
import { mkdirSync, readFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { chromium, login, openPage } from './atb-os.mjs'
import { frameHtml } from './frame.mjs'

const [outDir = join(tmpdir(), 'atb-store-shots'), which, only] = process.argv.slice(2)
mkdirSync(outDir, { recursive: true })

// cw/ch: הבד, ב-CSS px (כפול dpr = הגודל שאפל דורשת: 1290x2796 ו-2048x2732).
// vw/vh: המסך של המכשיר. sb/bi: פס השעה ושולי הבית. fw: רוחב המכשיר על הבד
const DEVICES = {
  phone: { cw: 430, ch: 932, dpr: 3, vw: 390, vh: 844, sb: 47, bi: 20, fw: 348, bz: 6, r: 48, top: 158, h1: 37, p: 17.5 },
  pad: { pad: true, cw: 1024, ch: 1366, dpr: 2, vw: 820, vh: 1093, sb: 26, bi: 14, fw: 820, bz: 9, r: 34, top: 218, h1: 62, p: 27 },
}
// overlay: פס השעה מעל המסך עצמו (מסך הפתיחה). hi: צבע הפס התחתון של המכשיר
const SHOTS = [
  { name: '1-start', path: '/start', anon: true, wait: 2800, overlay: true, title: 'ATB באולינג בטלפון', sub: 'אפליקציה אחת ללקוחות ולצוות' },
  { name: '2-vouchers', path: '/v?demo=1', hi: 'dark', title: 'השוברים שלך בכיס', sub: 'מציגים את הברקוד בקבלה ומשחקים' },
  { name: '3-event', path: '/e/demo', hi: 'dark', title: 'כל פרטי האירוע שלך', sub: 'שעות, לוח זמנים ומה כלול' },
  { name: '4-quote', path: '/quote/demo', hi: 'dark', title: 'הצעת מחיר בטלפון', sub: 'קוראים, חותמים ומשריינים תאריך' },
  { name: '5-home', path: '/home', wait: 2800, mask: true, title: 'גם הצוות עובד מכאן', sub: 'משמרות, משימות וסריקת שוברים' },
].filter((s) => !only || s.name.includes(only))

const { jar, logout } = await login()
const browser = await chromium.launch()
try {
  for (const [key, dev] of Object.entries(DEVICES)) {
    if (which && which !== 'all' && which !== key) continue
    dev.fh = Math.round((dev.fw * dev.vh) / dev.vw)
    for (const s of SHOTS) {
      const height = (s.overlay ? dev.vh : dev.vh - dev.sb) - dev.bi
      const { ctx, page } = await openPage(browser, s.anon ? new Map() : jar, s.path, {
        width: dev.vw,
        height,
        dpr: dev.dpr,
        wait: s.wait,
      })
      // השם של מי שמחובר לא נכנס לצילום ציבורי
      if (s.mask)
        await page.evaluate(() => {
          const walk = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT)
          for (let n = walk.nextNode(); n; n = walk.nextNode())
            if (n.nodeValue.trim().startsWith('שלום ')) n.nodeValue = 'שלום ישראל ישראלי'
        })
      const text = await page.evaluate(() => document.body.innerText.length)
      const raw = join(outDir, `raw-${key}-${s.name}.png`)
      await page.screenshot({ path: raw })
      await ctx.close()

      const fctx = await browser.newContext({ viewport: { width: dev.cw, height: dev.ch }, deviceScaleFactor: dev.dpr })
      const fp = await fctx.newPage()
      const img = 'data:image/png;base64,' + readFileSync(raw).toString('base64')
      await fp.setContent(frameHtml({ ...s, img, dev }), { waitUntil: 'networkidle' })
      await fp.evaluate(() => document.fonts.ready)
      const font = await fp.evaluate(() => document.fonts.check('900 30px Heebo'))
      await fp.screenshot({ path: join(outDir, `${key}-${s.name}.png`) })
      await fctx.close()
      // עמוד ריק (שרת שנפל) או גופן שלא נטען מצולמים כאילו הכול תקין: לבדוק כאן
      console.log(key, s.name, 'text', text, 'heebo', font)
    }
  }
  console.log('out:', outDir)
} finally {
  await browser.close()
  await logout().catch(() => {})
}
