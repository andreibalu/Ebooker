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
  "/screenshots/en/home.png",
  "/screenshots/en/library.png",
  "/screenshots/en/ai-moments.png",
  "/screenshots/en/alternatives.png",
  "/screenshots/en/recap.png",
  "/screenshots/en/free-books.png",
  "/screenshots/en/onboarding-choice.png",
  "/screenshots/en/reading-stats.png",
  "/screenshots/en/icloud-library.png",
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
          fontSize: cW * 0.024,
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
          fontSize: cW * 0.098,
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
            fontSize: cW * 0.028,
            fontWeight: 400,
            color: theme.muted,
            maxWidth: cW * 0.78,
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
   Slides
   ============================================================ */
type SlideProps = { cW: number; cH: number };
type SlideDef = {
  id: string;
  component: (p: SlideProps) => React.ReactElement;
};

/* --- Slide 1: hero — free-books grid --- */
const SlideHeroGrid: SlideDef = {
  id: "hero-free-grid",
  component: ({ cW, cH }) => {
    const fw = phoneW(cW, cH, 0.86) * 100;
    return (
      <SlideBg theme={CREAM}>
        <Caption
          cW={cW}
          label="FREE AUDIOBOOK PLAYER"
          theme={CREAM}
          headline={
            <>
              Free forever.
              <br />
              No ads.
            </>
          }
          sub="Twenty thousand free audiobooks built in, with curated collections. No account, no catch."
        />
        <Phone
          src={img("/screenshots/en/free-books.png")}
          alt="Free books"
          style={{
            position: "absolute",
            bottom: 0,
            width: `${fw}%`,
            left: "50%",
            transform: "translateX(-50%) translateY(14%)",
            filter: "drop-shadow(0 30px 60px rgba(26,20,16,0.18))",
          }}
        />
      </SlideBg>
    );
  },
};

/* --- Slide 2: onboarding choice — free vs own --- */
const SlideChoose: SlideDef = {
  id: "choose-start",
  component: ({ cW, cH }) => {
    const fw = phoneW(cW, cH, 0.84) * 100;
    return (
      <SlideBg theme={CREAM}>
        <Caption
          cW={cW}
          label="TWO WAYS TO LISTEN"
          theme={CREAM}
          headline={
            <>
              Free books, or
              <br />
              your own.
            </>
          }
          sub="Stream thousands of classics, or import audiobooks you already own. Your call."
        />
        <Phone
          src={img("/screenshots/en/onboarding-choice.png")}
          alt="Choose how to start"
          style={{
            position: "absolute",
            bottom: 0,
            width: `${fw}%`,
            left: "50%",
            transform: "translateX(-50%) translateY(14%)",
            filter: "drop-shadow(0 30px 60px rgba(26,20,16,0.18))",
          }}
        />
      </SlideBg>
    );
  },
};

/* --- Slide 3: import your own --- */
const SlideImport: SlideDef = {
  id: "import-own",
  component: ({ cW, cH }) => {
    const fw = phoneW(cW, cH, 0.82) * 100;
    return (
      <SlideBg theme={CREAM}>
        <Caption
          cW={cW}
          label="IMPORT MP3 & M4B"
          theme={CREAM}
          headline={
            <>
              Any book.
              <br />
              Yours, played.
            </>
          }
          sub="Import MP3, M4B, or AAC files from any source. No store. No lock-in."
        />
        <Phone
          src={img("/screenshots/en/library.png")}
          alt="Import library"
          style={{
            position: "absolute",
            bottom: 0,
            width: `${fw}%`,
            left: "-7%",
            transform: "translateY(12%) rotate(3deg)",
            filter: "drop-shadow(0 30px 60px rgba(26,20,16,0.18))",
          }}
        />
      </SlideBg>
    );
  },
};

/* --- Slide 4: AI moments --- */
const SlideAIMoments: SlideDef = {
  id: "ai-moments",
  component: ({ cW, cH }) => {
    const fw = phoneW(cW, cH, 0.84) * 100;
    return (
      <SlideBg theme={DARK}>
        <Caption
          cW={cW}
          label="ON-DEVICE APPLE INTELLIGENCE"
          theme={DARK}
          headline={
            <>
              Bookmarks that
              <br />
              name themselves.
            </>
          }
          sub="Apple Intelligence names the moment, pulls the quote, tags the mood. On your iPhone. Nothing uploaded."
        />
        <Phone
          src={img("/screenshots/en/ai-moments.png")}
          alt="AI moments"
          style={{
            position: "absolute",
            bottom: 0,
            width: `${fw}%`,
            left: "50%",
            transform: "translateX(-50%) translateY(13%)",
            filter:
              "drop-shadow(0 0 80px rgba(232,195,155,0.18)) drop-shadow(0 30px 60px rgba(0,0,0,0.5))",
          }}
        />
      </SlideBg>
    );
  },
};

/* --- Slide 5: AI recap --- */
const SlideRecap: SlideDef = {
  id: "recap-resume",
  component: ({ cW, cH }) => {
    const fw = phoneW(cW, cH, 0.82) * 100;
    return (
      <SlideBg theme={CREAM}>
        <Caption
          cW={cW}
          label="AI RECAP"
          theme={CREAM}
          headline={
            <>
              Forgot where
              <br />
              you left off?
            </>
          }
          sub="A two-line recap, written for you. Press play and you're back in the story."
        />
        <Phone
          src={img("/screenshots/en/recap.png")}
          alt="Recap"
          style={{
            position: "absolute",
            bottom: 0,
            width: `${fw}%`,
            right: "-8%",
            transform: "translateY(12%) rotate(-3deg)",
            filter: "drop-shadow(0 30px 60px rgba(26,20,16,0.18))",
          }}
        />
      </SlideBg>
    );
  },
};

/* --- Slide 6: other recordings --- */
const SlideAlternatives: SlideDef = {
  id: "other-recordings",
  component: ({ cW, cH }) => {
    const fw = phoneW(cW, cH, 0.82) * 100;
    return (
      <SlideBg theme={CREAM}>
        <Caption
          cW={cW}
          label="OTHER RECORDINGS"
          theme={CREAM}
          headline={
            <>
              Same book.
              <br />
              Different options.
            </>
          }
          sub="Compare narrators, sample each version, and choose the recording that fits."
        />
        <Phone
          src={img("/screenshots/en/alternatives.png")}
          alt="Other recordings"
          style={{
            position: "absolute",
            bottom: 0,
            width: `${fw}%`,
            right: "-8%",
            transform: "translateY(12%) rotate(-3deg)",
            filter: "drop-shadow(0 30px 60px rgba(26,20,16,0.18))",
          }}
        />
      </SlideBg>
    );
  },
};

/* --- Slide 7: reading stats --- */
const SlideStats: SlideDef = {
  id: "reading-stats",
  component: ({ cW, cH }) => {
    const fw = phoneW(cW, cH, 0.84) * 100;
    return (
      <SlideBg theme={DARK}>
        <Caption
          cW={cW}
          label="YOUR LISTENING, MAPPED"
          theme={DARK}
          headline={
            <>
              Every hour,
              <br />
              counted.
            </>
          }
          sub="Streaks, best times of day, and a heatmap of every book you finish."
        />
        <Phone
          src={img("/screenshots/en/reading-stats.png")}
          alt="Reading stats"
          style={{
            position: "absolute",
            bottom: 0,
            width: `${fw}%`,
            left: "50%",
            transform: "translateX(-50%) translateY(13%)",
            filter:
              "drop-shadow(0 0 80px rgba(232,195,155,0.16)) drop-shadow(0 30px 60px rgba(0,0,0,0.5))",
          }}
        />
      </SlideBg>
    );
  },
};

/* --- Slide 8: iCloud backup --- */
const SlideICloud: SlideDef = {
  id: "icloud-backup",
  component: ({ cW, cH }) => {
    const fw = phoneW(cW, cH, 0.82) * 100;
    return (
      <SlideBg theme={CREAM}>
        <Caption
          cW={cW}
          label="ICLOUD BACKUP"
          theme={CREAM}
          headline={
            <>
              Your library,
              <br />
              safe in iCloud.
            </>
          }
          sub="Progress, bookmarks, and moments sync across your iPhones. Never lose your place."
        />
        <Phone
          src={img("/screenshots/en/icloud-library.png")}
          alt="iCloud library"
          style={{
            position: "absolute",
            bottom: 0,
            width: `${fw}%`,
            right: "-8%",
            transform: "translateY(12%) rotate(-3deg)",
            filter: "drop-shadow(0 30px 60px rgba(26,20,16,0.18))",
          }}
        />
      </SlideBg>
    );
  },
};

function FeaturePill({ children }: { children: React.ReactNode }) {
  return (
    <div
      style={{
        fontFamily: SF,
        fontSize: 34,
        fontWeight: 600,
        lineHeight: 1,
        color: DARK.fg,
        padding: "24px 34px 26px",
        borderRadius: 999,
        background: "linear-gradient(180deg, #262629 0%, #202023 100%)",
        border: "1px solid rgba(255,255,255,0.08)",
        boxShadow: "inset 0 1px 0 rgba(255,255,255,0.04), 0 12px 30px rgba(0,0,0,0.2)",
      }}
    >
      {children}
    </div>
  );
}

/* --- Slide 9: closer --- */
const SlideCloser: SlideDef = {
  id: "closer-everything-free",
  component: ({ cW }) => {
    const pills = [
      "Free forever",
      "No ads",
      "No account",
      "20,000 LibriVox books",
      "Collections",
      "Other recordings",
      "MP3 & M4B import",
      "Reading stats",
      "CarPlay",
      "Siri shortcuts",
      "Sleep timer",
      "Audiobook EQ",
    ];
    return (
      <SlideBg theme={DARK}>
        <div
          style={{
            position: "absolute",
            top: cW * 0.16,
            left: 0,
            right: 0,
            display: "flex",
            justifyContent: "center",
          }}
        >
          <img
            src={img("/app-icon.png")}
            alt=""
            draggable={false}
            style={{
              width: cW * 0.22,
              height: cW * 0.22,
              borderRadius: cW * 0.046,
              boxShadow: "0 26px 60px rgba(0,0,0,0.34)",
            }}
          />
        </div>
        <div
          style={{
            position: "absolute",
            top: cW * 0.47,
            left: cW * 0.08,
            right: cW * 0.08,
            textAlign: "center",
            fontFamily: SF,
            fontSize: cW * 0.085,
            fontWeight: 700,
            lineHeight: 1.08,
            letterSpacing: 0,
            color: DARK.fg,
          }}
        >
          Everything you
          <br />
          need.
          <br />
          Pay nothing.
        </div>
        <div
          style={{
            position: "absolute",
            top: cW * 0.93,
            left: cW * 0.08,
            right: cW * 0.08,
            display: "flex",
            flexWrap: "wrap",
            justifyContent: "center",
            alignItems: "center",
            gap: 26,
          }}
        >
          {pills.map((pill) => (
            <FeaturePill key={pill}>{pill}</FeaturePill>
          ))}
        </div>
        <div
          style={{
            position: "absolute",
            bottom: cW * 0.09,
            left: 0,
            right: 0,
            textAlign: "center",
            fontFamily: SF,
            fontSize: cW * 0.022,
            fontWeight: 700,
            letterSpacing: 0,
            color: DARK.accent,
          }}
        >
          FOR READERS
        </div>
      </SlideBg>
    );
  },
};

/* Registry — App Store set, one source screenshot per feature plus a closer. */
const SLIDES: SlideDef[] = [
  SlideHeroGrid,
  SlideChoose,
  SlideAlternatives,
  SlideAIMoments,
  SlideRecap,
  SlideStats,
  SlideICloud,
  SlideImport,
  SlideCloser,
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
