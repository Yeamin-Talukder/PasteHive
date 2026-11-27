import type { NextConfig } from "next";

// Set NEXT_PUBLIC_BASE_PATH when the site is served from a sub-path, for
// example "/PasteHive" on GitHub Pages project sites. Leave it unset for a
// site served from the root of its domain (Vercel, Netlify, a custom domain).
const basePath = process.env.NEXT_PUBLIC_BASE_PATH || undefined;

const nextConfig: NextConfig = {
  // Plain HTML, CSS and JS in `out/`: hostable anywhere, no server needed.
  output: "export",
  basePath,
  trailingSlash: true,
  images: { unoptimized: true },
  turbopack: {
    rules: {
      "*.css": {
        loaders: ["@tailwindcss/turbopack"],
        as: "*.css",
      },
    },
  },
};

export default nextConfig;
