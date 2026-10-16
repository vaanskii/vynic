# Inline timeline.js into index.html (HyperFrames lint requires the timeline registry inline).
import pathlib, re
root = pathlib.Path(__file__).resolve().parent.parent
html = (root / "index.html").read_text(encoding="utf-8")
js = (root / "timeline.js").read_text(encoding="utf-8")
start, end = "<script>\n", "\n    </script>\n  </body>"
a = html.rindex(start) + len(start); b = html.rindex(end)
(root / "index.html").write_text(html[:a] + js.rstrip("\n") + html[b:], encoding="utf-8")
print("inlined timeline.js →", len(js.splitlines()), "lines")
