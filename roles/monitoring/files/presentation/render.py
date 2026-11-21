"""Renders each given slide HTML (1920x1080) to a PNG next to it."""
import sys
from playwright.sync_api import sync_playwright
with sync_playwright() as p:
    b = p.chromium.launch(channel="chrome")
    pg = b.new_page(viewport={"width": 1920, "height": 1080})
    for src in sys.argv[1:]:
        pg.goto("file://" + src, wait_until="networkidle")
        pg.evaluate("document.fonts.ready")
        pg.wait_for_timeout(600)
        ok = pg.evaluate("document.fonts.check('800 64px Inter') && document.fonts.check('500 16px \"JetBrains Mono\"')")
        over = pg.evaluate("[...document.querySelectorAll('.node, .stat, .note')].filter(e => e.getBoundingClientRect().bottom > 1030 || e.getBoundingClientRect().right > 1830).length")
        out = src[:-5] + ".png"
        pg.screenshot(path=out)
        print(out.split('/')[-1], "| fonts ok:", ok, "| elements past margins:", over)
    b.close()
