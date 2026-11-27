import { ArrowUpRight, Download } from "lucide-react";
import { BUILD_URL, RELEASES_URL, REPO_URL } from "@/lib/site";
import { GithubIcon } from "./icons";
import { HeroStage } from "./hero/HeroStage";

/** The logo's backdrop: outlines of the tile's shape, repeating outward. */
function EchoBackdrop() {
  const rings = [0, 1, 2, 3, 4, 5];
  return (
    <div
      aria-hidden="true"
      className="pointer-events-none absolute inset-0 overflow-hidden [mask-image:linear-gradient(to_bottom,transparent_44%,#000_66%)]"
    >
      <svg
        className="absolute left-1/2 top-[72%] h-[1500px] w-[1500px] -translate-x-1/2 -translate-y-1/2 [mask-image:radial-gradient(closest-side,#000_45%,transparent)]"
        viewBox="0 0 1500 1500"
        fill="none"
      >
        {rings.map((ring) => {
          const size = 300 + ring * 220;
          return (
            <rect
              key={ring}
              x={(1500 - size) / 2}
              y={(1500 - size) / 2}
              width={size}
              height={size}
              rx={size * 0.24}
              stroke="#fff"
              strokeWidth={1.5}
              className="animate-echo"
              style={{ animationDelay: `${ring * 0.45}s` }}
            />
          );
        })}
      </svg>
      <div className="grain absolute inset-0 opacity-[0.07] mix-blend-screen" />
    </div>
  );
}

export function Hero() {
  return (
    <section
      id="top"
      aria-labelledby="hero-title"
      className="relative flex h-svh min-h-[600px] flex-col overflow-hidden pt-14 lg:pt-16"
    >
      <EchoBackdrop />

      <div className="relative mx-auto flex w-full max-w-5xl shrink-0 flex-col items-center px-4 pt-[clamp(0.75rem,3.2svh,2.75rem)] text-center">
        <p className="mb-[clamp(0.6rem,1.8svh,1.25rem)] inline-flex items-center gap-2 rounded-full border border-white/15 bg-white/[0.06] px-3 py-1 text-[0.75rem] font-medium text-white/80">
          <span className="h-1.5 w-1.5 rounded-full bg-white" />
          Free and open source
          <span className="text-white/40">/</span>
          Windows, macOS, Android
        </p>

        <h1
          id="hero-title"
          className="text-[clamp(2.3rem,min(5.2vw,7.6svh),5rem)] font-semibold leading-[1.02] tracking-[-0.045em] text-balance"
        >
          <span className="inline-block">Copy here.</span>{" "}
          <span className="inline-block bg-gradient-to-b from-white to-white/55 bg-clip-text text-transparent">
            Paste there.
          </span>
        </h1>

        <p className="mt-[clamp(0.6rem,1.6svh,1.1rem)] max-w-[50rem] text-[clamp(0.95rem,min(1.25vw,2.2svh),1.2rem)] leading-snug text-dim text-balance">
          A clipboard manager that keeps a searchable history of everything you
          copy and syncs it between your own devices over the local network.
          Encrypted, with no cloud and no account.
        </p>

        <div className="mt-[clamp(0.8rem,2.2svh,1.6rem)] flex flex-wrap items-center justify-center gap-2.5">
          <a
            href={RELEASES_URL}
            className="group relative inline-flex h-11 items-center gap-2 overflow-hidden rounded-full bg-white px-5 text-[0.95rem] font-semibold text-black transition duration-200 ease-out-soft hover:-translate-y-0.5 hover:shadow-[0_10px_30px_-8px_rgb(255_255_255/0.5)] active:translate-y-0 active:scale-[0.98]"
          >
            <span
              aria-hidden="true"
              className="absolute inset-y-0 left-0 w-1/3 bg-gradient-to-r from-transparent via-black/15 to-transparent opacity-0 group-hover:animate-sheen group-hover:opacity-100"
            />
            <Download
              size={17}
              strokeWidth={2.4}
              className="transition-transform duration-200 group-hover:translate-y-0.5"
            />
            Download
          </a>
          <a
            href={REPO_URL}
            className="group inline-flex h-11 items-center gap-2 rounded-full border border-white/20 bg-white/[0.06] px-5 text-[0.95rem] font-medium text-white transition duration-200 ease-out-soft hover:-translate-y-0.5 hover:border-white/50 hover:bg-white/[0.12] active:translate-y-0 active:scale-[0.98]"
          >
            <GithubIcon className="h-[17px] w-[17px]" />
            View on GitHub
            <ArrowUpRight
              size={15}
              className="text-white/60 transition duration-200 group-hover:-translate-y-0.5 group-hover:translate-x-0.5 group-hover:text-white"
            />
          </a>
        </div>

        <p className="mt-2.5 text-[0.78rem] text-faint">
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

      <div className="relative mx-auto mb-4 mt-[clamp(0.75rem,2.4svh,2rem)] min-h-0 w-full max-w-[1560px] flex-1 px-4 lg:mb-6 lg:px-10">
        <HeroStage />
      </div>
    </section>
  );
}
