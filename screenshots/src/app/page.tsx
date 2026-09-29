"use client";

import { useEffect, useLayoutEffect, useRef, useState } from "react";
import { toPng } from "html-to-image";

/* ============================================================
   Fonts — SF Pro (matches the app's onboarding OBHeadline:
   .system(weight:.bold), tracking -0.025em). On macOS the
   -apple-system stack resolves to true SF Pro at export.
   ============================================================ */
const SF = `-apple-system, "SF Pro Display", "SF Pro Text", BlinkMacSystemFont, system-ui, "Helvetica Neue", sans-serif`;

/* ============================================================
   Canvas + export sizes
   ============================================================ */
const W = 1320;
const H = 2868;

const IPHONE_SIZES = [
  { label: '6.9"', w: 1320, h: 2868 },
  { label: '6.5"', w: 1284, h: 2778 },
  { label: '6.3"', w: 1206, h: 2622 },
  { label: '6.1"', w: 1125, h: 2436 },
] as const;

/* ============================================================
   iPhone mockup (PNG, pre-measured)
   ============================================================ */
const MK_W = 1022;
const MK_H = 2082;
const MK_RATIO = MK_W / MK_H;
const SC_L = (52 / MK_W) * 100;
const SC_T = (46 / MK_H) * 100;
const SC_W = (918 / MK_W) * 100;
const SC_H = (1990 / MK_H) * 100;
const SC_RX = (126 / 918) * 100;
const SC_RY = (126 / 1990) * 100;

/* ============================================================
   Theme
   ============================================================ */
const CREAM = {
  bg: "#F6F1EA",
  bgGradTo: "#EFE6D8",
  fg: "#1A1410",
  muted: "#7C6F62",
  accent: "#B8744A",
  card: "#FFFCF7",
};
const DARK = {
  bg: "#0E0E10",
  bgGradTo: "#18181B",
  fg: "#F4F1EC",
  muted: "#9C928A",
  accent: "#E8C39B",
  card: "#1C1C1F",
};
type Theme = typeof CREAM;

/* ============================================================
   Image preload (data URIs — required for html-to-image)
   ============================================================ */
const IMAGE_PATHS = [
  "/mockup.png",
  "/app-icon.png",
  "/screenshots/en/01-shelves-librivox.png",
  "/screenshots/en/02-library.png",
  "/screenshots/en/03-player.png",
  "/screenshots/en/04-moments.png",
  "/screenshots/en/05-shelves-audiobookshelf.png",
  "/screenshots/en/06-essentials-eq.png",
];

const imageCache: Record<string, string> = {};

function readBlobAsDataUrl(blob: Blob): Promise<string> {
  return new Promise<string>((resolve, reject) => {
    const reader = new FileReader();
    const timeout = window.setTimeout(() => reject(new Error("Image read timed out")), 5000);
    reader.onloadend = () => {
      window.clearTimeout(timeout);
      resolve(reader.result as string);
    };
    reader.onerror = () => {
      window.clearTimeout(timeout);
      reject(reader.error || new Error("Image read failed"));
    };
    reader.readAsDataURL(blob);
  });
}

async function preloadAllImages() {
  await Promise.allSettled(
    IMAGE_PATHS.map(async (path) => {
      try {
        const resp = await fetch(path);
        if (!resp.ok) return;
        const blob = await resp.blob();
        imageCache[path] = await readBlobAsDataUrl(blob);
      } catch {
        // leave fallback to raw path
      }
    }),
  );
}

function img(path: string): string {
  return imageCache[path] || path;
}

/* ============================================================
   iPhone frame component
   ============================================================ */
function Phone({
  src,
  alt,
  style,
}: {
  src: string;
  alt: string;
  style?: React.CSSProperties;
}) {
  return (
    <div
      style={{
        position: "relative",
        aspectRatio: `${MK_W}/${MK_H}`,
        ...style,
      }}
    >
      <img
        src={img("/mockup.png")}
        alt=""
        style={{ display: "block", width: "100%", height: "100%" }}
        draggable={false}
      />
      <div
        style={{
          position: "absolute",
          zIndex: 10,
          overflow: "hidden",
          left: `${SC_L}%`,
          top: `${SC_T}%`,
          width: `${SC_W}%`,
          height: `${SC_H}%`,
          borderRadius: `${SC_RX}% / ${SC_RY}%`,
        }}
      >
        <img
          src={src}
          alt={alt}
          style={{
            display: "block",
            width: "100%",
            height: "100%",
            objectFit: "cover",
            objectPosition: "top",
          }}
          draggable={false}
        />
      </div>
    </div>
  );
}

function phoneW(cW: number, cH: number, clamp = 0.86) {
  return Math.min(clamp, 0.72 * (cH / cW) * MK_RATIO);
}

/* Every slide anchors the phone directly under the caption block (rather than centered or
   bottom-anchored) so the real screen content starts within the top third of the canvas —
   App Store search results only ever show that much of slide 1. */
const HERO_TOP = 0.50; // fraction of cW; leaves room for headline and supporting copy

/* ============================================================
   Caption (label + SF Pro bold headline + supporting line)
   ============================================================ */
function Caption({
  cW,
  label,
  headline,
  sub,
  theme,
}: {
  cW: number;
  label: string;
  headline: React.ReactNode;
  sub?: React.ReactNode;
  theme: Theme;
}) {
  return (
    <div
      style={{
        position: "absolute",
        top: cW * 0.075,
        left: cW * 0.075,
        right: cW * 0.075,
        zIndex: 20,
      }}
    >
      <div
        style={{
          fontFamily: SF,
          fontSize: cW * 0.03,
          fontWeight: 700,
          letterSpacing: 0,
          textTransform: "uppercase",
          color: theme.accent,
          marginBottom: cW * 0.025,
        }}
      >
        {label}
      </div>
      <div
        style={{
          fontFamily: SF,
          fontSize: cW * 0.078,
          fontWeight: 700,
          lineHeight: 1.04,
          letterSpacing: 0,
          color: theme.fg,
        }}
      >
        {headline}
      </div>
      {sub && (
        <div
          style={{
            marginTop: cW * 0.04,
            fontFamily: SF,
            fontSize: cW * 0.036,
            fontWeight: 400,
            color: theme.muted,
            maxWidth: cW * 0.86,
            lineHeight: 1.45,
          }}
        >
          {sub}
        </div>
      )}
    </div>
  );
}

function SlideBg({
  theme,
  children,
}: {
  theme: Theme;
  children: React.ReactNode;
}) {
  return (
    <div
      style={{
        width: "100%",
        height: "100%",
        position: "relative",
        overflow: "hidden",
        background: `
          linear-gradient(90deg, rgba(255,255,255,0.08) 0%, transparent 44%, rgba(0,0,0,0.04) 100%),
          linear-gradient(170deg, ${theme.bg} 0%, ${theme.bgGradTo} 100%)
        `,
      }}
    >
      {children}
    </div>
  );
}

/* ============================================================
   Slides — Unpaged 1.4.0. Six ideas, six real screens, top-third
   composition throughout (headline + the start of the real screen
   both land above the 33% mark).
   ============================================================ */
type SlideProps = { cW: number; cH: number };
type SlideDef = {
  id: string;
  component: (p: SlideProps) => React.ReactElement;
};

function heroSlide({
  id,
  image,
  alt,
  label,
  headline,
  sub,
  theme = CREAM,
  phoneClamp = 0.86,
}: {
  id: string;
  image: string;
  alt: string;
  label: string;
  headline: React.ReactNode;
  sub: React.ReactNode;
  theme?: Theme;
  phoneClamp?: number;
}): SlideDef {
  return {
    id,
    component: ({ cW, cH }) => {
      const fw = phoneW(cW, cH, phoneClamp) * 100;
      return (
        <SlideBg theme={theme}>
          <Caption cW={cW} label={label} theme={theme} headline={headline} sub={sub} />
          <Phone
            src={img(image)}
            alt={alt}
            style={{
              position: "absolute",
              top: cW * HERO_TOP,
              left: "50%",
              transform: "translateX(-50%)",
              width: `${fw}%`,
              filter: `drop-shadow(0 30px 60px ${theme === DARK ? "rgba(0,0,0,0.5)" : "rgba(26,20,16,0.18)"})`,
            }}
          />
        </SlideBg>
      );
    },
  };
}

/* --- Slide 1: LibriVox catalog --- */
const SlideShelvesLibriVox = heroSlide({
  id: "shelves-librivox",
  image: "/screenshots/en/01-shelves-librivox.png",
  alt: "Browsing free classics on the Shelves tab",
  label: "FREE CLASSICS",
  headline: (
    <>
      20,000 audiobooks.
      <br />
      Free forever.
    </>
  ),
  sub: "Classics from LibriVox — stream instantly or download for offline listening.",
});

/* --- Slide 2: own library --- */
const SlideLibrary = heroSlide({
  id: "your-library",
  image: "/screenshots/en/02-library.png",
  alt: "Imported audiobooks, organized in the Library tab",
  label: "YOUR LIBRARY",
  headline: (
    <>
      Your audiobooks,
      <br />
      beautifully organized.
    </>
  ),
  sub: "Import MP3s and M4Bs. Unpaged keeps them grouped, tidy, and easy to find.",
});

/* --- Slide 3: player --- */
const SlidePlayer = heroSlide({
  id: "simple-private-player",
  image: "/screenshots/en/03-player.png",
  alt: "The Unpaged player screen",
  label: "SIMPLE & PRIVATE",
  headline: (
    <>
      No account. No ads.
      <br />
      Nothing tracked.
    </>
  ),
  sub: "Just you and the book — clean playback with nothing else in the way.",
  phoneClamp: 0.82,
});

/* --- Slide 4: on-device moments --- */
const SlideMoments = heroSlide({
  id: "moments-name-themselves",
  image: "/screenshots/en/04-moments.png",
  alt: "On-device AI naming a saved moment",
  label: "ON-DEVICE INTELLIGENCE",
  headline: (
    <>
      Bookmarks that
      <br />
      name themselves.
    </>
  ),
  sub: "With Unpaged Plus, on-device AI names each moment and pulls the quote, right on your iPhone.",
});

/* --- Slide 5: Audiobookshelf --- */
const SlideShelvesAudiobookshelf = heroSlide({
  id: "your-audiobookshelf-server",
  image: "/screenshots/en/05-shelves-audiobookshelf.png",
  alt: "A connected Audiobookshelf server, browsed inside Unpaged",
  label: "YOUR OWN SERVER",
  headline: (
    <>
      Your Audiobookshelf
      <br />
      server, in your pocket.
    </>
  ),
  sub: "Connect once — browse and stream the library you already host.",
});

/* --- Slide 6: essentials --- */
const SlideEssentials = heroSlide({
  id: "the-essentials",
  image: "/screenshots/en/06-essentials-eq.png",
  alt: "Equalizer, part of Unpaged's playback essentials",
  label: "THE ESSENTIALS",
  headline: (
    <>
      Sleep timer, EQ,
      <br />
      CarPlay. All here.
    </>
  ),
  sub: "Everything an audiobook needs, nothing it doesn't.",
});

/* Registry — 1.4.0 App Store set, in display order. */
const SLIDES: SlideDef[] = [
  SlideShelvesLibriVox,
  SlideLibrary,
  SlidePlayer,
  SlideMoments,
  SlideShelvesAudiobookshelf,
  SlideEssentials,
];

/* ============================================================
   Preview card
   ============================================================ */
function ScreenshotPreview({
  slide,
  onExport,
  exporting,
}: {
  slide: SlideDef;
  onExport: () => void;
  exporting: boolean;
}) {
  const containerRef = useRef<HTMLDivElement>(null);
  const [scale, setScale] = useState(0.18);

  useLayoutEffect(() => {
    const el = containerRef.current;
    if (!el) return;
    const ro = new ResizeObserver((entries) => {
      for (const e of entries) {
        const cw = e.contentRect.width;
        setScale(cw / W);
      }
    });
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  const previewH = H * scale;

  return (
    <div className="group flex flex-col gap-2">
      <div
        ref={containerRef}
        style={{
          width: "100%",
          height: previewH,
          position: "relative",
          borderRadius: 14,
          overflow: "hidden",
          background: "#fff",
          boxShadow: "0 4px 20px rgba(0,0,0,0.06)",
        }}
      >
        <div
          style={{
            width: W,
            height: H,
            transform: `scale(${scale})`,
            transformOrigin: "top left",
          }}
        >
          {slide.component({ cW: W, cH: H })}
        </div>
        <button
          onClick={onExport}
          disabled={exporting}
          className="opacity-0 group-hover:opacity-100 transition-opacity"
          style={{
            position: "absolute",
            top: 8,
            right: 8,
            padding: "5px 12px",
            fontSize: 11,
            fontWeight: 600,
            background: "white",
            border: "1px solid #e5e7eb",
            borderRadius: 6,
            cursor: exporting ? "default" : "pointer",
            color: "#2563eb",
          }}
        >
          Export
        </button>
      </div>
      <div className="text-[11px] text-neutral-500 font-mono">{slide.id}</div>
    </div>
  );
}

/* ============================================================
   Main page
   ============================================================ */
export default function ScreenshotsPage() {
  const [ready, setReady] = useState(false);
  const [sizeIdx, setSizeIdx] = useState(0);
  const [exporting, setExporting] = useState<string | null>(null);
  const exportRefs = useRef<(HTMLDivElement | null)[]>([]);

  useEffect(() => {
    preloadAllImages().then(() => setReady(true));
  }, []);

  if (!ready) {
    return (
      <div
        style={{
          minHeight: "100vh",
          display: "grid",
          placeItems: "center",
          fontFamily: SF,
        }}
      >
        Loading images…
      </div>
    );
  }

  const currentSizes = IPHONE_SIZES;
  const slides = SLIDES;

  async function captureSlide(
    el: HTMLElement,
    w: number,
    h: number,
  ): Promise<string> {
    el.style.left = "0px";
    el.style.opacity = "1";
    el.style.zIndex = "-1";
    const opts = { width: w, height: h, pixelRatio: 1, cacheBust: true };
    await toPng(el, opts);
    const dataUrl = await toPng(el, opts);
    el.style.left = "-9999px";
    el.style.opacity = "";
    el.style.zIndex = "";
    return dataUrl;
  }

  async function exportOne(i: number) {
    const size = currentSizes[sizeIdx];
    const el = exportRefs.current[i];
    if (!el) return;
    setExporting(`${i + 1}/${slides.length}`);
    const dataUrl = await captureSlide(el, size.w, size.h);
    const a = document.createElement("a");
    a.href = dataUrl;
    a.download = `${String(i + 1).padStart(2, "0")}-${slides[i].id}-${size.w}x${size.h}.png`;
    a.click();
    setExporting(null);
  }

  async function exportAll() {
    const size = currentSizes[sizeIdx];
    for (let i = 0; i < slides.length; i++) {
      setExporting(`${i + 1}/${slides.length}`);
      const el = exportRefs.current[i];
      if (!el) continue;
      const dataUrl = await captureSlide(el, size.w, size.h);
      const a = document.createElement("a");
      a.href = dataUrl;
      a.download = `${String(i + 1).padStart(2, "0")}-${slides[i].id}-${size.w}x${size.h}.png`;
      a.click();
      await new Promise((r) => setTimeout(r, 300));
    }
    setExporting(null);
  }

  return (
    <div
      style={{
        minHeight: "100vh",
        background: "#f3f4f6",
        position: "relative",
        overflowX: "hidden",
      }}
    >
      <div
        style={{
          position: "sticky",
          top: 0,
          zIndex: 50,
          background: "white",
          borderBottom: "1px solid #e5e7eb",
          display: "flex",
          alignItems: "center",
        }}
      >
        <div
          style={{
            flex: 1,
            display: "flex",
            alignItems: "center",
            gap: 12,
            padding: "10px 16px",
            overflowX: "auto",
            minWidth: 0,
          }}
        >
          <span
            style={{
              fontFamily: SF,
              fontWeight: 700,
              fontSize: 17,
              letterSpacing: 0,
              whiteSpace: "nowrap",
            }}
          >
            Unpaged
          </span>
          <span
            style={{
              fontFamily: SF,
              fontSize: 12,
              color: "#6b7280",
              whiteSpace: "nowrap",
            }}
          >
            App Store · iPhone · {SLIDES.length} slides
          </span>
          <div style={{ flex: 1 }} />
          <select
            value={sizeIdx}
            onChange={(e) => setSizeIdx(Number(e.target.value))}
            style={{
              fontSize: 12,
              border: "1px solid #e5e7eb",
              borderRadius: 6,
              padding: "5px 10px",
              fontFamily: SF,
            }}
          >
            {currentSizes.map((s, i) => (
              <option key={i} value={i}>
                {s.label} — {s.w}×{s.h}
              </option>
            ))}
          </select>
        </div>
        <div
          style={{
            flexShrink: 0,
            padding: "10px 16px",
            borderLeft: "1px solid #e5e7eb",
          }}
        >
          <button
            onClick={exportAll}
            disabled={!!exporting}
            style={{
              padding: "7px 22px",
              background: exporting ? "#93c5fd" : "#1A1410",
              color: "white",
              border: "none",
              borderRadius: 8,
              fontSize: 12,
              fontWeight: 600,
              cursor: exporting ? "default" : "pointer",
              whiteSpace: "nowrap",
              fontFamily: SF,
            }}
          >
            {exporting ? `Exporting… ${exporting}` : "Export All"}
          </button>
        </div>
      </div>

      <div
        style={{
          padding: "24px 16px 80px",
          display: "grid",
          gridTemplateColumns: "repeat(auto-fill, minmax(220px, 1fr))",
          gap: 20,
          maxWidth: 1600,
          margin: "0 auto",
        }}
      >
        {slides.map((s, i) => (
          <ScreenshotPreview
            key={s.id}
            slide={s}
            onExport={() => exportOne(i)}
            exporting={!!exporting}
          />
        ))}
      </div>

      <div
        style={{
          position: "absolute",
          left: -9999,
          top: 0,
          pointerEvents: "none",
        }}
      >
        {slides.map((s, i) => (
          <div
            key={`export-${s.id}`}
            ref={(el) => {
              exportRefs.current[i] = el;
            }}
            style={{
              position: "absolute",
              left: -9999,
              top: 0,
              width: currentSizes[sizeIdx].w,
              height: currentSizes[sizeIdx].h,
              opacity: 0,
            }}
          >
            <div
              style={{
                width: currentSizes[sizeIdx].w,
                height: currentSizes[sizeIdx].h,
              }}
            >
              {s.component({
                cW: currentSizes[sizeIdx].w,
                cH: currentSizes[sizeIdx].h,
              })}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
