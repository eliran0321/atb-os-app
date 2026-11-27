// האייקון ומסך הפתיחה של אפליקציית האייפון, מתוך נכסי המותג של המערכת.
// הרצה: node scripts/make-assets.mjs <תיקיית ATB-OS>
import { createRequire } from 'node:module'
import { join } from 'node:path'

const atbOs = process.argv[2]
if (!atbOs) throw new Error('usage: node scripts/make-assets.mjs <ATB-OS dir>')
const sharp = createRequire(join(atbOs, 'package.json'))('sharp')
const INK = '#2a1247'
const assets = 'ios/App/App/Assets.xcassets'

// האייקון: 1024 בלי שקיפות (אפל דוחה אייקון עם ערוץ אלפא)
await sharp(join(atbOs, 'public/icon-512.png'))
  .resize(1024, 1024, { kernel: 'lanczos3' })
  .flatten({ background: INK })
  .png()
  .toFile(`${assets}/AppIcon.appiconset/AppIcon-512@2x.png`)

// מסך הפתיחה: דיו עם הלוגו במרכז. התמונה ריבועית ונחתכת לפי המסך, ולכן
// הלוגו צר מספיק כדי להישאר שלם גם בטלפון עומד
const logo = await sharp(join(atbOs, 'public/brand/atb-logo-yellow.png'))
  .resize({ width: 720 })
  .png()
  .toBuffer()
const splash = await sharp({
  create: { width: 2732, height: 2732, channels: 3, background: INK },
})
  .composite([{ input: logo, gravity: 'centre' }])
  .png()
  .toBuffer()
for (const name of ['splash-2732x2732.png', 'splash-2732x2732-1.png', 'splash-2732x2732-2.png'])
  await sharp(splash).toFile(`${assets}/Splash.imageset/${name}`)

const icon = await sharp(`${assets}/AppIcon.appiconset/AppIcon-512@2x.png`).metadata()
console.log('icon', `${icon.width}x${icon.height}`, 'alpha', icon.hasAlpha, '| splash', splash.length, 'bytes')
