"""Стопка: скриншоты для App Store, 2880×1800 (16:10, без прозрачности).

Запуск: ~/.venvs/playwright/bin/python safari/appstore/shoot.py
Рисует безголовый Chromium — окна на экране нет. Результат: safari/appstore/screenshots/.
"""
import pathlib
import subprocess

from playwright.sync_api import sync_playwright

HERE = pathlib.Path(__file__).resolve().parent
OUT = HERE / "screenshots"
OUT.mkdir(exist_ok=True)

# Попапу нужен chrome.storage. Подменяем его в кадре popup.html записями
# из data.js — в изолированной области видимости, чтобы не задеть сцену.
STUB = """
if (location.pathname.endsWith('/popup.html')) {
  (function () {
    %s
    const store = { items: SAVED };
    window.chrome = {
      runtime: { lastError: undefined },
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
""" % (HERE / "data.js").read_text(encoding="utf-8")

with sync_playwright() as p:
    browser = p.chromium.launch()
    ctx = browser.new_context(viewport={"width": 1440, "height": 900},
                              device_scale_factor=2, color_scheme="dark")
    ctx.add_init_script(STUB)
    page = ctx.new_page()
    for n in (1, 2, 3):
        page.goto((HERE / "scene.html").as_uri() + f"?n={n}")
        page.wait_for_load_state("load")
        if n >= 2:
            frame = page.frame_locator("iframe.popup")
            frame.locator("li.row").first.wait_for()
            if n == 3:
                page.frames[1].evaluate(
                    "document.getElementById('toast').textContent = 'Скопировано ссылок: 4'")
        page.wait_for_timeout(300)
        png = OUT / f"{n}.png"
        page.screenshot(path=str(png))
        # App Store Connect не принимает альфа-канал — сохраняем в JPEG.
        jpg = OUT / f"{n}.jpg"
        subprocess.run(["sips", "-s", "format", "jpeg", "-s", "formatOptions", "95",
                        str(png), "--out", str(jpg)], check=True, capture_output=True)
        png.unlink()
        print("готово:", jpg.relative_to(HERE))
    browser.close()
