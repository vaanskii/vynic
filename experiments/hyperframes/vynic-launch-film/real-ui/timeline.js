// Vynic launch film · real-UI cut (43.0 s, 120 bpm grid: beat = 0.5 s).
// One world, one camera, one paused timeline. Scene map: STYLE_NOTES.md. Inlined into index.html by tools/inline.py.
(function () {
  const W = 1920, H = 1080, END = 43.0;
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
  // Manager rects (logical px inside the 396×856 phone screen), recorded from the real widgets (capture/mgr_rects.json).
  const phoneScreen = [3212, 272];
  const ph0 = scr(CAM.mgr, phoneScreen[0], phoneScreen[1]);
  const srcRev = { x: ph0[0] + 25, y: ph0[1] + 150, w: 346, h: 345 };   // revenue card
  const revVal = { x: ph0[0] + 49, y: ph0[1] + 227 };                 // ₾ figure (left, vertical centre)
  const srcSum = { x: ph0[0] + 40, y: ph0[1] + 280, w: 316, h: 215 };   // receiving payment summary
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

  /* ---------- real UI helpers: screen states, taps, highlights, shared-element crops ---------- */
  const posOvl = document.getElementById("pos-ovl"), mgrOvl = document.getElementById("mgr-ovl");
  function mk(parent, cls, css) { const d = document.createElement("div"); d.className = cls; Object.assign(d.style, css || {}); d.setAttribute("data-layout-allow-overlap", ""); parent.appendChild(d); return d; }
  function show(cls, id, at, fx) {
    tl.set("." + cls, { opacity: 0 }, at);
    tl.set("#" + id, { opacity: 1 }, at);
    if (fx === "slide") tl.fromTo("#" + id, { x: 42 }, { x: 0, duration: 0.3, ease: "expo.out", immediateRender: false }, at);
    if (fx === "back") tl.fromTo("#" + id, { x: -42 }, { x: 0, duration: 0.3, ease: "expo.out", immediateRender: false }, at);
    if (fx === "up") tl.fromTo("#" + id, { y: 60 }, { y: 0, duration: 0.34, ease: "expo.out", immediateRender: false }, at);
    if (fx === "pop") tl.fromTo("#" + id, { scale: 0.975 }, { scale: 1, duration: 0.25, ease: "expo.out", immediateRender: false }, at);
  }
  function tapAt(ovl, x, y, at, small) {
    const d = mk(ovl, "tapdot" + (small ? " m" : ""), { left: x + "px", top: y + "px" });
    tl.fromTo(d, { opacity: 0.95, scale: 0.35 }, { opacity: 0, scale: 1.45, duration: 0.42, ease: "power2.out", immediateRender: false }, at);
  }
  function hlBox(ovl, x, y, w, h, at, dur, r) {
    const d = mk(ovl, "hlbox", { left: x + "px", top: y + "px", width: w + "px", height: h + "px", borderRadius: (r || 12) + "px" });
    tl.fromTo(d, { opacity: 0, scale: 1.12 }, { opacity: 1, scale: 1, duration: 0.22, ease: "expo.out", immediateRender: false }, at);
    tl.to(d, { opacity: 0, duration: 0.18, ease: "power1.in" }, at + (dur || 0.7));
  }
  // an item leaves its tile and lands in the order (a crop of the real screen, moved along an arc)
  function itemFly(img, at) {
    const d = mk(posOvl, "crop", { left: "0px", top: "0px", width: "194px", height: "95px", backgroundImage: "url(assets/ui/" + img + ".png)", backgroundPosition: "-227px -79px" });
    const pts = [[227, 79], [680, -10], [1086, 118]];
    tl.set(d, { x: 227, y: 79 }, 0);
    tl.set(d, { opacity: 1 }, at);
    d.id = "fly-" + img;
    travel("#" + d.id, pts, at, 0.34, "power3.inOut");
    tl.to(d, { scale: 0.82, duration: 0.34, ease: "power3.inOut" }, at);
    tl.set(d, { opacity: 0 }, at + 0.36);
  }
  tl.set("#pos_01_floor", { opacity: 1 }, 0);
  tl.set("#mgr_01_dash_before", { opacity: 1 }, 0);

  /* ================= 2 · POS (2.5 – 13.0): real Vynic POS — Table 4 → order → 46.20 ₾ → occupied; then counting, takeaways, reservations, management ================= */
  // Table 4 (rects from capture/pos_rects.json, logical px on the 1440×900 screen)
  hlBox(posOvl, 704, 298, 86, 126, 2.92, 0.22, 40);
  tapAt(posOvl, 747, 361, 3.2);
  show("pui", "pos_02_editor_empty", 3.32, "slide");
  // khachapuri: tile → quantity pad → added (flies into the order)
  tapAt(posOvl, 393, 147, 3.75);
  show("pui", "pos_03a_pad", 3.85, "pop");
  tapAt(posOvl, 720, 659, 4.18);
  show("pui", "pos_03_item1", 4.28);
  itemFly("pos_02_editor_empty", 4.28);
  // salad
  tapAt(posOvl, 104, 171, 4.78);
  tapAt(posOvl, 393, 147, 5.0);
  show("pui", "pos_04_item2", 5.1);
  itemFly("pos_04_item2", 5.1);
  // lemonade
  tapAt(posOvl, 104, 259, 5.45);
  tapAt(posOvl, 393, 147, 5.66);
  show("pui", "pos_05_item3", 5.76);
  itemFly("pos_05_item3", 5.76);
  hlBox(posOvl, 1333, 780, 99, 45, 5.98, 0.4);
  // add the order → the table view: occupied, 46.20 ₾
  tapAt(posOvl, 1263, 858, 6.5);
  show("pui", "pos_07_detail_confirmed", 6.62, "up");
  hlBox(posOvl, 398, 20, 106, 33, 6.9, 0.7, 16);
  hlBox(posOvl, 1268, 158, 95, 44, 7.0, 0.6);
  // back to the floor: Table 4 is taken
  tapAt(posOvl, 94, 36, 7.5);
  show("pui", "pos_08_floor_after", 7.62, "back");
  hlBox(posOvl, 704, 298, 86, 126, 7.78, 0.35, 40);
  // the rest of the POS, fast: the camera makes room for the words
  const CAMF = { x: 770, y: 1165, s: 0.72 };
  camTo(CAMF, 8.2, 0.55, "expo.inOut");
  tapAt(posOvl, 163, 86, 8.6);
  show("pui", "pos_10_calc", 8.7, "slide");
  kwIn("#kw-p1", 8.62);
  kwOut("#kw-p1", 9.52);
  tapAt(posOvl, 258, 86, 9.6);
  show("pui", "pos_11_takeaway", 9.7, "slide");
  kwIn("#kw-p2", 9.74);
  kwOut("#kw-p2", 10.52);
  tapAt(posOvl, 390, 86, 10.6);
  show("pui", "pos_12_reservations", 10.7, "slide");
  kwIn("#kw-p3", 10.74);
  kwOut("#kw-p3", 11.52);
  tapAt(posOvl, 1346, 86, 11.6);
  show("pui", "pos_20_admin", 11.72, "slide");
  kwIn("#kw-p4", 11.76);
  tapAt(posOvl, 92, 165, 12.12);
  show("pui", "pos_21_admin_menu", 12.22);
  tapAt(posOvl, 124, 489, 12.52);
  show("pui", "pos_23_admin_close", 12.62);
  kwOut("#kw-p4", 12.7);
  camTo({ x: 1270, y: 1165, s: 1.35 }, 12.62, 0.45, "expo.in");

  /* ---- type wipe: signal-orange panel carries the words, the scene changes underneath ---- */
  tl.fromTo("#wipe-type", { x: 1920 }, { x: 0, duration: 0.34, ease: "power4.inOut" }, 13);
  kwIn("#kw-fast", 13.18, 0.08);
  tl.from("#wipe-type .tick", { opacity: 0, x: 30, duration: 0.3, ease: "expo.out" }, 13.23);
  // under the cover: dark foundation
  cut("#bg-ink", 13.38);
  tone(LIGHT, 13.38);
  camCut(CAM.found, 13.38);
  tl.set(["#pos", "#pos-stand"], { opacity: 0 }, 13.38);
  tl.set(["#hub", "#rings"], { opacity: 1 }, 13.38);
  tl.set("#hub-tile", { opacity: 1 }, 13.38);
  sec(2, 13.68);
  tl.to("#wipe-type", { x: -1920, duration: 0.36, ease: "power4.inOut" }, 13.9);
  tl.to("#kw-fast", { x: -700, duration: 0.36, ease: "power4.inOut" }, 13.88);

  /* ================= 3 · ONE SYSTEM (13.88 – 16.88): the order docks, the number becomes data ================= */
  tl.fromTo("#token", { opacity: 0, scale: 0.8 }, { opacity: 1, scale: 1, duration: 0.2, ease: "power2.out" }, 14.03);
  travel("#token", [[1560, 1130], [2300, 1130]], 14.03, 0.55, "power3.in");
  tl.to("#token", { opacity: 0, scale: 0.4, duration: 0.1, ease: "power1.in" }, 14.56);
  // dock: the mark answers
  tl.fromTo("#r-pulse", { attr: { r: 130 }, opacity: 1 }, { attr: { r: 330 }, opacity: 0, duration: 0.45, ease: "expo.out", immediateRender: false }, 14.58);
  tl.fromTo("#hub", { scale: 1.08 }, { scale: 1, duration: 0.35, ease: "expo.out", immediateRender: false }, 14.58);
  tl.fromTo("#record", { opacity: 0, y: 220, scale: 0.5 }, { opacity: 1, y: 0, scale: 1, duration: 0.42, ease: "expo.out" }, 14.68);
  tl.fromTo("#row-orders .hl", { opacity: 0 }, { opacity: 1, duration: 0.2, ease: "power2.out" }, 14.98);
  tl.to("#row-orders .st-idle", { opacity: 0, duration: 0.12 }, 14.98);
  tl.fromTo("#row-orders .st-ok", { opacity: 0, y: 8 }, { opacity: 1, y: 0, duration: 0.25, ease: "power3.out" }, 15);
  // big number: the order total, itemised
  tl.set("#bn", { opacity: 1 }, 14.83);
  tl.from("#bn .dk", { opacity: 0, x: 40, duration: 0.3, ease: "expo.out" }, 14.83);
  tl.from("#bn-num", { opacity: 0, x: 80, duration: 0.35, ease: "expo.out" }, 14.88);
  counter(document.getElementById("bn-v"), 0, 46.2, 14.88, 0.6);
  tl.from("#bn-rows .r", { opacity: 0, x: 40, duration: 0.25, ease: "expo.out", stagger: 0.07 }, 15.08);
  tl.from("#bn-rows", { borderTopColor: "rgba(242, 238, 231, 0)", duration: 0.2 }, 15.08);
  // the system reaches out: lines to Manager and web, one pulse
  tl.to(["#lb-mgr", "#lb-web", "#l-mgr", "#l-web"], { opacity: 1, duration: 0.1 }, 15.78);
  tl.fromTo(["#l-mgr", "#l-web"], { strokeDashoffset: 1 }, { strokeDashoffset: 0, duration: 0.35, ease: "power3.inOut", stagger: 0.08 }, 15.78);
  tl.to("#p-mgr", { opacity: 1, duration: 0.05 }, 16.28);
  tl.fromTo("#p-mgr", { strokeDashoffset: 0.05 }, { strokeDashoffset: -1, duration: 0.7, ease: "power2.in", immediateRender: false }, 16.28);
  tl.to("#p-mgr", { opacity: 0, duration: 0.05 }, 16.98);

  /* ---- whip to Manager along the line; the total flies into the revenue card ---- */
  tl.to(["#bn .dk", "#bn-rows"], { opacity: 0, x: -60, duration: 0.2, ease: "power2.in" }, 16.38);
  // #bn-num: left 1080, vertical centre ≈ 408 (scaled from its left-middle) → the revenue figure inside the card
  tl.to("#bn-num", { x: revVal.x - 1080, y: revVal.y - 408, scale: 0.21, duration: 0.62, ease: "power4.inOut" }, 16.48);
  tl.to("#bn-num", { opacity: 0, duration: 0.12 }, 17.06);
  tl.set("#phone", { opacity: 1 }, 16.38);
  camTo(CAM.mgr, 16.43, 0.62, "power4.inOut");
  tl.set(["#hub", "#record", "#rings", "#links"], { opacity: 0 }, 17.08);
  hit("#bg-signal", 16.68, 1340, 540, 0.45);
  tone(DARK, 16.83);
  sec(3, 16.88);

  /* ================= 4 · MANAGER (16.85 – 29.95): the real Manager app — refresh → figures respond → tables → Inventory → receiving (partial payment) → stock → a website booking confirmed ================= */
  kwIn("#kw-sales", 17.0);
  tapAt(mgrOvl, 198, 150, 17.3, true);
  tl.fromTo(mgrOvl.lastChild, { y: 0 }, { y: 120, duration: 0.4, ease: "power2.out", immediateRender: false }, 17.3);
  // the app's own pull-to-refresh spinner (not a captured frame: the captured pull frame scrolls to the placeholder insight card)
  const spin = mk(mgrOvl, "mspin", { left: "179px", top: "18px" });
  tl.fromTo(spin, { opacity: 0, y: -20, rotation: 0 }, { opacity: 1, y: 30, rotation: 240, duration: 0.3, ease: "power2.out", immediateRender: false }, 17.36);
  tl.to(spin, { rotation: 520, duration: 0.3, ease: "none" }, 17.66);
  tl.to(spin, { opacity: 0, y: 0, duration: 0.16, ease: "power1.in" }, 17.9);
  tl.fromTo("#mgr_01_dash_before", { y: 0 }, { y: 44, duration: 0.3, ease: "power2.out", immediateRender: false }, 17.36);
  show("mui", "mgr_03_dash_after", 17.9, "pop");
  hlBox(mgrOvl, 43, 191, 205, 72, 17.95, 0.55, 14);
  expand("#dc-a", srcRev, 18.4);
  counter(document.getElementById("dc-a-num"), 2868.65, 2914.85, 18.68, 0.55);
  tl.fromTo(["#dc-a-b1", "#dc-a-b2"], { scaleX: 0 }, { scaleX: 1, duration: 0.4, ease: "expo.out", stagger: 0.12 }, 18.8);
  collapse("#dc-a", srcRev, 19.85);
  // tables
  tapAt(mgrOvl, 102.6, 804.8, 20.3, true);
  show("mui", "mgr_05_tables", 20.4, "slide");
  kwOut("#kw-sales", 20.28);
  kwIn("#kw-tbl", 20.5);
  // Inventory
  tapAt(mgrOvl, 229.8, 804.8, 21.2, true);
  show("mui", "mgr_06_inventory", 21.3, "slide");
  kwOut("#kw-tbl", 21.18);
  kwIn("#kw-stock", 21.4);
  sec(4, 21.3);
  // receiving: goods → payment → review
  tapAt(mgrOvl, 207, 102, 21.95, true);
  show("mui", "mgr_08_recv_editor", 22.05, "up");
  kwOut("#kw-stock", 21.95);
  kwIn("#kw-recv", 22.17);
  tapAt(mgrOvl, 112, 388, 22.55, true);
  show("mui", "mgr_09_recv_lines", 22.65);
  tapAt(mgrOvl, 198, 736, 23.1, true);
  show("mui", "mgr_09b_recv_payment", 23.2, "slide");
  tapAt(mgrOvl, 218, 297, 23.6, true);
  show("mui", "mgr_09c_recv_review", 23.7);
  hlBox(mgrOvl, 48, 468, 304, 31, 23.8, 0.3, 8);
  expand("#dc-b1", srcSum, 24.05);
  expand("#dc-b2", srcSum, 24.15);
  counter(document.getElementById("dc-b1-num"), 0, 20, 24.35, 0.5, (v) => fmt(v, 3));
  counter(document.getElementById("dc-b2-num"), 0, 30, 24.45, 0.5);
  tl.fromTo("#dc-b2-bar", { scaleX: 0 }, { scaleX: 1, duration: 0.4, ease: "expo.out" }, 24.55);
  collapse("#dc-b1", srcSum, 25.35);
  collapse("#dc-b2", srcSum, 25.4);
  tapAt(mgrOvl, 198, 688, 25.8, true);
  show("mui", "mgr_09d_after_save", 25.92, "back");
  // stock balances
  tapAt(mgrOvl, 140, 345, 26.45, true);
  show("mui", "mgr_09e_stock", 26.55, "slide");
  kwOut("#kw-recv", 26.42);
  kwIn("#kw-bal", 26.62);
  hlBox(mgrOvl, 18, 318, 360, 118, 26.8, 0.55, 16);
  // a booking from the website, confirmed
  tapAt(mgrOvl, 293.4, 804.8, 27.45, true);
  show("mui", "mgr_07_reservations", 27.55, "slide");
  kwOut("#kw-bal", 27.42);
  kwIn("#kw-mres", 27.62);
  tapAt(mgrOvl, 160, 519, 28.15, true);
  show("mui", "mgr_10_res_detail", 28.25, "slide");
  hlBox(mgrOvl, 254, 88, 108, 30, 28.45, 0.45, 15);
  tapAt(mgrOvl, 119, 591, 28.95, true);
  show("mui", "mgr_11_res_confirmed", 29.08, "back");
  hlBox(mgrOvl, 226, 552, 118, 30, 29.2, 0.6, 15);

  /* ---- scale-through: the phone screen opens into the web scene ---- */
  const ph = scr(CAM.mgr, 3212, 272);
  tl.set("#wipe-scale", { opacity: 1, backgroundColor: "#e3edfc", x: ph[0], y: ph[1], scaleX: 396 / W, scaleY: 856 / H, borderRadius: "252px / 66px" }, 29.95);
  tl.to("#wipe-scale", { x: 0, y: 0, scaleX: 1, scaleY: 1, borderRadius: "0px / 0px", backgroundColor: "#f2eee7", duration: 0.46, ease: "expo.inOut" }, 29.95);
  kwOut("#kw-mres", 29.9);
  // under the cover: the web scene
  cut("#bg-paper2", 30.41);
  camCut(CAM.saas, 30.41);
  tl.set("#phone", { opacity: 0 }, 30.41);
  tl.set("#saas", { opacity: 1 }, 30.41);
  tl.fromTo("#saas", { scale: 1.16, transformOrigin: "50% 50%" }, { scale: 1, duration: 0.5, ease: "expo.out", immediateRender: false }, 30.41);
  tl.set("#wipe-scale", { opacity: 0 }, 30.43);
  sec(5, 30.45);

  /* ================= 5 · WEB (30.45 – 37.95): content → ready-made site → same data restyled as Custom ================= */
  kwIn("#kw-web", 30.55);
  const saasScroll = scrollPage("#saas-page", 68, 834);
  saasScroll(-1816, 30.95, 1.15, "expo.inOut");
  tapFx("#tap-nav", 32.2);
  saasScroll(-860, 32.3, 0.5, "expo.out");
  kwOut("#kw-web", 32.75);
  kwIn("#kw-menu", 32.97);
  // the shared menu line is annotated: dish, price
  tl.fromTo("#anchor", { opacity: 0, scale: 1.08 }, { opacity: 1, scale: 1, duration: 0.25, ease: "expo.out" }, 32.95);
  tl.from("#anchor .t", { y: 12, opacity: 0, duration: 0.25, ease: "expo.out", stagger: 0.08 }, 33.05);
  tl.set("#dish", { autoAlpha: 1 }, 33.45);
  tl.set("#saas-dish", { opacity: 0 }, 33.47);
  tl.fromTo("#dish", { y: 0, scale: 1, boxShadow: "0 0 0 rgba(0,0,0,0)" }, { y: -12, scale: 1.05, boxShadow: "0 26px 50px rgba(0,0,0,0.3)", duration: 0.3, ease: "expo.out" }, 33.47);
  // split wipe: the Custom design sweeps across the same content (lime edge)
  tl.set("#vk", { opacity: 1 }, 33.85);
  tl.set("#edge", { opacity: 1 }, 33.85);
  tl.fromTo("#vk", { clipPath: "inset(0px 0px 0px 1400px)" }, { clipPath: "inset(0px 0px 0px 0px)", duration: 1.2, ease: "power3.inOut", immediateRender: false }, 33.85);
  tl.fromTo("#edge", { x: 0 }, { x: -1400, duration: 1.2, ease: "power3.inOut", immediateRender: false }, 33.85);
  tl.to("#dish .dc-vk", { opacity: 1, duration: 0.18, ease: "sine.inOut" }, 34.53);
  tl.to("#edge", { opacity: 0, duration: 0.15 }, 35.05);
  tl.set("#saas", { opacity: 0 }, 35.07);
  kwOut("#kw-menu", 34.65);
  kwIn("#kw-two", 34.87);
  sec(6, 34.75);
  // the dish settles into the Custom menu row; the annotation follows it
  travel("#dish", [[0, -12], [dishTo[0], dishTo[1]]], 34.7, 0.5, "expo.inOut");
  tl.to("#dish", { scale: 1, boxShadow: "0 0 0 rgba(0,0,0,0)", duration: 0.3, ease: "expo.out" }, 35.05);
  tl.to("#anchor", { x: dishTo[0] - 2, y: dishTo[1] + 1, duration: 0.5, ease: "expo.inOut" }, 34.7);
  tl.to(["#anchor", "#anchor i"], { borderColor: "#ae895e", duration: 0.3 }, 34.7);
  tl.to("#anchor .t", { backgroundColor: "#ae895e", color: "#050505", duration: 0.3 }, 34.7);
  tl.set("#vk-row1", { opacity: 1 }, 35.25);
  tl.set("#dish", { autoAlpha: 0 }, 35.27);
  tl.to("#anchor", { opacity: 0, duration: 0.2 }, 35.95);
  // Custom's own hero
  const vkScroll = scrollPage("#vk-page", 0, 834);
  vkScroll(0, 36.05, 0.8, "expo.inOut");
  camTo(CAM.saasIn, 36.05, 1.9, "sine.inOut");

  /* ================= 6 · ECOSYSTEM (37.35 – 39.95): assemble around the V, then collapse into it ================= */
  hit("#bg-ink2", 37.35, 960, 590, 0.45);
  tone(LIGHT, 37.45);
  sec(7, 37.45);
  kwOut("#kw-two", 37.3);
  camTo(CAM.eco, 37.35, 0.7, "power4.inOut");
  show("pui", "pos_08_floor_after", 37.4);
  show("mui", "mgr_03_dash_after", 37.4);
  tl.set(["#hub", "#rings", "#links"], { opacity: 1 }, 37.5);
  tl.set(["#pos", "#pos-stand"], { opacity: 1 }, 37.6);
  tl.set("#phone", { opacity: 1 }, 37.65);
  tl.set("#saas", { opacity: 1 }, 37.7);
  tl.set(["#l-mgr", "#l-web", "#l-pos"], { opacity: 0 }, 37.5);
  tl.fromTo("#hub", { scale: 0.4 }, { scale: 1, duration: 0.45, ease: "expo.out", immediateRender: false }, 37.55);
  tl.fromTo(["#pos", "#pos-stand"], { x: -600 }, { x: 0, duration: 0.55, ease: "expo.out", immediateRender: false }, 37.6);
  tl.fromTo("#phone", { y: -700 }, { y: 0, duration: 0.55, ease: "expo.out", immediateRender: false }, 37.65);
  tl.fromTo("#saas", { scale: 1, y: 500 }, { scale: 0.72, y: 0, transformOrigin: "0% 0%", duration: 0.55, ease: "expo.out", immediateRender: false }, 37.7);
  tl.fromTo("#vk", { x: -1700, scale: 1 }, { x: -660, scale: 0.72, transformOrigin: "0% 0%", duration: 0.6, ease: "expo.inOut", immediateRender: false }, 37.7);
  tl.to(["#l-pos", "#l-mgr", "#l-web", "#lb-pos"], { opacity: 1, duration: 0.05 }, 38.2);
  tl.fromTo(["#l-pos", "#l-mgr", "#l-web"], { strokeDashoffset: 1 }, { strokeDashoffset: 0, duration: 0.3, ease: "power3.out", stagger: 0.05 }, 38.2);
  ["#p-pos", "#p-mgr", "#p-web"].forEach((sel) => {
    tl.to(sel, { opacity: 1, duration: 0.05 }, 38.55);
    tl.fromTo(sel, { strokeDashoffset: 0.05 }, { strokeDashoffset: -1, duration: 0.5, ease: "power2.inOut", immediateRender: false }, 38.55);
    tl.to(sel, { opacity: 0, duration: 0.05 }, 39.05);
  });
  tl.fromTo("#r-pulse", { attr: { r: 130 }, opacity: 1 }, { attr: { r: 380 }, opacity: 0, duration: 0.5, ease: "expo.out", immediateRender: false }, 38.55);
  kwIn("#kw-eco", 38.35);
  // collapse into the V
  kwOut("#kw-eco", 39.5);
  const fold = [["#pos", 420, -80], ["#pos-stand", 420, -80], ["#phone", -420, 150], ["#saas", -380, -230], ["#vk", -1200, -300]];
  fold.forEach(([sel, dx, dy]) => tl.to(sel, { opacity: 0, scale: 0.5, x: dx, y: dy, duration: 0.42, ease: "power3.in" }, 39.55));
  tl.to(["#l-pos", "#l-mgr", "#l-web"], { strokeDashoffset: -1, duration: 0.35, ease: "power2.in" }, 39.55);
  tl.to([".link-base"], { opacity: 0, duration: 0.3 }, 39.55);
  tl.set(["#l-pos", "#l-mgr", "#l-web"], { opacity: 0 }, 39.91);
  tl.to("#rings", { scale: 0.3, opacity: 0, transformOrigin: "50% 50%", duration: 0.42, ease: "power3.in" }, 39.55);

  /* ================= 7 · LOCKUP (39.95 – 44.75): plum hit from the V, wordmark, line ================= */
  const hubC = scr(CAM.eco, 2300, 1130);
  hit("#bg-plum2", 39.95, hubC[0].toFixed(0), hubC[1].toFixed(0), 0.5);
  sec(0, 40.05);
  camTo(CAM.lock, 39.95, 0.55, "expo.out");
  camTo(CAM.lockIn, 40.55, 2.4, "sine.inOut");
  tl.to("#hub-tile", { opacity: 0, duration: 0.2 }, 39.95);
  tl.fromTo("#hub", { scale: 0.85 }, { scale: 1, duration: 0.5, ease: "expo.out", immediateRender: false }, 39.95);
  tl.set("#wordmark", { autoAlpha: 1 }, 40.2);
  tl.fromTo("#wordmark-text", { opacity: 0, x: -140, filter: "blur(12px)" }, { opacity: 1, x: -44, filter: "blur(0px)", duration: 0.55, ease: "expo.out", immediateRender: false }, 40.2);
  tl.set("#tagline", { autoAlpha: 1 }, 40.45);
  tl.fromTo("#tagline-text", { x: 58, yPercent: 110 }, { x: 58, yPercent: 0, duration: 0.5, ease: "expo.out" }, 40.5);

  window.__timelines = window.__timelines || {};
  window.__timelines["main"] = tl;
})();
