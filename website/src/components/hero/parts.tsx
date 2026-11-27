"use client";

import { useId } from "react";
import { AnimatePresence, motion } from "motion/react";
import {
  AlignLeft,
  FileText,
  Globe,
  Link2,
  Mail,
  Search,
} from "lucide-react";
import { SWATCH, type Item, type Kind } from "./model";

/** A small stand-in photograph. Colour is allowed here: it is copied content. */
export function Picture({ className = "" }: { className?: string }) {
  // Unique per copy: a gradient inside a hidden layout cannot be relied on.
  const sky = useId();
  return (
    <svg
      viewBox="0 0 64 40"
      preserveAspectRatio="xMidYMid slice"
      className={className}
      aria-hidden="true"
    >
      <defs>
        <linearGradient id={sky} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#3b5bdb" />
          <stop offset="0.55" stopColor="#f783ac" />
          <stop offset="1" stopColor="#ffd8a8" />
        </linearGradient>
      </defs>
      <rect width="64" height="40" fill={`url(#${sky})`} />
      <circle cx="44" cy="17" r="6" fill="#fff3bf" />
      <path d="M0 40 L0 29 L14 18 L27 31 L37 23 L64 37 L64 40 Z" fill="#1c2541" />
      <path d="M0 40 L0 34 L20 27 L40 36 L64 31 L64 40 Z" fill="#0b132b" />
    </svg>
  );
}

const KIND_ICONS = {
  text: AlignLeft,
  link: Link2,
  file: FileText,
  email: Mail,
} as const;

/** The square at the start of a history row: a symbol, thumbnail or swatch. */
export function KindTile({ kind, size }: { kind: Kind; size: number }) {
  const radius = Math.round(size * 0.28);
  const base = {
    width: size,
    height: size,
    borderRadius: radius,
  };

  if (kind === "image") {
    return (
      <span className="block shrink-0 overflow-hidden" style={base}>
        <Picture className="h-full w-full" />
      </span>
    );
  }

  if (kind === "color") {
    return (
      <span
        className="block shrink-0 shadow-[inset_0_0_0_1px_rgb(255_255_255/0.25)]"
        style={{ ...base, background: SWATCH }}
      />
    );
  }

  const Icon = KIND_ICONS[kind];
  return (
    <span
      className="flex shrink-0 items-center justify-center bg-white/[0.11] text-white/85"
      style={base}
    >
      <Icon size={Math.round(size * 0.52)} strokeWidth={2} />
    </span>
  );
}

interface RowProps {
  item: Item;
  meta: string;
  dense?: boolean;
  /** The row under the pointer, or the one that has just arrived. */
  lit?: boolean;
}

/** One entry of the clipboard history, as the panel and the phone draw it. */
export function Row({ item, meta, dense, lit }: RowProps) {
  return (
    <div
      className={`flex w-full items-center rounded-[9px] transition-colors duration-200 ${
        dense ? "h-[34px] gap-[7px] px-[5px]" : "h-[38px] gap-2 px-1.5"
      } ${lit ? "bg-white/[0.16]" : "bg-transparent"}`}
    >
      <KindTile kind={item.kind} size={dense ? 22 : 26} />
      <span className="min-w-0 flex-1 leading-tight">
        <span
          className={`block truncate font-medium text-white ${
            dense ? "text-[10px]" : "text-[11px]"
          }`}
        >
          {item.title}
        </span>
        <span
          className={`block truncate text-white/60 ${
            dense ? "text-[7.5px]" : "text-[8.5px]"
          }`}
        >
          {meta}
        </span>
      </span>
    </div>
  );
}

/** The search field and filter chips that head every history view. */
export function SearchAndFilters({
  dense,
  filters,
}: {
  dense?: boolean;
  filters: string[];
}) {
  return (
    <>
      <div
        className={`flex items-center gap-1.5 rounded-full bg-white/[0.11] px-2 text-white/55 ${
          dense ? "h-[20px] text-[8px]" : "h-[24px] text-[9.5px]"
        }`}
      >
        <Search size={dense ? 9 : 11} strokeWidth={2.2} className="shrink-0" />
        <span className="truncate">Search Clipboard</span>
      </div>
      <div
        className={`flex items-center gap-1 overflow-hidden whitespace-nowrap ${
          dense ? "text-[7.5px]" : "text-[8.5px]"
        }`}
      >
        {filters.map((filter, index) => (
          <span
            key={filter}
            className={`rounded-full px-[7px] py-[2.5px] ${
              index === 0
                ? "bg-white/[0.22] font-semibold text-white"
                : "text-white/60"
            }`}
          >
            {filter}
          </span>
        ))}
      </div>
    </>
  );
}

/** The sweep of a text selection: grows from the left behind the text. */
function Selection({ on }: { on: boolean }) {
  return (
    <motion.span
      aria-hidden="true"
      initial={false}
      animate={{ scaleX: on ? 1 : 0, opacity: on ? 1 : 0 }}
      transition={{ duration: on ? 0.55 : 0.25, ease: [0.22, 1, 0.36, 1] }}
      className="absolute -inset-x-1 -inset-y-0.5 origin-left rounded-[3px] bg-white/30"
    />
  );
}

/** A ring around something that is not text: a picture, a swatch. */
function SelectionRing({ on, radius }: { on: boolean; radius: number }) {
  return (
    <motion.span
      aria-hidden="true"
      initial={false}
      animate={{ opacity: on ? 1 : 0, scale: on ? 1 : 1.08 }}
      transition={{ duration: 0.35, ease: [0.22, 1, 0.36, 1] }}
      className="absolute -inset-[3px] border-[1.5px] border-white"
      style={{ borderRadius: radius }}
    />
  );
}

const Bar = ({ w, strong }: { w: string; strong?: boolean }) => (
  <span
    className={`block h-[5px] rounded-full ${strong ? "bg-white/30" : "bg-white/[0.16]"}`}
    style={{ width: w }}
  />
);

/**
 * What the app window shows for the thing being copied: a line in a note, a
 * web address, a picture, or a colour in a palette.
 */
export function SourceView({
  item,
  selected,
  dense,
}: {
  item: Item;
  selected: boolean;
  dense?: boolean;
}) {
  const text = dense ? "text-[10px]" : "text-[11.5px]";

  return (
    <AnimatePresence mode="wait" initial={false}>
      <motion.div
        key={item.id}
        initial={{ opacity: 0, y: 4 }}
        animate={{ opacity: 1, y: 0 }}
        exit={{ opacity: 0, y: -4 }}
        transition={{ duration: 0.22 }}
        className="flex h-full flex-col justify-center gap-[7px]"
      >
        {item.kind === "text" && (
          <>
            <Bar w="46%" strong />
            <Bar w="88%" />
            <span className={`relative w-fit font-medium text-white ${text}`}>
              <Selection on={selected} />
              <span className="relative">{item.title}</span>
            </span>
            <Bar w="70%" />
          </>
        )}

        {item.kind === "link" && (
          <>
            <span
              className={`flex w-full items-center gap-1.5 rounded-full bg-white/[0.1] px-2 py-[5px] ${text}`}
            >
              <Globe size={dense ? 10 : 12} className="shrink-0 text-white/60" />
              <span className="relative w-fit text-white">
                <Selection on={selected} />
                <span className="relative">{item.title}</span>
              </span>
            </span>
            <Bar w="58%" strong />
            <Bar w="92%" />
            <Bar w="76%" />
          </>
        )}

        {item.kind === "image" && (
          <div className="flex items-center gap-3">
            <span
              className={`relative block shrink-0 ${
                dense ? "h-[58px] w-[92px]" : "h-[74px] w-[118px]"
              }`}
            >
              <Picture className="h-full w-full rounded-[6px]" />
              <SelectionRing on={selected} radius={8} />
            </span>
            <span className="flex flex-1 flex-col gap-[7px]">
              <Bar w="70%" strong />
              <Bar w="100%" />
              <Bar w="55%" />
            </span>
          </div>
        )}

        {item.kind === "color" && (
          <>
            <Bar w="34%" strong />
            <div className="flex items-center gap-[7px]">
              {["#f1f1f1", "#9a9a9a", SWATCH, "#4a4a4a", "#1d1d1d"].map(
                (color) => (
                  <span
                    key={color}
                    className={`relative block rounded-[6px] shadow-[inset_0_0_0_1px_rgb(255_255_255/0.2)] ${
                      dense ? "h-[22px] w-[22px]" : "h-[28px] w-[28px]"
                    }`}
                    style={{ background: color }}
                  >
                    {color === SWATCH && (
                      <SelectionRing on={selected} radius={8} />
                    )}
                  </span>
                ),
              )}
            </div>
            <span className={`relative w-fit font-mono text-white ${text}`}>
              <Selection on={selected} />
              <span className="relative">{item.title}</span>
            </span>
          </>
        )}
      </motion.div>
    </AnimatePresence>
  );
}

/** The field the entry is pasted into: a caret, then the pasted thing. */
export function Compose({
  pasted,
  dense,
}: {
  pasted: Item | null;
  dense?: boolean;
}) {
  const text = dense ? "text-[10px]" : "text-[11.5px]";

  return (
    <div
      className={`flex w-full items-center gap-1.5 rounded-[8px] border border-white/[0.14] bg-black/25 px-2 ${
        dense ? "h-[26px]" : "h-[34px]"
      }`}
    >
      <AnimatePresence initial={false}>
        {pasted && (
          <motion.span
            key={pasted.id}
            initial={{ opacity: 0, y: 5 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, transition: { duration: 0.15 } }}
            transition={{ duration: 0.28, ease: [0.22, 1, 0.36, 1] }}
            className={`flex min-w-0 items-center gap-1.5 text-white ${text}`}
          >
            {pasted.kind === "image" && (
              <Picture
                className={`shrink-0 rounded-[4px] ${
                  dense ? "h-[18px] w-[29px]" : "h-[24px] w-[38px]"
                }`}
              />
            )}
            {pasted.kind === "color" && (
              <span
                className="block h-3 w-3 shrink-0 rounded-[3px]"
                style={{ background: SWATCH }}
              />
            )}
            <span
              className={`truncate ${
                pasted.kind === "link" ? "underline underline-offset-2" : ""
              } ${pasted.kind === "color" ? "font-mono" : ""}`}
            >
              {pasted.kind === "image" ? "image.png" : pasted.title}
            </span>
          </motion.span>
        )}
      </AnimatePresence>
      <span
        aria-hidden="true"
        className="h-[55%] w-[1.5px] shrink-0 animate-caret rounded-full bg-white"
      />
      {!pasted && (
        <span className={`text-white/45 ${dense ? "text-[8.5px]" : "text-[10px]"}`}>
          Paste here
        </span>
      )}
    </div>
  );
}

/** The mouse pointer. Drawn in white with a dark edge so it shows on glass. */
export function Pointer() {
  return (
    <svg width="14" height="18" viewBox="0 0 14 18" aria-hidden="true">
      <path
        d="M1.5 1.5 L1.5 14.2 L4.9 11.2 L7.3 16.4 L9.6 15.3 L7.2 10.2 L11.9 10.2 Z"
        fill="#fff"
        stroke="#000"
        strokeWidth="1.2"
        strokeLinejoin="round"
      />
    </svg>
  );
}
