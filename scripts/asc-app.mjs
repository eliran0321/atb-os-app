// מצב האפליקציה ב-App Store Connect: הרשומה, הגרסאות והבניות שהועלו.
// הרצה: node scripts/asc-app.mjs
import { ENV, asc } from './asc.mjs'

const apps = (await asc('GET', `/v1/apps?filter[bundleId]=${ENV.BUNDLE_ID}`)).data
if (!apps.length) {
  console.log('no app record for', ENV.BUNDLE_ID)
  process.exit(0)
}
const app = apps[0]
console.log('app', app.id, '|', app.attributes.name, '|', app.attributes.sku, '|', app.attributes.primaryLocale)
const builds = (await asc('GET', `/v1/builds?filter[app]=${app.id}&sort=-uploadedDate&limit=5`)).data
for (const b of builds)
  console.log('build', b.attributes.version, b.attributes.processingState, b.attributes.uploadedDate, 'expired', b.attributes.expired)
if (!builds.length) console.log('no builds yet')
