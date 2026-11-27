"use client";

import { useEffect, useState } from "react";
import { AnimatePresence, motion } from "motion/react";
import { Download, Menu, X } from "lucide-react";
import { NAV_LINKS, RELEASES_URL, REPO_URL } from "@/lib/site";
import { GithubIcon, LogoTile } from "./icons";

export function Nav() {
  const [open, setOpen] = useState(false);

  useEffect(() => {
    if (!open) return;
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") setOpen(false);
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [open]);

  return (
    <header className="fixed inset-x-0 top-0 z-50">
      <div className="border-b border-white/[0.08] bg-black/55 backdrop-blur-xl backdrop-saturate-150">
        <nav
          aria-label="Main"
          className="mx-auto flex h-14 max-w-6xl items-center gap-4 px-4 lg:h-16"
        >
          <a
            href="#top"
            className="group flex items-center gap-2.5 text-[1.05rem] font-semibold tracking-tight"
          >
            <LogoTile className="h-8 w-8 transition-transform duration-300 ease-out-soft group-hover:rotate-[-8deg] group-hover:scale-105" />
            PasteHive
          </a>

          <ul className="ml-auto hidden items-center gap-1 lg:flex">
            {NAV_LINKS.map((link) => (
              <li key={link.href}>
                <a
                  href={link.href}
                  className="rounded-full px-3 py-1.5 text-sm text-dim transition-colors duration-200 hover:bg-white/[0.08] hover:text-white"
                >
                  {link.label}
                </a>
              </li>
            ))}
          </ul>

          <div className="ml-auto flex items-center gap-2 lg:ml-2">
            <a
              href={REPO_URL}
              aria-label="PasteHive on GitHub"
              title="PasteHive on GitHub"
              className="flex h-9 w-9 items-center justify-center rounded-full border border-white/15 text-white/80 transition duration-200 hover:border-white/45 hover:bg-white/[0.1] hover:text-white active:scale-95"
            >
              <GithubIcon className="h-[17px] w-[17px]" />
            </a>
            <a
              href={RELEASES_URL}
              className="group hidden h-9 items-center gap-1.5 rounded-full bg-white px-4 text-sm font-semibold text-black transition duration-200 hover:bg-white/85 active:scale-95 sm:inline-flex"
            >
              <Download
                size={15}
                strokeWidth={2.4}
                className="transition-transform duration-200 group-hover:translate-y-0.5"
              />
              Download
            </a>
            <button
              type="button"
              onClick={() => setOpen((value) => !value)}
              aria-expanded={open}
              aria-controls="mobile-menu"
              aria-label={open ? "Close menu" : "Open menu"}
              className="flex h-9 w-9 items-center justify-center rounded-full border border-white/15 text-white transition duration-200 hover:border-white/45 hover:bg-white/[0.1] active:scale-95 lg:hidden"
            >
              {open ? <X size={17} /> : <Menu size={17} />}
            </button>
          </div>
        </nav>
      </div>

      <AnimatePresence>
        {open && (
          <motion.div
            id="mobile-menu"
            initial={{ opacity: 0, y: -10 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -10, transition: { duration: 0.15 } }}
            transition={{ type: "spring", stiffness: 380, damping: 30 }}
            className="glass mx-3 mt-2 rounded-2xl bg-black/70 p-2 lg:hidden"
          >
            <ul>
              {NAV_LINKS.map((link) => (
                <li key={link.href}>
                  <a
                    href={link.href}
                    onClick={() => setOpen(false)}
                    className="block rounded-xl px-4 py-3 text-[0.95rem] text-white/85 transition-colors hover:bg-white/[0.1] hover:text-white"
                  >
                    {link.label}
                  </a>
                </li>
              ))}
              <li className="p-2 sm:hidden">
                <a
                  href={RELEASES_URL}
                  onClick={() => setOpen(false)}
                  className="flex h-11 items-center justify-center gap-2 rounded-full bg-white text-[0.95rem] font-semibold text-black active:scale-[0.98]"
                >
                  <Download size={16} strokeWidth={2.4} />
                  Download
                </a>
              </li>
            </ul>
          </motion.div>
        )}
      </AnimatePresence>
    </header>
  );
}
