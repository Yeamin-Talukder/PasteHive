import type { Metadata, Viewport } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import {
  SITE_DESCRIPTION,
  SITE_NAME,
  SITE_TITLE,
  SITE_URL,
} from "@/lib/site";
import "./globals.css";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

// The site may live in a sub-folder (a GitHub Pages project site). Next.js
// adds that folder to the icon and preview-image addresses by itself, so the
// base here is the origin alone and only the page address carries the folder.
const site = new URL(SITE_URL);
const pagePath = site.pathname.endsWith("/")
  ? site.pathname
  : `${site.pathname}/`;

export const metadata: Metadata = {
  metadataBase: new URL(site.origin),
  title: SITE_TITLE,
  description: SITE_DESCRIPTION,
  applicationName: SITE_NAME,
  keywords: [
    "clipboard manager",
    "clipboard history",
    "clipboard sync",
    "Windows",
    "macOS",
    "Android",
    "open source",
    "local network",
  ],
  alternates: { canonical: pagePath },
  openGraph: {
    type: "website",
    siteName: SITE_NAME,
    title: SITE_TITLE,
    description: SITE_DESCRIPTION,
    url: pagePath,
  },
  twitter: {
    card: "summary_large_image",
    title: SITE_TITLE,
    description: SITE_DESCRIPTION,
  },
};

export const viewport: Viewport = {
  themeColor: "#060606",
  colorScheme: "dark",
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html
      lang="en"
      className={`${geistSans.variable} ${geistMono.variable} antialiased`}
    >
      <body className="min-h-svh overflow-x-clip">{children}</body>
    </html>
  );
}
