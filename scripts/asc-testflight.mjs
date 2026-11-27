// בדיקה פנימית ב-TestFlight: קבוצה פנימית שמקבלת כל בנייה, ובה בעלי החשבון.
// בודק פנימי הוא משתמש של App Store Connect, ולכן אין סקירה של אפל לפני ההתקנה.
// הרצה: node scripts/asc-testflight.mjs
import { ENV, asc } from './asc.mjs'

const GROUP = 'ATB-OS team'
const mask = (email) => email.replace(/^(.).*(@.*)$/, '$1***$2')

const app = (await asc('GET', `/v1/apps?filter[bundleId]=${ENV.BUNDLE_ID}`)).data[0]
if (!app) throw new Error('no app record')

let group = (await asc('GET', `/v1/apps/${app.id}/betaGroups`)).data.find(
  (g) => g.attributes.name === GROUP,
)
if (!group) {
  group = (
    await asc('POST', '/v1/betaGroups', {
      type: 'betaGroups',
      attributes: { name: GROUP, isInternalGroup: true, hasAccessToAllBuilds: true },
      relationships: { app: { data: { type: 'apps', id: app.id } } },
    })
  ).data
  console.log('internal group created')
}

const users = (await asc('GET', '/v1/users?limit=50')).data
const testers = (await asc('GET', `/v1/betaGroups/${group.id}/betaTesters?limit=100`)).data
const have = new Set(testers.map((t) => (t.attributes.email || '').toLowerCase()))
for (const u of users) {
  const { username, firstName, lastName, roles } = u.attributes
  if (have.has(username.toLowerCase())) {
    console.log('already a tester', mask(username))
    continue
  }
  await asc('POST', '/v1/betaTesters', {
    type: 'betaTesters',
    attributes: { email: username, firstName, lastName },
    relationships: { betaGroups: { data: [{ type: 'betaGroups', id: group.id }] } },
  })
  console.log('tester added', mask(username), roles.join(','))
}
const builds = (await asc('GET', `/v1/builds?filter[app]=${app.id}&sort=-uploadedDate&limit=3`)).data
for (const b of builds)
  console.log('build', b.attributes.version, b.attributes.processingState, 'encryption', b.attributes.usesNonExemptEncryption)
