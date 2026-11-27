"use client";

import { useSyncExternalStore } from "react";

/**
 * Whether a media query matches. The server, and the first paint in the
 * browser, use `whenUnknown`, so the markup never disagrees between the two.
 */
export function useMediaQuery(query: string, whenUnknown: boolean) {
  return useSyncExternalStore(
    (onChange) => {
      const media = window.matchMedia(query);
      media.addEventListener("change", onChange);
      return () => media.removeEventListener("change", onChange);
    },
    () => window.matchMedia(query).matches,
    () => whenUnknown,
  );
}

/** True when the visitor has asked their system for less motion. */
export function usePrefersReducedMotion() {
  return useMediaQuery("(prefers-reduced-motion: reduce)", false);
}
