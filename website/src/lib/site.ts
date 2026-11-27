export const SITE_NAME = "PasteHive";

export const SITE_TITLE = "PasteHive: clipboard manager and clipboard sync";

export const SITE_DESCRIPTION =
  "A free, open-source clipboard manager for Windows, macOS and Android. Searchable clipboard history, and sync between your own devices over the local network: encrypted, with no cloud and no account.";

/** Where the site will live. Set NEXT_PUBLIC_SITE_URL at build time. */
export const SITE_URL =
  process.env.NEXT_PUBLIC_SITE_URL || "http://localhost:3000";

export const REPO_URL = "https://github.com/Yeamin-Talukder/PasteHive";
export const RELEASES_URL = `${REPO_URL}/releases/latest`;
export const BUILD_URL = `${REPO_URL}#build-from-source`;
export const LICENSE_URL = `${REPO_URL}/blob/main/LICENSE`;
export const ISSUES_URL = `${REPO_URL}/issues`;
export const README_URL = `${REPO_URL}#readme`;

export const NAV_LINKS = [
  { href: "#how-it-works", label: "How it works" },
  { href: "#features", label: "Features" },
  { href: "#download", label: "Download" },
  { href: "#privacy", label: "Privacy" },
  { href: "#shortcuts", label: "Shortcuts" },
  { href: "#faq", label: "FAQ" },
] as const;
