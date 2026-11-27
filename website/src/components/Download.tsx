"use client";

import { useState, type ReactNode } from "react";
import { AnimatePresence, motion } from "motion/react";
import { ArrowUpRight, Check, Copy, Hammer, Info } from "lucide-react";
import { BUILD_URL, RELEASES_URL } from "@/lib/site";
import { AndroidIcon, AppleIcon, WindowsIcon } from "./icons";
import { Card, Reveal, Section, SectionHeading } from "./ui";

interface Platform {
  id: string;
  name: string;
  icon: ReactNode;
  status: string;
  /** How solid the build is, said the way the README says it. */
  maturity: string;
  gets: string;
  file?: string;
  notes?: string[];
}

const PLATFORMS: Platform[] = [
  {
    id: "windows",
    name: "Windows",
    icon: <WindowsIcon className="h-6 w-6" />,
    status: "Most tested",
    maturity: "The most used and tested build.",
    gets: "Background panel, history, paste into the previous app, sync.",
    file: "Installer or zip",
  },
  {
    id: "macos",
    name: "macOS",
    icon: <AppleIcon className="h-6 w-6" />,
    status: "Less tested",
    maturity:
      "Release builds pass the app’s self-checks; less tested on real hardware.",
    gets: "Background panel, history, paste, sync.",
    file: "App bundle",
    notes: ["Pasting needs the Accessibility permission."],
  },
  {
    id: "android",
    name: "Android",
    icon: <AndroidIcon className="h-6 w-6" />,
    status: "Early",
    maturity: "Early, with limits.",
    gets: "Full-screen history, filters, preview, sync.",
    file: "APK",
    notes: [
      "Android does not let an app watch the clipboard in the background: PasteHive reads it each time the app comes to the front, and takes text from Share and the text-selection menu.",
      "While sync is on, a notification keeps the connection alive.",
      "Pictures arrive in the list but cannot yet be put on the phone’s clipboard.",
    ],
  },
  {
    id: "ios",
    name: "iOS",
    icon: <AppleIcon className="h-6 w-6" />,
    status: "Coming soon",
    maturity: "Planned. Not available yet.",
    gets: "Nothing to download for now.",
  },
];

/* ---------------------------------------------------------------------- */

function CopyLine({ command }: { command: string }) {
  const [copied, setCopied] = useState(false);

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(command);
      setCopied(true);
      setTimeout(() => setCopied(false), 1600);
    } catch {
      // Clipboard access can be refused; the command can still be selected.
    }
  };

  return (
    <div className="group/line flex items-center gap-3 rounded-lg py-1 pl-3 pr-1 transition-colors duration-150 hover:bg-white/[0.06]">
      <span aria-hidden="true" className="select-none text-white/35">
        $
      </span>
      <code className="min-w-0 flex-1 overflow-x-auto whitespace-nowrap py-1 text-[0.84rem] text-white/90 [scrollbar-width:none]">
        {command}
      </code>
      <button
        type="button"
        onClick={copy}
        aria-label={copied ? "Copied" : `Copy: ${command}`}
        className="relative flex h-8 w-8 shrink-0 items-center justify-center rounded-md text-white/55 transition duration-150 hover:bg-white/[0.12] hover:text-white active:scale-90"
      >
        <AnimatePresence mode="wait" initial={false}>
          <motion.span
            key={copied ? "done" : "copy"}
            initial={{ opacity: 0, scale: 0.6 }}
            animate={{ opacity: 1, scale: 1 }}
            exit={{ opacity: 0, scale: 0.6 }}
            transition={{ duration: 0.14 }}
          >
            {copied ? <Check size={15} /> : <Copy size={15} />}
          </motion.span>
        </AnimatePresence>
      </button>
    </div>
  );
}

const TARGETS = [
  {
    id: "windows",
    label: "Windows",
    toolchain: "Visual Studio",
    run: "flutter run -d windows",
    build: "flutter build windows",
  },
  {
    id: "macos",
    label: "macOS",
    toolchain: "Xcode",
    run: "flutter run -d macos",
    build: "flutter build macos",
  },
  {
    id: "android",
    label: "Android",
    toolchain: "Android Studio",
    run: "flutter run -d android",
    build: "flutter build apk",
  },
];

function BuildFromSource() {
  const [target, setTarget] = useState(TARGETS[0]);

  return (
    <Card className="p-6 sm:p-7">
      <div className="grid grid-cols-1 gap-6 lg:grid-cols-[minmax(0,4fr)_minmax(0,7fr)] lg:gap-10">
        <div>
          <p className="mb-2 flex items-center gap-2 font-mono text-[0.7rem] uppercase tracking-[0.2em] text-faint">
            <Hammer size={13} /> Until the first release
          </p>
          <h3
            id="build-from-source"
            className="mb-3 text-[1.45rem] font-semibold leading-tight tracking-[-0.02em]"
          >
            Build it from source.
          </h3>
          <p className="text-[0.93rem] leading-relaxed text-dim">
            It takes one command per platform. You need{" "}
            <a
              href="https://docs.flutter.dev/get-started/install"
              className="text-white underline decoration-white/30 underline-offset-4 transition-colors hover:decoration-white"
            >
              Flutter
            </a>{" "}
            and the platform’s own toolchain: {target.toolchain} for{" "}
            {target.label}.
          </p>
          <a
            href={BUILD_URL}
            className="group mt-5 inline-flex items-center gap-1.5 text-[0.93rem] font-medium text-white underline decoration-white/30 underline-offset-4 transition-colors hover:decoration-white"
          >
            Full instructions in the README
            <ArrowUpRight
              size={15}
              className="transition-transform duration-200 group-hover:-translate-y-0.5 group-hover:translate-x-0.5"
            />
          </a>
        </div>

        <div className="min-w-0 rounded-2xl border border-white/[0.12] bg-black/50 p-2 font-mono">
          <div
            role="group"
            aria-label="Platform to build for"
            className="mb-2 flex gap-1 border-b border-white/10 pb-2"
          >
            {TARGETS.map((item) => {
              const selected = item.id === target.id;
              return (
                <button
                  key={item.id}
                  type="button"
                  aria-pressed={selected}
                  onClick={() => setTarget(item)}
                  className={`relative rounded-md px-3 py-1.5 text-[0.78rem] transition-colors duration-200 ${
                    selected ? "text-white" : "text-white/55 hover:text-white"
                  }`}
                >
                  {selected && (
                    <motion.span
                      layoutId="build-tab"
                      className="absolute inset-0 rounded-md bg-white/[0.14]"
                      transition={{ type: "spring", stiffness: 420, damping: 34 }}
                    />
                  )}
                  <span className="relative">{item.label}</span>
                </button>
              );
            })}
          </div>
          <CopyLine command="git clone https://github.com/Yeamin-Talukder/PasteHive.git" />
          <CopyLine command="cd PasteHive" />
          <CopyLine command="flutter pub get" />
          <CopyLine command={target.run} />
          <p className="px-3 pb-1 pt-3 text-[0.72rem] text-white/45">
            # or build a release
          </p>
          <CopyLine command={target.build} />
        </div>
      </div>
    </Card>
  );
}

/* ---------------------------------------------------------------------- */

export function Download() {
  return (
    <Section id="download" labelledBy="download-title">
      <SectionHeading
        id="download-title"
        eyebrow="Platforms and download"
        title="Free on Windows, macOS and Android."
      >
        Open source under the MIT license. iOS is planned and not available
        yet.
      </SectionHeading>

      <Reveal>
        <p className="mx-auto mb-8 flex max-w-3xl items-start gap-3 rounded-2xl border border-white/20 bg-white/[0.06] p-4 text-[0.93rem] leading-relaxed text-white/85">
          <Info size={18} className="mt-0.5 shrink-0 text-white" />
          <span>
            <strong className="font-semibold text-white">
              There is no packaged release yet.
            </strong>{" "}
            The download buttons open the project’s releases page, which has
            nothing to offer for now. When the first release is published its
            files will be listed there. Until then,{" "}
            <a
              href="#build-from-source"
              className="text-white underline decoration-white/40 underline-offset-4 transition-colors hover:decoration-white"
            >
              build it from source
            </a>
            .
          </span>
        </p>
      </Reveal>

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
        {PLATFORMS.map((platform, index) => {
          const available = Boolean(platform.file);
          return (
            <Reveal key={platform.id} delay={index * 0.06} className="h-full">
              <Card as="article" className="flex h-full flex-col p-6">
                <div className="flex h-full flex-col">
                  <div className="mb-5 flex items-start justify-between">
                    <span
                      className={`flex h-12 w-12 items-center justify-center rounded-2xl border border-white/15 bg-white/[0.07] transition duration-300 ease-out-soft group-hover/card:-translate-y-0.5 group-hover/card:border-white/40 ${
                        available ? "text-white" : "text-white/50"
                      }`}
                    >
                      {platform.icon}
                    </span>
                    <span
                      className={`rounded-full border px-2.5 py-1 font-mono text-[0.68rem] uppercase tracking-[0.12em] ${
                        platform.status === "Most tested"
                          ? "border-white bg-white text-black"
                          : available
                            ? "border-white/50 text-white"
                            : "border-dashed border-white/35 text-white/70"
                      }`}
                    >
                      {platform.status}
                    </span>
                  </div>

                  <h3 className="text-xl font-semibold tracking-[-0.02em]">
                    {platform.name}
                  </h3>
                  <p className="mt-1.5 text-[0.9rem] leading-relaxed text-white/85">
                    {platform.maturity}
                  </p>
                  <p className="mt-3 text-[0.88rem] leading-relaxed text-dim">
                    {platform.gets}
                  </p>
                  {platform.notes && (
                    <ul className="mt-3 flex flex-col gap-2 border-t border-white/10 pt-3 text-[0.8rem] leading-relaxed text-dim">
                      {platform.notes.map((note) => (
                        <li key={note}>{note}</li>
                      ))}
                    </ul>
                  )}

                  <div className="mt-auto pt-6">
                    {platform.file && (
                      <p className="mb-2.5 flex items-center justify-between px-1 font-mono text-[0.7rem] uppercase tracking-[0.12em] text-faint">
                        <span>File</span>
                        <span className="text-white/75">{platform.file}</span>
                      </p>
                    )}
                    {available ? (
                      <a
                        href={RELEASES_URL}
                        aria-label={`Get PasteHive for ${platform.name} from the releases page`}
                        className="group flex h-11 items-center justify-between gap-2 rounded-full border border-white/20 bg-white/[0.06] pl-4 pr-3 text-[0.9rem] font-medium transition duration-200 ease-out-soft hover:border-white hover:bg-white hover:text-black active:scale-[0.98]"
                      >
                        Latest release
                        <ArrowUpRight
                          size={16}
                          className="transition-transform duration-200 group-hover:-translate-y-0.5 group-hover:translate-x-0.5"
                        />
                      </a>
                    ) : (
                      <p className="flex h-11 items-center justify-center rounded-full border border-dashed border-white/25 text-[0.9rem] text-white/60">
                        Not available yet
                      </p>
                    )}
                  </div>
                </div>
              </Card>
            </Reveal>
          );
        })}
      </div>

      <Reveal className="mt-4">
        <BuildFromSource />
      </Reveal>
    </Section>
  );
}
