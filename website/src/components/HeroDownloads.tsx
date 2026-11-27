"use client";

import type { ReactNode } from "react";
import { ArrowDownToLine, Star } from "lucide-react";
import {
  latestOf,
  totalDownloads,
  useProject,
  useVisitorPlatform,
  type PlatformId,
} from "@/lib/releases";
import { DOWNLOADS, REPO_URL } from "@/lib/site";
import { AndroidIcon, AppleIcon, WindowsIcon } from "./icons";

const ICONS: Record<PlatformId, ReactNode> = {
  windows: <WindowsIcon className="h-4 w-4" />,
  macos: <AppleIcon className="h-4 w-4" />,
  android: <AndroidIcon className="h-[18px] w-[18px]" />,
};

const ORDER: PlatformId[] = ["windows", "macos", "android"];

const format = new Intl.NumberFormat("en", {
  notation: "compact",
  maximumFractionDigits: 1,
});

/**
 * The hero's downloads: the latest version for each platform, one click
 * each, with the stars, the downloads and the version under them. Older
 * versions and the other Android files are in the Download section.
 */
export function HeroDownloads() {
  const platform = useVisitorPlatform();
  const project = useProject();
  const counts =
    project && project !== "unavailable"
      ? {
          stars: project.stars,
          downloads: totalDownloads(project),
          version: latestOf(project)?.tag ?? null,
        }
      : null;

  return (
    <>
      <div className="mt-[clamp(0.8rem,2.2svh,1.6rem)] flex flex-wrap items-center justify-center gap-1.5 sm:gap-2">
        {ORDER.map((id) => {
          const item = DOWNLOADS[id];
          const mine = id === platform;
          return (
            <a
              key={id}
              href={item.url}
              download
              aria-label={`Download PasteHive for ${item.name} (${item.kind})`}
              className={`group relative inline-flex h-11 items-center gap-1.5 overflow-hidden rounded-full px-3 text-[0.85rem] whitespace-nowrap transition duration-200 ease-out-soft hover:-translate-y-0.5 active:translate-y-0 active:scale-[0.98] sm:gap-2 sm:px-5 sm:text-[0.92rem] ${
                mine
                  ? "bg-white font-semibold text-black hover:shadow-[0_10px_30px_-8px_rgb(255_255_255/0.5)]"
                  : "border border-white/20 bg-white/[0.06] font-medium text-white hover:border-white hover:bg-white hover:text-black"
              }`}
            >
              {ICONS[id]}
              {item.name}
              <ArrowDownToLine
                size={15}
                strokeWidth={2.4}
                className="hidden opacity-60 transition duration-200 group-hover:translate-y-0.5 group-hover:opacity-100 sm:block"
              />
            </a>
          );
        })}
      </div>

      <p className="mt-2.5 flex flex-wrap items-center justify-center gap-x-3 gap-y-1 text-[0.78rem] text-faint">
        <a
          href={`${REPO_URL}/stargazers`}
          className="group inline-flex items-center gap-1.5 transition-colors hover:text-white"
        >
          <Star
            size={13}
            className="text-white/80 transition duration-300 group-hover:rotate-[72deg] group-hover:fill-white"
          />
          {counts ? (
            <>
              <span className="font-semibold tabular-nums text-white">
                {format.format(counts.stars)}
              </span>{" "}
              {counts.stars === 1 ? "star" : "stars"}
            </>
          ) : (
            "Star on GitHub"
          )}
        </a>
        {counts && (
          <>
            <span aria-hidden="true" className="text-white/25">
              /
            </span>
            <span className="inline-flex items-center gap-1.5">
              <ArrowDownToLine size={13} className="text-white/80" />
              <span className="font-semibold tabular-nums text-white">
                {format.format(counts.downloads)}
              </span>{" "}
              {counts.downloads === 1 ? "download" : "downloads"}
            </span>
          </>
        )}
        <span aria-hidden="true" className="text-white/25">
          /
        </span>
        <a
          href="#versions"
          className="inline-flex items-center gap-1.5 underline decoration-white/25 underline-offset-4 transition-colors hover:text-white hover:decoration-white"
        >
          {counts?.version && (
            <span className="font-mono no-underline">{counts.version}</span>
          )}
          Other versions and files
        </a>
      </p>
    </>
  );
}
