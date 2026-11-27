"use client";

import { useState, type ReactNode } from "react";
import { AnimatePresence, motion } from "motion/react";
import {
  ArrowDownToLine,
  ArrowUpRight,
  ChevronDown,
  FileCheck2,
  History,
  TriangleAlert,
} from "lucide-react";
import {
  describe,
  latestOf,
  useProject,
  useVisitorPlatform,
  type PlatformId,
  type Release,
  type ReleaseFile,
  type Variant,
} from "@/lib/releases";
import { DOWNLOADS, REPO_URL } from "@/lib/site";
import { AndroidIcon, AppleIcon, WindowsIcon } from "./icons";
import { Card } from "./ui";

const PLATFORMS: { id: PlatformId; name: string; icon: ReactNode }[] = [
  { id: "windows", name: "Windows", icon: <WindowsIcon className="h-4 w-4" /> },
  { id: "macos", name: "macOS", icon: <AppleIcon className="h-4 w-4" /> },
  { id: "android", name: "Android", icon: <AndroidIcon className="h-[18px] w-[18px]" /> },
];

const megabytes = (bytes: number) =>
  `${(bytes / 1024 / 1024).toFixed(bytes < 10 * 1024 * 1024 ? 1 : 0)} MB`;
const day = new Intl.DateTimeFormat("en", { dateStyle: "long" });
const number = (tag: string) => tag.replace(/^v/, "");

interface Row {
  key: string;
  variant: Variant;
  name: string;
  url: string;
  size: string | null;
}

/** One file: what it is for, its name and size, and the button to get it. */
function FileRow({ row, version }: { row: Row; version: string | null }) {
  return (
    <motion.li
      layout="position"
      initial={{ opacity: 0, y: 8 }}
      animate={{ opacity: 1, y: 0 }}
      exit={{ opacity: 0, transition: { duration: 0.1 } }}
      transition={{ type: "spring", stiffness: 420, damping: 36 }}
      className="group/file flex flex-col gap-3 rounded-2xl border border-white/10 p-4 transition-colors duration-200 hover:border-white/30 hover:bg-white/[0.04] sm:flex-row sm:items-center sm:gap-5"
    >
      <div className="min-w-0 flex-1">
        <p className="flex flex-wrap items-center gap-2 font-medium">
          {row.variant.title}
          {row.variant.usual && (
            <span className="rounded-full border border-white/40 px-2 py-0.5 font-mono text-[0.62rem] uppercase tracking-[0.12em] text-white/85">
              Usual choice
            </span>
          )}
        </p>
        <p className="mt-1 text-[0.88rem] leading-relaxed text-dim">
          {row.variant.detail}
        </p>
        <p className="mt-1.5 truncate font-mono text-[0.74rem] text-faint">
          {row.name}
          {row.size && <span> · {row.size}</span>}
        </p>
      </div>
      <a
        href={row.url}
        download
        aria-label={`Download ${row.name}${version ? `, version ${version}` : ""}`}
        className={`group inline-flex h-11 shrink-0 items-center justify-center gap-2 rounded-full px-5 text-[0.9rem] transition duration-200 ease-out-soft hover:-translate-y-0.5 active:translate-y-0 active:scale-[0.98] ${
          row.variant.usual
            ? "bg-white font-semibold text-black hover:shadow-[0_10px_30px_-8px_rgb(255_255_255/0.5)]"
            : "border border-white/20 bg-white/[0.06] font-medium hover:border-white hover:bg-white hover:text-black"
        }`}
      >
        <ArrowDownToLine
          size={16}
          strokeWidth={2.4}
          className="transition-transform duration-200 group-hover:translate-y-0.5"
        />
        Download
      </a>
    </motion.li>
  );
}

function rowsOf(release: Release, platform: PlatformId): Row[] {
  return release.files
    .map((file: ReleaseFile) => ({ file, variant: describe(file, release) }))
    .filter(
      (entry): entry is { file: ReleaseFile; variant: Variant } =>
        entry.variant?.platform === platform,
    )
    .sort((a, b) => Number(b.variant.usual) - Number(a.variant.usual))
    .map(({ file, variant }) => ({
      key: `${release.tag}/${file.name}`,
      variant,
      name: file.name,
      url: file.url,
      size: megabytes(file.bytes),
    }));
}

/** When GitHub cannot be asked: the fixed links to the latest files. */
function fallbackRows(platform: PlatformId): Row[] {
  const main = DOWNLOADS[platform];
  const latest = main.url.slice(0, main.url.lastIndexOf("/"));
  const stub: Release = {
    tag: "",
    page: "",
    published: "",
    prerelease: false,
    oneOffAndroidKey: false,
    files: [
      "PasteHive-windows-x64.zip",
      "PasteHive-macos.zip",
      "PasteHive-android.apk",
      "PasteHive-android-arm32.apk",
      "PasteHive-android-x86_64.apk",
    ].map((name) => ({ name, url: `${latest}/${name}`, bytes: 0, downloads: 0 })),
  };
  return rowsOf(stub, platform).map((row) => ({ ...row, size: null }));
}

/**
 * Pick a version, pick a platform, get the file. Every published release is
 * listed, with every file it has; the latest is chosen to begin with.
 */
export function VersionChooser() {
  const project = useProject();
  const visitor = useVisitorPlatform();
  const [chosenTag, setChosenTag] = useState<string | null>(null);
  const [chosenPlatform, setChosenPlatform] = useState<PlatformId | null>(null);

  const loaded = project && project !== "unavailable" ? project : null;
  const latest = loaded ? latestOf(loaded) : null;
  const release =
    loaded?.releases.find((item) => item.tag === chosenTag) ?? latest;
  const platform = chosenPlatform ?? visitor ?? "windows";
  const rows = release
    ? rowsOf(release, platform)
    : project === "unavailable"
      ? fallbackRows(platform)
      : [];
  const checksums = release?.files.find((file) => /sha256/i.test(file.name));
  const old = Boolean(release && latest && release.tag !== latest.tag);

  return (
    <Card className="p-6 sm:p-7">
      <div className="mb-6 flex flex-col gap-5 lg:flex-row lg:items-end lg:justify-between">
        <div>
          <p className="mb-2 flex items-center gap-2 font-mono text-[0.7rem] uppercase tracking-[0.2em] text-faint">
            <History size={13} /> Versions and files
          </p>
          <h3
            id="versions"
            className="text-[1.45rem] font-semibold leading-tight tracking-[-0.02em]"
          >
            Choose a version and a file.
          </h3>
        </div>

        <div className="flex flex-col gap-3 sm:flex-row sm:items-center">
          <label className="relative block">
            <span className="sr-only">Version</span>
            <select
              value={release?.tag ?? ""}
              disabled={!loaded}
              onChange={(event) => setChosenTag(event.target.value)}
              className="h-11 w-full cursor-pointer appearance-none rounded-full border border-white/20 bg-white/[0.06] pl-4 pr-10 font-mono text-[0.88rem] text-white transition-colors duration-200 hover:border-white/50 hover:bg-white/[0.1] disabled:cursor-default disabled:opacity-60 sm:w-auto [&>option]:bg-ink-raised [&>option]:text-white"
            >
              {loaded ? (
                loaded.releases.map((item) => (
                  <option key={item.tag} value={item.tag}>
                    {number(item.tag)}
                    {item.tag === latest?.tag ? " (latest)" : ""}
                    {item.prerelease ? " (pre-release)" : ""}
                  </option>
                ))
              ) : (
                <option value="">
                  {project === "unavailable" ? "Latest" : "Loading…"}
                </option>
              )}
            </select>
            <ChevronDown
              size={16}
              aria-hidden="true"
              className="pointer-events-none absolute right-3.5 top-1/2 -translate-y-1/2 text-white/60"
            />
          </label>

          <div
            role="group"
            aria-label="Platform"
            className="flex rounded-full border border-white/15 bg-black/40 p-1"
          >
            {PLATFORMS.map((item) => {
              const selected = item.id === platform;
              return (
                <button
                  key={item.id}
                  type="button"
                  aria-pressed={selected}
                  onClick={() => setChosenPlatform(item.id)}
                  className={`relative flex h-9 flex-1 items-center justify-center gap-2 rounded-full px-3.5 text-[0.86rem] transition-colors duration-200 sm:flex-none ${
                    selected
                      ? "font-semibold text-black"
                      : "text-white/65 hover:text-white"
                  }`}
                >
                  {selected && (
                    <motion.span
                      layoutId="version-platform"
                      className="absolute inset-0 rounded-full bg-white"
                      transition={{ type: "spring", stiffness: 420, damping: 34 }}
                    />
                  )}
                  <span className="relative flex items-center gap-2">
                    {item.icon}
                    {item.name}
                  </span>
                </button>
              );
            })}
          </div>
        </div>
      </div>

      {project === "unavailable" && (
        <p className="mb-4 flex items-start gap-2.5 rounded-2xl border border-white/15 bg-white/[0.04] p-3.5 text-[0.86rem] leading-relaxed text-dim">
          <TriangleAlert size={16} className="mt-0.5 shrink-0 text-white" />
          <span>
            The list of versions could not be read from GitHub just now, so
            these are the latest files. Older versions are on the{" "}
            <a
              href={`${REPO_URL}/releases`}
              className="text-white underline decoration-white/40 underline-offset-4 hover:decoration-white"
            >
              releases page
            </a>
            .
          </span>
        </p>
      )}

      {release && (
        <p className="mb-4 flex flex-wrap items-center gap-x-4 gap-y-1.5 text-[0.84rem] text-dim">
          <span>
            Version{" "}
            <span className="font-mono text-white">{number(release.tag)}</span>,
            released {day.format(new Date(release.published))}
          </span>
          <a
            href={release.page}
            className="group inline-flex items-center gap-1 text-white/85 underline decoration-white/30 underline-offset-4 transition-colors hover:text-white hover:decoration-white"
          >
            What changed
            <ArrowUpRight
              size={13}
              className="transition-transform duration-200 group-hover:-translate-y-0.5 group-hover:translate-x-0.5"
            />
          </a>
          {checksums && (
            <a
              href={checksums.url}
              download
              className="inline-flex items-center gap-1.5 text-white/85 underline decoration-white/30 underline-offset-4 transition-colors hover:text-white hover:decoration-white"
            >
              <FileCheck2 size={13} />
              Checksums
            </a>
          )}
        </p>
      )}

      {old && release && (
        <p className="mb-4 flex items-start gap-2.5 rounded-2xl border border-white/15 bg-white/[0.04] p-3.5 text-[0.86rem] leading-relaxed text-dim">
          <TriangleAlert size={16} className="mt-0.5 shrink-0 text-white" />
          <span>
            This is an older version; the latest is{" "}
            <button
              type="button"
              onClick={() => setChosenTag(latest!.tag)}
              className="font-mono text-white underline decoration-white/40 underline-offset-4 hover:decoration-white"
            >
              {number(latest!.tag)}
            </button>
            .
            {release.oneOffAndroidKey && platform === "android" && (
              <>
                {" "}
                Its Android file was signed with a one-off key: a newer
                version will not install over it, so it has to be uninstalled
                first.
              </>
            )}
          </span>
        </p>
      )}

      <ul className="flex min-h-[5.75rem] flex-col gap-2.5">
        <AnimatePresence initial={false} mode="popLayout">
          {rows.map((row) => (
            <FileRow
              key={row.key}
              row={row}
              version={release ? number(release.tag) : null}
            />
          ))}
        </AnimatePresence>
        {project === null && (
          <li
            aria-hidden="true"
            className="h-[5.75rem] animate-pulse rounded-2xl border border-white/10 bg-white/[0.03]"
          />
        )}
        {release && rows.length === 0 && (
          <li className="rounded-2xl border border-dashed border-white/20 p-5 text-[0.9rem] text-dim">
            Version {number(release.tag)} has no file for this platform.
          </li>
        )}
      </ul>
    </Card>
  );
}
