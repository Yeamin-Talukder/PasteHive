"use client";

import { useState, type ReactNode } from "react";
import Image from "next/image";
import { AnimatePresence, motion } from "motion/react";
import {
  ArrowUpToLine,
  ClipboardPaste,
  Contrast,
  CopyCheck,
  EyeOff,
  History,
  Layers,
  type LucideIcon,
  MousePointer2,
  Pin,
  RefreshCw,
  Search,
  Share2,
  Trash2,
  Undo2,
  Users,
} from "lucide-react";
import screenshotDark from "@/assets/screenshot-dark.png";
import screenshotSync from "@/assets/screenshot-sync.png";
import { KindTile } from "./hero/parts";
import type { Kind } from "./hero/model";
import { LogoMark } from "./icons";
import { Card, Reveal, Section, SectionHeading } from "./ui";

/* ---------------------------------------------------------------------- */
/* Search and filters: a small working copy of the real thing              */
/* ---------------------------------------------------------------------- */

interface Entry {
  id: string;
  kind: Kind;
  title: string;
  meta: string;
  pinned?: boolean;
  synced?: boolean;
}

const ENTRIES: Entry[] = [
  { id: "color", kind: "color", title: "#FF6B9D", meta: "Color", pinned: true },
  {
    id: "synced",
    kind: "text",
    title: "Copied on the other computer",
    meta: "from Sam’s MacBook",
    synced: true,
  },
  { id: "image", kind: "image", title: "Image", meta: "1920 × 1080" },
  { id: "file", kind: "file", title: "summary.pdf", meta: "in report" },
  {
    id: "note",
    kind: "text",
    title: "Remember to call the dentist",
    meta: "28 characters",
  },
  {
    id: "link",
    kind: "link",
    title: "https://flutter.dev/docs",
    meta: "flutter.dev",
  },
  { id: "email", kind: "email", title: "sam@example.com", meta: "Email" },
];

const FILTERS: { label: string; test: (entry: Entry) => boolean }[] = [
  { label: "All", test: () => true },
  { label: "Pinned", test: (entry) => Boolean(entry.pinned) },
  { label: "Text", test: (entry) => entry.kind === "text" },
  { label: "Links", test: (entry) => entry.kind === "link" },
  { label: "Images", test: (entry) => entry.kind === "image" },
  { label: "Files", test: (entry) => entry.kind === "file" },
  { label: "Emails", test: (entry) => entry.kind === "email" },
  { label: "Colors", test: (entry) => entry.kind === "color" },
  { label: "Synced", test: (entry) => Boolean(entry.synced) },
];

function FilterDemo() {
  const [filter, setFilter] = useState("All");
  const [query, setQuery] = useState("");

  const test = FILTERS.find((item) => item.label === filter)!.test;
  const needle = query.trim().toLowerCase();
  const results = ENTRIES.filter(
    (entry) =>
      test(entry) &&
      (!needle ||
        entry.title.toLowerCase().includes(needle) ||
        entry.meta.toLowerCase().includes(needle)),
  );

  return (
    <div className="rounded-2xl border border-white/[0.14] bg-[rgb(20_20_26/0.6)] p-3 shadow-[inset_0_1px_0_rgb(255_255_255/0.3)]">
      <label className="flex h-10 items-center gap-2.5 rounded-full bg-white/[0.09] px-3.5 text-white/60 transition-colors duration-200 focus-within:bg-white/[0.14] focus-within:text-white hover:bg-white/[0.12]">
        <Search size={16} />
        <span className="sr-only">Search the sample clipboard</span>
        <input
          type="search"
          value={query}
          onChange={(event) => setQuery(event.target.value)}
          placeholder="Search Clipboard"
          className="h-full min-w-0 flex-1 bg-transparent text-[0.92rem] text-white outline-none placeholder:text-white/50 [&::-webkit-search-cancel-button]:hidden"
        />
      </label>

      <div
        role="group"
        aria-label="Filter the sample clipboard"
        className="-mx-1 mt-2.5 flex gap-1 overflow-x-auto px-1 pb-1 [scrollbar-width:none]"
      >
        {FILTERS.map((item) => {
          const selected = item.label === filter;
          return (
            <button
              key={item.label}
              type="button"
              aria-pressed={selected}
              onClick={() => setFilter(item.label)}
              className={`relative shrink-0 rounded-full px-3 py-1.5 text-[0.82rem] transition-colors duration-200 ${
                selected
                  ? "font-semibold text-white"
                  : "text-white/60 hover:bg-white/[0.08] hover:text-white"
              }`}
            >
              {selected && (
                <motion.span
                  layoutId="filter-pill"
                  className="absolute inset-0 rounded-full bg-white/[0.22]"
                  transition={{ type: "spring", stiffness: 420, damping: 34 }}
                />
              )}
              <span className="relative">{item.label}</span>
            </button>
          );
        })}
      </div>

      <ul
        aria-live="polite"
        className="relative mt-1.5 flex h-[236px] flex-col overflow-hidden"
      >
        <AnimatePresence initial={false} mode="popLayout">
          {results.slice(0, 5).map((entry) => (
            <motion.li
              key={entry.id}
              layout="position"
              initial={{ opacity: 0, y: 8 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, scale: 0.97, transition: { duration: 0.12 } }}
              transition={{ type: "spring", stiffness: 420, damping: 36 }}
              className="group/row flex h-[46px] shrink-0 items-center gap-3 rounded-xl px-2 transition-colors duration-150 hover:bg-white/[0.09]"
            >
              <KindTile kind={entry.kind} size={32} />
              <span className="min-w-0 flex-1 leading-tight">
                <span className="block truncate text-[0.9rem] font-medium">
                  {entry.title}
                </span>
                <span className="block truncate text-[0.74rem] text-dim">
                  {entry.meta}
                </span>
              </span>
              {entry.pinned && <Pin size={14} className="text-white/70" />}
            </motion.li>
          ))}
        </AnimatePresence>
        {results.length === 0 && (
          <li className="absolute inset-0 flex items-center justify-center text-[0.9rem] text-dim">
            Nothing matches.
          </li>
        )}
      </ul>
    </div>
  );
}

/* ---------------------------------------------------------------------- */
/* The top-edge gesture                                                    */
/* ---------------------------------------------------------------------- */

function EdgeDemo() {
  // Plain CSS: the card's hover (or keyboard focus inside it) moves the
  // pointer to the top middle and the panel drops. On touch screens, where
  // nothing hovers, the panel is simply shown open.
  const openPanel =
    "group-hover/card:translate-y-0 group-hover/card:opacity-100 group-focus-within/card:translate-y-0 group-focus-within/card:opacity-100 [@media(hover:none)]:translate-y-0 [@media(hover:none)]:opacity-100";
  const movePointer =
    "group-hover/card:-translate-y-[92px] group-hover/card:-translate-x-[6px] group-focus-within/card:-translate-y-[92px] group-focus-within/card:-translate-x-[6px] [@media(hover:none)]:hidden";

  return (
    <div
      aria-hidden="true"
      className="relative h-[168px] overflow-hidden rounded-2xl border border-white/[0.14] bg-[linear-gradient(150deg,#2b2b2b,#0d0d0d_62%,#000)]"
    >
      <span className="absolute -left-[6%] -top-[40%] h-[120%] w-[40%] rotate-12 rounded-[22%] bg-white/[0.16]" />
      <span className="absolute -right-[8%] top-[20%] h-[120%] w-[44%] -rotate-12 rounded-[22%] bg-white/[0.08]" />

      {/* The strip at the top middle that the pointer rests on */}
      <span className="absolute left-1/2 top-0 h-[3px] w-24 -translate-x-1/2 rounded-b-full bg-white/50 transition-colors duration-300 group-hover/card:bg-white" />

      <div
        className={`absolute left-1/2 top-2 w-[200px] -translate-x-1/2 -translate-y-[115%] rounded-xl border border-white/[0.16] bg-[rgb(20_20_26/0.55)] p-2 opacity-0 shadow-[inset_0_1px_0_rgb(255_255_255/0.5),0_18px_36px_-10px_rgb(0_0_0/0.9)] backdrop-blur-md transition-[translate,opacity] duration-500 ease-[cubic-bezier(0.3,1.35,0.5,1)] ${openPanel}`}
      >
        <div className="flex h-6 items-center gap-1.5 rounded-full bg-white/[0.11] px-2 text-[0.62rem] text-white/55">
          <Search size={10} /> Search Clipboard
        </div>
        {[
          ["text", "Meeting moved to 3 pm, room 4B"],
          ["link", "https://flutter.dev/docs"],
          ["color", "#FF6B9D"],
        ].map(([kind, title], index) => (
          <div
            key={title}
            className={`mt-1 flex items-center gap-2 rounded-lg px-1 py-1 text-[0.68rem] font-medium ${
              index === 0 ? "bg-white/[0.16]" : ""
            }`}
          >
            <KindTile kind={kind as Kind} size={20} />
            <span className="truncate">{title}</span>
          </div>
        ))}
      </div>

      <span
        className={`absolute left-1/2 top-[110px] transition-transform delay-75 duration-500 ease-out-soft ${movePointer}`}
      >
        <MousePointer2 size={18} className="fill-white text-black" strokeWidth={1.4} />
      </span>

      <span className="absolute bottom-2.5 left-1/2 -translate-x-1/2 text-[0.68rem] text-white/55 transition-opacity duration-300 group-hover/card:opacity-0 [@media(hover:none)]:hidden">
        Hover this card
      </span>
    </div>
  );
}

/* ---------------------------------------------------------------------- */
/* Sync: a group of devices                                                */
/* ---------------------------------------------------------------------- */

function HiveDiagram() {
  const nodes = [
    { x: 50, y: 22 },
    { x: 20, y: 76 },
    { x: 80, y: 76 },
  ];
  return (
    <div
      aria-hidden="true"
      className="relative h-[168px] overflow-hidden rounded-2xl border border-white/[0.14] bg-black/40"
    >
      <svg
        viewBox="0 0 100 100"
        preserveAspectRatio="none"
        className="absolute inset-0 h-full w-full"
      >
        {[
          [0, 1],
          [1, 2],
          [2, 0],
        ].map(([a, b]) => (
          <line
            key={`${a}-${b}`}
            x1={nodes[a].x}
            y1={nodes[a].y}
            x2={nodes[b].x}
            y2={nodes[b].y}
            stroke="rgb(255 255 255 / 0.28)"
            strokeWidth="1"
            strokeDasharray="2 3"
            vectorEffect="non-scaling-stroke"
          />
        ))}
      </svg>
      {nodes.map((node, index) => (
        <span
          key={index}
          className="absolute flex h-11 w-11 -translate-x-1/2 -translate-y-1/2 items-center justify-center rounded-[30%] border border-white/25 bg-gradient-to-br from-white/25 to-white/5 shadow-[inset_0_1px_0_rgb(255_255_255/0.35)] transition-transform duration-500 ease-out-soft group-hover/card:scale-110"
          style={{
            left: `${node.x}%`,
            top: `${node.y}%`,
            transitionDelay: `${index * 70}ms`,
          }}
        >
          <LogoMark className="h-6 w-6" />
          <span
            className="absolute -inset-px animate-echo rounded-[30%] border border-white [--echo-high:0.9] [--echo-low:0]"
            style={{ animationDelay: `${index * 1.6}s` }}
          />
        </span>
      ))}
    </div>
  );
}

/* ---------------------------------------------------------------------- */

function Points({ items }: { items: { icon: LucideIcon; text: ReactNode }[] }) {
  return (
    <ul className="flex flex-col gap-3">
      {items.map((item, index) => (
        <li key={index} className="flex gap-3 text-[0.93rem] leading-relaxed text-dim">
          <item.icon size={17} className="mt-[3px] shrink-0 text-white" />
          <span>{item.text}</span>
        </li>
      ))}
    </ul>
  );
}

function CardTitle({ kicker, children }: { kicker: string; children: ReactNode }) {
  return (
    <>
      <p className="mb-2 font-mono text-[0.7rem] uppercase tracking-[0.2em] text-faint">
        {kicker}
      </p>
      <h3 className="mb-5 text-[1.45rem] font-semibold leading-tight tracking-[-0.02em]">
        {children}
      </h3>
    </>
  );
}

export function Features() {
  return (
    <Section id="features" labelledBy="features-title">
      <SectionHeading
        id="features-title"
        eyebrow="Features"
        title="Everything you copy, where you need it."
      >
        A history you can search, sync between your own devices, and an app
        that stays out of the way until you reach for it.
      </SectionHeading>

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-12">
        <Reveal className="lg:col-span-7">
          <Card className="h-full p-6 sm:p-7">
            <CardTitle kicker="Search and filters">
              Find it as fast as you can type.
            </CardTitle>
            <FilterDemo />
            <p className="mt-4 text-[0.93rem] leading-relaxed text-dim">
              Try it: this one works. Search as you type, and filter by All,
              Pinned, Text, Links, Images, Files, Emails, Colors and Synced.
              Links, email addresses and hex colours are recognised; a colour
              is shown as a swatch and a picture as a thumbnail.
            </p>
          </Card>
        </Reveal>

        <Reveal delay={0.08} className="lg:col-span-5">
          <Card className="h-full p-6 sm:p-7">
            <CardTitle kicker="Clipboard history">
              Everything you copy, newest first.
            </CardTitle>
            <div className="mb-6 flex flex-wrap gap-1.5" aria-hidden="true">
              {["Pinned", "Today", "Yesterday", "This Week", "Earlier"].map(
                (group, index) => (
                  <span
                    key={group}
                    className="rounded-full border border-white/15 px-3 py-1 text-[0.78rem] text-white/75 transition duration-300 group-hover/card:border-white/35 group-hover/card:text-white"
                    style={{ transitionDelay: `${index * 50}ms` }}
                  >
                    {group}
                  </span>
                ),
              )}
            </div>
            <Points
              items={[
                {
                  icon: History,
                  text: "Records text, pictures (screenshots, images copied from a page or an editor) and files copied in a file manager, newest first.",
                },
                {
                  icon: Layers,
                  text: "Groups entries under Pinned, Today, Yesterday, This Week and Earlier.",
                },
                {
                  icon: Pin,
                  text: "Preview an entry in full, pin it, or delete it.",
                },
                {
                  icon: Undo2,
                  text: "A deleted entry can be brought back for a few seconds.",
                },
                {
                  icon: CopyCheck,
                  text: "Copying the same thing again moves it to the top instead of adding a duplicate.",
                },
              ]}
            />
          </Card>
        </Reveal>

        <Reveal className="lg:col-span-5">
          <Card className="h-full p-6 sm:p-7">
            <CardTitle kicker="Clipboard sync">
              Your devices become one hive.
            </CardTitle>
            <div className="mb-6">
              <HiveDiagram />
            </div>
            <Points
              items={[
                {
                  icon: RefreshCw,
                  text: "Copy on one device, paste on another: text and pictures.",
                },
                {
                  icon: Users,
                  text: "More than two devices can share one group: pair a new device with any member and it syncs with all of them.",
                },
                {
                  icon: Trash2,
                  text: "Deleting an entry, undoing the delete and Clear History carry over to every connected device.",
                },
                {
                  icon: Share2,
                  text: "Optionally share the text already in your history with a newly connected device.",
                },
              ]}
            />
          </Card>
        </Reveal>

        <Reveal delay={0.08} className="lg:col-span-7">
          <Card className="h-full p-6 sm:p-7">
            <CardTitle kicker="Made to stay out of the way">
              It is there when the pointer asks.
            </CardTitle>
            <div className="mb-6">
              <EdgeDemo />
            </div>
            <Points
              items={[
                {
                  icon: ArrowUpToLine,
                  text: "Opens when the pointer rests at the top middle of any screen. Closes when the pointer leaves, on Esc, or when you click elsewhere.",
                },
                {
                  icon: ClipboardPaste,
                  text: "Picking an entry pastes it straight into the app you were working in.",
                },
                {
                  icon: EyeOff,
                  text: "No taskbar button and no Dock icon. A tray icon (Windows) or menu bar icon (macOS) offers Show Clipboard, Sync Settings, Pause Capturing, start at login, Clear History and Quit.",
                },
                {
                  icon: Contrast,
                  text: "Light and dark appearance, an opaque fallback when more contrast is requested, and no motion when reduced motion is on.",
                },
              ]}
            />
          </Card>
        </Reveal>
      </div>

      <Reveal className="mt-4">
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          {[
            {
              src: screenshotDark,
              alt: "PasteHive clipboard history panel with search, filters and pinned entries",
              caption: "The history panel, dark appearance",
            },
            {
              src: screenshotSync,
              alt: "PasteHive sync settings showing a connected device on the local network",
              caption: "Sync settings, light appearance",
            },
          ].map((shot) => (
            <figure
              key={shot.caption}
              className="group/shot overflow-hidden rounded-3xl border border-white/10 bg-ink-raised transition-colors duration-300 hover:border-white/25"
            >
              <div className="overflow-hidden">
                <Image
                  src={shot.src}
                  alt={shot.alt}
                  sizes="(min-width: 640px) 50vw, 100vw"
                  className="aspect-[4/3] w-full object-cover object-top grayscale transition duration-700 ease-out-soft group-hover/shot:scale-[1.03] group-hover/shot:grayscale-0 [@media(hover:none)]:grayscale-0"
                />
              </div>
              <figcaption className="flex items-center justify-between gap-3 px-5 py-3.5 text-[0.85rem] text-dim">
                <span>{shot.caption}</span>
                <span className="font-mono text-[0.7rem] uppercase tracking-[0.18em] text-faint">
                  Real screenshot
                </span>
              </figcaption>
            </figure>
          ))}
        </div>
      </Reveal>
    </Section>
  );
}
