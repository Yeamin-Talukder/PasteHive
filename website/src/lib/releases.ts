"use client";

import { useEffect, useState, useSyncExternalStore } from "react";
import { REPO_API_URL } from "./site";

/**
 * What GitHub knows about the project: its stars and every published
 * release with its files. Read from GitHub's public API in the visitor's
 * browser, so the numbers and the list are the real ones at that moment.
 *
 * One request per page for everything that needs it (the hero's counts, the
 * version chooser), kept for ten minutes. GitHub allows a visitor 60
 * requests an hour; when it refuses, or the visitor is offline, callers get
 * "unavailable" and fall back to the fixed links to the latest files.
 */

export type PlatformId = "windows" | "macos" | "android";

export interface ReleaseFile {
  name: string;
  url: string;
  bytes: number;
  downloads: number;
}

export interface Release {
  /** As tagged, for example "v1.0.3". */
  tag: string;
  page: string;
  published: string;
  prerelease: boolean;
  /** The release's own notes say its Android file used a one-off key. */
  oneOffAndroidKey: boolean;
  files: ReleaseFile[];
}

export interface Project {
  stars: number;
  releases: Release[];
}

interface ApiRelease {
  tag_name: string;
  html_url: string;
  published_at: string;
  draft: boolean;
  prerelease: boolean;
  body: string | null;
  assets: {
    name: string;
    size: number;
    download_count: number;
    browser_download_url: string;
  }[];
}

const CACHE_KEY = "pastehive-project-v2";
const CACHE_MS = 10 * 60 * 1000;

async function ask(url: string) {
  const response = await fetch(url, {
    headers: { Accept: "application/vnd.github+json" },
  });
  if (!response.ok) throw new Error(`GitHub answered ${response.status}`);
  return response.json();
}

async function load(): Promise<Project> {
  try {
    const cached = JSON.parse(sessionStorage.getItem(CACHE_KEY) ?? "null");
    if (cached && Date.now() - cached.at < CACHE_MS) return cached.project;
  } catch {
    // No storage, or nothing usable in it: ask GitHub.
  }

  const [repo, list] = await Promise.all([
    ask(REPO_API_URL),
    ask(`${REPO_API_URL}/releases?per_page=100`),
  ]);

  const project: Project = {
    stars: repo.stargazers_count,
    releases: (list as ApiRelease[])
      .filter((release) => !release.draft)
      .map((release) => ({
        tag: release.tag_name,
        page: release.html_url,
        published: release.published_at,
        prerelease: release.prerelease,
        oneOffAndroidKey: /one-off key/i.test(release.body ?? ""),
        files: release.assets.map((asset) => ({
          name: asset.name,
          url: asset.browser_download_url,
          bytes: asset.size,
          downloads: asset.download_count,
        })),
      })),
  };

  try {
    sessionStorage.setItem(
      CACHE_KEY,
      JSON.stringify({ at: Date.now(), project }),
    );
  } catch {
    // Fine: the next page view asks again.
  }
  return project;
}

// Shared by every component on the page, so GitHub is asked once.
let pending: Promise<Project> | null = null;

/** The project, null while it loads, or "unavailable" if GitHub said no. */
export function useProject(): Project | null | "unavailable" {
  const [project, setProject] = useState<Project | null | "unavailable">(null);

  useEffect(() => {
    let cancelled = false;
    pending ??= load();
    pending.then(
      (result) => {
        if (!cancelled) setProject(result);
      },
      () => {
        pending = null;
        if (!cancelled) setProject("unavailable");
      },
    );
    return () => {
      cancelled = true;
    };
  }, []);

  return project;
}

/** The app's files in a release. The checksum list is not one of them. */
export const appFiles = (release: Release) =>
  release.files.filter((file) => file.name.startsWith("PasteHive-"));

/** Every download of an app file, over all releases. */
export const totalDownloads = (project: Project) =>
  project.releases
    .flatMap(appFiles)
    .reduce((sum, file) => sum + file.downloads, 0);

/** The newest release that is not a pre-release. */
export const latestOf = (project: Project) =>
  project.releases.find((release) => !release.prerelease) ??
  project.releases[0];

export interface Variant {
  platform: PlatformId;
  /** What kind of machine it is for. */
  title: string;
  /** Who should pick it, in a sentence. */
  detail: string;
  /** The one to pick when unsure. */
  usual: boolean;
}

/**
 * What a release file is, worked out from its name. Android releases up to
 * 1.0.2 have one file for every processor; later ones have one per kind.
 */
export function describe(file: ReleaseFile, release: Release): Variant | null {
  const name = file.name.toLowerCase();
  if (name === "pastehive-windows-x64.zip") {
    return {
      platform: "windows",
      title: "64-bit (x64)",
      detail: "A zip. Unzip it and run pastehive.exe.",
      usual: true,
    };
  }
  if (name === "pastehive-macos.zip") {
    return {
      platform: "macos",
      title: "App bundle",
      detail: "A zip. Unzip it and move the app to Applications.",
      usual: true,
    };
  }
  if (!name.startsWith("pastehive-android") || !name.endsWith(".apk")) {
    return null;
  }

  const split = release.files.some((other) =>
    /^pastehive-android-.+\.apk$/i.test(other.name),
  );
  if (name === "pastehive-android.apk") {
    return split
      ? {
          platform: "android",
          title: "64-bit ARM",
          detail: "Nearly every Android phone. Pick this if you are unsure.",
          usual: true,
        }
      : {
          platform: "android",
          title: "All processors",
          detail: "One file for every Android device.",
          usual: true,
        };
  }
  if (name.includes("arm32")) {
    return {
      platform: "android",
      title: "32-bit ARM",
      detail: "Older phones with a 32-bit processor.",
      usual: false,
    };
  }
  if (name.includes("x86_64")) {
    return {
      platform: "android",
      title: "x86_64",
      detail: "Emulators and devices with an Intel or AMD processor.",
      usual: false,
    };
  }
  return {
    platform: "android",
    title: file.name.replace(/^pastehive-android-?|\.apk$/gi, "") || "APK",
    detail: "Another Android build.",
    usual: false,
  };
}

/** Which of the three the visitor is on, or null when it is none of them. */
function detectPlatform(): PlatformId | null {
  const agent = navigator.userAgent;
  if (/Android/i.test(agent)) return "android";
  if (/iPhone|iPad|iPod/i.test(agent)) return null;
  if (/Windows/i.test(agent)) return "windows";
  if (/Macintosh|Mac OS X/i.test(agent)) return "macos";
  return null;
}

const never = () => () => {};

/** Unknown on the server and on the first paint, so the markup agrees. */
export const useVisitorPlatform = () =>
  useSyncExternalStore(never, detectPlatform, () => null);
