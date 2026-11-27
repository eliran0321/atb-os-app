// הגישה למערכת עצמה בשביל הצילומים: Playwright והכניסה כבעלים באים מהתיקייה
// של ATB-OS (ATB_OS_DIR, ברירת מחדל ../ATB-OS ליד הריפו הזה), מול שרת הפיתוח
// שלה (ATB_OS_URL). צפייה בלבד: פעולות שרת ורישום שגיאות חסומים בכל דף.
import { readFileSync } from 'node:fs'
import { createRequire } from 'node:module'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const HERE = dirname(fileURLToPath(import.meta.url))
const ROOT = resolve(process.env.ATB_OS_DIR || join(HERE, '../../ATB-OS'))
const require = createRequire(join(ROOT, 'package.json'))
const { createClient } = require('@supabase/supabase-js')
const { createServerClient } = require('@supabase/ssr')
export const { chromium } = require('playwright')
export const BASE = process.env.ATB_OS_URL || 'http://localhost:3030'

const env = Object.fromEntries(
  readFileSync(join(ROOT, '.env.local'), 'utf8')
    .split(/\r?\n/)
    .filter((l) => /^[A-Z0-9_]+=/.test(l))
    .map((l) => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1).replace(/^"|"$/g, '')]),
)

/** סשן של הבעלים (QA_OWNER_ID) בקישור קסם, מאומת כמו מכשיר מוכר. logout מקומי בלבד */
export async function login() {
  const admin = createClient(env.NEXT_PUBLIC_SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false },
  })
  const { data: u } = await admin.auth.admin.getUserById(env.QA_OWNER_ID)
  const { data: link } = await admin.auth.admin.generateLink({ type: 'magiclink', email: u.user.email })
  const jar = new Map()
  const sb = createServerClient(env.NEXT_PUBLIC_SUPABASE_URL, env.NEXT_PUBLIC_SUPABASE_ANON_KEY, {
    cookies: {
      getAll: () => [...jar].map(([name, value]) => ({ name, value })),
      setAll: (list) => list.forEach((c) => jar.set(c.name, c.value)),
    },
  })
  const { data: v, error } = await sb.auth.verifyOtp({ type: 'magiclink', token_hash: link.properties.hashed_token })
  if (error) throw new Error('verify failed')
  const claims = JSON.parse(Buffer.from(v.session.access_token.split('.')[1], 'base64url').toString())
  await admin.rpc('staff_session_verify', { p_staff: env.QA_OWNER_ID, p_session: claims.session_id })
  return { jar, logout: () => sb.auth.signOut({ scope: 'local' }) }
}

/** דף במידות של מכשיר. jar ריק = גולש לא מחובר */
export async function openPage(browser, jar, path, { width, height, dpr, wait = 2000 }) {
  const ctx = await browser.newContext({
    viewport: { width, height },
    deviceScaleFactor: dpr,
    locale: 'he-IL',
    timezoneId: 'Asia/Jerusalem',
    isMobile: width < 1000,
    hasTouch: width < 1000,
  })
  await ctx.addCookies([...jar].map(([name, value]) => ({ name, value, domain: new URL(BASE).hostname, path: '/' })))
  const page = await ctx.newPage()
  await page.route('**/*', (route) => {
    const q = route.request()
    const write = q.headers()['next-action'] || q.url().includes('/rest/v1/rpc/log_app_error')
    return q.method() === 'POST' && write ? route.abort() : route.continue()
  })
  await page.goto(BASE + path, { waitUntil: 'networkidle', timeout: 120000 }).catch(() => {})
  await page.waitForTimeout(wait)
  await page.addStyleTag({ content: 'nextjs-portal{display:none!important}' }).catch(() => {})
  return { ctx, page }
}
