/* =========================================================================
   ExamVault — Figma 4-Screen Builder
   Creates four 393 x 852 frames on a 1772 x 1040 presentation board.
   Run: Plugins → Development → Import plugin from manifest…
   Fonts: Plus Jakarta Sans + IBM Plex Mono (fallback: Inter / Roboto Mono)
   ========================================================================= */

const C = {
  bg: "#0B0F19",
  surface: "#111827",
  sunken: "#0E1522",
  border: "#1F2937",
  borderStrong: "#263246",
  walletBorder: "#28374F",
  blue: "#3B82F6",
  blueBright: "#60A5FA",
  blueText: "#93C5FD",
  blueDeep: "#2563EB",
  green: "#10B981",
  greenText: "#6EE7B7",
  amber: "#F59E0B",
  amberText: "#FCD34D",
  red: "#EF4444",
  redText: "#FCA5A5",
  text: "#F9FAFB",
  text2: "#9CA3AF",
  text3: "#6B7280",
  alabaster: "#F8FAFC",
  white: "#FFFFFF",
  ink: "#0B0F19",
};

/* ------------------------------- utilities ------------------------------ */

function rgb(hex) {
  const h = hex.replace("#", "");
  const n = parseInt(h.length === 3 ? h.split("").map(c => c + c).join("") : h, 16);
  return { r: ((n >> 16) & 255) / 255, g: ((n >> 8) & 255) / 255, b: (n & 255) / 255 };
}
function solid(hex, opacity = 1) {
  return { type: "SOLID", color: rgb(hex), opacity };
}
function grad(colors, opacity = 1, horizontal = false) {
  return {
    type: "GRADIENT_LINEAR",
    opacity,
    gradientTransform: horizontal ? [[1, 0, 0], [0, 1, 0]] : [[0, 1, 0], [-1, 0, 1]],
    gradientStops: colors.map((c, i) => ({
      position: i / (colors.length - 1),
      color: { ...rgb(c), a: 1 },
    })),
  };
}
function radialGlow(hex, alpha = 0.18) {
  return {
    type: "GRADIENT_RADIAL",
    gradientTransform: [[1, 0, 0], [0, 1, 0]],
    gradientStops: [
      { position: 0, color: { ...rgb(hex), a: alpha } },
      { position: 1, color: { ...rgb(hex), a: 0 } },
    ],
  };
}
function shadow(hex, a, x, y, blur, spread = 0) {
  return {
    type: "DROP_SHADOW",
    color: { ...rgb(hex), a },
    offset: { x, y },
    radius: blur,
    spread,
    visible: true,
    blendMode: "NORMAL",
  };
}

const FONT = { ui: {}, mono: {} };

async function loadFont(family, style) {
  try { await figma.loadFontAsync({ family, style }); return { family, style }; }
  catch (e) { return null; }
}
async function resolve(family, style, fallbackFamily, fallbackStyle) {
  return (await loadFont(family, style)) ||
         (await loadFont(fallbackFamily, fallbackStyle || style)) ||
         (await loadFont("Inter", "Regular"));
}
async function initFonts() {
  const uiStyles = ["Regular", "Medium", "SemiBold", "Bold", "ExtraBold"];
  const uiFallback = { ExtraBold: "Bold" };
  for (const s of uiStyles) {
    FONT.ui[s] = await resolve("Plus Jakarta Sans", s, "Inter", uiFallback[s] || s);
  }
  for (const s of ["Regular", "Medium", "SemiBold"]) {
    FONT.mono[s] = await resolve("IBM Plex Mono", s, "Roboto Mono", s);
  }
}

function T(str, o = {}) {
  const n = figma.createText();
  const weights = FONT[o.mono ? "mono" : "ui"];
  n.fontName = weights[o.weight || (o.mono ? "Regular" : "Medium")] || FONT.ui.Regular;
  n.characters = str;
  n.fontSize = o.size || 12;
  n.fills = [solid(o.color || C.text)];
  n.letterSpacing = { value: o.ls || 0, unit: "PIXELS" };
  n.lineHeight = { value: o.lh || Math.round((o.size || 12) * 1.35), unit: "PIXELS" };
  n.textAutoResize = "WIDTH_AND_HEIGHT";
  if (o.align) n.textAlignHorizontal = o.align;
  n.name = o.name || str.slice(0, 40);
  return n;
}
function addT(parent, str, o = {}) {
  const n = T(str, o);
  parent.appendChild(n);
  if (o.x !== undefined) n.x = o.x;
  if (o.y !== undefined) n.y = o.y;
  return n;
}
function fixedT(parent, str, o = {}, w = 100, h = 14) {
  const n = addT(parent, str, o);
  n.textAutoResize = "NONE";
  n.resize(w, h);
  if (o.align) n.textAlignHorizontal = o.align;
  return n;
}

function box(name, x, y, w, h, o = {}) {
  const f = figma.createFrame();
  f.name = name;
  f.resize(w, h);
  f.fills = o.fill ? [o.fill] : [];
  if (o.stroke) { f.strokes = [o.stroke]; f.strokeWeight = o.strokeWeight || 1; f.strokeAlign = "INSIDE"; }
  if (o.r) f.cornerRadius = o.r;
  if (o.clip) f.clipsContent = true;
  if (o.effects) f.effects = o.effects;
  f.x = x; f.y = y;
  return f;
}
function centerBox(name, w, h, o = {}) {
  const f = box(name, 0, 0, w, h, o);
  f.layoutMode = "HORIZONTAL";
  f.primaryAxisSizingMode = "FIXED";
  f.counterAxisSizingMode = "FIXED";
  f.primaryAxisAlignItems = "CENTER";
  f.counterAxisAlignItems = "CENTER";
  return f;
}
function dashedLine(parent, width, y, opacity = 0.15) {
  const f = box("Dashed Perforation", 0, 0, width, 1, {});
  f.x = 0; f.y = y;
  for (let x = 0; x < width; x += 7) {
    const d = figma.createRectangle();
    d.resize(Math.min(4, width - x), 1);
    d.x = x; d.y = 0;
    d.fills = [solid("#FFFFFF", opacity)];
    f.appendChild(d);
  }
  parent.appendChild(f);
  return f;
}

function hug(name, h, o = {}) {
  const f = figma.createFrame();
  f.name = name;
  f.layoutMode = "HORIZONTAL";
  f.primaryAxisSizingMode = "AUTO";
  f.counterAxisSizingMode = "FIXED";
  f.resize(10, h);
  f.itemSpacing = o.gap || 0;
  f.paddingLeft = o.pl || 0;
  f.paddingRight = o.pr || 0;
  f.paddingTop = o.pt || 0;
  f.paddingBottom = o.pb || 0;
  f.counterAxisAlignItems = o.align || "CENTER";
  f.primaryAxisAlignItems = o.justify || "MIN";
  f.fills = o.fill ? [o.fill] : [];
  if (o.stroke) { f.strokes = [o.stroke]; f.strokeWeight = o.sw || 1; f.strokeAlign = "INSIDE"; }
  if (o.r) f.cornerRadius = o.r;
  if (o.clip) f.clipsContent = true;
  if (o.effects) f.effects = o.effects;
  return f;
}

function row(name, w, h, o = {}) {
  const f = figma.createFrame();
  f.name = name;
  f.resize(w, h);
  f.layoutMode = "HORIZONTAL";
  f.primaryAxisSizingMode = "FIXED";
  f.counterAxisSizingMode = "FIXED";
  f.itemSpacing = o.gap || 0;
  f.paddingLeft = o.pl || 0;
  f.paddingRight = o.pr || 0;
  f.paddingTop = o.pt || 0;
  f.paddingBottom = o.pb || 0;
  f.counterAxisAlignItems = o.align || "CENTER";
  f.primaryAxisAlignItems = o.justify || "MIN";
  f.fills = o.fill ? [o.fill] : [];
  if (o.stroke) { f.strokes = [o.stroke]; f.strokeWeight = o.sw || 1; f.strokeAlign = "INSIDE"; }
  if (o.r) f.cornerRadius = o.r;
  if (o.clip) f.clipsContent = true;
  if (o.effects) f.effects = o.effects;
  return f;
}

function col(name, w, o = {}) {
  const f = figma.createFrame();
  f.name = name;
  f.resize(w, o.h || 10);
  f.layoutMode = "VERTICAL";
  f.primaryAxisSizingMode = o.h ? "FIXED" : "AUTO";
  f.counterAxisSizingMode = "FIXED";
  f.itemSpacing = o.gap || 0;
  f.paddingLeft = o.pl || 0;
  f.paddingRight = o.pr || 0;
  f.paddingTop = o.pt || 0;
  f.paddingBottom = o.pb || 0;
  f.counterAxisAlignItems = o.align || "MIN";
  f.primaryAxisAlignItems = o.justify || "MIN";
  f.fills = o.fill ? [o.fill] : [];
  if (o.stroke) { f.strokes = [o.stroke]; f.strokeWeight = o.sw || 1; f.strokeAlign = "INSIDE"; }
  if (o.r) f.cornerRadius = o.r;
  if (o.clip) f.clipsContent = true;
  if (o.effects) f.effects = o.effects;
  return f;
}

function vspace(parent, h) {
  const f = figma.createFrame();
  f.name = " ";
  f.resize(1, h);
  f.fills = [];
  f.layoutAlign = "STRETCH";
  parent.appendChild(f);
  return f;
}
function hspace(parent, w) {
  const f = figma.createFrame();
  f.name = " ";
  f.resize(w, 1);
  f.fills = [];
  parent.appendChild(f);
  return f;
}
function dividerV(parent, color = "rgba", opacity = 0.06, inset = 0) {
  const f = row("Divider", 1, 1, { pl: inset, pr: inset });
  f.layoutAlign = "STRETCH";
  f.fills = [];
  const line = figma.createRectangle();
  line.resize(1, 1);
  line.layoutAlign = "STRETCH";
  line.fillStyleId = "";
  line.fills = [solid("#FFFFFF", opacity)];
  f.appendChild(line);
  parent.appendChild(f);
  return f;
}

/* --------------------------------- icons -------------------------------- */
const ICON = {
  vault: `<path d="M12 3l7 3v5.5c0 4.3-2.9 7.6-7 9.5-4.1-1.9-7-5.2-7-9.5V6l7-3z" stroke="{{c}}" stroke-width="1.6" stroke-linejoin="round"/><circle cx="12" cy="11" r="2.4" stroke="{{c}}" stroke-width="1.6"/><path d="M12 13.4V16" stroke="{{c}}" stroke-width="1.6" stroke-linecap="round"/>`,
  bell: `<path d="M18 8a6 6 0 10-12 0c0 6-2 7-2 7h16s-2-1-2-7" stroke="{{c}}" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/><path d="M13.7 20a2 2 0 01-3.4 0" stroke="{{c}}" stroke-width="1.6" stroke-linecap="round"/>`,
  copy: `<rect x="9" y="9" width="11" height="11" rx="2.5" stroke="{{c}}" stroke-width="1.7"/><path d="M15 6.5V5a2 2 0 00-2-2H5a2 2 0 00-2 2v8a2 2 0 002 2h1.5" stroke="{{c}}" stroke-width="1.7" stroke-linecap="round"/>`,
  chev: `<path d="M9 5l7 7-7 7" stroke="{{c}}" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>`,
  back: `<path d="M15 5l-7 7 7 7" stroke="{{c}}" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>`,
  share: `<path d="M12 15V3m0 0L8 7m4-4l4 4" stroke="{{c}}" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/><path d="M5 12v7a2 2 0 002 2h10a2 2 0 002-2v-7" stroke="{{c}}" stroke-width="1.7" stroke-linecap="round"/>`,
  x: `<path d="M6 6l12 12M18 6L6 18" stroke="{{c}}" stroke-width="1.8" stroke-linecap="round"/>`,
  search: `<circle cx="11" cy="11" r="6.5" stroke="{{c}}" stroke-width="1.7"/><path d="M16 16l4 4" stroke="{{c}}" stroke-width="1.7" stroke-linecap="round"/>`,
  download: `<path d="M12 3v11m0 0l-4-4m4 4l4-4" stroke="{{c}}" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/><path d="M4 18v1a2 2 0 002 2h12a2 2 0 002-2v-1" stroke="{{c}}" stroke-width="1.8" stroke-linecap="round"/>`,
  check: `<path d="M4.5 12.5l5 5 10-11" stroke="{{c}}" stroke-width="2.1" stroke-linecap="round" stroke-linejoin="round"/>`,
  pdf: `<path d="M6 2.8h8l4 4V21a1.2 1.2 0 01-1.2 1.2H6A1.2 1.2 0 014.8 21V4A1.2 1.2 0 016 2.8z" stroke="{{c}}" stroke-width="1.6" stroke-linejoin="round"/><path d="M14 3v4.2h4.2" stroke="{{c}}" stroke-width="1.6" stroke-linejoin="round"/><path d="M8.5 16.5h7" stroke="{{c}}" stroke-width="1.6" stroke-linecap="round"/>`,
  clock: `<circle cx="12" cy="12" r="8.5" stroke="{{c}}" stroke-width="1.6"/><path d="M12 7.5V12l3 2" stroke="{{c}}" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/>`,
  home: `<path d="M4 10.5L12 4l8 6.5V20a1 1 0 01-1 1h-5v-6h-4v6H5a1 1 0 01-1-1v-9.5z" stroke="{{c}}" stroke-width="1.6" stroke-linejoin="round"/>`,
  lock: `<rect x="4.5" y="10.5" width="15" height="10" rx="2.2" stroke="{{c}}" stroke-width="1.6"/><path d="M8 10.5V7.5a4 4 0 018 0v3" stroke="{{c}}" stroke-width="1.6" stroke-linecap="round"/><circle cx="12" cy="15.5" r="1.3" fill="{{c}}"/>`,
  radar: `<circle cx="12" cy="12" r="8.5" stroke="{{c}}" stroke-width="1.6"/><circle cx="12" cy="12" r="4.2" stroke="{{c}}" stroke-width="1.6"/><path d="M12 12l5-5" stroke="{{c}}" stroke-width="1.6" stroke-linecap="round"/><circle cx="12" cy="12" r="1.4" fill="{{c}}"/>`,
  users: `<circle cx="9" cy="8" r="3.2" stroke="{{c}}" stroke-width="1.6"/><path d="M3.5 20c0-3.2 2.5-5.4 5.5-5.4s5.5 2.2 5.5 5.4" stroke="{{c}}" stroke-width="1.6" stroke-linecap="round"/><path d="M16 5.2a3 3 0 010 5.6M17.5 14.9c1.8.5 3 2.2 3 5.1" stroke="{{c}}" stroke-width="1.6" stroke-linecap="round"/>`,
  external: `<path d="M14 4h6v6M20 4l-8 8" stroke="{{c}}" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/><path d="M18 14v5a1 1 0 01-1 1H5a1 1 0 01-1-1V7a1 1 0 011-1h5" stroke="{{c}}" stroke-width="1.7" stroke-linecap="round"/>`,
  link: `<path d="M10 13.5a4 4 0 005.7 0l3-3a4 4 0 10-5.7-5.7L11.5 6.3" stroke="{{c}}" stroke-width="1.7" stroke-linecap="round"/><path d="M14 10.5a4 4 0 00-5.7 0l-3 3a4 4 0 105.7 5.7l1.5-1.5" stroke="{{c}}" stroke-width="1.7" stroke-linecap="round"/>`,
  spark: `<path d="M12 3l1.7 5.3L19 10l-5.3 1.7L12 17l-1.7-5.3L5 10l5.3-1.7L12 3z" stroke="{{c}}" stroke-width="1.5" stroke-linejoin="round"/>`,
  pin: `<path d="M12 21s7-6.1 7-11a7 7 0 10-14 0c0 4.9 7 11 7 11z" stroke="{{c}}" stroke-width="1.6" stroke-linejoin="round"/><circle cx="12" cy="10" r="2.6" stroke="{{c}}" stroke-width="1.6"/>`,
  send: `<path d="M21 3L3 10.5l7.2 2.8L13 20l8-17z" stroke="{{c}}" stroke-width="1.6" stroke-linejoin="round"/><path d="M10.2 13.3L21 3" stroke="{{c}}" stroke-width="1.6" stroke-linejoin="round"/>`,
  save: `<path d="M12 3v11m0 0l-4-4m4 4l4-4" stroke="{{c}}" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/><path d="M4 17v2a2 2 0 002 2h12a2 2 0 002-2v-2" stroke="{{c}}" stroke-width="1.7" stroke-linecap="round"/>`,
  wifi: `<path d="M8 10.6l2-2.4a3 3 0 00-4 0l2 2.4z" fill="{{c}}"/><path d="M3.2 5.3a7 7 0 019.6 0" fill="none" stroke="{{c}}" stroke-width="1.5" stroke-linecap="round"/><path d="M5.4 7.6a4.2 4.2 0 015.2 0" fill="none" stroke="{{c}}" stroke-width="1.5" stroke-linecap="round"/>`,
  whatsapp: `<path fill="{{c}}" fill-rule="evenodd" clip-rule="evenodd" d="M12 2.2a9.8 9.8 0 00-8.4 14.9L2.2 21.8l4.9-1.3A9.8 9.8 0 1012 2.2zm-4.3 5.2c.2-.4.4-.5.7-.5h.5c.2 0 .4.1.5.4l.7 1.7c.1.2 0 .4-.1.6l-.5.5c-.1.1-.1.3 0 .5.6 1.1 1.4 1.9 2.5 2.5.2.1.4.1.5 0l.6-.6c.1-.2.3-.2.5-.2l1.7.8c.2.1.3.3.3.5v.6c0 .7-.6 1.3-1.3 1.4-3.5.4-7-3-6.8-6.5 0-.5.2-1 .2-1.2z"/>`,
};

function icon(parent, name, size, color, opts = {}) {
  const svg = `<svg width="24" height="24" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">${ICON[name].replace(/\{\{c\}\}/g, color)}</svg>`;
  const n = figma.createNodeFromSvg(svg);
  n.name = "icon/" + name;
  n.resize(size, size);
  parent.appendChild(n);
  if (opts.x !== undefined) n.x = opts.x;
  if (opts.y !== undefined) n.y = opts.y;
  return n;
}

/* ------------------------------ primitives ------------------------------ */

function mark(size, radius = 8) {
  const m = figma.createFrame();
  m.name = "Vault Mark";
  m.resize(size, size);
  m.cornerRadius = radius;
  m.layoutMode = "HORIZONTAL";
  m.primaryAxisSizingMode = "FIXED";
  m.counterAxisSizingMode = "FIXED";
  m.primaryAxisAlignItems = "CENTER";
  m.counterAxisAlignItems = "CENTER";
  m.fills = [grad([C.blueBright, C.blueDeep])];
  m.strokes = [solid("#FFFFFF", 0.25)];
  m.strokeWeight = 1;
  m.effects = [shadow(C.blue, 0.5, 0, 6, 16, -6)];
  icon(m, "vault", size * 0.56, "#FFFFFF");
  return m;
}

function pill(label, color, textColor, opts = {}) {
  const p = hug("Pill", opts.h || 19, {
    gap: 5,
    pl: 7,
    pr: 7,
    fill: solid(color, 0.12),
    stroke: solid(color, 0.28),
    r: opts.r || 6,
    effects: [shadow(color, 0.3, 0, 0, 16, -6)],
  });
  if (opts.dot !== false) {
    const d = figma.createEllipse();
    d.resize(4.5, 4.5);
    d.fills = [solid(color)];
    p.appendChild(d);
  }
  addT(p, label, {
    mono: true,
    size: opts.size || 7.5,
    weight: "SemiBold",
    ls: 0.9,
    color: textColor,
    lh: opts.size ? opts.size + 2 : 11,
  });
  return p;
}

function copyButton(size = 34, iconSize = 15) {
  const b = box("Copy", 0, 0, size, size, {
    fill: solid(C.blue, 0.13),
    stroke: solid(C.blue, 0.3),
    r: 10,
  });
  b.layoutMode = "HORIZONTAL";
  b.primaryAxisSizingMode = "FIXED";
  b.counterAxisSizingMode = "FIXED";
  b.primaryAxisAlignItems = "CENTER";
  b.counterAxisAlignItems = "CENTER";
  icon(b, "copy", iconSize, C.blueText);
  return b;
}

function copyPill() {
  const p = hug("Copy Pill", 31, {
    gap: 5,
    pl: 11,
    pr: 11,
    fill: grad(["#4C8DF7", "#2563EB"]),
    r: 999,
    effects: [shadow(C.blueDeep, 0.55, 0, 6, 16, -6)],
  });
  icon(p, "copy", 12, "#FFFFFF");
  addT(p, "Copy", { size: 10, weight: "Bold", color: "#FFFFFF", lh: 12 });
  return p;
}

function primaryButton(label, w, h = 52, iconName = "download") {
  const b = row("Primary Button", w, h, {
    fill: grad(["#4E90F9", "#2F74E8", C.blueDeep]),
    r: 14,
    justify: "CENTER",
    effects: [shadow(C.blue, 0.45, 0, 12, 26, -12)],
  });
  const group = hug("Button Label", h, { gap: 8 });
  icon(group, iconName, 17, "#FFFFFF");
  addT(group, label, { size: 12.5, weight: "Bold", color: "#FFFFFF", lh: 15 });
  b.appendChild(group);
  return b;
}

function outlineButton(label, w, iconName) {
  const b = row("Secondary Button", w, 44, {
    fill: solid(C.surface, 0.7),
    stroke: solid(C.borderStrong),
    r: 12,
    justify: "CENTER",
    gap: 7,
  });
  icon(b, iconName, 14, "#8FA0B8");
  addT(b, label, { size: 10.5, weight: "SemiBold", color: "#C7D0DD", lh: 13 });
  return b;
}

function statusRow(iconName, colorBg, colorFg) {
  const t = box("Icon Tile", 0, 0, 34, 34, {
    fill: solid(colorBg, 0.1),
    stroke: solid(colorBg, 0.2),
    r: 11,
  });
  t.layoutMode = "HORIZONTAL";
  t.primaryAxisSizingMode = "FIXED";
  t.counterAxisSizingMode = "FIXED";
  t.primaryAxisAlignItems = "CENTER";
  t.counterAxisAlignItems = "CENTER";
  icon(t, iconName, 16, colorFg);
  return t;
}

function sectionHead(label, rightText, opts = {}) {
  const r = row("Section Head", 361, 16, { justify: "SPACE_BETWEEN" });
  addT(r, label, {
    mono: true, size: 9, weight: "Medium", ls: 1.6, color: C.text3, lh: 12,
  });
  const right = hug("Right", 14, { gap: 2 });
  addT(right, rightText, {
    size: 9.5, weight: "SemiBold", color: "#7F8DA3", lh: 12,
  });
  if (opts.chevron) icon(right, "chev", 11, "#7F8DA3");
  r.appendChild(right);
  return r;
}

function badge(label, color, textColor) {
  const b = hug("Badge", 20, {
    pl: 7, pr: 7, fill: solid(color, 0.15), stroke: solid(color, 0.35), r: 6,
  });
  addT(b, label, { mono: true, size: 8, weight: "SemiBold", ls: 1.2, color: textColor, lh: 10 });
  return b;
}

/* -------------------------------- screens ------------------------------- */

function statusBar(screen) {
  const sb = box("Status Bar", 0, 0, 393, 44, {});
  screen.appendChild(sb);

  addT(sb, "9:41", {
    size: 12.5, weight: "Bold", color: C.text, lh: 16, x: 26, y: 13,
  });

  const heights = [5, 7, 9, 11];
  heights.forEach((h, i) => {
    const r = figma.createRectangle();
    r.resize(3, h);
    r.x = 296 + i * 5;
    r.y = 31 - h;
    r.cornerRadius = 1;
    r.fills = [solid("#E5E7EB", i === 3 ? 0.35 : 1)];
    sb.appendChild(r);
  });
  icon(sb, "wifi", 15, "#E5E7EB", { x: 323, y: 20 });

  const bat = box("Battery", 0, 0, 23, 11, {
    stroke: solid("#E5E7EB", 0.55), r: 3.5,
  });
  bat.x = 346; bat.y = 20;
  sb.appendChild(bat);
  const batFill = figma.createRectangle();
  batFill.resize(13, 6.5);
  batFill.x = 2.2; batFill.y = 2.2;
  batFill.cornerRadius = 1.5;
  batFill.fills = [solid("#E5E7EB")];
  bat.appendChild(batFill);

  const cap = figma.createRectangle();
  cap.resize(1.8, 4);
  cap.x = 24; cap.y = 3.5;
  cap.fills = [solid("#E5E7EB", 0.55)];
  sb.appendChild(cap);

  const island = box("Dynamic Island", 0, 0, 98, 26, { fill: solid("#020408"), r: 13 });
  screen.appendChild(island);
  island.layoutPositioning = "ABSOLUTE";
  island.x = 147.5;
  island.y = 9;
  const cam = figma.createEllipse();
  cam.resize(8, 8);
  cam.x = 74; cam.y = 9;
  cam.fills = [radialGlow(C.blue, 0.4)];
  island.appendChild(cam);
}

function homeIndicator(screen) {
  const h = box("Home Indicator", 0, 0, 132, 4, { fill: solid("#FFFFFF", 0.28), r: 999 });
  screen.appendChild(h);
  h.layoutPositioning = "ABSOLUTE";
  h.x = 130.5;
  h.y = 838;
}

function iconButton(screen, name, size = 34, ghost = false) {
  const b = box("Icon Button", 0, 0, size, size, {
    fill: ghost ? null : solid(C.surface, 0.7),
    stroke: ghost ? null : solid(C.border),
    r: 11,
  });
  b.layoutMode = "HORIZONTAL";
  b.primaryAxisSizingMode = "FIXED";
  b.counterAxisSizingMode = "FIXED";
  b.primaryAxisAlignItems = "CENTER";
  b.counterAxisAlignItems = "CENTER";
  icon(b, name, ghost ? 17 : 16, ghost ? "#C7D0DD" : "#B6C0CF");
  return b;
}

function makeScreen(name, x) {
  const s = figma.createFrame();
  s.name = name;
  s.resize(393, 852);
  s.x = x;
  s.y = 120;
  s.fills = [solid(C.bg)];
  s.clipsContent = true;
  s.layoutMode = "VERTICAL";
  s.primaryAxisSizingMode = "FIXED";
  s.counterAxisSizingMode = "FIXED";
  s.itemSpacing = 0;

  const glow = figma.createEllipse();
  glow.name = "Top Glow";
  glow.resize(560, 340);
  glow.x = -84;
  glow.y = -190;
  glow.fills = [radialGlow(C.blue, 0.16)];
  s.appendChild(glow);
  glow.layoutPositioning = "ABSOLUTE";
  glow.x = -84;
  glow.y = -190;

  statusBar(s);

  const content = col("Content", 393, { pl: 16, pr: 16, pt: 8 });
  content.layoutAlign = "STRETCH";
  s.appendChild(content);

  return { s, c: content };
}

/* ------------------------------- screen 1 ------------------------------- */

function buildHome(x) {
  const { s, c } = makeScreen("01 · Home — Command Center", x);

  // App bar
  const ab = row("App Bar", 361, 32, { justify: "SPACE_BETWEEN" });
  const brand = hug("Brand", 32, { gap: 9 });
  brand.appendChild(mark(27, 8));
  addT(brand, "EXAMVAULT", {
    mono: true, size: 10.5, weight: "SemiBold", ls: 2.6, color: "#E5E7EB", lh: 13,
  });
  ab.appendChild(brand);

  const actions = hug("Actions", 34, { gap: 8 });
  const bell = iconButton(s, "bell");
  const nd = figma.createEllipse();
  nd.resize(6, 6);
  nd.x = 22; nd.y = 7;
  nd.fills = [solid(C.red)];
  nd.effects = [shadow(C.red, 0.8, 0, 0, 7, 0)];
  bell.appendChild(nd);
  nd.layoutPositioning = "ABSOLUTE";
  nd.x = 22;
  nd.y = 7;
  actions.appendChild(bell);
  const av = centerBox("Avatar", 32, 32, {
    fill: solid("#1E293B"), stroke: solid("#93C5FD", 0.3), r: 999,
  });
  addT(av, "A", { size: 11.5, weight: "Bold", color: "#DBEAFE", lh: 14 });
  actions.appendChild(av);
  ab.appendChild(actions);
  c.appendChild(ab);

  vspace(c, 15);

  // Hero
  const hero = col("Hero", 361, { gap: 5 });
  addT(hero, "SUNDAY · 08 NOV 2026", {
    mono: true, size: 9, weight: "Regular", ls: 1.7, color: "#7C8AA3", lh: 12,
  });
  addT(hero, "Command Center", {
    size: 26.5, weight: "Bold", ls: -0.7, color: C.text, lh: 30, name: "Command Center",
  });
  const sub = hug("Hero Sub", 17, { gap: 4 });
  addT(sub, "3 exams tracked", { size: 11.5, weight: "Medium", color: C.text2, lh: 15 });
  addT(sub, "·", { size: 11.5, weight: "Medium", color: "#3A4658", lh: 15 });
  addT(sub, "1 live update", { size: 11.5, weight: "Medium", color: C.green, lh: 15 });
  hero.appendChild(sub);
  c.appendChild(hero);

  vspace(c, 13);

  // Chips
  const chips = row("Filter Chips", 361, 32, { gap: 7, clip: true, align: "CENTER" });
  const chipData = [
    ["All Exams", true], ["SSC", false], ["UPSC", false], ["IBPS/SBI", false], ["Railways", false], ["State PSC", false],
  ];
  chipData.forEach(([label, active]) => {
    const ch = hug("Chip", 30, {
      pl: 13, pr: 13,
      fill: active ? solid(C.blue, 0.15) : solid(C.surface, 0.55),
      stroke: active ? solid(C.blue, 0.45) : solid(C.border),
      r: 999,
    });
    if (active) ch.effects = [shadow(C.blue, 0.25, 0, 0, 18, -8)];
    addT(ch, label, {
      size: 11, weight: "SemiBold", color: active ? "#BFDBFE" : "#AEB8C7", lh: 14,
    });
    chips.appendChild(ch);
  });
  c.appendChild(chips);

  vspace(c, 17);
  c.appendChild(sectionHead("MY ADMIT CARDS", "3 saved", { chevron: true }));

  vspace(c, 8);

  // Wallet stack
  const wallet = box("Wallet Stack", 0, 0, 361, 264, {});
  c.appendChild(wallet);

  const back3 = walletCard(321, 164, {
    name: "Wallet · RRB NTPC", x: 20, y: 0,
    colors: ["#1C2433", "#141B28", "#101723"],
    badgeLabel: "RRB", badgeColor: C.amber, badgeText: C.amberText,
    title: "RRB NTPC 2026", meta: "In 34 days", opacity: 0.94,
  });
  wallet.appendChild(back3);
  const back2 = walletCard(341, 164, {
    name: "Wallet · IBPS PO", x: 10, y: 40,
    colors: ["#1A2438", "#131C2C", "#0F1624"],
    badgeLabel: "IBPS", badgeColor: C.blue, badgeText: "#BFDBFE",
    title: "IBPS PO Prelims 2026", meta: "In 21 days", opacity: 0.97,
  });
  wallet.appendChild(back2);

  const front = walletCard(361, 176, {
    name: "Wallet · SSC CGL", x: 0, y: 88,
    colors: ["#1E2C46", "#172136", "#121A29"],
    badgeLabel: "SSC", badgeColor: C.blue, badgeText: "#BFDBFE",
    title: "SSC CGL Tier-1 2026", meta: "", front: true,
  });
  wallet.appendChild(front);

  vspace(c, 17);
  const radarHead = row("Live Radar Head", 361, 16, { justify: "SPACE_BETWEEN" });
  const rl = hug("Radar Label", 14, { gap: 7 });
  const dot = figma.createEllipse();
  dot.resize(6, 6);
  dot.fills = [solid(C.green)];
  dot.effects = [shadow(C.green, 0.8, 0, 0, 10, 2)];
  rl.appendChild(dot);
  addT(rl, "LIVE RADAR", { mono: true, size: 9, weight: "Medium", ls: 1.6, color: C.text3, lh: 12 });
  radarHead.appendChild(rl);
  addT(radarHead, "UPDATED 12S AGO", {
    mono: true, size: 8.5, weight: "Regular", ls: 1.1, color: "#5D6B80", lh: 11,
  });
  c.appendChild(radarHead);

  vspace(c, 8);
  const feed = col("Live Feed", 361, {
    fill: solid(C.surface), stroke: solid(C.border), r: 18, clip: true,
  });
  c.appendChild(feed);
  const updates = [
    ["pdf", C.green, C.greenText, "SSC CGL Tier-1 2026", "Direct PDF · 18.4 MB", "RESULT OUT", "2m"],
    ["clock", C.amber, C.amberText, "IBPS PO Prelims 2026", "4 mirrors live · no queue", "CARD LIVE", "18m"],
    ["radar", C.red, C.redText, "RRB NTPC 2026", "Application closes 11:59 PM", "CLOSING", "1h"],
  ];
  updates.forEach((u, i) => {
    if (i > 0) {
      const d = row("Divider", 361, 1, { pl: 13, pr: 13 });
      d.fills = [];
      const ln = figma.createRectangle();
      ln.resize(335, 1);
      ln.fills = [solid("#FFFFFF", 0.05)];
      d.appendChild(ln);
      feed.appendChild(d);
    }
    feed.appendChild(feedRow(u));
  });

  // Bottom fade + tab bar
  const fade = box("Bottom Fade", 0, 0, 393, 104, {});
  fade.fills = [{
    type: "GRADIENT_LINEAR",
    gradientTransform: [[0, 1, 0], [-1, 0, 1]],
    gradientStops: [
      { position: 0, color: { ...rgb(C.bg), a: 0 } },
      { position: 1, color: { ...rgb(C.bg), a: 0.96 } },
    ],
  }];
  s.appendChild(fade);
  fade.layoutPositioning = "ABSOLUTE";
  fade.x = 0;
  fade.y = 748;

  const tab = row("Tab Bar", 361, 58, {
    fill: solid(C.surface, 0.92), stroke: solid("#94A3B8", 0.13), r: 19, pl: 5, pr: 5,
    gap: 4, justify: "SPACE_BETWEEN",
    effects: [shadow("#000000", 0.5, 0, 18, 40, -16)],
  });
  s.appendChild(tab);
  tab.layoutPositioning = "ABSOLUTE";
  tab.x = 16; tab.y = 770;

  // Shipped tabs are Home / Vault / Radar / Share (EvTab in root_shell.dart).
  // "Groups" was never built.
  const tabs = [["home", "Home", true, false], ["lock", "Vault", false, false], ["radar", "Radar", false, true], ["share", "Share", false, false]];
  tabs.forEach(([ic, label, active, dotOn]) => {
    const t = col("Tab · " + label, 80, {
      h: 48, gap: 3, align: "CENTER", justify: "CENTER",
      fill: active ? solid(C.blue, 0.13) : null,
      r: 14,
    });
    const iw = row("Icon Wrap", 20, 18, { justify: "CENTER" });
    iw.fills = [];
    icon(iw, ic, 18, active ? C.blueText : "#68778E");
    if (dotOn) {
      const d = figma.createEllipse();
      d.resize(5, 5);
      d.x = 16; d.y = 0;
      d.fills = [solid(C.red)];
      d.effects = [shadow(C.red, 0.7, 0, 0, 6, 0)];
      iw.appendChild(d);
      d.layoutPositioning = "ABSOLUTE";
      d.x = 16;
      d.y = 0;
    }
    t.appendChild(iw);
    addT(t, label, { size: 8, weight: "SemiBold", color: active ? C.blueText : "#68778E", lh: 10 });
    tab.appendChild(t);
  });

  homeIndicator(s);
  return s;
}

function walletCard(w, h, o) {
  const card = col(o.name, w, {
    h, pl: 16, pr: 16, pt: o.front ? 15 : 13, pb: o.front ? 14 : 13,
    fill: grad(o.colors), stroke: solid(o.front ? C.walletBorder : C.border), r: 20, clip: true,
    effects: [shadow("#000000", 0.6, 0, 18, 40, -20)],
  });
  if (o.x !== undefined) card.x = o.x;
  if (o.y !== undefined) card.y = o.y;
  if (o.opacity) card.opacity = o.opacity;

  const highlight = figma.createRectangle();
  highlight.name = "Inner Top Highlight";
  highlight.resize(w, 1);
  highlight.x = 0; highlight.y = 0;
  highlight.fills = [solid("#FFFFFF", 0.15)];
  card.appendChild(highlight);
  highlight.layoutPositioning = "ABSOLUTE";
  highlight.x = 0;
  highlight.y = 0;

  const top = row("Card Top", w - 32, 22, { justify: "SPACE_BETWEEN" });
  const left = hug("Exam", 20, { gap: 7 });
  left.appendChild(badge(o.badgeLabel, o.badgeColor, o.badgeText));
  if (o.front) {
    addT(left, "CGL · TIER-1", {
      mono: true, size: 8.5, weight: "Regular", ls: 1.4, color: "#7C8DA6", lh: 11,
    });
  } else {
    addT(left, o.title, { size: 11.5, weight: "SemiBold", color: "#D6DEEA", lh: 15, name: "Back Title" });
  }
  top.appendChild(left);
  if (o.front) {
    const cd = hug("Countdown", 22, {
      gap: 5, pl: 8, pr: 8,
      fill: solid(C.amber, 0.11), stroke: solid(C.amber, 0.26), r: 999,
    });
    const d = figma.createEllipse();
    d.resize(5, 5);
    d.fills = [solid(C.amber)];
    d.effects = [shadow(C.amber, 0.8, 0, 0, 6, 0)];
    cd.appendChild(d);
    addT(cd, "IN 12 DAYS", {
      mono: true, size: 8.5, weight: "SemiBold", ls: 0.9, color: C.amberText, lh: 11,
    });
    top.appendChild(cd);
  } else {
    addT(top, o.meta, { mono: true, size: 8.5, weight: "Regular", color: "#8291A8", lh: 11 });
  }
  card.appendChild(top);

  if (!o.front) {
    return card;
  }

  vspace(card, 9);
  addT(card, o.title, { size: 17, weight: "Bold", ls: -0.25, color: "#F3F6FB", lh: 21, name: "Exam Title" });
  vspace(card, 12);

  const rollRow = row("Roll Row", 329, 31, { justify: "SPACE_BETWEEN", align: "MAX" });
  const rollCol = col("Roll", 230, { gap: 3 });
  addT(rollCol, "ROLL NUMBER", { mono: true, size: 8.5, weight: "Medium", ls: 1.25, color: C.text3, lh: 11 });
  addT(rollCol, "2201049821", {
    mono: true, size: 23, weight: "Medium", ls: 1.2, color: "#FFFFFF", lh: 26, name: "Roll Number",
  });
  rollRow.appendChild(rollCol);
  rollRow.appendChild(copyPill());
  card.appendChild(rollRow);

  const grow = figma.createFrame();
  grow.name = "Flex";
  grow.resize(1, 1);
  grow.fills = [];
  grow.layoutGrow = 1;
  grow.layoutAlign = "STRETCH";
  card.appendChild(grow);
  const div = box("Hairline", 0, 0, 329, 1, { fill: solid("#FFFFFF", 0.07) });
  div.layoutAlign = "STRETCH";
  card.appendChild(div);
  vspace(card, 8);

  const foot = row("Card Foot", 329, 14, { justify: "SPACE_BETWEEN" });
  addT(foot, "24 NOV 2026 · 09:00 AM", {
    mono: true, size: 9.5, weight: "Regular", ls: 0.55, color: C.text2, lh: 12,
  });
  const saved = hug("Autosaved", 12, { gap: 5 });
  const sd = figma.createEllipse();
  sd.resize(4, 4);
  sd.fills = [solid(C.green)];
  saved.appendChild(sd);
  addT(saved, "AUTOSAVED", {
    mono: true, size: 8, weight: "SemiBold", ls: 1.2, color: C.greenText, lh: 10,
  });
  foot.appendChild(saved);
  card.appendChild(foot);

  return card;
}

function feedRow(u) {
  const [ic, color, textColor, title, sub, statusText, time] = u;
  const r = row("Update", 361, 59, { pl: 13, pr: 13, gap: 11 });
  r.appendChild(statusRow(ic, color, textColor));
  const main = col("Main", 187, { gap: 2 });
  main.layoutGrow = 1;
  addT(main, title, { size: 11.5, weight: "SemiBold", color: "#E9EDF4", lh: 14 });
  addT(main, sub, { size: 9.5, weight: "Regular", color: "#76859B", lh: 12 });
  r.appendChild(main);
  const right = col("Right", 92, { gap: 4, align: "MAX" });
  right.appendChild(pill(statusText, color, textColor));
  addT(right, time, { mono: true, size: 8, weight: "Regular", color: "#5B697E", lh: 10 });
  r.appendChild(right);
  return r;
}

/* ------------------------------- screen 2 ------------------------------- */

function buildVault(x) {
  const { s, c } = makeScreen("02 · Vault — 1-Tap Card Detail", x);

  const nav = row("Nav", 361, 40, { justify: "SPACE_BETWEEN" });
  nav.appendChild(iconButton(s, "back", 36, true));
  const title = hug("Nav Title", 24, { gap: 7 });
  addT(title, "Saved Pass", { size: 13.5, weight: "SemiBold", ls: -0.2, color: "#E8EDF4", lh: 17 });
  const count = hug("Count", 18, { pl: 6, pr: 6, fill: solid("#FFFFFF", 0.04), stroke: solid(C.border), r: 5 });
  addT(count, "1 / 3", { mono: true, size: 8.5, weight: "Regular", ls: 1, color: "#5E6C81", lh: 10 });
  title.appendChild(count);
  nav.appendChild(title);
  nav.appendChild(iconButton(s, "share", 36, true));
  c.appendChild(nav);

  vspace(c, 16);

  const pass = col("Boarding Pass", 361, {
    fill: grad(["#1A2437", "#141D2E", "#111827"]),
    stroke: solid(C.walletBorder), r: 20, pl: 18, pr: 18, pt: 17, pb: 14, clip: true,
    effects: [shadow("#000000", 0.55, 0, 22, 50, -24)],
  });
  c.appendChild(pass);

  const pglow = figma.createEllipse();
  pglow.resize(230, 190);
  pglow.x = 200; pglow.y = -80;
  pglow.fills = [radialGlow(C.blueBright, 0.18)];
  pass.appendChild(pglow);
  pglow.layoutPositioning = "ABSOLUTE";
  pglow.x = 200;
  pglow.y = -80;

  const head = row("Pass Head", 325, 30, { justify: "SPACE_BETWEEN", align: "MIN" });
  const org = col("Exam Org", 210, { gap: 4 });
  addT(org, "SSC · CGL TIER-1 2026", {
    mono: true, size: 9, weight: "SemiBold", ls: 1.6, color: C.blueText, lh: 11,
  });
  addT(org, "Staff Selection Commission", { size: 10.5, weight: "Medium", color: "#8291A7", lh: 13 });
  head.appendChild(org);
  head.appendChild(pill("SAVED", C.green, C.greenText, { h: 21 }));
  pass.appendChild(head);

  vspace(pass, 15);

  const roll = col("Pass Roll", 325, { gap: 4 });
  addT(roll, "ROLL NUMBER", { mono: true, size: 8.5, weight: "Medium", ls: 1.25, color: C.text3, lh: 11 });
  const rr = row("Roll Value Row", 325, 34, { justify: "SPACE_BETWEEN" });
  addT(rr, "2201049821", {
    mono: true, size: 31, weight: "Medium", ls: 1.6, color: "#FFFFFF", lh: 34, name: "Roll Number",
  });
  rr.appendChild(copyButton(34, 15));
  roll.appendChild(rr);
  pass.appendChild(roll);

  vspace(pass, 15);

  // Perforation with punched notches
  const perf = box("Perforation", 0, 0, 325, 16, {});
  perf.layoutAlign = "STRETCH";
  perf.clipsContent = false;
  const dash = dashedLine(perf, 361, 7.5, 0.15);
  dash.x = -18;
  [-26, 325 + 10].forEach((x, i) => {
    const n = figma.createEllipse();
    n.resize(16, 16);
    n.x = x; n.y = 0;
    n.fills = [solid(C.bg)];
    perf.appendChild(n);
  });
  pass.appendChild(perf);

  vspace(pass, 14);

  const grid1 = row("Fields Row 1", 325, 31, { gap: 16 });
  ["REGISTRATION ID", "SSC-CGL-26-884213", "D.O.B / PASSWORD", "14/03/1999"].forEach((v, i) => {
    if (i % 2 === 0) {
      const f = field(v, i === 0 ? "SSC-CGL-26-884213" : "14/03/1999", 154);
      f.layoutGrow = 1;
      grid1.appendChild(f);
    }
  });
  pass.appendChild(grid1);
  vspace(pass, 14);
  const grid2 = row("Fields Row 2", 325, 31, { gap: 16 });
  ["EXAM CENTER CODE", "DL-04-1187", "EXAM DATE", "24/11/2026"].forEach((v, i) => {
    if (i % 2 === 0) {
      const f = field(v, i === 0 ? "DL-04-1187" : "24/11/2026", 154);
      f.layoutGrow = 1;
      grid2.appendChild(f);
    }
  });
  pass.appendChild(grid2);

  vspace(pass, 15);

  const foot = row("Pass Foot", 325, 25, { gap: 12 });
  foot.appendChild(barcode(150, 25));
  fixedT(foot, "AUTOSAVED ON DEVICE · 2:14 PM", {
    mono: true, size: 7, weight: "Regular", ls: 0.9, color: "#5C6A80", lh: 10,
  }, 163, 10);
  pass.appendChild(foot);

  vspace(c, 12);

  const cd = row("Countdown", 361, 72, {
    fill: solid(C.surface), stroke: solid(C.border), r: 16, pl: 15, pr: 15,
    justify: "SPACE_BETWEEN",
  });
  const cdLeft = col("Countdown Label", 130, { gap: 4 });
  addT(cdLeft, "EXAM COUNTDOWN", { mono: true, size: 8.5, weight: "Medium", ls: 1.25, color: C.text3, lh: 11 });
  addT(cdLeft, "Report by 8:15 AM", { size: 9.5, weight: "Medium", color: "#74839A", lh: 12 });
  cd.appendChild(cdLeft);
  const clock = hug("Clock", 42, { gap: 4 });
  [["12", "DAYS"], ["04", "HRS"], ["32", "MIN"]].forEach(([n, l], i) => {
    if (i > 0) addT(clock, ":", { mono: true, size: 13, weight: "Regular", color: "#39465A", lh: 16 });
    const unit = col("Unit", 36, {
      h: 42, gap: 2, align: "CENTER", justify: "CENTER",
      fill: solid(C.bg), stroke: solid("#222E41"), r: 9,
    });
    addT(unit, n, { mono: true, size: 15, weight: "SemiBold", color: "#E9EEF6", lh: 17 });
    addT(unit, l, { mono: true, size: 6, weight: "Regular", ls: 0.8, color: "#5E6C81", lh: 8 });
    clock.appendChild(unit);
  });
  cd.appendChild(clock);
  c.appendChild(cd);

  vspace(c, 14);

  const check = col("Document Checklist", 361, {
    fill: solid(C.surface), stroke: solid(C.border), r: 18, pl: 15, pr: 15, pt: 13, pb: 4,
  });
  c.appendChild(check);
  const chHead = row("Checklist Head", 331, 16, { justify: "SPACE_BETWEEN" });
  addT(chHead, "DOCUMENT CHECKLIST", { mono: true, size: 9, weight: "Medium", ls: 1.6, color: C.text3, lh: 12 });
  addT(chHead, "3 / 3 READY", { mono: true, size: 8, weight: "SemiBold", ls: 1.1, color: "#34D399", lh: 10 });
  check.appendChild(chHead);
  vspace(check, 4);

  const items = [
    ["Admit Card PDF saved", "18.4 MB · offline"],
    ["2 Passport photos", "Recent · 50×50 mm"],
    ["Original Aadhaar ID", "Carry physical copy"],
  ];
  items.forEach((it, idx) => {
    if (idx > 0) {
      const d = box("Divider", 0, 0, 331, 1, { fill: solid("#FFFFFF", 0.05) });
      d.layoutAlign = "STRETCH";
      check.appendChild(d);
    }
    const r = row("Check Row", 331, 44, { gap: 11 });
    const cb = centerBox("Check", 22, 22, {
      fill: solid(C.green, 0.13), stroke: solid(C.green, 0.36), r: 7,
    });
    icon(cb, "check", 12, "#34D399");
    r.appendChild(cb);
    const m = col("Copy", 230, { gap: 1 });
    addT(m, it[0], { size: 11.5, weight: "SemiBold", color: "#E4E9F1", lh: 14 });
    addT(m, it[1], { size: 9, weight: "Regular", color: "#6F7E94", lh: 11 });
    m.layoutGrow = 1;
    r.appendChild(m);
    addT(r, "DONE", { mono: true, size: 7.5, weight: "SemiBold", ls: 1.1, color: "#34D399", lh: 10 });
    check.appendChild(r);
  });

  vspace(c, 12);

  // Exam centre card
  const center = row("Exam Center", 361, 58, {
    fill: solid(C.surface), stroke: solid(C.border), r: 15, pl: 12, pr: 12, gap: 10,
  });
  const ci = centerBox("Pin", 32, 32, {
    fill: solid(C.blue, 0.11), stroke: solid(C.blue, 0.25), r: 10,
  });
  icon(ci, "pin", 16, C.blueText);
  center.appendChild(ci);
  const cm = col("Center Copy", 230, { gap: 1 });
  addT(cm, "EXAM CENTER · DL-04-1187", { mono: true, size: 7, weight: "Medium", ls: 1.1, color: "#66758B", lh: 9 });
  addT(cm, "Sector 12, Dwarka, New Delhi", { size: 10.5, weight: "SemiBold", color: "#E4E9F1", lh: 13 });
  addT(cm, "Gate 3 · report by 8:15 AM", { size: 8.5, weight: "Regular", color: "#6F7E94", lh: 11 });
  cm.layoutGrow = 1;
  center.appendChild(cm);
  const map = hug("Map", 12, { gap: 2 });
  addT(map, "MAP", { mono: true, size: 7.5, weight: "SemiBold", ls: 0.9, color: C.blueText, lh: 10 });
  icon(map, "external", 10, C.blueText);
  center.appendChild(map);
  c.appendChild(center);

  // Sticky dock
  const scrim = box("Dock Scrim", 0, 715, 393, 50, {});
  scrim.fills = [{
    type: "GRADIENT_LINEAR",
    gradientTransform: [[0, 1, 0], [-1, 0, 1]],
    gradientStops: [
      { position: 0, color: { ...rgb(C.bg), a: 0 } },
      { position: 1, color: { ...rgb(C.bg), a: 1 } },
    ],
  }];
  s.appendChild(scrim);
  scrim.layoutPositioning = "ABSOLUTE";
  scrim.x = 0; scrim.y = 715;

  const dock = col("Action Dock", 361, { gap: 7 });
  s.appendChild(dock);
  dock.layoutPositioning = "ABSOLUTE";
  dock.x = 16; dock.y = 757;
  const cta = row("CTA Row", 361, 52, { gap: 9 });
  const open = primaryButton("Open Admit Card", 300, 52, "download");
  cta.appendChild(open);
  const shareIcon = centerBox("Share", 52, 52, {
    fill: solid(C.surface, 0.75), stroke: solid(C.borderStrong), r: 14,
  });
  icon(shareIcon, "share", 18, "#B9C4D4");
  cta.appendChild(shareIcon);
  dock.appendChild(cta);

  const footNote = row("Dock Note", 361, 11, { gap: 4, justify: "CENTER" });
  icon(footNote, "lock", 9, "#34D399");
  addT(footNote, "TAP ANY FIELD TO COPY · AES-256 · OFFLINE", {
    mono: true, size: 7, weight: "Regular", ls: 0.7, color: "#65748A", lh: 9,
  });
  dock.appendChild(footNote);

  homeIndicator(s);
  return s;
}

function field(label, value, w) {
  const f = col("Field", w, { gap: 4 });
  addT(f, label, { mono: true, size: 8.5, weight: "Medium", ls: 1.25, color: C.text3, lh: 11 });
  const r = hug("Value", 16, { gap: 6 });
  addT(r, value, { mono: true, size: 11.5, weight: "Medium", ls: 0.2, color: "#E7ECF3", lh: 14 });
  icon(r, "copy", 12, "#5F7089");
  f.appendChild(r);
  return f;
}

function barcode(w, h) {
  const f = box("Barcode", 0, 0, w, h, {});
  f.clipsContent = true;
  const pattern = [2, 1, 1, 3, 1, 2, 1, 1, 3, 2, 1, 1, 2, 3, 1, 1, 2, 1, 3, 2, 1, 1, 2, 1, 3];
  let x = 0; let i = 0;
  while (x < w) {
    const bw = pattern[i % pattern.length] === 1 ? 1 : 2;
    if (i % 3 !== 2) {
      const r = figma.createRectangle();
      r.resize(bw, h);
      r.x = x; r.y = 0;
      r.fills = [solid("#DDE3EC", 0.6)];
      f.appendChild(r);
    }
    x += bw + 1;
    i++;
  }
  return f;
}

/* ------------------------------- screen 3 ------------------------------- */

function buildRadar(x) {
  const { s, c } = makeScreen("03 · Radar — Result Checker", x);

  const nav = row("Nav", 361, 40, { justify: "SPACE_BETWEEN" });
  nav.appendChild(iconButton(s, "back", 36, true));
  addT(nav, "Result Radar", { size: 13.5, weight: "SemiBold", ls: -0.2, color: "#E8EDF4", lh: 17 });
  const live = hug("Live", 24, {
    gap: 5, pl: 9, pr: 9,
    fill: solid(C.green, 0.1), stroke: solid(C.green, 0.28), r: 999,
  });
  const ld = figma.createEllipse();
  ld.resize(5, 5);
  ld.fills = [solid(C.green)];
  ld.effects = [shadow(C.green, 0.8, 0, 0, 7, 0)];
  live.appendChild(ld);
  addT(live, "LIVE", { mono: true, size: 8, weight: "SemiBold", ls: 1.2, color: C.greenText, lh: 10 });
  nav.appendChild(live);
  c.appendChild(nav);

  vspace(c, 15);

  const head = col("Result Head", 361, { gap: 7 });
  addT(head, "UPSC · CIVIL SERVICES", { mono: true, size: 9, weight: "Regular", ls: 1.7, color: "#7C8AA3", lh: 12 });
  const h1 = hug("H1", 29, { gap: 4 });
  addT(h1, "UPSC CSE Prelims 2026", { size: 22, weight: "Bold", ls: -0.5, color: C.text, lh: 26 });
  addT(h1, "Result", { size: 22, weight: "Bold", ls: -0.5, color: C.green, lh: 26 });
  head.appendChild(h1);
  addT(head, "RELEASED 09:12 IST · 08 NOV 2026", {
    mono: true, size: 9.5, weight: "Regular", ls: 0.55, color: C.text2, lh: 12,
  });
  c.appendChild(head);

  vspace(c, 15);

  const server = col("Mirror Status", 361, {
    fill: solid(C.surface), stroke: solid(C.border), r: 18, pl: 14, pr: 14, pt: 13, pb: 6,
  });
  c.appendChild(server);
  const sh = row("Server Head", 333, 16, { justify: "SPACE_BETWEEN" });
  addT(sh, "MIRROR STATUS", { mono: true, size: 9, weight: "Medium", ls: 1.6, color: C.text3, lh: 12 });
  const ar = hug("Auto", 12, { gap: 5 });
  const ad = figma.createEllipse();
  ad.resize(4, 4);
  ad.fills = [solid(C.green)];
  ad.effects = [shadow(C.green, 0.8, 0, 0, 6, 0)];
  ar.appendChild(ad);
  addT(ar, "AUTO-REFRESH 30s", { mono: true, size: 7.5, weight: "Regular", ls: 0.9, color: C.greenText, lh: 10 });
  sh.appendChild(ar);
  server.appendChild(sh);
  vspace(server, 3);

  const rows = [
    ["Server 1", "· upsc.gov.in", 74, C.amber, "BUSY", "1,204ms"],
    ["Direct PDF Mirror", "", 22, C.green, "FAST", "82ms"],
    ["Vault Cache", "· instant", 8, C.blue, "READY", "4ms"],
  ];
  rows.forEach(([name, sub, pct, color, state, ms], i) => {
    if (i > 0) {
      const d = box("Divider", 0, 0, 333, 1, { fill: solid("#FFFFFF", 0.05) });
      d.layoutAlign = "STRETCH";
      server.appendChild(d);
    }
    const r = row("Mirror Row", 333, 44, { gap: 9 });
    const nm = hug("Name", 16, { gap: 3 });
    addT(nm, name, { size: 11, weight: "SemiBold", color: "#DDE4EE", lh: 14 });
    if (sub) addT(nm, sub, { size: 9.5, weight: "Regular", color: "#6D7C92", lh: 12 });
    nm.layoutGrow = 1;
    r.appendChild(nm);
    const bar = box("Latency", 0, 0, 52, 4, { fill: solid("#1C2739"), r: 99, clip: true });
    const fill = figma.createRectangle();
    fill.resize(Math.max(4, Math.round(52 * pct / 100)), 4);
    fill.fills = [grad([color, "#FFFFFF"], 0.9, true)];
    fill.opacity = 0.85;
    bar.appendChild(fill);
    r.appendChild(bar);
    fixedT(r, state, { mono: true, size: 7.5, weight: "SemiBold", ls: 0.7, color, lh: 10, align: "RIGHT", name: "State" }, 38, 10);
    fixedT(r, ms, { mono: true, size: 8, weight: "Regular", color: "#66758B", lh: 10, align: "RIGHT" }, 47, 10);
    server.appendChild(r);
  });

  vspace(c, 8);
  const note = row("Retry Note", 361, 14, { gap: 5, pl: 2 });
  icon(note, "spark", 12, "#4E5D73");
  addT(note, "Server checked 4s ago · retrying automatically", {
    mono: true, size: 8, weight: "Regular", ls: 0.4, color: "#5E6D83", lh: 10,
  });
  note.layoutAlign = "STRETCH";
  c.appendChild(note);

  vspace(c, 9);

  const dl = primaryButton("Download Official PDF", 361, 52, "download");
  const meta = hug("Size", 24, { pl: 7, pr: 7, fill: solid("#000000", 0.16), r: 6 });
  addT(meta, "4.2 MB", { mono: true, size: 9.5, weight: "Medium", ls: 0.4, color: "#FFFFFF", lh: 12 });
  dl.primaryAxisAlignItems = "SPACE_BETWEEN";
  dl.paddingLeft = 18; dl.paddingRight = 14;
  dl.appendChild(meta);
  c.appendChild(dl);

  vspace(c, 8);
  const pair = row("Secondary Actions", 361, 44, { gap: 8 });
  pair.appendChild(outlineButton("Open Mirror", 176, "external"));
  pair.appendChild(outlineButton("Copy Link", 177, "link"));
  c.appendChild(pair);

  vspace(c, 18);

  c.appendChild(sectionHead("FIND MY ROLL NUMBER", "In PDF"));
  vspace(c, 8);

  const search = row("Search Bar", 361, 52, {
    fill: solid(C.sunken), stroke: solid("#283650"), r: 14, pl: 13, pr: 7, gap: 9,
  });
  icon(search, "search", 17, "#718199");
  addT(search, "0812045678", {
    mono: true, size: 14, weight: "Medium", ls: 1.2, color: "#F1F5FA", lh: 18, name: "Search Value",
  });
  const caret = figma.createRectangle();
  caret.resize(1.5, 18);
  caret.fills = [solid(C.blueBright)];
  caret.effects = [shadow(C.blueBright, 0.8, 0, 0, 8, 0)];
  search.appendChild(caret);
  const searchGrow = figma.createFrame();
  searchGrow.name = "Flex";
  searchGrow.resize(1, 1);
  searchGrow.fills = [];
  searchGrow.layoutGrow = 1;
  search.appendChild(searchGrow);
  const find = hug("Find", 38, {
    pl: 15, pr: 15, justify: "CENTER",
    fill: grad(["#4C8DF7", C.blueDeep]), r: 10,
  });
  addT(find, "Find", { size: 10.5, weight: "Bold", color: "#FFFFFF", lh: 13 });
  search.appendChild(find);
  c.appendChild(search);

  vspace(c, 8);

  const found = row("Found", 361, 54, {
    fill: solid(C.green, 0.07), stroke: solid(C.green, 0.2), r: 12, pl: 11, pr: 11, gap: 10,
  });
  const fi = centerBox("Found Icon", 26, 26, {
    fill: solid(C.green, 0.15), stroke: solid(C.green, 0.3), r: 8,
  });
  icon(fi, "check", 13, "#34D399");
  found.appendChild(fi);
  const fm = col("Found Copy", 235, { gap: 2 });
  addT(fm, "Roll number found", { size: 11, weight: "SemiBold", color: "#DDF5EA", lh: 14 });
  addT(fm, "Page 14 · UPSC CSE Prelims 2026", { mono: true, size: 8, weight: "Regular", color: "#6F8291", lh: 10 });
  fm.layoutGrow = 1;
  found.appendChild(fm);
  const jump = hug("Jump", 12, { gap: 1 });
  addT(jump, "JUMP", { mono: true, size: 8, weight: "SemiBold", ls: 0.9, color: "#34D399", lh: 10 });
  icon(jump, "chev", 10, "#34D399");
  found.appendChild(jump);
  c.appendChild(found);

  vspace(c, 16);

  c.appendChild(sectionHead("RECENT CHECKS", "Clear"));
  vspace(c, 7);

  const recent = col("Recent Checks", 361, {
    fill: solid(C.surface), stroke: solid(C.border), r: 16, clip: true,
  });
  c.appendChild(recent);
  [
    ["SSC CGL Tier-1 2025", "Checked 12 Mar 2026", "FOUND", C.green, C.greenText],
    ["UPSC CSE Mains 2025", "Checked 04 Jan 2026", "AWAITED", C.amber, C.amberText],
  ].forEach((it, i) => {
    if (i > 0) {
      const d = box("Divider", 0, 0, 361, 1, { fill: solid("#FFFFFF", 0.05) });
      d.layoutAlign = "STRETCH";
      recent.appendChild(d);
    }
    const r = row("Recent Row", 361, 50, { pl: 12, pr: 12, gap: 9 });
    const m = col("Recent Copy", 230, { gap: 2 });
    addT(m, it[0], { size: 11, weight: "SemiBold", color: "#E3E9F1", lh: 14 });
    addT(m, it[1], { mono: true, size: 8, weight: "Regular", color: "#6C7B91", lh: 10 });
    m.layoutGrow = 1;
    r.appendChild(m);
    r.appendChild(pill(it[2], it[3], it[4], { h: 18, size: 7 }));
    icon(r, "chev", 12, "#4F5D72");
    recent.appendChild(r);
  });

  homeIndicator(s);
  return s;
}

/* ------------------------------- screen 4 ------------------------------- */

function buildShare(x) {
  const { s, c } = makeScreen("04 · Share — WhatsApp Card", x);

  const nav = row("Nav", 361, 40, { justify: "SPACE_BETWEEN" });
  nav.appendChild(iconButton(s, "x", 36, true));
  addT(nav, "Share Card", { size: 13.5, weight: "SemiBold", ls: -0.2, color: "#E8EDF4", lh: 17 });
  const prev = hug("Preview", 24, {
    pl: 9, pr: 9, fill: solid("#FFFFFF", 0.03), stroke: solid(C.border), r: 999,
  });
  addT(prev, "PREVIEW", { mono: true, size: 8, weight: "SemiBold", ls: 1.2, color: "#7C8AA3", lh: 10 });
  nav.appendChild(prev);
  c.appendChild(nav);

  vspace(c, 14);

  const stage = col("Share Stage", 361, { align: "CENTER" });
  c.appendChild(stage);

  const glow = figma.createEllipse();
  glow.resize(360, 320);
  glow.x = 0; glow.y = 10;
  glow.fills = [radialGlow(C.blue, 0.22)];
  stage.appendChild(glow);
  glow.layoutPositioning = "ABSOLUTE";
  glow.x = 0; glow.y = 10;

  const card = col("Share Card", 345, {
    fill: solid(C.alabaster), r: 20, clip: true,
    effects: [shadow("#000000", 0.7, 0, 26, 55, -18)],
  });
  stage.appendChild(card);

  const alert = row("Alert", 345, 38, {
    fill: grad(["#F05252", "#DC2626"], 1, true), pl: 17, pr: 17, justify: "SPACE_BETWEEN",
  });
  const al = hug("Alert Text", 14, { gap: 5 });
  addT(al, "🚨", { size: 10, weight: "Regular", color: "#FFFFFF", lh: 13 });
  addT(al, "RESULT IS LIVE", { size: 9.5, weight: "ExtraBold", ls: 1.3, color: "#FFFFFF", lh: 12 });
  alert.appendChild(al);
  addT(alert, "08 NOV 2026", { mono: true, size: 8, weight: "Medium", ls: 0.9, color: "#FFFFFF", lh: 10 }).opacity = 0.86;
  card.appendChild(alert);

  const body = col("Card Body", 345, { pl: 18, pr: 18, pt: 17, pb: 15 });
  card.appendChild(body);

  const brand = row("Brand Row", 309, 17, { justify: "SPACE_BETWEEN" });
  const bl = hug("Brand", 17, { gap: 6 });
  const bm = centerBox("Brand Mark", 17, 17, {
    fill: grad([C.blueBright, C.blueDeep]), r: 5,
  });
  icon(bm, "vault", 10, "#FFFFFF");
  bl.appendChild(bm);
  addT(bl, "EXAMVAULT", { mono: true, size: 8.5, weight: "SemiBold", ls: 1.9, color: "#64748B", lh: 11 });
  brand.appendChild(bl);
  // The app's real CTA line (share_infographic.dart). The project owns no
  // domain, so the card never prints a URL — the fictional one that used to
  // sit here was never registered by anyone.
  addT(brand, "Ask in your study group", { mono: true, size: 8, weight: "Regular", ls: 0.3, color: "#94A3B8", lh: 10 });
  body.appendChild(brand);

  vspace(body, 14);
  addT(body, "SSC CGL · TIER-1 2026", {
    mono: true, size: 8.5, weight: "SemiBold", ls: 1.5, color: C.blueDeep, lh: 11,
  });
  vspace(body, 6);

  addT(body, "RESULT", {
    size: 39, weight: "ExtraBold", ls: -1.9, color: C.ink, lh: 37, name: "Headline / RESULT",
  });
  const line2 = hug("Headline / IS LIVE", 37, { gap: 0 });
  addT(line2, "IS ", {
    size: 39, weight: "ExtraBold", ls: -1.9, color: C.ink, lh: 37,
  });
  const liveText = T("LIVE", {
    size: 39, weight: "ExtraBold", ls: -1.9, color: C.ink, lh: 37,
  });
  const liveWidth = liveText.width;
  const liveWrap = box("LIVE Highlight", 0, 0, liveWidth + 4, 37, {});
  const hi = figma.createRectangle();
  hi.resize(liveWidth + 4, 13);
  hi.x = 0; hi.y = 23;
  hi.fills = [solid(C.blue, 0.22)];
  liveWrap.appendChild(hi);
  const hiLine = figma.createRectangle();
  hiLine.resize(liveWidth + 4, 3);
  hiLine.x = 0; hiLine.y = 33;
  hiLine.fills = [solid(C.blue, 0.9)];
  liveWrap.appendChild(hiLine);
  liveText.x = 2; liveText.y = 0;
  liveWrap.appendChild(liveText);
  line2.appendChild(liveWrap);
  body.appendChild(line2);
  vspace(body, 9);
  // Real subline for a published result (whatsapp_share_card_screen.dart).
  // "Cut-off & direct PDF link inside" promised data the app never fabricates.
  addT(body, "Official link & instant roll-number check", {
    size: 11, weight: "SemiBold", ls: -0.1, color: "#475569", lh: 14,
  });
  vspace(body, 13);

  // The invented CUT-OFF grid (UR 152.5 / OBC 149.0 / SC 141.0 / ST 138.5)
  // was removed: the shipped card renders cut-offs ONLY when a publisher
  // actually released them (_CutoffBlock in share_infographic.dart), and the
  // numbers above were made up for the mock.

  const cta = row("Share CTA", 309, 40, {
    fill: solid(C.blueDeep), r: 10, pl: 13, pr: 13, justify: "SPACE_BETWEEN",
    effects: [shadow(C.blueDeep, 0.3, 0, 8, 18, -8)],
  });
  addT(cta, "Check your roll no.", { size: 11, weight: "Bold", color: "#FFFFFF", lh: 14 });
  addT(cta, "→", { size: 15, weight: "Medium", color: "#FFFFFF", lh: 16 });
  body.appendChild(cta);

  vspace(body, 10);
  // Real footer (share_infographic.dart): always-true claims only. The shipped
  // code even documents why "VERIFIED SOURCE" was dropped — it is a promise
  // the app cannot keep for a card the user typed in themselves — and
  // "JOIN 12,480 ASPIRANTS" was an invented counter.
  fixedT(body, "FREE · NO ACCOUNT · CHECKED ON YOUR DEVICE", {
    mono: true, size: 6.5, weight: "Regular", ls: 0.8, color: "#94A3B8", lh: 9, align: "CENTER",
  }, 309, 9);

  vspace(c, 17);

  const targets = row("Share Targets", 361, 70);
  const targetData = [
    ["WhatsApp", "whatsapp", C.green, "#25D366", true],
    ["Telegram", "send", C.blue, "#54A9EB", false],
    ["Copy link", "link", C.text3, "#AEB9C9", false],
    ["Save", "save", C.text3, "#AEB9C9", false],
  ];
  targetData.forEach(([label, ic, color, fg, hot]) => {
    const t = col("Target · " + label, 72, { gap: 6, align: "CENTER" });
    const tile = centerBox("Tile", 46, 46, {
      fill: solid(color, hot ? 0.11 : 0),
      stroke: solid(color, hot ? 0.32 : C.border),
      r: 16,
      effects: hot ? [shadow(color, 0.4, 0, 0, 22, -8)] : [],
    });
    if (!hot) tile.fills = [solid(C.surface)];
    icon(tile, ic, 20, fg);
    t.appendChild(tile);
    addT(t, label, { size: 8.5, weight: "SemiBold", color: hot ? "#D8E4F4" : "#8494AB", lh: 11 });
    targets.appendChild(t);
  });
  targets.primaryAxisAlignItems = "SPACE_BETWEEN";
  c.appendChild(targets);

  vspace(c, 10);

  const group = row("Study Group", 361, 50, {
    fill: solid(C.surface), stroke: solid(C.border), r: 13, pl: 12, pr: 12, gap: 10,
  });
  const gi = centerBox("Group Icon", 28, 28, {
    fill: solid(C.green, 0.1), stroke: solid(C.green, 0.26), r: 9,
  });
  icon(gi, "whatsapp", 15, "#25D366");
  group.appendChild(gi);
  const gm = col("Group Copy", 230, { gap: 1 });
  addT(gm, "SSC CGL 2026 Warriors", { size: 11, weight: "SemiBold", color: "#E3E9F1", lh: 14 });
  addT(gm, "248 members · WhatsApp group", { size: 8.5, weight: "Regular", color: "#718097", lh: 11 });
  gm.layoutGrow = 1;
  group.appendChild(gm);
  addT(group, "CHANGE", { mono: true, size: 7.5, weight: "SemiBold", ls: 1, color: "#7C8AA3", lh: 10 });
  c.appendChild(group);

  vspace(c, 14);

  const wa = row("WhatsApp CTA", 361, 52, {
    fill: grad(["#31E07A", "#1FBE63"]), r: 14, justify: "CENTER", gap: 8,
    effects: [shadow("#25D366", 0.35, 0, 12, 28, -12)],
  });
  icon(wa, "whatsapp", 18, "#05130B");
  addT(wa, "Share to study group", { size: 12.5, weight: "Bold", color: "#05130B", lh: 15 });
  c.appendChild(wa);

  vspace(c, 10);

  const attach = row("Attach", 361, 56, {
    fill: solid(C.surface), stroke: solid(C.border), r: 14, pl: 14, pr: 14, justify: "SPACE_BETWEEN",
  });
  const am = col("Attach Copy", 240, { gap: 2 });
  addT(am, "Attach PDF to message", { size: 11.5, weight: "SemiBold", color: "#E4E9F1", lh: 14 });
  addT(am, "Off = a direct link is sent instead", { size: 9, weight: "Regular", color: "#718097", lh: 11 });
  attach.appendChild(am);
  const sw = box("Switch", 0, 0, 38, 22, { fill: solid(C.green, 0.9), r: 999 });
  const knob = figma.createEllipse();
  knob.resize(16, 16);
  knob.x = 19; knob.y = 3;
  knob.fills = [solid("#FFFFFF")];
  sw.appendChild(knob);
  attach.appendChild(sw);
  c.appendChild(attach);

  vspace(c, 12);
  fixedT(c, "Card auto-updates when the result drops", {
    mono: true, size: 8, weight: "Regular", ls: 0.4, color: "#58677D", lh: 10, align: "CENTER",
  }, 361, 10);

  homeIndicator(s);
  return s;
}

/* --------------------------------- board -------------------------------- */

async function main() {
  await initFonts();

  const board = figma.createFrame();
  board.name = "ExamVault · Deep Navy";
  board.resize(1772, 1040);
  board.x = 0; board.y = 0;
  board.fills = [solid("#05070C")];
  board.clipsContent = true;

  addT(board, "ExamVault", {
    size: 22, weight: "ExtraBold", ls: -0.5, color: C.text, x: 40, y: 34,
  });
  addT(board, "Ultra-fast exam utility · Design system v1.0", {
    mono: true, size: 9, weight: "Regular", ls: 0.4, color: "#6B7280", x: 40, y: 64,
  });
  addT(board, "393 × 852  ·  8PX GRID  ·  DEEP NAVY  ·  4 SCREENS", {
    mono: true, size: 9, weight: "Regular", ls: 0.9, color: "#7C8AA3", x: 1160, y: 64,
  });

  const labels = [
    ["01 / HOME", "Command Center"],
    ["02 / VAULT", "1-Tap Card Detail"],
    ["03 / RADAR", "Result Checker"],
    ["04 / SHARE", "WhatsApp Card"],
  ];
  const builders = [buildHome, buildVault, buildRadar, buildShare];
  const xs = [40, 473, 906, 1339];

  labels.forEach(([kicker, name], i) => {
    addT(board, kicker, {
      mono: true, size: 9, weight: "Regular", ls: 1.4, color: "#6B7280", x: xs[i], y: 102,
    });
    const nm = addT(board, name, {
      size: 11, weight: "SemiBold", color: C.text2, x: xs[i], y: 102,
    });
    nm.x = xs[i] + 393 - nm.width;
  });

  builders.forEach((build, i) => {
    const screen = build(xs[i]);
    board.appendChild(screen);
  });

  addT(board, "PLUS JAKARTA SANS  ·  IBM PLEX MONO  ·  #0B0F19 / #3B82F6 / #10B981 / #F59E0B / #EF4444", {
    mono: true, size: 8, weight: "Regular", ls: 1, color: "#4B5563", x: 40, y: 1010,
  });

  figma.currentPage.selection = [board];
  figma.viewport.scrollAndZoomIntoView([board]);
  figma.closePlugin("ExamVault · 4 screens created");
}

main().catch(e => {
  console.error(e);
  figma.notify("ExamVault builder failed: " + e.message, { error: true, timeout: 8000 });
  figma.closePlugin();
});