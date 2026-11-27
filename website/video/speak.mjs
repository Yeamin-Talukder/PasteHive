// Speaks the narration in audio/narration.json and saves one file per line
// in audio/voice/. Only needed after the words change; the spoken lines are
// kept in the repository.
//
//   npm install --no-save kokoro-js      (once; downloads a 90 MB voice model
//                                         from Hugging Face on first use)
//   node video/speak.mjs                 (from website/)
//   node video/sound.mjs                 (then mix it into the video)
//
// The voice is Kokoro, an open-source model (Apache-2.0) that runs on this
// computer: nothing is sent anywhere. Each line has "text", what is said and
// shown as a caption, and "say", how to spell it so that it is pronounced
// right ("Paste Hive"). Needs ffmpeg, to trim the silence off both ends.

import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { KokoroTTS } from "kokoro-js";

const VOICE = "af_heart";

const here = path.dirname(fileURLToPath(import.meta.url));
const lines = JSON.parse(readFileSync(path.join(here, "audio", "narration.json"), "utf8"));
const outDir = path.join(here, "audio", "voice");
mkdirSync(outDir, { recursive: true });

const tts = await KokoroTTS.from_pretrained("onnx-community/Kokoro-82M-v1.0-ONNX", {
  dtype: "q8",
  device: "cpu",
});

const work = mkdtempSync(path.join(tmpdir(), "pastehive-voice-"));
const trim = "silenceremove=start_periods=1:start_threshold=-48dB:start_silence=0.03";
try {
  for (const [index, line] of lines.entries()) {
    const name = `line-${String(index + 1).padStart(2, "0")}`;
    const raw = path.join(work, `${name}.wav`);
    const audio = await tts.generate(line.say ?? line.text, { voice: VOICE });
    await audio.save(raw);
    const flac = path.join(outDir, `${name}.flac`);
    const made = spawnSync("ffmpeg", ["-hide_banner", "-loglevel", "error", "-y", "-i", raw,
      "-af", `${trim},areverse,${trim},areverse`, "-c:a", "flac", flac], { encoding: "utf8" });
    if (made.status !== 0) throw new Error(made.stderr);
    const seconds = Number(spawnSync("ffprobe", ["-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", flac], { encoding: "utf8" }).stdout);
    const room = line.until - line.at;
    console.log(`${name}  ${seconds.toFixed(2)} s of ${room.toFixed(2)} s${seconds > room ? "  (too long: sound.mjs will speed it up)" : ""}  ${line.text}`);
  }
} finally {
  rmSync(work, { recursive: true, force: true });
}
