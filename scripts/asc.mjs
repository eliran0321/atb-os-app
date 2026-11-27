// גישה ל-App Store Connect API עם מפתח הצוות. המפתח עצמו לא בריפו: התיקייה
// שלו מגיעה מ-ATB_APP_KEYS (ברירת מחדל ~/.atb-app-keys), ובה asc.env עם
// ASC_KEY_ID ו-ASC_ISSUER_ID והקובץ AuthKey_<KEY_ID>.p8
import { createSign } from 'node:crypto'
import { readFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { join } from 'node:path'

export const KEYS = process.env.ATB_APP_KEYS || join(homedir(), '.atb-app-keys')
export const ENV = Object.fromEntries(
  readFileSync(join(KEYS, 'asc.env'), 'utf8')
    .split(/\r?\n/)
    .filter((l) => l.includes('='))
    .map((l) => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1).trim()]),
)

const b64url = (x) => Buffer.from(x).toString('base64url')

function token() {
  const now = Math.floor(Date.now() / 1000)
  const head = b64url(JSON.stringify({ alg: 'ES256', kid: ENV.ASC_KEY_ID, typ: 'JWT' }))
  const body = b64url(
    JSON.stringify({ iss: ENV.ASC_ISSUER_ID, iat: now, exp: now + 600, aud: 'appstoreconnect-v1' }),
  )
  const key = readFileSync(join(KEYS, `AuthKey_${ENV.ASC_KEY_ID}.p8`), 'utf8')
  const sig = createSign('SHA256')
    .update(`${head}.${body}`)
    .sign({ key, dsaEncoding: 'ieee-p1363' })
  return `${head}.${body}.${b64url(sig)}`
}

/** קריאה אחת ל-API. שגיאה נזרקת עם הפירוט של אפל, בלי הטוקן */
export async function asc(method, path, data) {
  const res = await fetch(`https://api.appstoreconnect.apple.com${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${token()}`,
      ...(data ? { 'Content-Type': 'application/json' } : {}),
    },
    body: data ? JSON.stringify({ data }) : undefined,
  })
  const text = await res.text()
  const json = text ? JSON.parse(text) : {}
  if (!res.ok) {
    const why = (json.errors ?? []).map((e) => `${e.status} ${e.code}: ${e.detail}`).join(' | ')
    throw new Error(`${method} ${path} -> ${res.status} ${why}`)
  }
  return json
}
