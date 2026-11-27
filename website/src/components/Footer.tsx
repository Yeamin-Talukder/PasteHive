import Image from "next/image";
import { ArrowUpRight, Download, Star } from "lucide-react";
import appIcon from "@/assets/concept-3-icon.svg";
import {
  BUILD_URL,
  ISSUES_URL,
  LICENSE_URL,
  NAV_LINKS,
  RELEASES_URL,
  REPO_URL,
} from "@/lib/site";
import { GithubIcon, LogoTile } from "./icons";
import { Reveal } from "./ui";

export function ClosingCall() {
  return (
    <section
      aria-labelledby="closing-title"
      className="relative mx-auto w-full max-w-6xl px-4 pb-20 pt-8 lg:pb-28"
    >
      <Reveal>
        <div className="relative overflow-hidden rounded-[2rem] border border-white/15 bg-[linear-gradient(160deg,#1c1c1c,#0a0a0a_55%,#000)] px-6 py-14 text-center sm:px-12 sm:py-20">
          <div
            aria-hidden="true"
            className="pointer-events-none absolute inset-0 [mask-image:radial-gradient(ellipse_at_50%_30%,#000_10%,transparent_70%)]"
          >
            {[0, 1, 2, 3].map((ring) => (
              <span
                key={ring}
                className="absolute left-1/2 top-[34%] -translate-x-1/2 -translate-y-1/2 animate-echo rounded-[24%] border border-white"
                style={{
                  width: 200 + ring * 170,
                  height: 200 + ring * 170,
                  animationDelay: `${ring * 0.5}s`,
                }}
              />
            ))}
          </div>

          <div className="relative">
            <Image
              src={appIcon}
              alt=""
              width={104}
              height={104}
              className="mx-auto mb-8 h-[104px] w-[104px] transition-transform duration-500 ease-out-soft hover:rotate-[-6deg] hover:scale-105"
            />
            <h2
              id="closing-title"
              className="text-[clamp(1.9rem,4.4vw,3.4rem)] font-semibold leading-[1.05] tracking-[-0.04em] text-balance"
            >
              One clipboard across your own devices.
            </h2>
            <p className="mx-auto mt-5 max-w-xl text-[1.05rem] leading-relaxed text-dim text-pretty">
              Free and open source. If PasteHive is useful to you, a star helps
              other people find it.
            </p>
            <div className="mt-8 flex flex-wrap items-center justify-center gap-2.5">
              <a
                href={RELEASES_URL}
                className="group inline-flex h-12 items-center gap-2 rounded-full bg-white px-6 font-semibold text-black transition duration-200 ease-out-soft hover:-translate-y-0.5 hover:shadow-[0_10px_30px_-8px_rgb(255_255_255/0.5)] active:translate-y-0 active:scale-[0.98]"
              >
                <Download
                  size={18}
                  strokeWidth={2.4}
                  className="transition-transform duration-200 group-hover:translate-y-0.5"
                />
                Download
              </a>
              <a
                href={REPO_URL}
                className="group inline-flex h-12 items-center gap-2 rounded-full border border-white/20 bg-white/[0.06] px-6 font-medium transition duration-200 ease-out-soft hover:-translate-y-0.5 hover:border-white/50 hover:bg-white/[0.12] active:translate-y-0 active:scale-[0.98]"
              >
                <Star
                  size={17}
                  className="transition duration-300 group-hover:rotate-[72deg] group-hover:fill-white"
                />
                Star on GitHub
              </a>
            </div>
            <p className="mt-4 text-[0.82rem] text-faint">
              Free for Windows, macOS and Android. Or{" "}
              <a
                href={BUILD_URL}
                className="text-white/80 underline decoration-white/30 underline-offset-4 transition-colors hover:text-white hover:decoration-white"
              >
                build it from source
              </a>
              .
            </p>
          </div>
        </div>
      </Reveal>
    </section>
  );
}

const FOOT_LINK =
  "group inline-flex items-center gap-1 text-[0.92rem] text-dim transition-colors duration-200 hover:text-white";

export function Footer() {
  const external = [
    { href: REPO_URL, label: "GitHub" },
    { href: RELEASES_URL, label: "Releases" },
    { href: ISSUES_URL, label: "Issues and ideas" },
    { href: BUILD_URL, label: "Build from source" },
    { href: LICENSE_URL, label: "MIT license" },
  ];

  return (
    <footer className="border-t border-white/10">
      <div className="mx-auto grid max-w-6xl grid-cols-1 gap-10 px-4 py-14 sm:grid-cols-[minmax(0,2fr)_minmax(0,1fr)_minmax(0,1fr)]">
        <div>
          <a
            href="#top"
            className="inline-flex items-center gap-2.5 text-[1.05rem] font-semibold tracking-tight"
          >
            <LogoTile className="h-8 w-8" />
            PasteHive
          </a>
          <p className="mt-4 max-w-sm text-[0.92rem] leading-relaxed text-dim">
            A free, open-source clipboard manager for Windows, macOS and
            Android. Clipboard history and sync over the local network,
            encrypted, with no cloud and no account.
          </p>
          <a
            href={REPO_URL}
            className="mt-5 inline-flex h-10 items-center gap-2 rounded-full border border-white/15 px-4 text-[0.88rem] text-white/85 transition duration-200 hover:border-white/45 hover:bg-white/[0.08] hover:text-white active:scale-[0.98]"
          >
            <GithubIcon className="h-4 w-4" />
            Yeamin-Talukder/PasteHive
          </a>
        </div>

        <nav aria-label="On this page">
          <h2 className="mb-4 font-mono text-xs uppercase tracking-[0.2em] text-faint">
            On this page
          </h2>
          <ul className="flex flex-col gap-2.5">
            {NAV_LINKS.map((link) => (
              <li key={link.href}>
                <a href={link.href} className={FOOT_LINK}>
                  {link.label}
                </a>
              </li>
            ))}
          </ul>
        </nav>

        <nav aria-label="Project">
          <h2 className="mb-4 font-mono text-xs uppercase tracking-[0.2em] text-faint">
            Project
          </h2>
          <ul className="flex flex-col gap-2.5">
            {external.map((link) => (
              <li key={link.label}>
                <a href={link.href} className={FOOT_LINK}>
                  {link.label}
                  <ArrowUpRight
                    size={13}
                    className="text-white/40 transition duration-200 group-hover:-translate-y-0.5 group-hover:translate-x-0.5 group-hover:text-white"
                  />
                </a>
              </li>
            ))}
          </ul>
        </nav>
      </div>

      <div className="border-t border-white/10">
        <p className="mx-auto max-w-6xl px-4 py-6 text-[0.82rem] text-faint">
          Released under the{" "}
          <a
            href={LICENSE_URL}
            className="underline decoration-white/25 underline-offset-4 transition-colors hover:text-white"
          >
            MIT license
          </a>
          . Built with Flutter. Windows, macOS, Android and iOS are trademarks
          of their owners.
        </p>
      </div>
    </footer>
  );
}
