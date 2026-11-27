import { Reveal, Section, SectionHeading } from "./ui";

// Files in public/ are not given the site's sub-folder by Next.js, so it is
// added here. Empty when the site is served from the root of its domain.
const BASE = process.env.NEXT_PUBLIC_BASE_PATH ?? "";

const CHAPTERS = [
  {
    at: "0:00",
    title: "The problem",
    body: "Copied on the computer, needed on the phone. And the clipboard remembers only one thing.",
  },
  {
    at: "0:17",
    title: "History",
    body: "The panel at the top middle of the screen, search as you type, paste where you were typing.",
  },
  {
    at: "0:26",
    title: "Sync and pairing",
    body: "Copy on one device, paste on another, after pairing once with a six-digit code.",
  },
];

/**
 * The 48-second film. It is rendered from website/video/video.html, an
 * animation rather than a recording, and has no sound.
 */
export function Video() {
  return (
    <Section id="video" labelledBy="video-title">
      <SectionHeading
        id="video-title"
        eyebrow="Video"
        title="The whole idea in 48 seconds."
      >
        The problem, what PasteHive does about it, and how your devices
        connect.
      </SectionHeading>

      <Reveal>
        <figure className="mx-auto max-w-5xl">
          <div className="overflow-hidden rounded-3xl border border-white/15 bg-black shadow-[0_40px_80px_-40px_rgb(0_0_0),inset_0_1px_0_rgb(255_255_255/0.12)] transition-colors duration-300 hover:border-white/30">
            <video
              controls
              muted
              playsInline
              preload="none"
              poster={`${BASE}/video/poster.jpg`}
              width={1920}
              height={1080}
              aria-label="PasteHive in 48 seconds: an animated explanation of the problem, clipboard history, sync between devices, and pairing"
              className="block aspect-video h-auto w-full"
            >
              <source src={`${BASE}/video/pastehive.webm`} type="video/webm" />
              <source src={`${BASE}/video/pastehive.mp4`} type="video/mp4" />
              Your browser cannot play this video.{" "}
              <a href={`${BASE}/video/pastehive.mp4`}>Download it</a> instead.
            </video>
          </div>
          <figcaption className="mt-3 text-center text-[0.82rem] text-faint">
            An animation, not a screen recording. No sound.
          </figcaption>
        </figure>
      </Reveal>

      <Reveal className="mx-auto mt-8 max-w-5xl">
        <ol className="grid grid-cols-1 gap-3 sm:grid-cols-3">
          {CHAPTERS.map((chapter) => (
            <li
              key={chapter.title}
              className="rounded-2xl border border-white/10 p-4 transition-colors duration-300 hover:border-white/25"
            >
              <p className="mb-2 flex items-baseline justify-between gap-3">
                <span className="font-medium">{chapter.title}</span>
                <span className="font-mono text-[0.75rem] text-faint">
                  {chapter.at}
                </span>
              </p>
              <p className="text-[0.88rem] leading-relaxed text-dim">
                {chapter.body}
              </p>
            </li>
          ))}
        </ol>
      </Reveal>
    </Section>
  );
}
