// מעלה את צילומי המסך לגרסה שבהכנה ומחליף את מה שיש בכל סט: מוחק את הקיימים
// ומעלה לפי הסדר של שמות הקבצים (phone-1-..., pad-1-...).
// הרצה: node store/upload-shots.mjs <תיקיית הצילומים>
import { createHash } from 'node:crypto'
import { readFileSync, readdirSync } from 'node:fs'
import { join } from 'node:path'
import { ENV, asc } from '../scripts/asc.mjs'

const dir = process.argv[2]
if (!dir) throw new Error('usage: node store/upload-shots.mjs <dir>')
// הסט של אפל לכל מכשיר: אייפון 6.7 אינץ' (1290x2796) ואייפד 12.9 אינץ' (2048x2732)
const SETS = { phone: 'APP_IPHONE_67', pad: 'APP_IPAD_PRO_3GEN_129' }
const wait = (ms) => new Promise((r) => setTimeout(r, ms))

const app = (await asc('GET', `/v1/apps?filter[bundleId]=${ENV.BUNDLE_ID}`)).data[0]
const ver = (await asc('GET', `/v1/apps/${app.id}/appStoreVersions?limit=1`)).data[0]
const loc = (await asc('GET', `/v1/appStoreVersions/${ver.id}/appStoreVersionLocalizations`)).data[0]
const sets = (await asc('GET', `/v1/appStoreVersionLocalizations/${loc.id}/appScreenshotSets?limit=50`)).data

for (const [key, type] of Object.entries(SETS)) {
  const files = readdirSync(dir)
    .filter((f) => f.startsWith(key + '-') && f.endsWith('.png'))
    .sort()
  if (!files.length) {
    console.log('no files for', key)
    continue
  }
  const set =
    sets.find((s) => s.attributes.screenshotDisplayType === type) ??
    (
      await asc('POST', '/v1/appScreenshotSets', {
        type: 'appScreenshotSets',
        attributes: { screenshotDisplayType: type },
        relationships: { appStoreVersionLocalization: { data: { type: 'appStoreVersionLocalizations', id: loc.id } } },
      })
    ).data
  for (const old of (await asc('GET', `/v1/appScreenshotSets/${set.id}/appScreenshots?limit=20`)).data)
    await asc('DELETE', `/v1/appScreenshots/${old.id}`)

  const ids = []
  for (const f of files) {
    const bytes = readFileSync(join(dir, f))
    const shot = (
      await asc('POST', '/v1/appScreenshots', {
        type: 'appScreenshots',
        attributes: { fileName: f, fileSize: bytes.length },
        relationships: { appScreenshotSet: { data: { type: 'appScreenshotSets', id: set.id } } },
      })
    ).data
    for (const op of shot.attributes.uploadOperations) {
      const res = await fetch(op.url, {
        method: op.method,
        headers: Object.fromEntries(op.requestHeaders.map((h) => [h.name, h.value])),
        body: bytes.subarray(op.offset, op.offset + op.length),
      })
      if (!res.ok) throw new Error(`upload ${f} -> ${res.status}`)
    }
    await asc('PATCH', `/v1/appScreenshots/${shot.id}`, {
      type: 'appScreenshots',
      id: shot.id,
      attributes: { uploaded: true, sourceFileChecksum: createHash('md5').update(bytes).digest('hex') },
    })
    ids.push(shot.id)
    console.log('uploaded', type, f)
  }

  // אפל מעבדת כל קובץ אחרי ההעלאה: מחכים למצב סופי, עד דקה וחצי
  for (let i = 0; i < 22; i++) {
    const cur = (await asc('GET', `/v1/appScreenshotSets/${set.id}/appScreenshots?limit=20`)).data
    const states = cur.map((s) => s.attributes.assetDeliveryState?.state)
    if (states.every((s) => s === 'COMPLETE' || s === 'FAILED')) {
      for (const s of cur) {
        const d = s.attributes.assetDeliveryState
        console.log(' ', s.attributes.fileName, d.state, (d.errors ?? []).map((e) => e.description).join(' | '))
      }
      break
    }
    if (i === 21) console.log('  still processing:', states.join(','))
    await wait(4000)
  }
  // הסדר בחנות לפי סדר ההעלאה
  await asc('PATCH', `/v1/appScreenshotSets/${set.id}/relationships/appScreenshots`, ids.map((id) => ({ type: 'appScreenshots', id })))
}
