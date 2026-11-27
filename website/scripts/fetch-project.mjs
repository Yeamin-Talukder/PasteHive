// Saves what GitHub knows about the project (stars, releases, their files)
// into public/project.json, so the site carries a copy of it.
//
// It runs before every build ("prebuild" in package.json). The pages read
// that copy first, which means the list of versions is there for every
// visitor, including one GitHub refuses to answer: it allows a visitor only
// 60 unsigned requests an hour. The browser still asks GitHub afterwards,
// for numbers newer than the build.
//
// In the Website workflow the request is signed with the workflow's own
// token (GH_TOKEN), which has no such limit. On your own machine it runs
// unsigned; if that fails, the last saved copy is kept and the build goes on.

import { existsSync, mkdirSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const API = "https://api.github.com/repos/Yeamin-Talukder/PasteHive";
const target = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "..",
  "public",
  "project.json",
);
const token = process.env.GH_TOKEN || process.env.GITHUB_TOKEN;

async function ask(url) {
  const response = await fetch(url, {
    headers: {
      Accept: "application/vnd.github+json",
      "User-Agent": "pastehive-website-build",
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
  });
  if (!response.ok) throw new Error(`GitHub answered ${response.status} for ${url}`);
  return response.json();
}

try {
  const [repo, releases] = await Promise.all([
    ask(API),
    ask(`${API}/releases?per_page=100`),
  ]);

  // Only the fields the site reads, in the shape GitHub gives them, so the
  // page treats this copy and a fresh answer the same way.
  const project = {
    savedAt: new Date().toISOString(),
    repo: { stargazers_count: repo.stargazers_count },
    releases: releases
      .filter((release) => !release.draft)
      .map((release) => ({
        tag_name: release.tag_name,
        html_url: release.html_url,
        published_at: release.published_at,
        draft: false,
        prerelease: release.prerelease,
        body: release.body,
        assets: release.assets.map((asset) => ({
          name: asset.name,
          size: asset.size,
          download_count: asset.download_count,
          browser_download_url: asset.browser_download_url,
        })),
      })),
  };

  mkdirSync(path.dirname(target), { recursive: true });
  writeFileSync(target, JSON.stringify(project));
  console.log(`Saved ${project.releases.length} releases to public/project.json.`);
} catch (error) {
  console.warn(
    `Could not read the project from GitHub (${error.message}). ` +
      (existsSync(target)
        ? "Keeping the copy saved earlier."
        : "The site will ask GitHub from the browser only."),
  );
}
