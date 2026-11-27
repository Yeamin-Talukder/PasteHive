"use client";

import { useEffect, useState, useSyncExternalStore, type ReactNode } from "react";
import { ArrowDownToLine, Star } from "lucide-react";
import { DOWNLOADS, REPO_API_URL, REPO_URL } from "@/lib/site";
import { AndroidIcon, AppleIcon, WindowsIcon } from "./icons";

type Platform = keyof typeof DOWNLOADS;

const ICONS: Record<Platform, ReactNode> = {
  windows: <WindowsIcon className="h-4 w-4" />,
  macos: <AppleIcon className="h-4 w-4" />,
  android: <AndroidIcon className="h-[18px] w-[18px]" />,
};

const ORDER: Platform[] = ["windows", "macos", "android"];

/** Which of the three the visitor is on, or null when it is none of them. */
function detectPlatform(): Platform | null {
  const agent = navigator.userAgent;
  if (/Android/i.test(agent)) return "android";
  if (/iPhone|iPad|iPod/i.test(agent)) return null;
  if (/Windows/i.test(agent)) return "windows";
  if (/Macintosh|Mac OS X/i.test(agent)) return "macos";
  return null;
}

const never = () => () => {};

interface Counts {
  stars: number;
  downloads: number;
  version: string | null;
}

const CACHE_KEY = "pastehive-counts";
const CACHE_MS = 10 * 60 * 1000;

/**
 * Stars and downloads, read from GitHub's public API in the visitor's
 * browser, so the numbers are the real ones at the time of the visit. Kept
 * for ten minutes so that moving around the site does not ask again. If
 * GitHub cannot be reached, the numbers are left out rather than guessed.
 */
function useCounts() {
  const [counts, setCounts] = useState<Counts | null>(null);

  useEffect(() => {
    let cancelled = false;

    const load = async (): Promise<Counts> => {
      try {
        const cached = JSON.parse(sessionStorage.getItem(CACHE_KEY) ?? "null");
        if (cached && Date.now() - cached.at < CACHE_MS) return cached.counts;
      } catch {
        // No storage, or nothing usable in it: ask GitHub.
      }

      const [repo, releases] = await Promise.all(
        [REPO_API_URL, `${REPO_API_URL}/releases?per_page=100`].map(
          async (url) => {
            const response = await fetch(url, {
              headers: { Accept: "application/vnd.github+json" },
            });
            if (!response.ok) throw new Error(`GitHub answered ${response.status}`);
            return response.json();
          },
        ),
      );

      const published = (
        releases as {
          draft: boolean;
          prerelease: boolean;
          tag_name: string;
          assets: { name: string; download_count: number }[];
        }[]
      ).filter((release) => !release.draft);

      const result: Counts = {
        stars: repo.stargazers_count,
        // Every download of an app file, over all releases. The checksum
        // list is not an install, so it is not counted.
        downloads: published
          .flatMap((release) => release.assets)
          .filter((asset) => asset.name.startsWith("PasteHive-"))
          .reduce((sum, asset) => sum + asset.download_count, 0),
        version:
          published.find((release) => !release.prerelease)?.tag_name ?? null,
      };

      try {
        sessionStorage.setItem(
          CACHE_KEY,
          JSON.stringify({ at: Date.now(), counts: result }),
        );
      } catch {
        // Fine: the next page view asks again.
      }
      return result;
    };

    load()
      .then((result) => {
        if (!cancelled) setCounts(result);
      })
      .catch(() => {
        // Offline, or GitHub's hourly limit: show the links without numbers.
      });

    return () => {
      cancelled = true;
    };
  }, []);

  return counts;
}

const format = new Intl.NumberFormat("en", {
  notation: "compact",
  maximumFractionDigits: 1,
});

export function HeroDownloads() {
  // Unknown on the server and on the first paint, so the markup agrees.
  const platform = useSyncExternalStore(never, detectPlatform, () => null);
  const counts = useCounts();

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
            <a
              href={`${REPO_URL}/releases`}
              className="inline-flex items-center gap-1.5 transition-colors hover:text-white"
            >
              <ArrowDownToLine size={13} className="text-white/80" />
              <span className="font-semibold tabular-nums text-white">
                {format.format(counts.downloads)}
              </span>{" "}
              {counts.downloads === 1 ? "download" : "downloads"}
            </a>
            {counts.version && (
              <>
                <span aria-hidden="true" className="text-white/25">
                  /
                </span>
                <span className="font-mono">{counts.version}</span>
              </>
            )}
          </>
        )}
      </p>
    </>
  );
}
