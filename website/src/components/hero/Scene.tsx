"use client";

import {
  useEffect,
  useReducer,
  useRef,
  type CSSProperties,
  type ReactNode,
} from "react";
import { AnimatePresence, motion, useInView } from "motion/react";
import { BatteryMedium, Lock, Minus, Square, Wifi, X } from "lucide-react";
import { useMediaQuery, usePrefersReducedMotion } from "@/lib/hooks";
import { AndroidIcon, AppleIcon, LogoMark, WindowsIcon } from "../icons";
import {
  ACTS,
  DEVICE_NAMES,
  INITIAL_STATE,
  ITEMS,
  PHASE_MS,
  STATIC_STATE,
  advance,
  devicesOf,
  isAtOrAfter,
  sourceOf,
  targetOf,
  type DesktopId,
  type DeviceId,
  type Item,
  type Layout,
  type SceneState,
} from "./model";
import {
  Compose,
  KindTile,
  Pointer,
  Row,
  SearchAndFilters,
  SourceView,
} from "./parts";

/* -------------------------------------------------------------------------
   Geometry. The scene is drawn at a fixed size in its own pixels and scaled
   as a whole, so every position below is a plain number.
   ---------------------------------------------------------------------- */

interface Point {
  x: number;
  y: number;
}

interface Geometry {
  w: number;
  h: number;
  /** Never scale up past this, however large the screen. */
  max: number;
  dense: boolean;
  screen: { w: number; h: number; bezel: number };
  desktops: Partial<Record<DesktopId, Point>>;
  window: { x: number; y: number; w: number; h: number };
  panel: { w: number; rows: number };
  phone: { x: number; y: number; w: number; h: number };
}

const GEOMETRY: Record<Layout, Geometry> = {
  // A Windows laptop, an Android phone and a Mac, side by side.
  wide: {
    w: 1160,
    h: 340,
    max: 1.3,
    dense: false,
    screen: { w: 460, h: 288, bezel: 8 },
    desktops: { win: { x: 12, y: 0 }, mac: { x: 688, y: 0 } },
    window: { x: 22, y: 38, w: 400, h: 194 },
    panel: { w: 250, rows: 3 },
    phone: { x: 505, y: 0, w: 150, h: 300 },
  },
  // Small screens: one desktop and the phone, drawn at a readable size
  // instead of three devices shrunk to nothing.
  compact: {
    w: 358,
    h: 290,
    max: 1.7,
    dense: true,
    screen: { w: 300, h: 196, bezel: 6 },
    desktops: { win: { x: 0, y: 0 } },
    window: { x: 10, y: 28, w: 224, h: 130 },
    panel: { w: 190, rows: 2 },
    phone: { x: 250, y: 40, w: 108, h: 250 },
  },
};

const BAR = { menu: 16, task: 22, taskDense: 18 };

function panelTop(id: DesktopId, g: Geometry) {
  if (id === "mac") return BAR.menu + 4;
  return g.dense ? 4 : 6;
}

/** Where a copied thing leaves from, in scene pixels. */
function sourcePoint(id: DesktopId, g: Geometry): Point {
  const origin = g.desktops[id]!;
  return {
    x: origin.x + g.screen.bezel + g.window.x + g.window.w * 0.4,
    y: origin.y + g.screen.bezel + g.window.y + g.window.h * 0.4,
  };
}

/** Where it lands on another device. */
function landingPoint(device: DeviceId, g: Geometry): Point {
  if (device === "phone") {
    return { x: g.phone.x + g.phone.w / 2, y: g.phone.y + g.phone.h * 0.4 };
  }
  const origin = g.desktops[device]!;
  return {
    x: origin.x + g.screen.w / 2,
    y: origin.y + g.screen.bezel + panelTop(device, g) + 26,
  };
}

function metaFor(
  item: Item,
  device: DeviceId,
  layout: Layout,
  index: number,
  withTime: boolean,
) {
  const origin: DeviceId = layout === "compact" ? "win" : item.source;
  const synced = item.kind !== "file" && origin !== device;
  const detail = synced ? `from ${DEVICE_NAMES[origin]}` : item.meta;
  if (!withTime) return detail;
  return `${index === 0 ? "now" : `${index} min ago`} · ${detail}`;
}

/* -------------------------------------------------------------------------
   Small pieces
   ---------------------------------------------------------------------- */

/** The logo's echo: an outline that leaves the device when something lands. */
function Echo({ on, radius }: { on: boolean; radius: number }) {
  return (
    <AnimatePresence>
      {on && (
        <motion.span
          aria-hidden="true"
          initial={{ opacity: 0.85, scale: 1 }}
          animate={{ opacity: 0, scale: 1.07 }}
          exit={{ opacity: 0 }}
          transition={{ duration: 0.75, ease: [0.22, 1, 0.36, 1] }}
          className="pointer-events-none absolute -inset-px border border-white"
          style={{ borderRadius: radius }}
        />
      )}
    </AnimatePresence>
  );
}

function Wallpaper({ variant }: { variant: DesktopId | "phone" }) {
  // Flat grey shapes: enough contrast for the glass panel to have something
  // to frost, and nothing but black, white and grey.
  const shapes: Record<typeof variant, ReactNode> = {
    win: (
      <>
        <span className="absolute -left-[8%] -top-[30%] h-[110%] w-[46%] rotate-12 rounded-[22%] bg-white/[0.26]" />
        <span className="absolute -right-[10%] top-[18%] h-[120%] w-[50%] -rotate-12 rounded-[22%] bg-white/[0.14]" />
        <span className="absolute left-[34%] -top-[40%] h-[70%] w-[30%] rotate-45 rounded-[22%] bg-white/[0.36]" />
      </>
    ),
    mac: (
      <>
        <span className="absolute -right-[6%] -top-[34%] h-[110%] w-[44%] -rotate-12 rounded-[22%] bg-white/[0.26]" />
        <span className="absolute -left-[12%] top-[26%] h-[120%] w-[52%] rotate-12 rounded-[22%] bg-white/[0.14]" />
        <span className="absolute left-[30%] -top-[46%] h-[74%] w-[32%] -rotate-45 rounded-[22%] bg-white/[0.36]" />
      </>
    ),
    phone: (
      <span className="absolute -right-[30%] -top-[12%] h-[46%] w-[90%] rotate-12 rounded-[22%] bg-white/[0.08]" />
    ),
  };

  return (
    <div
      aria-hidden="true"
      className="absolute inset-0 overflow-hidden bg-[linear-gradient(150deg,#383838,#141414_62%,#050505)]"
    >
      {shapes[variant]}
    </div>
  );
}

function Token({
  item,
  from,
  to,
  delay,
}: {
  item: Item;
  from: Point;
  to: Point;
  delay: number;
}) {
  const lift = Math.min(from.y, to.y) - 30;
  const duration = 0.72;

  return (
    <motion.div
      aria-hidden="true"
      className="absolute left-0 top-0 z-40"
      initial={{ x: from.x, y: from.y, opacity: 0, scale: 0.6 }}
      animate={{
        x: to.x,
        y: [from.y, lift, to.y],
        opacity: [0, 1, 1, 0],
        scale: [0.6, 1, 1, 0.72],
      }}
      transition={{
        duration,
        delay,
        ease: [0.45, 0, 0.25, 1],
        opacity: { duration, delay, times: [0, 0.14, 0.84, 1] },
        scale: { duration, delay, times: [0, 0.2, 0.8, 1] },
      }}
    >
      <span className="glass flex -translate-x-1/2 -translate-y-1/2 items-center gap-1.5 rounded-full py-[3px] pl-[3px] pr-2.5 text-[10.5px] font-medium whitespace-nowrap text-white">
        <KindTile kind={item.kind} size={22} />
        {item.short}
      </span>
    </motion.div>
  );
}

function Label({
  at,
  align,
  icon,
  platform,
  device,
}: {
  at: Point;
  align: "left" | "center" | "right";
  icon: ReactNode;
  platform: string;
  device?: string;
}) {
  const shift =
    align === "center"
      ? "-translate-x-1/2"
      : align === "right"
        ? "-translate-x-full"
        : "";

  return (
    <div
      className={`absolute flex items-center gap-1.5 text-[11px] whitespace-nowrap text-white/60 ${shift}`}
      style={{ left: at.x, top: at.y }}
    >
      <span className="text-white/85">{icon}</span>
      <span className="font-medium text-white/85">{platform}</span>
      {device && <span className="font-mono text-[10px]">{device}</span>}
    </div>
  );
}

/* -------------------------------------------------------------------------
   The desktop: a window to copy from and paste into, and the glass panel
   that drops from the top middle of the screen.
   ---------------------------------------------------------------------- */

const WINDOW_TITLES: Record<string, string> = {
  text: "Notes",
  link: "Browser",
  image: "Photos",
  color: "Palette",
};

function Desktop({
  id,
  g,
  state,
  layout,
}: {
  id: DesktopId;
  g: Geometry;
  state: SceneState;
  layout: Layout;
}) {
  const { act, phase } = state;
  const item = ACTS[act];
  const isSource = sourceOf(act, layout) === id;
  const isTarget = targetOf(act, layout) === id;

  // A desktop that is not copying still shows what it copied last time.
  const own = isSource ? item : ACTS[(act + ACTS.length - 1) % ACTS.length];
  const selected = isSource && !isAtOrAfter(phase, "arrive");
  const copied = isSource && (phase === "copy" || phase === "travel");
  const pasted = isTarget && isAtOrAfter(phase, "paste") ? item : null;
  const panelOpen = isTarget && phase === "open";
  const received = !isSource && phase === "arrive";

  const origin = g.desktops[id]!;
  const { bezel } = g.screen;
  const innerW = g.screen.w - bezel * 2;
  const top = panelTop(id, g);
  const taskbar = g.dense ? BAR.taskDense : BAR.task;
  const win = g.window;

  // The pointer: along the selection, up to the top middle of the screen (the
  // gesture that opens the panel), onto the newest entry, then back.
  let pointer: Point = { x: win.x + 46, y: win.y + win.h - (g.dense ? 15 : 20) };
  let pointerDelay = 0;
  if (isTarget && phase === "arrive") {
    pointer = { x: innerW / 2 - 4, y: 1 };
  } else if (isTarget && phase === "open") {
    pointer = { x: innerW / 2 + 22, y: top + (g.dense ? 64 : 78) };
    pointerDelay = 0.42;
  } else if (isSource && !isAtOrAfter(phase, "paste")) {
    pointer = { x: win.x + win.w * 0.62, y: win.y + win.h * 0.46 };
  }

  const rows = state.lists[id].slice(0, g.panel.rows);

  return (
    <div
      className="absolute isolate"
      style={{ left: origin.x, top: origin.y, width: g.screen.w }}
    >
      {/* Lid */}
      <div
        className="relative rounded-[14px] border border-white/20 bg-[#0b0b0b] shadow-[0_30px_60px_-30px_rgb(0_0_0/0.9),inset_0_1px_0_rgb(255_255_255/0.12)]"
        style={{ height: g.screen.h, padding: bezel }}
      >
        <Echo on={received} radius={14} />

        <div className="relative h-full w-full overflow-hidden rounded-[7px]">
          <Wallpaper variant={id} />

          {id === "mac" ? (
            <div
              className="absolute inset-x-0 top-0 z-10 flex items-center gap-2 bg-black/35 px-2 text-[7.5px] text-white/85"
              style={{ height: BAR.menu }}
            >
              <AppleIcon className="h-[9px] w-[9px]" />
              <span className="font-semibold">{WINDOW_TITLES[own.kind]}</span>
              <span>File</span>
              <span>Edit</span>
              <span className="ml-auto flex items-center gap-1.5">
                <LogoMark className="h-[10px] w-[10px]" />
                <Wifi size={9} />
              </span>
            </div>
          ) : (
            <div
              className="absolute inset-x-0 bottom-0 z-10 flex items-center justify-center gap-1.5 bg-black/45"
              style={{ height: taskbar }}
            >
              <WindowsIcon className="h-[10px] w-[10px] text-white/90" />
              {[0, 1, 2].map((slot) => (
                <span
                  key={slot}
                  className="h-[10px] w-[10px] rounded-[3px] bg-white/25"
                />
              ))}
              <span className="absolute right-2 flex items-center gap-1.5 text-white/85">
                <LogoMark className="h-[10px] w-[10px]" />
                <Wifi size={9} />
              </span>
            </div>
          )}

          {/* The app the user is working in */}
          <div
            className="absolute flex flex-col overflow-hidden rounded-[8px] border border-white/[0.18] bg-[#1b1b1b]/95 shadow-[0_16px_30px_-12px_rgb(0_0_0/0.8)]"
            style={{ left: win.x, top: win.y, width: win.w, height: win.h }}
          >
            <div
              className={`flex shrink-0 items-center border-b border-white/[0.08] px-2 text-white/60 ${
                g.dense ? "h-[15px] text-[7px]" : "h-[18px] text-[8px]"
              }`}
            >
              {id === "mac" ? (
                <span className="flex gap-[3px]">
                  {[0, 1, 2].map((dot) => (
                    <span
                      key={dot}
                      className="h-[6px] w-[6px] rounded-full bg-white/30"
                    />
                  ))}
                </span>
              ) : (
                <span>{WINDOW_TITLES[own.kind]}</span>
              )}
              {id === "win" && (
                <span className="ml-auto flex items-center gap-1.5">
                  <Minus size={8} />
                  <Square size={6} />
                  <X size={8} />
                </span>
              )}
            </div>

            <div
              className={`relative flex min-h-0 flex-1 flex-col ${
                g.dense ? "gap-1.5 p-2" : "gap-2 px-3 py-2.5"
              }`}
            >
              <div className="min-h-0 flex-1">
                <SourceView item={own} selected={selected} dense={g.dense} />
              </div>
              <Compose pasted={pasted} dense={g.dense} />

              <AnimatePresence>
                {copied && (
                  <motion.div
                    key="copied"
                    initial={{ opacity: 0, y: 6, scale: 0.9 }}
                    animate={{ opacity: 1, y: 0, scale: 1 }}
                    exit={{ opacity: 0, y: -4, transition: { duration: 0.2 } }}
                    transition={{ type: "spring", stiffness: 520, damping: 28 }}
                    className={`absolute right-2 top-2 flex items-center gap-1 rounded-full border border-white/20 bg-white/[0.14] px-1.5 py-[3px] font-medium text-white ${
                      g.dense ? "text-[7.5px]" : "text-[8.5px]"
                    }`}
                  >
                    <span className="rounded-[4px] bg-white px-1 font-mono text-black">
                      {id === "mac" ? "⌘C" : "Ctrl+C"}
                    </span>
                    Copied
                  </motion.div>
                )}
              </AnimatePresence>
            </div>
          </div>

          {/* The clipboard panel, dropping from the top middle */}
          <div
            className="absolute left-1/2 z-20 -translate-x-1/2"
            style={{ top, width: g.panel.w }}
          >
            <AnimatePresence>
              {panelOpen && (
                <motion.div
                  key="panel"
                  initial={{ y: "-112%", opacity: 0.5 }}
                  animate={{ y: 0, opacity: 1 }}
                  exit={{
                    y: "-16%",
                    opacity: 0,
                    transition: { duration: 0.19, ease: [0.32, 0, 0.67, 0] },
                  }}
                  // The app's own spring: stiffness 380, damping 30.
                  transition={{ type: "spring", stiffness: 380, damping: 30 }}
                  className={`flex flex-col rounded-[14px] border border-white/[0.16] bg-[rgb(20_20_26/0.55)] shadow-[inset_0_1px_0_rgb(255_255_255/0.5),0_18px_36px_-10px_rgb(0_0_0/0.9)] backdrop-blur-[14px] ${
                    g.dense ? "gap-[5px] p-1.5" : "gap-1.5 p-2"
                  }`}
                >
                  <SearchAndFilters
                    dense={g.dense}
                    filters={["All", "Pinned", "Text", "Links", "Images", "Files"]}
                  />
                  <div className="flex flex-col">
                    {rows.map((entry, index) => {
                      const row = (
                        <Row
                          item={ITEMS[entry]}
                          meta={metaFor(ITEMS[entry], id, layout, index, true)}
                          dense={g.dense}
                          lit={index === 0}
                        />
                      );
                      return index === 0 ? (
                        // A click, just before the panel closes and pastes.
                        <motion.div
                          key={entry}
                          animate={{ scale: [1, 1, 0.955, 1] }}
                          transition={{
                            duration: PHASE_MS.open / 1000,
                            times: [0, 0.8, 0.9, 1],
                          }}
                        >
                          {row}
                        </motion.div>
                      ) : (
                        <div key={entry}>{row}</div>
                      );
                    })}
                  </div>
                </motion.div>
              )}
            </AnimatePresence>
          </div>

          <motion.div
            aria-hidden="true"
            className="absolute left-0 top-0 z-30"
            initial={false}
            animate={{ x: pointer.x, y: pointer.y }}
            transition={{
              duration: 0.5,
              delay: pointerDelay,
              ease: [0.22, 1, 0.36, 1],
            }}
          >
            <Pointer />
          </motion.div>
        </div>
      </div>

      {/* Base of the laptop. The compact scene shows the screen alone. */}
      {!g.dense && (
        <div className="relative -mx-3 h-3 rounded-b-[10px] rounded-t-[2px] border border-white/[0.16] bg-gradient-to-b from-[#2a2a2a] to-[#0d0d0d]">
          <span className="absolute left-1/2 top-0 h-[3px] w-16 -translate-x-1/2 rounded-b-full bg-black/60" />
        </div>
      )}
    </div>
  );
}

/* -------------------------------------------------------------------------
   The phone: Android shows the history full screen.
   ---------------------------------------------------------------------- */

function Phone({
  g,
  state,
  layout,
}: {
  g: Geometry;
  state: SceneState;
  layout: Layout;
}) {
  const { phase } = state;
  const rowHeight = g.dense ? 36 : 40;
  const fresh = phase === "arrive" || phase === "open";
  const peers = devicesOf(layout).length - 1;

  return (
    <div
      className="absolute z-10 rounded-[24px] border border-white/20 bg-[#0b0b0b] p-[5px] shadow-[0_30px_60px_-24px_rgb(0_0_0/0.95),inset_0_1px_0_rgb(255_255_255/0.12)]"
      style={{
        left: g.phone.x,
        top: g.phone.y,
        width: g.phone.w,
        height: g.phone.h,
      }}
    >
      <Echo on={phase === "arrive"} radius={24} />

      <div className="relative flex h-full w-full flex-col overflow-hidden rounded-[19px]">
        <Wallpaper variant="phone" />

        <div className="relative flex items-center justify-between px-3 pt-1.5 text-[7.5px] font-medium text-white/85">
          <span>10:24</span>
          <span className="absolute left-1/2 top-[5px] h-[5px] w-[5px] -translate-x-1/2 rounded-full bg-black shadow-[0_0_0_1px_rgb(255_255_255/0.15)]" />
          <span className="flex items-center gap-1">
            <Wifi size={8} />
            <BatteryMedium size={10} />
          </span>
        </div>

        <div
          className={`relative flex flex-col ${
            g.dense ? "gap-[5px] px-1.5 pt-1.5" : "gap-1.5 px-2 pt-2"
          }`}
        >
          <div className="flex items-center gap-1 text-[10px] font-semibold text-white">
            <LogoMark className="h-3 w-3" />
            PasteHive
          </div>
          <SearchAndFilters dense filters={["All", "Pinned", "Text", "Links"]} />
        </div>

        <div
          className={`relative mt-1 min-h-0 flex-1 overflow-hidden ${g.dense ? "mx-1" : "mx-1.5"}`}
        >
          {state.lists.phone.map((entry, index) => (
            <motion.div
              key={entry}
              initial={false}
              animate={{ y: index * rowHeight }}
              transition={{ type: "spring", stiffness: 420, damping: 38 }}
              className="absolute inset-x-0 top-0"
              style={{ zIndex: index === 0 ? 2 : 1 }}
            >
              <Row
                item={ITEMS[entry]}
                meta={metaFor(ITEMS[entry], "phone", layout, index, false)}
                dense
                lit={index === 0 && fresh}
              />
            </motion.div>
          ))}
        </div>

        <div className="relative flex items-center justify-center gap-1 border-t border-white/10 bg-black/60 py-1.5 text-[7.5px] text-white/70">
          <Lock size={8} />
          Syncing with {peers} {peers === 1 ? "device" : "devices"}
        </div>
      </div>
    </div>
  );
}

/* -------------------------------------------------------------------------
   The scene
   ---------------------------------------------------------------------- */

const QUERIES: Record<Layout, string> = {
  wide: "(min-width: 1024px)",
  compact: "(max-width: 1023.98px)",
};

export function Scene({ layout, paused }: { layout: Layout; paused: boolean }) {
  const g = GEOMETRY[layout];
  const boxRef = useRef<HTMLDivElement>(null);
  const canvasRef = useRef<HTMLDivElement>(null);

  const shown = useMediaQuery(QUERIES[layout], true);
  const inView = useInView(boxRef, { amount: 0.2 });
  const reduced = usePrefersReducedMotion();

  const [live, step] = useReducer(
    (current: SceneState) => advance(current, layout),
    INITIAL_STATE,
  );

  // Only the layout on screen keeps time, and only while it can be seen.
  const running = shown && inView && !paused && !reduced;
  useEffect(() => {
    if (!running) return;
    const timer = setTimeout(step, PHASE_MS[live.phase]);
    return () => clearTimeout(timer);
  }, [running, live.phase, live.act]);

  // Keep the scale in step with the box (CSS has already set a first value).
  useEffect(() => {
    const box = boxRef.current;
    const canvas = canvasRef.current;
    if (!box || !canvas) return;
    const observer = new ResizeObserver(([entry]) => {
      const { width, height } = entry.contentRect;
      if (!width || !height) return;
      const scale = Math.min(width / g.w, height / g.h, g.max);
      canvas.style.setProperty("--s", scale.toFixed(4));
    });
    observer.observe(box);
    return () => observer.disconnect();
  }, [g]);

  // With reduced motion the scene is one composed frame, as in the app.
  const state = reduced ? STATIC_STATE : live;
  const item = ACTS[state.act];
  const source = sourceOf(state.act, layout);
  const from = sourcePoint(source, g);
  const destinations = devicesOf(layout).filter((device) => device !== source);

  const labelY = g.screen.h + 22;

  return (
    <div ref={boxRef} className="scene-box absolute inset-0">
      <div
        ref={canvasRef}
        className="scene-canvas absolute left-1/2 top-1/2 select-none"
        style={{ "--w": g.w, "--h": g.h, "--max": g.max } as CSSProperties}
      >
        {(Object.keys(g.desktops) as DesktopId[]).map((id) => (
          <Desktop key={id} id={id} g={g} state={state} layout={layout} />
        ))}
        <Phone g={g} state={state} layout={layout} />

        {state.phase === "travel" &&
          destinations.map((device, index) => (
            <Token
              key={`${state.act}-${device}`}
              item={item}
              from={from}
              to={landingPoint(device, g)}
              delay={index * 0.05}
            />
          ))}

        {layout === "wide" ? (
          <>
            <Label
              at={{ x: g.desktops.win!.x + g.screen.w / 2, y: labelY }}
              align="center"
              icon={<WindowsIcon className="h-3 w-3" />}
              platform="Windows"
              device={DEVICE_NAMES.win}
            />
            <Label
              at={{ x: g.phone.x + g.phone.w / 2, y: labelY }}
              align="center"
              icon={<AndroidIcon className="h-3.5 w-3.5" />}
              platform="Android"
            />
            <Label
              at={{ x: g.desktops.mac!.x + g.screen.w / 2, y: labelY }}
              align="center"
              icon={<AppleIcon className="h-3 w-3" />}
              platform="macOS"
              device={DEVICE_NAMES.mac}
            />
          </>
        ) : (
          <>
            <Label
              at={{ x: 2, y: g.screen.h + 14 }}
              align="left"
              icon={<WindowsIcon className="h-3 w-3" />}
              platform="Windows"
              device={DEVICE_NAMES.win}
            />
            <Label
              at={{ x: 2, y: g.screen.h + 38 }}
              align="left"
              icon={<AndroidIcon className="h-3.5 w-3.5" />}
              platform="Android"
              device={DEVICE_NAMES.phone}
            />
            <div
              className="absolute flex items-center gap-1.5 text-[10px] text-white/60"
              style={{ left: 2, top: g.screen.h + 64 }}
            >
              <Lock size={11} className="text-white/85" />
              Same network, encrypted, no cloud
            </div>
          </>
        )}
      </div>
    </div>
  );
}
