// הכנה חד-פעמית של החתימה לאייפון, מכל מחשב (גם בלי מק): רישום מזהה האפליקציה
// והיכולות שלו, תעודת הפצה ופרופיל App Store. כל שלב בודק קודם מה כבר קיים,
// כך שאפשר להריץ שוב. הקבצים נשמרים בתיקיית המפתחות, מחוץ לריפו.
// הרצה: node scripts/asc-setup.mjs
import { execFileSync } from 'node:child_process'
import { randomBytes } from 'node:crypto'
import { existsSync, readFileSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import { ENV, KEYS, asc } from './asc.mjs'

const BUNDLE = ENV.BUNDLE_ID
const PROFILE_NAME = 'ATB-OS App Store'
const CAPABILITIES = ['PUSH_NOTIFICATIONS', 'ASSOCIATED_DOMAINS']
const file = (name) => join(KEYS, name)
const stateFile = file('ios-signing.json')
const state = existsSync(stateFile) ? JSON.parse(readFileSync(stateFile, 'utf8')) : {}
const save = () => writeFileSync(stateFile, JSON.stringify(state, null, 2))
const openssl = (...args) => execFileSync('openssl', args, { stdio: ['ignore', 'pipe', 'pipe'] })

// 1. מזהה האפליקציה
let bundle = (await asc('GET', `/v1/bundleIds?filter[identifier]=${BUNDLE}`)).data.find(
  (b) => b.attributes.identifier === BUNDLE,
)
if (!bundle) {
  bundle = (
    await asc('POST', '/v1/bundleIds', {
      type: 'bundleIds',
      attributes: { identifier: BUNDLE, name: 'ATB OS', platform: 'IOS' },
    })
  ).data
  console.log('bundle id registered')
}
state.bundleIdId = bundle.id
save()

// 2. היכולות: התראות דחיפה ודומיינים משויכים (כניסה ביומטרית מול האתר)
const have = (await asc('GET', `/v1/bundleIds/${bundle.id}/bundleIdCapabilities`)).data.map(
  (c) => c.attributes.capabilityType,
)
for (const capabilityType of CAPABILITIES.filter((c) => !have.includes(c))) {
  await asc('POST', '/v1/bundleIdCapabilities', {
    type: 'bundleIdCapabilities',
    attributes: { capabilityType },
    relationships: { bundleId: { data: { type: 'bundleIds', id: bundle.id } } },
  })
  console.log('capability enabled', capabilityType)
}

// 3. תעודת ההפצה: המפתח הפרטי נוצר כאן ונשאר כאן, לאפל נשלחת רק הבקשה
if (!state.certificateId) {
  if (!existsSync(file('ios-dist.key')))
    openssl('genrsa', '-out', file('ios-dist.key'), '2048')
  openssl('req', '-new', '-key', file('ios-dist.key'), '-out', file('ios-dist.csr'), '-subj', '/CN=ATB-OS distribution/C=IL')
  const cert = (
    await asc('POST', '/v1/certificates', {
      type: 'certificates',
      attributes: {
        certificateType: 'DISTRIBUTION',
        csrContent: readFileSync(file('ios-dist.csr'), 'utf8'),
      },
    })
  ).data
  writeFileSync(file('ios-dist.cer'), Buffer.from(cert.attributes.certificateContent, 'base64'))
  state.certificateId = cert.id
  state.certificateExpires = cert.attributes.expirationDate
  save()
  console.log('distribution certificate created, expires', cert.attributes.expirationDate)
}

// 4. קובץ p12 לבנייה בענן. 3DES ו-SHA1: הפורמט ש-security import של מק קורא
if (!existsSync(file('ios-dist.p12'))) {
  openssl('x509', '-inform', 'DER', '-in', file('ios-dist.cer'), '-out', file('ios-dist.pem'))
  writeFileSync(file('ios-dist.p12.pass'), randomBytes(18).toString('hex'))
  openssl(
    'pkcs12', '-export',
    '-inkey', file('ios-dist.key'),
    '-in', file('ios-dist.pem'),
    '-out', file('ios-dist.p12'),
    '-name', 'ATB-OS distribution',
    '-passout', `file:${file('ios-dist.p12.pass')}`,
    '-keypbe', 'PBE-SHA1-3DES', '-certpbe', 'PBE-SHA1-3DES', '-macalg', 'sha1',
  )
  console.log('p12 written')
}

// 5. פרופיל App Store למזהה ולתעודה. פרופיל קיים באותו שם נמחק ונוצר מחדש,
// כדי שיכלול את היכולות כפי שהן עכשיו
const old = (await asc('GET', `/v1/profiles?filter[name]=${encodeURIComponent(PROFILE_NAME)}`)).data
for (const p of old) await asc('DELETE', `/v1/profiles/${p.id}`)
const profile = (
  await asc('POST', '/v1/profiles', {
    type: 'profiles',
    attributes: { name: PROFILE_NAME, profileType: 'IOS_APP_STORE' },
    relationships: {
      bundleId: { data: { type: 'bundleIds', id: bundle.id } },
      certificates: { data: [{ type: 'certificates', id: state.certificateId }] },
    },
  })
).data
writeFileSync(file('ios-appstore.mobileprovision'), Buffer.from(profile.attributes.profileContent, 'base64'))
state.profileId = profile.id
state.profileUuid = profile.attributes.uuid
state.profileName = profile.attributes.name
state.profileExpires = profile.attributes.expirationDate
save()
console.log('profile', profile.attributes.name, profile.attributes.uuid, 'expires', profile.attributes.expirationDate)
