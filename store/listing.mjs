// דף האפליקציה בחנות של אפל, כטיוטה: טקסטים, קטגוריות, דירוג גיל, זכויות
// תוכן, בנייה, מחיר, זמינות והערות לבודק. אפשר להריץ שוב ושוב. לא שולח
// לבדיקה: פרטי הקשר, חשבונות ההדגמה, שאלון הפרטיות וההגשה נעשים בממשק.
// הרצה: node store/listing.mjs
import { ENV, asc } from '../scripts/asc.mjs'
import { LISTING as L, REVIEW_NOTES } from './he.mjs'

const step = async (label, fn) => {
  try {
    const out = await fn()
    console.log('ok  ', label, typeof out === 'string' ? out : '')
  } catch (e) {
    console.log('FAIL', label, '::', String(e.message).slice(0, 400))
  }
}
const patch = (type, id, body) => asc('PATCH', `/v1/${type}/${id}`, { type, id, ...body })
const rel = (type, id) => ({ data: { type, id } })

const app = (await asc('GET', `/v1/apps?filter[bundleId]=${ENV.BUNDLE_ID}`)).data[0]
const info = await asc('GET', `/v1/apps/${app.id}/appInfos?include=appInfoLocalizations,ageRatingDeclaration`)
const infoLoc = info.included.find((i) => i.type === 'appInfoLocalizations')
const age = info.included.find((i) => i.type === 'ageRatingDeclarations')
const ver = (await asc('GET', `/v1/apps/${app.id}/appStoreVersions?limit=1`)).data[0]
const verLoc = (await asc('GET', `/v1/appStoreVersions/${ver.id}/appStoreVersionLocalizations`)).data[0]

await step('subtitle, privacy url', () =>
  patch('appInfoLocalizations', infoLoc.id, {
    attributes: { subtitle: L.subtitle, privacyPolicyUrl: L.privacyPolicyUrl },
  }),
)
await step('categories', () =>
  patch('appInfos', info.data[0].id, {
    relationships: {
      primaryCategory: rel('appCategories', L.primaryCategory),
      secondaryCategory: rel('appCategories', L.secondaryCategory),
    },
  }),
)
await step('content rights', () =>
  patch('apps', app.id, { attributes: { contentRightsDeclaration: 'DOES_NOT_USE_THIRD_PARTY_CONTENT' } }),
)

// שאלון הגיל: אין תוכן רגיש, אין פרסומות, אין רכישות ואין צ'אט בין משתמשים
// (תיבת ההודעות של הצוות היא כלי עבודה מול הוואטסאפ של העסק). יוצא 4+
const NONE = ['alcoholTobaccoOrDrugUseOrReferences', 'contests', 'gamblingSimulated', 'gunsOrOtherWeapons',
  'horrorOrFearThemes', 'matureOrSuggestiveThemes', 'medicalOrTreatmentInformation', 'profanityOrCrudeHumor',
  'sexualContentGraphicAndNudity', 'sexualContentOrNudity', 'violenceCartoonOrFantasy', 'violenceRealistic',
  'violenceRealisticProlongedGraphicOrSadistic']
const NO = ['gambling', 'lootBox', 'unrestrictedWebAccess', 'advertising', 'ageAssurance', 'healthOrWellnessTopics',
  'messagingAndChat', 'parentalControls', 'userGeneratedContent', 'socialMedia', 'datingAndRelationships',
  'sharedLocation', 'socialMediaAgeRestricted']
await step('age rating', async () => {
  await patch('ageRatingDeclarations', age.id, {
    attributes: Object.fromEntries([...NONE.map((k) => [k, 'NONE']), ...NO.map((k) => [k, false])]),
  })
  return (await asc('GET', `/v1/apps/${app.id}/appInfos`)).data[0].attributes.appStoreAgeRating
})

await step('copyright', () => patch('appStoreVersions', ver.id, { attributes: { copyright: L.copyright } }))
await step('description, keywords, urls', () =>
  patch('appStoreVersionLocalizations', verLoc.id, {
    attributes: {
      description: L.description,
      keywords: L.keywords,
      supportUrl: L.supportUrl,
      marketingUrl: L.marketingUrl,
      promotionalText: L.promotionalText,
    },
  }),
)

await step('build', async () => {
  const q = `filter[app]=${app.id}&filter[processingState]=VALID&sort=-uploadedDate&limit=1`
  const b = (await asc('GET', `/v1/builds?${q}`)).data[0]
  await asc('PATCH', `/v1/appStoreVersions/${ver.id}/relationships/build`, { type: 'builds', id: b.id })
  return b.attributes.version
})

await step('price', async () => {
  const have = await asc('GET', `/v1/appPriceSchedules/${app.id}/manualPrices?limit=5`).catch(() => ({ data: [] }))
  if (have.data.length) return 'already set'
  const points = (await asc('GET', `/v1/apps/${app.id}/appPricePoints?filter[territory]=USA&limit=20`)).data
  const free = points.find((p) => Number(p.attributes.customerPrice) === 0)
  await asc(
    'POST',
    '/v1/appPriceSchedules',
    {
      type: 'appPriceSchedules',
      relationships: {
        app: rel('apps', app.id),
        baseTerritory: rel('territories', 'USA'),
        manualPrices: { data: [{ type: 'appPrices', id: '${free}' }] },
      },
    },
    [
      {
        type: 'appPrices',
        id: '${free}',
        attributes: { startDate: null },
        relationships: { appPricePoint: rel('appPricePoints', free.id) },
      },
    ],
  )
  return 'free'
})

// אפל דורשת שורה לכל מדינה, זמינה או לא
await step('availability', async () => {
  const have = await asc('GET', `/v1/apps/${app.id}/appAvailabilityV2`).catch(() => null)
  if (have?.data) return 'already set'
  const all = (await asc('GET', '/v1/territories?limit=200')).data.map((t) => t.id)
  const local = (id) => '${' + id + '}'
  await asc(
    'POST',
    '/v2/appAvailabilities',
    {
      type: 'appAvailabilities',
      attributes: { availableInNewTerritories: false },
      relationships: {
        app: rel('apps', app.id),
        territoryAvailabilities: { data: all.map((id) => ({ type: 'territoryAvailabilities', id: local(id) })) },
      },
    },
    all.map((id) => ({
      type: 'territoryAvailabilities',
      id: local(id),
      attributes: { available: L.territories.includes(id) },
      relationships: { territory: rel('territories', id) },
    })),
  )
  return L.territories.join(',')
})

await step('review notes', async () => {
  const cur = await asc('GET', `/v1/appStoreVersions/${ver.id}/appStoreReviewDetail`).catch(() => null)
  // אחרי שנוצר, אפל מקבלת עדכון רק יחד עם פרטי הקשר, והם ממולאים בממשק
  if (cur?.data) return 'exists, edit in App Store Connect'
  await asc('POST', '/v1/appStoreReviewDetails', {
    type: 'appStoreReviewDetails',
    attributes: { notes: REVIEW_NOTES },
    relationships: { appStoreVersion: rel('appStoreVersions', ver.id) },
  })
  return 'created'
})
