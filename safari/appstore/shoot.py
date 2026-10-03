"""Стопка: скриншоты для App Store, 2880×1800 (16:10, без прозрачности), en и ru.

Запуск: ~/.venvs/playwright/bin/python safari/appstore/shoot.py
Рисует безголовый Chromium — окна на экране нет.
Результат: safari/appstore/screenshots/<язык>/<1..3>.jpg
"""
import json
import pathlib
import subprocess

from playwright.sync_api import sync_playwright

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent.parent
DATA = (HERE / "data.js").read_text(encoding="utf-8")

# Попапу нужны chrome.storage и chrome.i18n. Подменяем их в кадре
# popup.html: записи — из data.js, строки — из настоящих _locales.
STUB = """
if (location.pathname.endsWith('/popup.html')) {
  (function () {
    const LANG = %(lang)s;
    const MESSAGES = %(messages)s;
    %(data)s
    const store = { items: SAVED };
    window.chrome = {
      runtime: { lastError: undefined },
      i18n: {
        getMessage(key, subs) {
          const m = MESSAGES[key];
          if (!m) return '';
          const args = [].concat(subs || []);
          let s = m.message;
          for (const [name, ph] of Object.entries(m.placeholders || {})) {
            s = s.replace(new RegExp('\\\\$' + name + '\\\\$', 'gi'), args[Number(ph.content.slice(1)) - 1] ?? '');
          }
          return s;
        },
      },
      storage: {
        local: {
          get: (k, cb) => cb({ items: store.items }),
          set: (v, cb) => { Object.assign(store, v); cb && cb(); },
          remove: (k, cb) => cb && cb(),
        },
        onChanged: { addListener() {} },
      },
    };
  })();
}
"""

with sync_playwright() as p:
    browser = p.chromium.launch()
    for lang in ("en", "ru"):
        out = HERE / "screenshots" / lang
        out.mkdir(parents=True, exist_ok=True)
        messages = (ROOT / "_locales" / lang / "messages.json").read_text(encoding="utf-8")
        ctx = browser.new_context(viewport={"width": 1440, "height": 900}, device_scale_factor=2,
                                  color_scheme="dark", locale=lang)
        ctx.add_init_script(STUB % {"lang": json.dumps(lang), "messages": messages, "data": DATA})
        page = ctx.new_page()
        for n in (1, 2, 3):
            page.goto((HERE / "scene.html").as_uri() + f"?n={n}&l={lang}")
            page.wait_for_load_state("load")
            if n >= 2:
                page.frame_locator("iframe.popup").locator("li.row").first.wait_for()
                if n == 3:
                    page.frames[1].evaluate(
                        "document.getElementById('toast').textContent = chrome.i18n.getMessage('copiedLinks', ['4'])")
            page.wait_for_timeout(300)
            png = out / f"{n}.png"
            page.screenshot(path=str(png))
            # App Store Connect не принимает альфа-канал — сохраняем в JPEG.
            jpg = out / f"{n}.jpg"
            subprocess.run(["sips", "-s", "format", "jpeg", "-s", "formatOptions", "95",
                            str(png), "--out", str(jpg)], check=True, capture_output=True)
            png.unlink()
            print("готово:", jpg.relative_to(HERE))
        ctx.close()
    browser.close()
