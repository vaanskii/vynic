// Vynic launch film · fast-motion refine (32.2 s, 120 bpm grid: beat = 0.5 s).
// One world, one camera, one paused timeline. Scene map: STYLE_NOTES.md. Inlined into index.html by tools/inline.py.
(function () {
  const W = 1920, H = 1080, END = 32.2;
  const world = document.getElementById("world");
  const tl = gsap.timeline({ paused: true });

  /* ---------- camera ---------- */
  const cam = { x: 2300, y: 1130, s: 1.3 };
  function applyCamera() {
    world.style.transform = "translate(" + (W / 2 - cam.s * cam.x).toFixed(2) + "px," + (H / 2 - cam.s * cam.y).toFixed(2) + "px) scale(" + cam.s.toFixed(4) + ")";
  }
  applyCamera();
  const CAM = {
    open: { x: 2300, y: 1130, s: 1.3 },
    openIn: { x: 2300, y: 1130, s: 1.38 },
    mark: { x: 2610, y: 1130, s: 1.0 },
    posWide: { x: 1270, y: 1165, s: 0.62 },
    pos: { x: 1270, y: 1165, s: 0.95 },
    t4: { x: 1398, y: 1160, s: 2.6 },
    found: { x: 2600, y: 1000, s: 1.0 },
    mgr: { x: 3030, y: 700, s: 1.0 },
    saas: { x: 3450, y: 1829, s: 0.82 },
    saasIn: { x: 3450, y: 1829, s: 0.86 },
    eco: { x: 2660, y: 1290, s: 0.44 },
    lock: { x: 2510, y: 1130, s: 1.1 },
    lockIn: { x: 2510, y: 1130, s: 1.14 },
  };
  const camTo = (t, at, dur, ease) => tl.to(cam, { x: t.x, y: t.y, s: t.s, duration: dur, ease: ease || "power3.inOut", onUpdate: applyCamera }, at);
  const camCut = (t, at) => tl.to(cam, { x: t.x, y: t.y, s: t.s, duration: 0.001, ease: "none", onUpdate: applyCamera }, at);
  // screen position of a world point for a given camera
  const scr = (c, x, y) => [W / 2 + c.s * (x - c.x), H / 2 + c.s * (y - c.y)];

  /* ---------- helpers ---------- */
  const fmt = (n, d) => n.toLocaleString("en-US", { minimumFractionDigits: d === undefined ? 2 : d, maximumFractionDigits: d === undefined ? 2 : d });
  function counter(el, from, to, at, dur, render) {
    const p = { v: from };
    tl.fromTo(p, { v: from }, { v: to, duration: dur, ease: "power3.out", immediateRender: false, onUpdate: () => { el.textContent = render ? render(p.v) : fmt(p.v); } }, at);
  }
  function along(pts) {
    const seg = [], total = [0];
    for (let i = 1; i < pts.length; i++) { const d = Math.hypot(pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1]); seg.push(d); total.push(total[i - 1] + d); }
    const len = total[total.length - 1];
    return (p) => {
      const d = Math.max(0, Math.min(1, p)) * len;
      let i = 1; while (i < total.length - 1 && total[i] < d) i++;
      const k = seg[i - 1] ? (d - total[i - 1]) / seg[i - 1] : 0;
      return [pts[i - 1][0] + (pts[i][0] - pts[i - 1][0]) * k, pts[i - 1][1] + (pts[i][1] - pts[i - 1][1]) * k];
    };
  }
  function travel(sel, pts, at, dur, ease) {
    const el = document.querySelector(sel), path = along(pts), p = { t: 0 };
    tl.fromTo(p, { t: 0 }, { t: 1, duration: dur, ease: ease || "power2.inOut", immediateRender: false,
      onUpdate: () => { const q = path(p.t); gsap.set(el, { x: q[0], y: q[1] }); } }, at);
  }
  function scrollPage(pageSel, viewTop, viewH) {
    const page = document.querySelector(pageSel);
    const items = Array.from(page.querySelectorAll(".cull")).map((el) => ({ el, top: el.offsetTop, bottom: el.offsetTop + el.offsetHeight }));
    const cull = () => {
      const S = -gsap.getProperty(page, "y");
      for (const it of items) it.el.style.visibility = (it.bottom < S + viewTop || it.top > S + viewH) ? "hidden" : "visible";
    };
    cull();
    return (y, at, dur, ease) => tl.to(page, { y, duration: dur, ease, onUpdate: cull }, at);
  }
  // offset of el inside an ancestor (layout units, measured once at setup)
  function offsetIn(el, anc) {
    let x = 0, y = 0, n = el;
    while (n && n !== anc) { x += n.offsetLeft; y += n.offsetTop; n = n.offsetParent; }
    return [x, y];
  }
  const tap = (rip, at) => tl.fromTo(rip, { opacity: 0.85, scale: 0.25 }, { opacity: 0, scale: 1.6, duration: 0.5, ease: "power2.out", immediateRender: false }, at);
  const tapFx = (sel, at) => tl.fromTo(sel, { opacity: 0 }, { opacity: 1, duration: 0.09, ease: "power2.out", yoyo: true, repeat: 1, immediateRender: false }, at);
  // colour hit: a full field opens as a circle from (x, y); cut = instant (under a cover)
  const hit = (sel, at, x, y, dur) => tl.fromTo(sel, { clipPath: "circle(0px at " + x + "px " + y + "px)" }, { clipPath: "circle(2300px at " + x + "px " + y + "px)", duration: dur || 0.5, ease: "expo.inOut" }, at);
  const cut = (sel, at) => tl.set(sel, { clipPath: "circle(2300px at 960px 540px)" }, at);
  const DARK = "rgb(18, 16, 18)", LIGHT = "rgba(242, 238, 231, 0.9)";
  const tone = (c, at) => { tl.to("#hud", { color: c, duration: 0.18, ease: "none" }, at); tl.to("#fx-grid", { color: c, duration: 0.18, ease: "none" }, at); };
  // kinetic words: lines rise out of their masks; out = they leave upward
  // (inactive words are hidden outright so nothing masked counts as on screen)
  function kwIn(sel, at, st) {
    tl.set(sel, { autoAlpha: 1 }, at);
    tl.fromTo(sel + " .l > span", { yPercent: 108 }, { yPercent: 0, duration: 0.5, ease: "expo.out", stagger: st === undefined ? 0.06 : st }, at);
  }
  function kwOut(sel, at) {
    tl.to(sel + " .l > span", { yPercent: -108, duration: 0.32, ease: "power3.in", stagger: 0.03 }, at);
    tl.set(sel, { autoAlpha: 0 }, at + 0.42);
  }
  // HUD section label
  let secNow = 0;
  function sec(n, at) {
    tl.to("#sec-" + secNow, { yPercent: -110, duration: 0.25, ease: "power3.in" }, at);
    tl.fromTo("#sec-" + n, { yPercent: 110 }, { yPercent: 0, duration: 0.3, ease: "expo.out" }, at + 0.12);
    secNow = n;
  }
  gsap.set("#secs span", { yPercent: 110 }); gsap.set("#sec-0", { yPercent: 0 });
  // data card: expands from a UI element's screen rect (FLIP), later collapses back into it
  function rectOf(el) { return { x: parseFloat(el.style.left), y: parseFloat(el.style.top), w: parseFloat(el.style.width), h: parseFloat(el.style.height) }; }
  function cardFrom(sel, src) { const t = rectOf(document.querySelector(sel)); return { x: src.x - t.x, y: src.y - t.y, scaleX: src.w / t.w, scaleY: src.h / t.h }; }
  function expand(sel, src, at) {
    tl.set("#fx-type .l.o", { autoAlpha: 0 }, at);   // the outline echoes sit behind the card
    tl.set(sel, { opacity: 1 }, at);
    tl.fromTo(sel, cardFrom(sel, src), { x: 0, y: 0, scaleX: 1, scaleY: 1, duration: 0.42, ease: "expo.inOut", immediateRender: false }, at);
    tl.fromTo(sel + " .in", { opacity: 0, y: 16 }, { opacity: 1, y: 0, duration: 0.3, ease: "power2.out" }, at + 0.28);
  }
  function collapse(sel, src, at) {
    tl.to(sel + " .in", { opacity: 0, duration: 0.12, ease: "power1.in" }, at);
    tl.to(sel, Object.assign(cardFrom(sel, src), { duration: 0.32, ease: "power3.in" }), at + 0.06);
    tl.set(sel, { opacity: 0 }, at + 0.38);
    tl.set("#fx-type .l.o", { autoAlpha: 1 }, at + 0.38);
  }

  /* ---------- setup (layout measured once) ---------- */
  // rings: 90 ticks, a long lime one every 30°
  const ticks = document.getElementById("r-ticks");
  for (let k = 0; k < 90; k++) {
    const a = (k * 4 * Math.PI) / 180, long = k % 15 === 0, r0 = long ? 290 : 298, r1 = 312;
    const ln = document.createElementNS("http://www.w3.org/2000/svg", "line");
    ln.setAttribute("x1", (400 + r0 * Math.sin(a)).toFixed(1)); ln.setAttribute("y1", (400 - r0 * Math.cos(a)).toFixed(1));
    ln.setAttribute("x2", (400 + r1 * Math.sin(a)).toFixed(1)); ln.setAttribute("y2", (400 - r1 * Math.cos(a)).toFixed(1));
    ln.setAttribute("stroke-width", long ? "3" : "1.5");
    if (long) ln.setAttribute("style", "stroke: #d5f24b");
    ln.setAttribute("opacity", long ? "1" : "0.45");
    ticks.appendChild(ln);
  }
  tl.to("#r-ticks", { rotation: 60, svgOrigin: "400 400", duration: END, ease: "none" }, 0);
  tl.to("#r-orb1", { rotation: 300, svgOrigin: "400 400", duration: END, ease: "none" }, 0);
  tl.to("#r-orb2", { rotation: -420, svgOrigin: "400 400", duration: END, ease: "none" }, 0);
  tl.set("#wipe-type", { x: 1920 }, 0);
  // capsule starts where it enters the foundation scene
  tl.set("#token", { x: 1560, y: 1130 }, 0);
  // Custom sits exactly on top of SaaS (the split wipe reveals it); its menu is in view
  gsap.set("#vk", { x: -1700 });
  gsap.set("#vk-page", { y: -834 });
  const editor = document.getElementById("p-editor");
  const flyFrom = [document.getElementById("tile-1"), document.getElementById("tile-2"), document.getElementById("tile-3")].map((t) => offsetIn(t, editor));
  const flyTo = ["line-1", "line-2", "line-3"].map((id) => offsetIn(document.getElementById(id), editor));
  // Manager source rects (screen, camera fixed at CAM.mgr): revenue card and receiving summary
  const phoneScreen = [3212, 272];
  const scrRect = (el, anc, dy) => { const o = offsetIn(el, anc), p = scr(CAM.mgr, phoneScreen[0] + o[0], phoneScreen[1] + o[1] + (dy || 0)); return { x: p[0], y: p[1], w: el.offsetWidth, h: el.offsetHeight }; };
  const screenEl = document.querySelector("#phone .screen");
  const revCard = document.querySelectorAll("#m-scroll .m-card")[1];
  const srcRev = scrRect(revCard, screenEl); // offsets include m-dash (top 48) and m-scroll (top -48)
  const srcSum = scrRect(document.querySelector("#m-recv .r-sum"), screenEl);
  // the split wipe overlaps the two menus on purpose (clip-path reveals one over the other)
  document.querySelectorAll("#saas-page .s-menu *, #vk-page .v-menu *").forEach((el) => el.setAttribute("data-layout-allow-overlap", ""));
  // dish landing spot inside the Custom menu (world)
  const vkPage = document.getElementById("vk-page"), row1 = document.getElementById("vk-row1");
  const rowIn = offsetIn(row1, vkPage);
  const rowWorld = [2750 + rowIn[0], 1450 + 46 + rowIn[1] - 834];
  const dishTo = [rowWorld[0] - 2860, rowWorld[1] - 1764];

  /* ---------- running layers: timecode, progress, grain ---------- */
  const tcEl = document.getElementById("tc"), grain = document.getElementById("fx-grain");
  const pad = (n) => String(n).padStart(2, "0");
  const clock = { t: 0 };
  tl.fromTo(clock, { t: 0 }, { t: END, duration: END, ease: "none", immediateRender: false, onUpdate: () => {
    const f = Math.round(clock.t * 30), s = Math.floor(f / 30), k = Math.floor(f / 2);
    tcEl.textContent = "00:" + pad(Math.floor(s / 60)) + ":" + pad(s % 60) + ":" + pad(f % 30);
    grain.style.transform = "translate(" + ((k * 73) % 64) + "px," + ((k * 151) % 64) + "px)";
  } }, 0);
  tl.fromTo("#hud-prog-i", { scaleX: 0 }, { scaleX: 1, duration: END, ease: "none" }, 0);

  /* ================= 1 · OPEN (0 – 2.5): stroke → pulse → plum hit → wordmark → stroke becomes the terminal ================= */
  tl.from("#hud .br", { scale: 0.4, opacity: 0, duration: 0.35, ease: "expo.out", stagger: 0.04 }, 0);
  tl.from("#hud .lab, #hud-prog", { opacity: 0, duration: 0.3, stagger: 0.03 }, 0.1);
  camTo(CAM.openIn, 0, 1.0, "sine.out");
  tl.fromTo(".v-thick", { strokeDashoffset: 1 }, { strokeDashoffset: 0, duration: 0.32, ease: "power3.inOut" }, 0.08);
  tl.fromTo(".v-thin", { strokeDashoffset: 1 }, { strokeDashoffset: 0, duration: 0.26, ease: "power3.out" }, 0.34);
  // sharp graphic pulse
  tl.set("#rings", { opacity: 1 }, 0.55);
  tl.fromTo("#r-pulse", { attr: { r: 130 }, opacity: 1 }, { attr: { r: 380 }, opacity: 0, duration: 0.55, ease: "expo.out" }, 0.55);
  tl.from(["#r-a", "#r-b", "#r-c"], { scale: 0.6, opacity: 0, svgOrigin: "400 400", duration: 0.5, ease: "expo.out", stagger: 0.04 }, 0.56);
  tl.from("#r-ticks line", { opacity: 0, duration: 0.02, stagger: 0.003 }, 0.58);
  // colour hit: plum from the V
  hit("#bg-plum", 1.0, 960, 540, 0.45);
  tl.to("#rings", { color: "#f2eee7", duration: 0.1 }, 1.0);
  // wordmark snaps out beside the V
  camTo(CAM.mark, 1.05, 0.5, "expo.out");
  tl.set("#wordmark", { autoAlpha: 1 }, 1.1);
  tl.fromTo("#wordmark-text", { opacity: 0, x: -60, filter: "blur(10px)" }, { opacity: 1, x: 0, filter: "blur(0px)", duration: 0.4, ease: "expo.out" }, 1.1);
  tl.to("#fx-grid", { opacity: 0.1, duration: 0.3 }, 1.2);
  // the thick stroke keeps going: it traces the terminal while the camera pulls wide
  tl.to("#wordmark-text", { opacity: 0, x: 40, duration: 0.2, ease: "power2.in" }, 1.85);
  tl.set("#wordmark", { autoAlpha: 0 }, 2.06);
  tl.to("#rings", { opacity: 0, duration: 0.3, ease: "power2.in" }, 1.95);
  tl.to("#hub", { opacity: 0, duration: 0.2, ease: "power2.in" }, 2.35);
  camTo(CAM.posWide, 1.9, 0.62, "power3.inOut");
  tl.set("#v-trace-a", { opacity: 1 }, 1.95);
  tl.fromTo("#v-trace-a", { strokeDashoffset: 1 }, { strokeDashoffset: 0, duration: 0.6, ease: "power2.inOut" }, 1.95);
  tl.set("#v-trace-b", { opacity: 1 }, 2.05);
  tl.fromTo("#v-trace-b", { strokeDashoffset: 1 }, { strokeDashoffset: 0, duration: 0.5, ease: "power2.inOut" }, 2.05);
  // colour hit: warm paper from the terminal; the terminal fills in and the camera pushes in
  const posC = scr(CAM.posWide, 1270, 1160);
  hit("#bg-paper", 2.5, posC[0].toFixed(0), posC[1].toFixed(0), 0.45);
  tone(DARK, 2.55);
  tl.fromTo(["#pos", "#pos-stand"], { opacity: 0 }, { opacity: 1, duration: 0.2, ease: "power2.out" }, 2.5);
  tl.to(["#v-trace-a", "#v-trace-b"], { opacity: 0, duration: 0.2 }, 2.62);
  camTo(CAM.pos, 2.55, 0.5, "expo.out");
  sec(1, 2.6);

  /* ================= 2 · POS (2.5 – 6.9): table → order → items → total → confirm → occupied ================= */
  tl.to(".canvas .tbl:not(#t4), .canvas .obj", { opacity: 0.5, duration: 0.2, ease: "sine.inOut" }, 2.95);
  tl.fromTo("#t4-ring", { opacity: 0, scale: 1.12 }, { opacity: 1, scale: 1, duration: 0.25, ease: "expo.out" }, 2.95);
  tap("#rip-t4", 3.2);
  tl.to("#p-floorview", { autoAlpha: 0, duration: 0.14, ease: "power2.in" }, 3.3);
  tl.set(".canvas .tbl:not(#t4), .canvas .obj", { opacity: 1 }, 3.5);
  tl.set("#p-editor", { autoAlpha: 1 }, 3.36);
  tl.fromTo("#p-editor", { opacity: 0, x: 40 }, { opacity: 1, x: 0, duration: 0.3, ease: "expo.out", immediateRender: false }, 3.36);
  const tSum = document.getElementById("t-sum"), tSvc = document.getElementById("t-svc"), tTotal = document.getElementById("t-total"), tCount = document.getElementById("t-count");
  const items = [
    { at: 3.9, rip: "#rip-1", tile: "#tile-1", line: "#line-1", fly: "#fly-1", from: 0, to: 22, n: 1 },
    { at: 4.35, rip: "#rip-2", tile: "#tile-2", line: "#line-2", fly: "#fly-2", from: 22, to: 36, n: 2 },
    { at: 4.8, rip: "#rip-3", tile: "#tile-3", line: "#line-3", fly: "#fly-3", from: 36, to: 42, n: 3 },
  ];
  items.forEach((it, i) => {
    tap(it.rip, it.at);
    tl.fromTo(it.tile + " .flash", { opacity: 1 }, { opacity: 0, duration: 0.4, ease: "power2.out", immediateRender: false }, it.at);
    // the item flies from its tile into the order (a small arc), then becomes the order line
    const a = [flyFrom[i][0] + 20, flyFrom[i][1] + 26], b = [flyTo[i][0], flyTo[i][1] + 4];
    tl.set(it.fly, { x: a[0], y: a[1] }, 0);
    tl.set(it.fly, { opacity: 1 }, it.at + 0.02);
    travel(it.fly, [a, [(a[0] + b[0]) / 2, Math.min(a[1], b[1]) - 60], b], it.at + 0.02, 0.3, "power3.inOut");
    tl.set(it.fly, { opacity: 0 }, it.at + 0.33);
    tl.fromTo(it.line, { opacity: 0, x: -14 }, { opacity: 1, x: 0, duration: 0.22, ease: "power3.out" }, it.at + 0.3);
    counter(tSum, it.from, it.to, it.at + 0.3, 0.3);
    counter(tSvc, it.from * 0.1, it.to * 0.1, it.at + 0.3, 0.3);
    counter(tTotal, it.from * 1.1, it.to * 1.1, it.at + 0.3, 0.3, (v) => fmt(v) + " ₾");
    counter(tCount, it.n - 1, it.n, it.at + 0.3, 0.12, (v) => String(Math.round(v)));
  });
  tl.fromTo("#t-total", { scale: 1 }, { scale: 1.12, duration: 0.12, ease: "power2.out", yoyo: true, repeat: 1, transformOrigin: "100% 50%", immediateRender: false }, 5.12);
  tl.to("#o-go", { scale: 0.97, duration: 0.07, ease: "power2.in" }, 5.4);
  tl.to("#o-go", { scale: 1, duration: 0.25, ease: "expo.out" }, 5.475);
  tl.set("#o-go .c1", { autoAlpha: 0 }, 5.47);
  tl.fromTo("#o-go .c2", { opacity: 0 }, { opacity: 1, duration: 0.15, ease: "power2.out" }, 5.47);
  tl.to("#p-editor", { autoAlpha: 0, duration: 0.16, ease: "power2.in" }, 5.85);
  tl.to("#p-floorview", { autoAlpha: 1, duration: 0.18, ease: "power2.out" }, 5.95);
  tl.set("#t4 .surf.before", { autoAlpha: 0 }, 6.02);
  tl.to("#t4 .surf.after", { opacity: 1, duration: 0.2, ease: "power2.out" }, 6.02);
  tl.fromTo("#t4", { scale: 1.08 }, { scale: 1, duration: 0.35, ease: "expo.out", immediateRender: false }, 6.02);
  tl.to(".kpi b.sw .a", { opacity: 0, duration: 0.12 }, 6.1);
  tl.to(".kpi b.sw .b", { opacity: 1, duration: 0.18 }, 6.14);
  // fast push into Table 4 …
  camTo(CAM.t4, 6.35, 0.6, "expo.in");

  /* ---- type wipe: signal-orange panel carries the words, the scene changes underneath ---- */
  tl.fromTo("#wipe-type", { x: 1920 }, { x: 0, duration: 0.34, ease: "power4.inOut" }, 6.72);
  kwIn("#kw-fast", 6.9, 0.08);
  tl.from("#wipe-type .tick", { opacity: 0, x: 30, duration: 0.3, ease: "expo.out" }, 6.95);
  // under the cover: dark foundation
  cut("#bg-ink", 7.1);
  tone(LIGHT, 7.1);
  camCut(CAM.found, 7.1);
  tl.set(["#pos", "#pos-stand"], { opacity: 0 }, 7.1);
  tl.set(["#hub", "#rings"], { opacity: 1 }, 7.1);
  tl.set("#hub-tile", { opacity: 1 }, 7.1);
  sec(2, 7.4);
  tl.to("#wipe-type", { x: -1920, duration: 0.36, ease: "power4.inOut" }, 7.62);
  tl.to("#kw-fast", { x: -700, duration: 0.36, ease: "power4.inOut" }, 7.6);

  /* ================= 3 · ONE SYSTEM (7.6 – 10.6): the order docks, the number becomes data ================= */
  tl.fromTo("#token", { opacity: 0, scale: 0.8 }, { opacity: 1, scale: 1, duration: 0.2, ease: "power2.out" }, 7.75);
  travel("#token", [[1560, 1130], [2300, 1130]], 7.75, 0.55, "power3.in");
  tl.to("#token", { opacity: 0, scale: 0.4, duration: 0.1, ease: "power1.in" }, 8.28);
  // dock: the mark answers
  tl.fromTo("#r-pulse", { attr: { r: 130 }, opacity: 1 }, { attr: { r: 330 }, opacity: 0, duration: 0.45, ease: "expo.out", immediateRender: false }, 8.3);
  tl.fromTo("#hub", { scale: 1.08 }, { scale: 1, duration: 0.35, ease: "expo.out", immediateRender: false }, 8.3);
  tl.fromTo("#record", { opacity: 0, y: 220, scale: 0.5 }, { opacity: 1, y: 0, scale: 1, duration: 0.42, ease: "expo.out" }, 8.4);
  tl.fromTo("#row-orders .hl", { opacity: 0 }, { opacity: 1, duration: 0.2, ease: "power2.out" }, 8.7);
  tl.to("#row-orders .st-idle", { opacity: 0, duration: 0.12 }, 8.7);
  tl.fromTo("#row-orders .st-ok", { opacity: 0, y: 8 }, { opacity: 1, y: 0, duration: 0.25, ease: "power3.out" }, 8.72);
  // big number: the order total, itemised
  tl.set("#bn", { opacity: 1 }, 8.55);
  tl.from("#bn .dk", { opacity: 0, x: 40, duration: 0.3, ease: "expo.out" }, 8.55);
  tl.from("#bn-num", { opacity: 0, x: 80, duration: 0.35, ease: "expo.out" }, 8.6);
  counter(document.getElementById("bn-v"), 0, 46.2, 8.6, 0.6);
  tl.from("#bn-rows .r", { opacity: 0, x: 40, duration: 0.25, ease: "expo.out", stagger: 0.07 }, 8.8);
  tl.from("#bn-rows", { borderTopColor: "rgba(242, 238, 231, 0)", duration: 0.2 }, 8.8);
  // the system reaches out: lines to Manager and web, one pulse
  tl.to(["#lb-mgr", "#lb-web", "#l-mgr", "#l-web"], { opacity: 1, duration: 0.1 }, 9.5);
  tl.fromTo(["#l-mgr", "#l-web"], { strokeDashoffset: 1 }, { strokeDashoffset: 0, duration: 0.35, ease: "power3.inOut", stagger: 0.08 }, 9.5);
  tl.to("#p-mgr", { opacity: 1, duration: 0.05 }, 10.0);
  tl.fromTo("#p-mgr", { strokeDashoffset: 0.05 }, { strokeDashoffset: -1, duration: 0.7, ease: "power2.in", immediateRender: false }, 10.0);
  tl.to("#p-mgr", { opacity: 0, duration: 0.05 }, 10.7);

  /* ---- whip to Manager along the line; the total flies into the revenue card ---- */
  tl.to(["#bn .dk", "#bn-rows"], { opacity: 0, x: -60, duration: 0.2, ease: "power2.in" }, 10.1);
  // #bn-num: left 1080, vertical centre ≈ 408 (scaled from its left-middle) → the revenue figure inside the card
  tl.to("#bn-num", { x: srcRev.x + 18 - 1080, y: srcRev.y + 61 - 408, scale: 0.21, duration: 0.62, ease: "power4.inOut" }, 10.2);
  tl.to("#bn-num", { opacity: 0, duration: 0.12 }, 10.78);
  tl.set("#phone", { opacity: 1 }, 10.1);
  camTo(CAM.mgr, 10.15, 0.62, "power4.inOut");
  tl.set(["#hub", "#record", "#rings", "#links"], { opacity: 0 }, 10.8);
  hit("#bg-signal", 10.4, 1340, 540, 0.45);
  tone(DARK, 10.55);
  sec(3, 10.6);

  /* ================= 4 · MANAGER (10.6 – 19.2): update → numbers respond → Inventory → receiving → stock ================= */
  kwIn("#kw-sales", 10.75);
  tl.to("#m-scroll", { y: 48, duration: 0.2, ease: "power2.out" }, 10.85);
  tl.fromTo("#m-spin", { opacity: 0, rotation: 0 }, { opacity: 1, rotation: 220, duration: 0.3, ease: "none" }, 10.85);
  tl.to("#m-spin", { opacity: 0, rotation: 330, duration: 0.15, ease: "power1.in" }, 11.15);
  tl.to("#m-scroll", { y: 0, duration: 0.28, ease: "expo.out" }, 11.1);
  counter(document.getElementById("m-rev"), 2868.65, 2914.85, 11.2, 0.5);
  counter(document.getElementById("m-open"), 1586.2, 1632.4, 11.2, 0.45);
  tl.to(".m-row.open .o1", { opacity: 0, duration: 0.12 }, 11.2);
  tl.to(".m-row.open .o2", { opacity: 1, duration: 0.18 }, 11.24);
  // the revenue card expands into a big data card, then folds back into the app
  expand("#dc-a", srcRev, 11.75);
  counter(document.getElementById("dc-a-num"), 2868.65, 2914.85, 12.05, 0.55);
  tl.fromTo(["#dc-a-b1", "#dc-a-b2"], { scaleX: 0 }, { scaleX: 1, duration: 0.4, ease: "expo.out", stagger: 0.12 }, 12.15);
  collapse("#dc-a", srcRev, 13.25);
  // to Inventory, inside the same phone
  tl.to("#m-scroll", { y: -330, duration: 0.3, ease: "power3.inOut" }, 13.7);
  tapFx("#tap-open", 14.02);
  tl.to("#m-dash", { x: -50, opacity: 0, duration: 0.18, ease: "power2.in" }, 14.1);
  tl.to("#m-pill", { x: 177, duration: 0.3, ease: "expo.inOut" }, 14.1);
  tl.to(".m-nav > i:nth-of-type(1)", { opacity: 1, duration: 0.2 }, 14.2);
  tl.to(".m-nav > i:nth-of-type(4)", { opacity: 0, duration: 0.15 }, 14.2);
  tl.set("#m-inv", { autoAlpha: 1 }, 14.22);
  tl.fromTo("#m-inv", { x: 50, opacity: 0 }, { x: 0, opacity: 1, duration: 0.28, ease: "expo.out", immediateRender: false }, 14.22);
  kwOut("#kw-sales", 14.05);
  kwIn("#kw-stock", 14.25);
  sec(4, 14.2);
  // receiving: review → big cards (stock added, supplier debt) → back → confirm
  tapFx("#tap-add", 14.75);
  tl.set("#m-recv", { autoAlpha: 1 }, 14.85);
  tl.fromTo("#m-recv", { y: 856 }, { y: 0, duration: 0.34, ease: "expo.out", immediateRender: false }, 14.85);
  tl.to("#m-inv", { opacity: 0, duration: 0.2, ease: "power1.in" }, 14.85);
  kwOut("#kw-stock", 14.8);
  kwIn("#kw-recv", 15.02);
  tl.fromTo("#r-debt", { boxShadow: "0 0 0 0 rgba(245, 158, 11, 0)" }, { boxShadow: "0 0 0 3px rgba(245, 158, 11, 0.6)", duration: 0.2, ease: "power2.out", yoyo: true, repeat: 1 }, 15.25);
  expand("#dc-b1", srcSum, 15.45);
  expand("#dc-b2", srcSum, 15.55);
  counter(document.getElementById("dc-b1-num"), 0, 20, 15.75, 0.5, (v) => fmt(v, 3));
  counter(document.getElementById("dc-b2-num"), 0, 30, 15.85, 0.5);
  tl.fromTo("#dc-b2-bar", { scaleX: 0 }, { scaleX: 1, duration: 0.4, ease: "expo.out" }, 15.95);
  collapse("#dc-b1", srcSum, 16.95);
  collapse("#dc-b2", srcSum, 17.0);
  tapFx("#tap-go", 17.45);
  tl.to("#m-recv", { y: 856, duration: 0.28, ease: "power3.in" }, 17.55);
  tl.set("#m-recv", { autoAlpha: 0 }, 17.84);
  tl.to("#m-inv", { opacity: 1, duration: 0.2, ease: "power1.out" }, 17.6);
  counter(document.getElementById("inv-today"), 0, 60, 17.8, 0.4, (v) => fmt(v) + " ₾");
  tl.to(".i-chip .lo2", { opacity: 0, y: -8, duration: 0.14, ease: "power2.in" }, 17.82);
  tl.fromTo(".i-chip .lo1", { opacity: 0, y: 8 }, { opacity: 1, y: 0, duration: 0.2, ease: "power3.out" }, 17.9);
  tl.to("#inv-empty", { opacity: 0, duration: 0.1 }, 17.8);
  tl.fromTo("#inv-rcpt", { opacity: 0, y: 14 }, { opacity: 1, y: 0, duration: 0.3, ease: "expo.out" }, 17.85);
  // stock balances
  tapFx("#tap-stock", 18.3);
  tl.to("#m-inv", { x: -50, opacity: 0, duration: 0.18, ease: "power2.in" }, 18.42);
  tl.set("#m-stock", { autoAlpha: 1 }, 18.52);
  tl.fromTo("#m-stock", { x: 50, opacity: 0 }, { x: 0, opacity: 1, duration: 0.28, ease: "expo.out", immediateRender: false }, 18.52);
  tl.fromTo("#s-flour", { boxShadow: "0 0 0 0 rgba(16, 185, 129, 0)" }, { boxShadow: "0 0 0 3px rgba(16, 185, 129, 0.55)", duration: 0.22, ease: "power2.out", yoyo: true, repeat: 1 }, 18.75);
  kwOut("#kw-recv", 18.4);
  kwIn("#kw-bal", 18.62);

  /* ---- scale-through: the phone screen opens into the web scene ---- */
  const ph = scr(CAM.mgr, 3212, 272);
  tl.set("#wipe-scale", { opacity: 1, backgroundColor: "#e3edfc", x: ph[0], y: ph[1], scaleX: 396 / W, scaleY: 856 / H, borderRadius: "252px / 66px" }, 19.2);
  tl.to("#wipe-scale", { x: 0, y: 0, scaleX: 1, scaleY: 1, borderRadius: "0px / 0px", backgroundColor: "#f2eee7", duration: 0.46, ease: "expo.inOut" }, 19.2);
  kwOut("#kw-bal", 19.15);
  // under the cover: the web scene
  cut("#bg-paper2", 19.66);
  camCut(CAM.saas, 19.66);
  tl.set("#phone", { opacity: 0 }, 19.66);
  tl.set("#saas", { opacity: 1 }, 19.66);
  tl.fromTo("#saas", { scale: 1.16, transformOrigin: "50% 50%" }, { scale: 1, duration: 0.5, ease: "expo.out", immediateRender: false }, 19.66);
  tl.set("#wipe-scale", { opacity: 0 }, 19.68);
  sec(5, 19.7);

  /* ================= 5 · WEB (19.7 – 27.2): content → ready-made site → same data restyled as Custom ================= */
  kwIn("#kw-web", 19.8);
  const saasScroll = scrollPage("#saas-page", 68, 834);
  saasScroll(-1816, 20.2, 1.15, "expo.inOut");
  tapFx("#tap-nav", 21.45);
  saasScroll(-860, 21.55, 0.5, "expo.out");
  kwOut("#kw-web", 22.0);
  kwIn("#kw-menu", 22.22);
  // the shared menu line is annotated: dish, price
  tl.fromTo("#anchor", { opacity: 0, scale: 1.08 }, { opacity: 1, scale: 1, duration: 0.25, ease: "expo.out" }, 22.2);
  tl.from("#anchor .t", { y: 12, opacity: 0, duration: 0.25, ease: "expo.out", stagger: 0.08 }, 22.3);
  tl.set("#dish", { autoAlpha: 1 }, 22.7);
  tl.set("#saas-dish", { opacity: 0 }, 22.72);
  tl.fromTo("#dish", { y: 0, scale: 1, boxShadow: "0 0 0 rgba(0,0,0,0)" }, { y: -12, scale: 1.05, boxShadow: "0 26px 50px rgba(0,0,0,0.3)", duration: 0.3, ease: "expo.out" }, 22.72);
  // split wipe: the Custom design sweeps across the same content (lime edge)
  tl.set("#vk", { opacity: 1 }, 23.1);
  tl.set("#edge", { opacity: 1 }, 23.1);
  tl.fromTo("#vk", { clipPath: "inset(0px 0px 0px 1400px)" }, { clipPath: "inset(0px 0px 0px 0px)", duration: 1.2, ease: "power3.inOut", immediateRender: false }, 23.1);
  tl.fromTo("#edge", { x: 0 }, { x: -1400, duration: 1.2, ease: "power3.inOut", immediateRender: false }, 23.1);
  tl.to("#dish .dc-vk", { opacity: 1, duration: 0.18, ease: "sine.inOut" }, 23.78);
  tl.to("#edge", { opacity: 0, duration: 0.15 }, 24.3);
  tl.set("#saas", { opacity: 0 }, 24.32);
  kwOut("#kw-menu", 23.9);
  kwIn("#kw-two", 24.12);
  sec(6, 24.0);
  // the dish settles into the Custom menu row; the annotation follows it
  travel("#dish", [[0, -12], [dishTo[0], dishTo[1]]], 23.95, 0.5, "expo.inOut");
  tl.to("#dish", { scale: 1, boxShadow: "0 0 0 rgba(0,0,0,0)", duration: 0.3, ease: "expo.out" }, 24.3);
  tl.to("#anchor", { x: dishTo[0] - 2, y: dishTo[1] + 1, duration: 0.5, ease: "expo.inOut" }, 23.95);
  tl.to(["#anchor", "#anchor i"], { borderColor: "#ae895e", duration: 0.3 }, 23.95);
  tl.to("#anchor .t", { backgroundColor: "#ae895e", color: "#050505", duration: 0.3 }, 23.95);
  tl.set("#vk-row1", { opacity: 1 }, 24.5);
  tl.set("#dish", { autoAlpha: 0 }, 24.52);
  tl.to("#anchor", { opacity: 0, duration: 0.2 }, 25.2);
  // Custom's own hero
  const vkScroll = scrollPage("#vk-page", 0, 834);
  vkScroll(0, 25.3, 0.8, "expo.inOut");
  camTo(CAM.saasIn, 25.3, 1.9, "sine.inOut");

  /* ================= 6 · ECOSYSTEM (26.6 – 29.2): assemble around the V, then collapse into it ================= */
  hit("#bg-ink2", 26.6, 960, 590, 0.45);
  tone(LIGHT, 26.7);
  sec(7, 26.7);
  kwOut("#kw-two", 26.55);
  camTo(CAM.eco, 26.6, 0.7, "power4.inOut");
  tl.set(["#hub", "#rings", "#links"], { opacity: 1 }, 26.75);
  tl.set(["#pos", "#pos-stand"], { opacity: 1 }, 26.85);
  tl.set("#phone", { opacity: 1 }, 26.9);
  tl.set("#saas", { opacity: 1 }, 26.95);
  tl.set(["#l-mgr", "#l-web", "#l-pos"], { opacity: 0 }, 26.75);
  tl.fromTo("#hub", { scale: 0.4 }, { scale: 1, duration: 0.45, ease: "expo.out", immediateRender: false }, 26.8);
  tl.fromTo(["#pos", "#pos-stand"], { x: -600 }, { x: 0, duration: 0.55, ease: "expo.out", immediateRender: false }, 26.85);
  tl.fromTo("#phone", { y: -700 }, { y: 0, duration: 0.55, ease: "expo.out", immediateRender: false }, 26.9);
  tl.fromTo("#saas", { scale: 1, y: 500 }, { scale: 0.72, y: 0, transformOrigin: "0% 0%", duration: 0.55, ease: "expo.out", immediateRender: false }, 26.95);
  tl.fromTo("#vk", { x: -1700, scale: 1 }, { x: -660, scale: 0.72, transformOrigin: "0% 0%", duration: 0.6, ease: "expo.inOut", immediateRender: false }, 26.95);
  tl.to(["#l-pos", "#l-mgr", "#l-web", "#lb-pos"], { opacity: 1, duration: 0.05 }, 27.45);
  tl.fromTo(["#l-pos", "#l-mgr", "#l-web"], { strokeDashoffset: 1 }, { strokeDashoffset: 0, duration: 0.3, ease: "power3.out", stagger: 0.05 }, 27.45);
  ["#p-pos", "#p-mgr", "#p-web"].forEach((sel) => {
    tl.to(sel, { opacity: 1, duration: 0.05 }, 27.8);
    tl.fromTo(sel, { strokeDashoffset: 0.05 }, { strokeDashoffset: -1, duration: 0.5, ease: "power2.inOut", immediateRender: false }, 27.8);
    tl.to(sel, { opacity: 0, duration: 0.05 }, 28.3);
  });
  tl.fromTo("#r-pulse", { attr: { r: 130 }, opacity: 1 }, { attr: { r: 380 }, opacity: 0, duration: 0.5, ease: "expo.out", immediateRender: false }, 27.8);
  kwIn("#kw-eco", 27.6);
  // collapse into the V
  kwOut("#kw-eco", 28.75);
  const fold = [["#pos", 420, -80], ["#pos-stand", 420, -80], ["#phone", -420, 150], ["#saas", -380, -230], ["#vk", -1200, -300]];
  fold.forEach(([sel, dx, dy]) => tl.to(sel, { opacity: 0, scale: 0.5, x: dx, y: dy, duration: 0.42, ease: "power3.in" }, 28.8));
  tl.to(["#l-pos", "#l-mgr", "#l-web"], { strokeDashoffset: -1, duration: 0.35, ease: "power2.in" }, 28.8);
  tl.to([".link-base"], { opacity: 0, duration: 0.3 }, 28.8);
  tl.set(["#l-pos", "#l-mgr", "#l-web"], { opacity: 0 }, 29.16);
  tl.to("#rings", { scale: 0.3, opacity: 0, transformOrigin: "50% 50%", duration: 0.42, ease: "power3.in" }, 28.8);

  /* ================= 7 · LOCKUP (29.2 – 34.0): plum hit from the V, wordmark, line ================= */
  const hubC = scr(CAM.eco, 2300, 1130);
  hit("#bg-plum2", 29.2, hubC[0].toFixed(0), hubC[1].toFixed(0), 0.5);
  sec(0, 29.3);
  camTo(CAM.lock, 29.2, 0.55, "expo.out");
  camTo(CAM.lockIn, 29.8, 2.4, "sine.inOut");
  tl.to("#hub-tile", { opacity: 0, duration: 0.2 }, 29.2);
  tl.fromTo("#hub", { scale: 0.85 }, { scale: 1, duration: 0.5, ease: "expo.out", immediateRender: false }, 29.2);
  tl.set("#wordmark", { autoAlpha: 1 }, 29.45);
  tl.fromTo("#wordmark-text", { opacity: 0, x: -140, filter: "blur(12px)" }, { opacity: 1, x: -44, filter: "blur(0px)", duration: 0.55, ease: "expo.out", immediateRender: false }, 29.45);
  tl.set("#tagline", { autoAlpha: 1 }, 29.7);
  tl.fromTo("#tagline-text", { x: 58, yPercent: 110 }, { x: 58, yPercent: 0, duration: 0.5, ease: "expo.out" }, 29.75);

  window.__timelines = window.__timelines || {};
  window.__timelines["main"] = tl;
})();
