"""Mide el FPS del build web con la GPU real.

Usa Chrome headless con ANGLE/D3D11. Si el navegador cae a render por software
(SwiftShader, llvmpipe) aborta: ese FPS no representa la GPU del usuario.

    python tools/web_bench.py [--url URL] [--seconds N]
"""

import argparse
import json
import sys

try:
    from playwright.sync_api import sync_playwright
except ImportError:
    print("Falta playwright-core: pip install playwright-core")
    sys.exit(2)

SOFTWARE_MARKERS = ("swiftshader", "llvmpipe", "software", "basic render")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", default="http://127.0.0.1:8060/index.html")
    parser.add_argument("--seconds", type=int, default=20)
    parser.add_argument("--headed", action="store_true")
    args = parser.parse_args()

    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(
            headless=not args.headed,
            args=[
                "--use-gl=angle",
                "--use-angle=d3d11",
                "--ignore-gpu-blocklist",
                "--enable-gpu-rasterization",
            ],
        )
        page = browser.new_page(viewport={"width": 1280, "height": 720})
        page.goto(args.url, wait_until="domcontentloaded", timeout=120000)

        renderer = page.evaluate(
            """() => {
                const canvas = document.querySelector('canvas');
                if (!canvas) return '';
                const gl = canvas.getContext('webgl2') || canvas.getContext('webgl');
                if (!gl) return '';
                const ext = gl.getExtension('WEBGL_debug_renderer_info');
                return ext ? gl.getParameter(ext.UNMASKED_RENDERER_WEBGL) : gl.getParameter(gl.RENDERER);
            }"""
        )
        print("RENDERER:", renderer or "(desconocido)")
        if not renderer:
            print("ABORT: no se pudo leer el renderer WebGL")
            browser.close()
            sys.exit(3)
        lowered = renderer.lower()
        if any(marker in lowered for marker in SOFTWARE_MARKERS):
            print("ABORT: el navegador esta usando render por software (%s)" % renderer)
            browser.close()
            sys.exit(3)

        ready = False
        for _ in range(60):
            page.wait_for_timeout(2000)
            state = page.evaluate("() => window.__rito || null")
            if state and state.get("ready"):
                ready = True
                break
        if not ready:
            print("ABORT: el juego no quedo listo")
            browser.close()
            sys.exit(4)

        page.wait_for_timeout(3000)
        samples = []
        for _ in range(args.seconds):
            page.wait_for_timeout(1000)
            value = page.evaluate("() => window.__rito ? window.__rito.fps : 0")
            if value:
                samples.append(float(value))
        state = page.evaluate("() => ({...window.__rito})")
        samples.sort()
        median = samples[len(samples) // 2] if samples else 0.0
        print("WEBBENCH samples=%d median_fps=%.1f min=%.1f max=%.1f state=%s"
              % (len(samples), median, samples[0] if samples else 0,
                 samples[-1] if samples else 0, json.dumps(state)))
        browser.close()


if __name__ == "__main__":
    main()
