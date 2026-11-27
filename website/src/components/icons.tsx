import type { SVGProps } from "react";
import { siAndroid, siApple, siGithub } from "simple-icons";

type IconProps = SVGProps<SVGSVGElement>;

/** The PasteHive mark (logo concept 3, "Loop board"), in the current colour. */
export function LogoMark(props: IconProps) {
  return (
    <svg viewBox="192 192 640 640" aria-hidden="true" {...props}>
      <g
        fill="none"
        stroke="currentColor"
        strokeWidth="56"
        strokeLinecap="round"
      >
        <path d="M 322 482 V 382 A 90 90 0 0 1 412 292 H 612 A 90 90 0 0 1 702 382 V 428" />
        <path d="M 702 582 V 682 A 90 90 0 0 1 612 772 H 412 A 90 90 0 0 1 322 682 V 636" />
      </g>
      <polygon points="644,426 760,426 702,510" fill="currentColor" />
      <polygon points="380,638 264,638 322,554" fill="currentColor" />
      <rect x="432" y="222" width="160" height="114" rx="38" fill="currentColor" />
      <g
        fill="none"
        stroke="currentColor"
        strokeWidth="40"
        strokeLinecap="round"
      >
        <path d="M 446 492 H 578" />
        <path d="M 446 572 H 532" />
      </g>
    </svg>
  );
}

/** The mark on its frosted tile, for the nav and footer. */
export function LogoTile({ className = "" }: { className?: string }) {
  return (
    <span
      aria-hidden="true"
      className={`relative inline-flex items-center justify-center rounded-[28%] border border-white/25 bg-gradient-to-br from-white/25 via-white/10 to-white/5 shadow-[inset_0_1px_0_rgb(255_255_255/0.35)] ${className}`}
    >
      <LogoMark className="h-[68%] w-[68%] text-white" />
    </span>
  );
}

function BrandIcon({ path, ...props }: IconProps & { path: string }) {
  return (
    <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true" {...props}>
      <path d={path} />
    </svg>
  );
}

export function WindowsIcon(props: IconProps) {
  return (
    <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true" {...props}>
      <path d="M2 2h9.5v9.5H2zM12.5 2H22v9.5h-9.5zM2 12.5h9.5V22H2zM12.5 12.5H22V22h-9.5z" />
    </svg>
  );
}

export function AppleIcon(props: IconProps) {
  return <BrandIcon path={siApple.path} {...props} />;
}

export function AndroidIcon(props: IconProps) {
  return <BrandIcon path={siAndroid.path} {...props} />;
}

export function GithubIcon(props: IconProps) {
  return <BrandIcon path={siGithub.path} {...props} />;
}
