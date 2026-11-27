// The video's sound: music, sound effects and narration, mixed and put into
// the two video files, with captions beside them.
//
//   node video/sound.mjs            (from website/; render.mjs runs it too)
//   node video/sound.mjs --keep     (also keeps the mix and its parts in audio/)
//
// Needs ffmpeg. Nothing here is a recording or a sample from anywhere else:
//   - the music and every sound effect are computed below, from sine waves
//     and filtered noise, timed to the scenes in video.html;
//   - the narration in audio/voice/ was spoken by Kokoro, an open-source
//     voice model (see speak.mjs), from the lines in audio/narration.json.
//
// If the timing of a scene changes in video.html, change the matching
// numbers here and in audio/narration.json.

import { spawnSync } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const videoDir = path.resolve(here, "..", "public", "video");
const voiceDir = path.join(here, "audio", "voice");
const narration = JSON.parse(readFileSync(path.join(here, "audio", "narration.json"), "utf8"));

const RATE = 48000;
const LENGTH = 48;
const TARGET_LUFS = -16;
// How loud the music and the effects sit under the voice.
const MUSIC_LEVEL = 0.55;
const FX_LEVEL = 1.4;
const SAMPLES = RATE * LENGTH;
const TAU = Math.PI * 2;

/* ------------------------------------------------------------- the bench */

function track() {
  return [new Float32Array(SAMPLES), new Float32Array(SAMPLES)];
}

// The same "random" numbers every run, so every render sounds the same.
let seed = 20261127;
const random = () => {
  seed = (seed * 1664525 + 1013904223) >>> 0;
  return seed / 4294967296 * 2 - 1;
};

const hz = (midi) => 440 * 2 ** ((midi - 69) / 12);
const pans = (pan) => [Math.cos((pan + 1) * Math.PI / 4), Math.sin((pan + 1) * Math.PI / 4)];

/** Adds a sound made by wave(secondsSinceStart) to a track. */
function add(out, at, length, pan, wave) {
  const [left, right] = pans(pan);
  const start = Math.round(at * RATE);
  const count = Math.round(length * RATE);
  for (let n = 0; n < count; n++) {
    const index = start + n;
    if (index < 0 || index >= SAMPLES) continue;
    const value = wave(n / RATE);
    out[0][index] += value * left;
    out[1][index] += value * right;
  }
}

/** Noise through a band-pass filter whose centre moves from one pitch to another. */
function sweep(out, at, length, from, to, level, panFrom = 0, panTo = 0, q = 1.6) {
  let low = 0;
  let band = 0;
  const start = Math.round(at * RATE);
  const count = Math.round(length * RATE);
  for (let n = 0; n < count; n++) {
    const index = start + n;
    if (index < 0 || index >= SAMPLES) continue;
    const progress = n / count;
    const centre = from * (to / from) ** progress;
    const f = 2 * Math.sin(Math.PI * Math.min(centre, RATE / 6.5) / RATE);
    const high = random() - low - band / q;
    band += f * high;
    low += f * band;
    const envelope = Math.sin(Math.PI * progress) ** 2;
    const [left, right] = pans(panFrom + (panTo - panFrom) * progress);
    out[0][index] += band * envelope * level * left;
    out[1][index] += band * envelope * level * right;
  }
}

/* ----------------------------------------------------------------- music */

const music = track();

function pad(at, length, notes, level = 0.045) {
  for (const note of notes) {
    for (const [cents, pan] of [[-5, -0.6], [5, 0.6]]) {
      const f = hz(note) * 2 ** (cents / 1200);
      add(music, at - 0.3, length + 2.0, pan, (t) => {
        const envelope = Math.min(1, t / 1.0) * Math.min(1, Math.max(0, (length + 2.0 - t) / 1.6));
        // A few soft overtones: warm, not buzzy.
        return (Math.sin(TAU * f * t) + 0.34 * Math.sin(TAU * 2 * f * t) + 0.12 * Math.sin(TAU * 3 * f * t)) * envelope * level;
      });
    }
  }
}

function pluck(at, note, level = 0.1, pan = 0) {
  const f = hz(note);
  // The note, then two quieter echoes on the other side.
  for (const [delay, gain, side] of [[0, 1, pan], [0.469, 0.34, -pan], [0.938, 0.14, pan]]) {
    add(music, at + delay, 1.3, side, (t) =>
      (Math.sin(TAU * f * t) + 0.3 * Math.sin(TAU * 2 * f * t) + 0.1 * Math.sin(TAU * 3 * f * t)) *
      Math.min(1, t / 0.004) * Math.exp(-t / 0.2) * level * gain);
  }
}

function bass(at, length, note, level = 0.15) {
  const f = hz(note);
  add(music, at, length, 0, (t) =>
    (Math.sin(TAU * f * t) + 0.22 * Math.sin(TAU * 2 * f * t)) *
    Math.min(1, t / 0.03) * Math.exp(-t / 1.5) * Math.min(1, (length - t) / 0.08) * level);
}

function pulse(at, level = 0.2) {
  add(music, at, 0.4, 0, (t) => {
    // A soft, low thud whose pitch falls: a heartbeat rather than a drum.
    const phase = TAU * (45 * t + 70 * 0.03 * (1 - Math.exp(-t / 0.03)));
    return Math.sin(phase) * Math.exp(-t / 0.11) * level;
  });
}

const BEAT = 0.625; // 96 beats a minute
const BAR = BEAT * 4;

// The problem: sparse, a little uneasy.
pad(0, 5, [57, 60, 64, 71]); bass(0, 5, 45, 0.1);
pad(5, 5, [53, 57, 60, 64]); bass(5, 5, 41, 0.1);
pad(10, 3, [52, 57, 59, 64]); bass(10, 3, 40, 0.11);
[[1.25, 76], [3.75, 71], [6.25, 72], [8.75, 69], [10.6, 71], [11.85, 76]].forEach(([at, note], n) => pluck(at, note, 0.06, n % 2 ? 0.4 : -0.4));

// The answer arrives: everything opens up to C major.
pad(13, 4, [60, 64, 67, 74], 0.055); bass(13, 4, 36, 0.16);
[72, 76, 79, 84].forEach((note, n) => pluck(13.25 + n * 0.11, note, 0.085, n % 2 ? 0.35 : -0.35));

// History, sync, pairing: one steady, hopeful loop.
const LOOP = [
  { notes: [60, 64, 67], root: 48 },
  { notes: [59, 62, 67], root: 47 },
  { notes: [57, 60, 64], root: 45 },
  { notes: [53, 57, 60], root: 41 },
];
const PATTERN = [0, 2, 1, 2, 3, 2, 1, 2];
for (let bar = 0; 17 + bar * BAR < 43; bar++) {
  const at = 17 + bar * BAR;
  const length = Math.min(BAR, 43 - at);
  const chord = LOOP[bar % LOOP.length];
  pad(at, length, chord.notes);
  bass(at, length, chord.root);
  const tones = [...chord.notes.map((note) => note + 12), chord.notes[0] + 24];
  for (let step = 0; step * BEAT / 2 < length - 0.01; step++) {
    pluck(at + step * BEAT / 2, tones[PATTERN[step % 8]], step % 4 === 0 ? 0.085 : 0.058, step % 2 ? 0.45 : -0.45);
  }
  for (let beat = 0; beat * BEAT < length - 0.01; beat += 2) pulse(at + beat * BEAT, bar < 1 ? 0.12 : 0.19);
}

// Home.
pad(43, 5, [60, 64, 67, 74], 0.06); bass(43, 4.5, 36, 0.17);
[72, 76, 79, 84, 88].forEach((note, n) => pluck(43.2 + n * 0.12, note, 0.09, n % 2 ? 0.35 : -0.35));
pluck(45.2, 84, 0.05, 0.3); pluck(46.1, 79, 0.04, -0.3);

/* --------------------------------------------------------- sound effects */

const fx = track();

const tick = (at, pitch, level = 0.12, pan = 0) =>
  add(fx, at, 0.06, pan, (t) => Math.sin(TAU * pitch * t) * Math.exp(-t / 0.012) * level);
const click = (at, level = 0.16, pan = 0) => {
  add(fx, at, 0.03, pan, (t) => (random() * 0.5 + Math.sin(TAU * 2100 * t)) * Math.exp(-t / 0.004) * level);
  add(fx, at, 0.08, pan, (t) => Math.sin(TAU * 320 * t) * Math.exp(-t / 0.02) * level * 0.6);
};
/** Two quick notes: the "copied" sound. */
const blip = (at, low, high, level = 0.13, pan = 0) => {
  add(fx, at, 0.09, pan, (t) => Math.sin(TAU * low * t) * Math.min(1, t / 0.003) * Math.exp(-t / 0.03) * level);
  add(fx, at + 0.07, 0.16, pan, (t) => Math.sin(TAU * high * t) * Math.min(1, t / 0.003) * Math.exp(-t / 0.05) * level);
};
const pop = (at, pitch = 520, level = 0.13, pan = 0) =>
  add(fx, at, 0.12, pan, (t) => Math.sin(TAU * pitch * (t - 2.2 * t * t)) * Math.min(1, t / 0.002) * Math.exp(-t / 0.035) * level);
const thump = (at, level = 0.22, pan = 0) =>
  add(fx, at, 0.35, pan, (t) => Math.sin(TAU * (55 * t + 60 * 0.025 * (1 - Math.exp(-t / 0.025)))) * Math.exp(-t / 0.09) * level);
/** Bell-like notes, one after another: something arrived, or worked. */
const chime = (at, notes, level = 0.1, pan = 0, gap = 0.085) =>
  notes.forEach((note, n) => add(fx, at + n * gap, 1.4, pan, (t) =>
    (Math.sin(TAU * hz(note) * t) + 0.25 * Math.sin(TAU * hz(note) * 2.76 * t) * Math.exp(-t / 0.08)) *
    Math.min(1, t / 0.003) * Math.exp(-t / 0.42) * level));
/** Two low, flat notes: no. */
const buzz = (at, level = 0.085, pan = 0) =>
  [[0, 196], [0.13, 155]].forEach(([delay, f]) => add(fx, at + delay, 0.11, pan, (t) =>
    (Math.sin(TAU * f * t) + 0.5 * Math.sin(TAU * 3 * f * t) + 0.25 * Math.sin(TAU * 5 * f * t)) *
    Math.min(1, t / 0.004) * Math.min(1, (0.11 - t) / 0.02) * level));
const whoosh = (at, length, from, to, level, panFrom = 0, panTo = 0) =>
  sweep(fx, at, length, from, to, level, panFrom, panTo);

// 1. Copied on the computer, needed on the phone.
whoosh(1.0, 0.6, 900, 2600, 0.05, -0.5, -0.2);
blip(1.75, 660, 990, 0.13, -0.4);
tick(3.3, 900, 0.1, 0.5);
click(3.82, 0.13, 0.5);
buzz(4.15, 0.085, 0.5);
[5.2, 5.5, 5.8].forEach((at, n) => pop(at, 430 + n * 50, 0.1, -0.3 + n * 0.3));
[6.3, 6.6, 6.9].forEach((at, n) => whoosh(at, 0.3, 3200, 700, 0.07, -0.4 + n * 0.3, -0.2 + n * 0.3));

// 2. One thing at a time.
pop(8.5, 480, 0.13);
whoosh(9.75, 0.7, 1500, 300, 0.07, 0, 0.3); pop(9.8, 480, 0.13);
whoosh(11.05, 0.7, 1500, 300, 0.07, 0, 0.3); pop(11.1, 480, 0.13);

// 3. PasteHive.
whoosh(12.3, 1.0, 300, 5200, 0.085);
thump(13.27, 0.26);
chime(13.3, [72, 79, 84], 0.07);

// 4. History.
tick(18.7, 1500, 0.08, 0.3);
whoosh(18.8, 0.5, 2400, 500, 0.1, 0.3, 0.3); thump(19.2, 0.14, 0.3);
[20.6, 20.84, 21.08].forEach((at, n) => click(at, 0.1, 0.25 + n * 0.03));
click(22.68, 0.15, 0.3);
whoosh(23.0, 0.25, 700, 2600, 0.07, 0.3, 0.3);
blip(23.2, 784, 1175, 0.12, 0.3);

// 5. Sync.
whoosh(27.4, 0.6, 900, 2600, 0.045, -0.6, -0.4);
blip(28.05, 660, 990, 0.13, -0.55);
whoosh(28.3, 0.95, 500, 3200, 0.11, -0.6, 0.6);
chime(29.15, [79, 86], 0.09, 0.3);
whoosh(29.2, 0.45, 2400, 500, 0.06, 0.55, 0.55);
blip(31.4, 660, 990, 0.13, 0.55);
whoosh(31.7, 0.95, 500, 3200, 0.11, 0.6, -0.6);
chime(32.6, [79, 86], 0.09, -0.3);
whoosh(32.6, 0.45, 2400, 500, 0.06, -0.55, -0.55);

// 6. Pairing.
click(37.0, 0.13, -0.4); click(37.3, 0.13, 0.4);
click(38.78, 0.14, -0.3);
for (let digit = 0; digit < 6; digit++) tick(39.6 + digit * 0.07, 1050 + digit * 110, 0.085, digit % 2 ? 0.4 : -0.4);
click(40.48, 0.15, 0.4);
chime(41.05, [72, 76, 79, 84], 0.1);
[0, 1, 2, 3].forEach((n) => pop(41.5 + n * 0.14, 500 + n * 45, 0.085, -0.45 + n * 0.3));

// 7. Where to get it.
whoosh(42.4, 0.9, 300, 5000, 0.07);
thump(43.22, 0.24);

/* ------------------------------------------------------------------ files */

function writeWav(file, [left, right], gain = 1) {
  const data = Buffer.alloc(SAMPLES * 4);
  for (let n = 0; n < SAMPLES; n++) {
    // Rounded off rather than clipped, should anything get loud.
    data.writeInt16LE(Math.round(Math.tanh(left[n] * gain) * 32767), n * 4);
    data.writeInt16LE(Math.round(Math.tanh(right[n] * gain) * 32767), n * 4 + 2);
  }
  const header = Buffer.alloc(44);
  header.write("RIFF", 0); header.writeUInt32LE(36 + data.length, 4); header.write("WAVEfmt ", 8);
  header.writeUInt32LE(16, 16); header.writeUInt16LE(1, 20); header.writeUInt16LE(2, 22);
  header.writeUInt32LE(RATE, 24); header.writeUInt32LE(RATE * 4, 28); header.writeUInt16LE(4, 32);
  header.writeUInt16LE(16, 34); header.write("data", 36); header.writeUInt32LE(data.length, 40);
  writeFileSync(file, Buffer.concat([header, data]));
}

function run(command, args) {
  const result = spawnSync(command, args, { encoding: "utf8" });
  if (result.status !== 0) throw new Error(`${command} failed:\n${result.stderr}`);
  return result.stdout;
}
const ffmpeg = (...args) => run("ffmpeg", ["-hide_banner", "-loglevel", "error", "-y", ...args]);

const work = mkdtempSync(path.join(tmpdir(), "pastehive-sound-"));
try {
  writeWav(path.join(work, "music.wav"), music, 1.5);
  writeWav(path.join(work, "fx.wav"), fx, 1.6);

  // Each line of narration starts at its own second. A line that runs past
  // its slot is sped up a little, never by more than a seventh.
  const inputs = ["-i", path.join(work, "music.wav"), "-i", path.join(work, "fx.wav")];
  const chains = [];
  const voices = [];
  const cues = [];
  narration.forEach((line, index) => {
    const file = path.join(voiceDir, `line-${String(index + 1).padStart(2, "0")}.flac`);
    if (!existsSync(file)) return;
    const seconds = Number(run("ffprobe", ["-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", file]));
    const tempo = Math.min(1.15, Math.max(1, seconds / (line.until - line.at)));
    if (seconds / tempo > line.until - line.at + 0.05) {
      console.warn(`Line ${index + 1} is ${(seconds / tempo - (line.until - line.at)).toFixed(2)} s too long for its slot.`);
    }
    inputs.push("-i", file);
    cues.push({ from: line.at, to: line.at + seconds / tempo + 0.25, text: line.text });
    const label = `v${index}`;
    chains.push(`[${voices.length + 2}:a]aresample=${RATE},atempo=${tempo.toFixed(4)},adelay=${Math.round(line.at * 1000)}:all=1[${label}]`);
    voices.push(`[${label}]`);
  });

  let graph;
  if (voices.length) {
    graph = [
      ...chains,
      // One voice track: cleaned up, evened out, and split so that it can
      // also push the music down while someone is speaking.
      `${voices.join("")}amix=inputs=${voices.length}:normalize=0,highpass=f=75,acompressor=threshold=-20dB:ratio=3:attack=8:release=160:makeup=2,volume=1.25,apad=whole_dur=${LENGTH},asplit=3[voice][key][voice2]`,
      `[0:a][key]sidechaincompress=threshold=0.035:ratio=2.6:attack=80:release=900,volume=${MUSIC_LEVEL},asplit[bed][bed2]`,
      `[1:a]volume=${FX_LEVEL},asplit[fx][fx2]`,
      `[bed][fx][voice]amix=inputs=3:normalize=0,atrim=0:${LENGTH}[mix]`,
    ];
  } else {
    graph = [`[0:a]volume=0.9[bed]`, `[1:a]volume=${FX_LEVEL}[fx]`, `[bed][fx]amix=inputs=2:normalize=0,atrim=0:${LENGTH}[mix]`];
    console.warn("No narration found in audio/voice/: music and sound effects only.");
  }
  const rough = path.join(work, "rough.wav");
  const stems = voices.length && process.argv.includes("--keep")
    ? ["voice", "bed", "fx"].flatMap((name) => ["-map", `[${name}2]`, "-ac", "2", path.join(here, "audio", `stem-${name}.wav`)])
    : [];
  if (voices.length && !stems.length) graph.push("[voice2]anullsink", "[bed2]anullsink", "[fx2]anullsink");
  ffmpeg(...inputs, "-filter_complex", graph.join(";"), "-map", "[mix]", "-ac", "2", rough, ...stems);

  // Bring the whole thing to the loudness the web expects (-16 LUFS), with
  // a limiter to catch the few peaks that would go over.
  const report = spawnSync("ffmpeg", ["-hide_banner", "-i", rough, "-af", "ebur128", "-f", "null", "-"], { encoding: "utf8" }).stderr;
  const measured = Number(/I:\s+(-?[\d.]+) LUFS/g.exec(report.slice(report.lastIndexOf("Summary")))[1]);
  const gain = TARGET_LUFS - measured;
  const mix = path.join(work, "mix.wav");
  ffmpeg("-i", rough, "-af", `volume=${gain.toFixed(2)}dB,alimiter=limit=0.84:attack=3:release=60:level=false,afade=t=in:d=0.25,afade=t=out:st=${LENGTH - 1.4}:d=1.4`, mix);
  console.log(`Mix measured ${measured} LUFS; ${gain.toFixed(1)} dB applied.`);

  // Into the video files. The pictures are copied as they are.
  for (const [name, codec] of [["pastehive.mp4", ["-c:a", "aac", "-b:a", "160k", "-movflags", "+faststart"]], ["pastehive.webm", ["-c:a", "libopus", "-b:a", "112k"]]]) {
    const target = path.join(videoDir, name);
    const fresh = path.join(work, name);
    ffmpeg("-i", target, "-i", mix, "-map", "0:v:0", "-map", "1:a:0", "-c:v", "copy", ...codec, "-shortest", fresh);
    rmSync(target);
    try { renameSync(fresh, target); } catch { writeFileSync(target, readFileSync(fresh)); }
  }
  // Captions for the player, from the same lines.
  const stamp = (t) => `00:${String(Math.floor(t / 60)).padStart(2, "0")}:${(t % 60).toFixed(3).padStart(6, "0")}`;
  writeFileSync(path.join(videoDir, "captions.vtt"),
    "WEBVTT\n\n" + cues.map((cue, n) => `${n + 1}\n${stamp(cue.from)} --> ${stamp(Math.min(cue.to, LENGTH))}\n${cue.text}\n`).join("\n"));
  if (process.argv.includes("--keep")) {
    writeFileSync(path.join(here, "audio", "mix.wav"), readFileSync(mix));
  }
  console.log(`Sound added to the video files (${voices.length} narration lines).`);
} finally {
  rmSync(work, { recursive: true, force: true });
}
