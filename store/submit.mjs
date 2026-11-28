// הגשת הגרסה לבדיקה של אפל. בלי --go רק בודק שהכול מוכן ולא משנה כלום; עם --go
// מצרף את הבנייה התקינה האחרונה ומגיש. הקוד של חשבון ההדגמה לא מודפס ולא נכתב
// מכאן: בעל החשבון מדביק אותו ב-App Store Connect, והסקריפט רק משווה את מה
// שנשמר אצל אפל למה שהמערכת מצפה לו (הגישה לבודקי החנויות ב-ATB-OS).
// הרצה: node store/submit.mjs [--min-build N] [--go]
import { ENV, asc } from '../scripts/asc.mjs'
import { serviceDb } from './atb-os.mjs'
import { DEMO_PHONE } from './he.mjs'

const args = process.argv.slice(2)
const go = args.includes('--go')
const at = args.indexOf('--min-build')
const minBuild = at < 0 ? 0 : Number(args[at + 1]) || 0
const DAYS_AHEAD = 14 // הבדיקה של אפל יכולה להימשך; הגישה צריכה להישאר פתוחה

const app = (await asc('GET', `/v1/apps?filter[bundleId]=${ENV.BUNDLE_ID}`)).data[0]
const ver = (await asc('GET', `/v1/apps/${app.id}/appStoreVersions?limit=1`)).data[0]
const review = (await asc('GET', `/v1/appStoreVersions/${ver.id}/appStoreReviewDetail`)).data.attributes
const builds = (await asc('GET', `/v1/builds?filter[app]=${app.id}&sort=-uploadedDate&limit=5`)).data
const latest = builds[0]
const latestValid = builds.find((b) => b.attributes.processingState === 'VALID' && !b.attributes.expired)
const attached = (await asc('GET', `/v1/appStoreVersions/${ver.id}/build`)).data

// הגישה לבודק במערכת: פתוחה, רחוקה מספיק מהתפוגה, והקוד שלה הוא מה שנשמר אצל אפל
const db = serviceDb()
const { data: row } = await db.from('app_secrets').select('value').eq('key', 'store_review').maybeSingle()
let access = null
try {
  access = row?.value ? JSON.parse(row.value) : null
} catch {
  access = null
}
const { data: reviewer } = await db.from('staff_users').select('is_active').like('email', 'qa-store-review%').maybeSingle()
const today = new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Jerusalem' })
const daysLeft = access?.until ? Math.round((new Date(access.until) - new Date(today)) / 864e5) : null

const checks = {
  [`version ${ver.attributes.versionString} is in preparation (${ver.attributes.appStoreState})`]:
    ver.attributes.appStoreState === 'PREPARE_FOR_SUBMISSION',
  'contact details': Boolean(review.contactEmail && review.contactPhone),
  'apple: demo user name is the demo phone': review.demoAccountName === DEMO_PHONE,
  'apple: demo password saved (6 digits)': /^[0-9]{6}$/.test(review.demoAccountPassword ?? ''),
  'system: reviewer access is open': Boolean(access?.code),
  'apple password == system code': Boolean(access?.code) && review.demoAccountPassword === access.code,
  [`system: open until ${access?.until} (${daysLeft} days left, need ${DAYS_AHEAD}+)`]:
    daysLeft !== null && daysLeft >= DAYS_AHEAD,
  [`system: wrong attempts so far ${access?.fails} (access closes at 20)`]: Number(access?.fails ?? 99) < 5,
  'system: reviewer user is active': reviewer?.is_active === true,
  [`newest build is valid (newest ${latest?.attributes.version}: ${latest?.attributes.processingState})`]:
    latest?.attributes.processingState === 'VALID',
  [`valid build is at least ${minBuild} (have ${latestValid?.attributes.version})`]:
    Number(latestValid?.attributes.version) >= minBuild,
}
for (const [k, v] of Object.entries(checks)) console.log(v ? 'ok  ' : 'MISSING', k)
console.log('attached build now:', attached?.attributes?.version)
const ready = Object.values(checks).every(Boolean)
if (!go) {
  console.log(ready ? 'READY (dry run, nothing changed)' : 'NOT READY (dry run)')
  process.exit(0)
}
if (!ready) {
  console.log('not submitting: something is missing')
  process.exit(1)
}

if (attached?.id !== latestValid.id) {
  await asc('PATCH', `/v1/appStoreVersions/${ver.id}/relationships/build`, { type: 'builds', id: latestValid.id })
  console.log('attached build', latestValid.attributes.version)
}
// ההגשה: טיוטת הגשה (או אחת פתוחה שכבר קיימת), הגרסה כפריט בה, ואז submitted
const open = (
  await asc('GET', `/v1/reviewSubmissions?filter[app]=${app.id}&filter[platform]=IOS&filter[state]=READY_FOR_REVIEW&limit=5`)
).data
const sub =
  open[0] ??
  (
    await asc('POST', '/v1/reviewSubmissions', {
      type: 'reviewSubmissions',
      attributes: { platform: 'IOS' },
      relationships: { app: { data: { type: 'apps', id: app.id } } },
    })
  ).data
const items = (await asc('GET', `/v1/reviewSubmissions/${sub.id}/items?limit=10`)).data
if (!items.length)
  await asc('POST', '/v1/reviewSubmissionItems', {
    type: 'reviewSubmissionItems',
    relationships: {
      reviewSubmission: { data: { type: 'reviewSubmissions', id: sub.id } },
      appStoreVersion: { data: { type: 'appStoreVersions', id: ver.id } },
    },
  })
const done = (
  await asc('PATCH', `/v1/reviewSubmissions/${sub.id}`, {
    type: 'reviewSubmissions',
    id: sub.id,
    attributes: { submitted: true },
  })
).data
console.log('submission state:', done.attributes.state, '| submitted', done.attributes.submittedDate)
const after = (await asc('GET', `/v1/apps/${app.id}/appStoreVersions?limit=1`)).data[0]
console.log('version state:', after.attributes.appStoreState)
