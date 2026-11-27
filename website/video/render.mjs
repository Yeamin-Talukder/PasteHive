// Renders video.html to the files the website and the README use.
//
//   npm install --no-save puppeteer-core     (once; it is not a site dependency)
//   node video/render.mjs                    (from website/)
//
// Needs Chrome and ffmpeg. Chrome is looked for in the usual places, or set
// CHROME_PATH. Writes:
//   public/video/pastehive.mp4    H.264, plays everywhere
//   public/video/pastehive.webm   VP9, smaller where it is supported
//   public/video/poster.jpg       the frame shown before it plays
//   public/video/captions.vtt     the narration as captions
//   ../docs/video.gif             a small silent copy for the GitHub README
// The pictures are made here; sound.mjs then adds the music, the sound
// effects and the narration to both video files.
//
// Stills only, to check a change without rendering everything:
//   node video/render.mjs --stills 3.9,10.5,21.6

import { spawn } from "node:child_process";
import { existsSync, mkdirSync } from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import puppeteer from "puppeteer-core";

const here = path.dirname(fileURLToPath(import.meta.url));
const site = path.resolve(here, "..");
const outDir = path.join(site, "public", "video");
const gifPath = path.resolve(site, "..", "docs", "video.gif");
const FPS = 30;
const POSTER_AT = 15.8;

const chrome = [
  process.env.CHROME_PATH,
  "C:/Program Files/Google/Chrome/Application/chrome.exe",
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  "/usr/bin/google-chrome",
  "/usr/bin/chromium",
].find((candidate) => candidate && existsSync(candidate));
if (!chrome) throw new Error("Chrome not found. Set CHROME_PATH.");

const stillsArg = process.argv.indexOf("--stills");
const stills =
  stillsArg > 0 ? process.argv[stillsArg + 1].split(",").map(Number) : null;

function ffmpeg(args, { stdin = false } = {}) {
  const child = spawn(
    "ffmpeg",
    ["-hide_banner", "-loglevel", "error", "-y", ...args],
    { stdio: [stdin ? "pipe" : "ignore", "inherit", "inherit"] },
  );
  const done = new Promise((resolve, reject) => {
    child.on("error", reject);
    child.on("exit", (code) =>
      code === 0 ? resolve() : reject(new Error(`ffmpeg exited with ${code}`)),
    );
  });
  return { child, done };
}

mkdirSync(outDir, { recursive: true });
const browser = await puppeteer.launch({
  executablePath: chrome,
  headless: true,
  args: ["--hide-scrollbars", "--force-color-profile=srgb"],
});
const page = await browser.newPage();
await page.setViewport({ width: 1920, height: 1080, deviceScaleFactor: 1 });
page.on("pageerror", (error) => {
  console.error(String(error));
  process.exitCode = 1;
});
await page.goto(pathToFileURL(path.join(here, "video.html")).href);
await page.evaluate(() => window.ready);
const duration = await page.evaluate(() => window.DURATION);
const frameAt = async (seconds, options) => {
  await page.evaluate((t) => window.seek(t), seconds);
  return page.screenshot(options);
};

if (stills) {
  const dir = path.join(here, "stills");
  mkdirSync(dir, { recursive: true });
  for (const t of stills) {
    await frameAt(t, {
      path: path.join(dir, `${t.toFixed(2).padStart(5, "0")}.png`),
      optimizeForSpeed: true,
    });
  }
  console.log(`Wrote ${stills.length} stills to ${dir}`);
  await browser.close();
  process.exit();
}

await frameAt(POSTER_AT, {
  path: path.join(outDir, "poster.jpg"),
  type: "jpeg",
  quality: 86,
});

// Every frame goes straight into ffmpeg, which writes both video files.
const total = Math.round(duration * FPS);
const encoder = ffmpeg(
  [
    "-f", "image2pipe", "-framerate", String(FPS), "-c:v", "png", "-i", "-",
    "-an", "-c:v", "libx264", "-preset", "slow", "-crf", "20",
    "-pix_fmt", "yuv420p", "-colorspace", "bt709", "-color_primaries", "bt709",
    "-color_trc", "bt709", "-movflags", "+faststart",
    path.join(outDir, "pastehive.mp4"),
    "-an", "-c:v", "libvpx-vp9", "-crf", "34", "-b:v", "0", "-row-mt", "1",
    "-pix_fmt", "yuv420p",
    path.join(outDir, "pastehive.webm"),
  ],
  { stdin: true },
);

const began = Date.now();
for (let frame = 0; frame < total; frame++) {
  const png = await frameAt(frame / FPS, { optimizeForSpeed: true });
  if (!encoder.child.stdin.write(png)) {
    await new Promise((resolve) => encoder.child.stdin.once("drain", resolve));
  }
  if (frame % 150 === 0) {
    const seconds = Math.round((Date.now() - began) / 1000);
    console.log(`frame ${frame} of ${total} (${seconds} s)`);
  }
}
encoder.child.stdin.end();
await encoder.done;
await browser.close();

// The README copy: GitHub does not play a video file kept in a repository,
// so it gets a GIF, smaller and slower, with its own palette.
mkdirSync(path.dirname(gifPath), { recursive: true });
await ffmpeg([
  "-i", path.join(outDir, "pastehive.mp4"),
  "-vf",
  "fps=10,scale=720:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=96:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle",
  "-loop", "0", gifPath,
]).done;
// Last, the sound: music, effects and narration (see sound.mjs).
const sound = spawn(process.execPath, [path.join(here, "sound.mjs")], { stdio: "inherit" });
await new Promise((resolve, reject) => sound.on("exit", (code) => (code === 0 ? resolve() : reject(new Error("sound.mjs failed")))));
console.log("Done.");
