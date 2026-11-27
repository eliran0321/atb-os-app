// תבנית המסגרת של צילום לחנות: במה של דיו עם אור סגול, כיתוב, ומכשיר עם הצילום
const GLYPHS = (pad) => `
<svg width="${pad ? 17 : 18}" height="12" viewBox="0 0 18 12" fill="#fff"><rect x="0" y="8" width="3" height="4" rx="1"/><rect x="5" y="5.5" width="3" height="6.5" rx="1"/><rect x="10" y="3" width="3" height="9" rx="1"/><rect x="15" y="0" width="3" height="12" rx="1"/></svg>
<svg width="17" height="12" viewBox="0 0 17 12" fill="none" stroke="#fff" stroke-width="1.9" stroke-linecap="round"><path d="M1.2 4.2a10.4 10.4 0 0 1 14.6 0"/><path d="M3.9 6.9a6.6 6.6 0 0 1 9.2 0"/><circle cx="8.5" cy="10" r="1.3" fill="#fff" stroke="none"/></svg>
<svg width="27" height="13" viewBox="0 0 27 13" fill="none"><rect x="0.6" y="0.6" width="22.8" height="11.8" rx="3.6" stroke="#fff" stroke-opacity=".45" stroke-width="1.2"/><rect x="2.3" y="2.3" width="19.4" height="8.4" rx="2.2" fill="#fff"/><rect x="24.6" y="4.2" width="1.9" height="4.6" rx="1" fill="#fff" fill-opacity=".5"/></svg>`

export function frameHtml({ title, sub, img, dev, overlay, hi }) {
  const pad = dev.pad
  return `<!doctype html><html lang="he" dir="rtl"><head><meta charset="utf-8">
<link href="https://fonts.googleapis.com/css2?family=Heebo:wght@500;800;900&display=block" rel="stylesheet">
<style>
*{box-sizing:border-box;margin:0}
html,body{width:${dev.cw}px;height:${dev.ch}px;overflow:hidden}
body{background:#2a1247;font-family:Heebo,'Segoe UI',sans-serif;color:#fff;position:relative;
 background-image:radial-gradient(${pad ? 60 : 30}rem ${pad ? 46 : 24}rem at 100% 0%,rgba(139,92,246,.55),transparent 70%),
 radial-gradient(${pad ? 56 : 28}rem ${pad ? 44 : 22}rem at 0% 100%,rgba(124,58,237,.5),transparent 70%)}
.cap{position:absolute;inset-inline:0;top:0;height:${dev.top}px;display:flex;flex-direction:column;align-items:center;justify-content:center;padding:${pad ? 20 : 12}px ${pad ? 60 : 22}px 0;text-align:center}
.bar{width:${pad ? 64 : 40}px;height:${pad ? 8 : 5}px;border-radius:9px;background:#d7fb00;margin-bottom:${pad ? 22 : 13}px}
h1{font-size:${dev.h1}px;line-height:1.12;font-weight:900;letter-spacing:-.01em}
p{font-size:${dev.p}px;line-height:1.3;font-weight:500;color:#dccdff;margin-top:${pad ? 14 : 8}px}
.dev{position:absolute;left:50%;top:${dev.top}px;transform:translateX(-50%);width:${dev.fw + dev.bz * 2}px;border:${dev.bz}px solid #140a22;border-radius:${dev.r}px;overflow:hidden;background:#2a1247;
 box-shadow:0 0 0 1.5px rgba(255,255,255,.16),0 ${pad ? 50 : 28}px ${pad ? 110 : 60}px rgba(8,2,20,.62)}
.scr{position:relative;width:${dev.fw}px;height:${dev.fh}px;overflow:hidden;border-radius:${dev.r - dev.bz}px}
.sb{direction:ltr;display:flex;align-items:center;justify-content:space-between;height:${dev.sb}px;padding:0 ${pad ? 22 : 30}px 0 ${pad ? 22 : 34}px;font:600 ${pad ? 13 : 16}px/1 'Segoe UI',sans-serif;color:#fff;background:#2a1247}
.sb.over{position:absolute;inset:0 0 auto 0;background:transparent;z-index:2}
.sb span{display:flex;align-items:center;gap:${pad ? 6 : 6}px}
img{display:block;width:${dev.fw}px}
.hs{height:${Math.ceil((dev.bi * dev.fw) / dev.vw) + 1}px;background-position:bottom;background-size:100% 20000%;background-repeat:no-repeat}
.hi{position:absolute;left:50%;bottom:${pad ? 7 : 8}px;transform:translateX(-50%);width:${pad ? 260 : 128}px;height:5px;border-radius:5px;background:${hi === 'dark' ? 'rgba(20,10,34,.5)' : 'rgba(255,255,255,.75)'}}
</style></head><body>
<div class="cap"><div class="bar"></div><h1>${title}</h1><p>${sub}</p></div>
<div class="dev"><div class="scr">
<div class="sb${overlay ? ' over' : ''}"><span>9:41</span><span>${GLYPHS(pad)}</span></div>
<img src="${img}"><div class="hs" style="background-image:url(${img})"></div><div class="hi"></div></div></div>
</body></html>`
}
