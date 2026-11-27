import { ShieldAlert } from "lucide-react";
import { Fragment } from "react";
import { Reveal, Section, SectionHeading } from "./ui";

interface Shortcut {
  /** Alternatives, each a combination of keys pressed together. */
  keys: string[][];
  /** The same shortcut on a Mac, where it differs. */
  mac?: string[];
  does: string;
}

const SHORTCUTS: Shortcut[] = [
  { keys: [["Type"]], does: "Search" },
  { keys: [["↑"], ["↓"]], does: "Move through the list" },
  {
    keys: [["Enter"]],
    does: "Paste the selected entry where you were typing, and close",
  },
  {
    keys: [["Space"]],
    does: "Preview the selected entry (while the search field is empty)",
  },
  { keys: [["Tab"], ["Shift", "Tab"]], does: "Next / previous filter" },
  {
    keys: [["Delete"]],
    does: "Delete the selected entry (while the search field is empty)",
  },
  {
    keys: [["Ctrl", "Z"]],
    mac: ["⌘", "Z"],
    does: "Bring back the entry just deleted",
  },
  {
    keys: [["Ctrl", "P"]],
    mac: ["⌘", "P"],
    does: "Pin or unpin the selected entry",
  },
  {
    keys: [["Esc"]],
    does: "Close the preview, clear the search, reset the filter, then close",
  },
];

function Combo({ keys }: { keys: string[] }) {
  return (
    <span className="inline-flex items-center gap-1">
      {keys.map((key, index) => (
        <Fragment key={key}>
          {index > 0 && <span className="text-white/40">+</span>}
          <kbd className="kbd transition duration-200 group-hover:-translate-y-px group-hover:border-white/50 group-hover:bg-white group-hover:text-black">
            {key}
          </kbd>
        </Fragment>
      ))}
    </span>
  );
}

export function Shortcuts() {
  return (
    <Section id="shortcuts" labelledBy="shortcuts-title">
      <SectionHeading
        id="shortcuts-title"
        eyebrow="Keyboard shortcuts"
        title="Hands on the keyboard."
      >
        With the panel open, everything is a key away.
      </SectionHeading>

      <Reveal>
        <dl className="mx-auto grid max-w-4xl grid-cols-1 gap-x-10 md:grid-cols-2">
          {SHORTCUTS.map((shortcut) => (
            <div
              key={shortcut.does}
              className="group flex items-center gap-4 border-b border-white/10 px-2 py-4 transition-colors duration-200 hover:border-white/30 hover:bg-white/[0.03]"
            >
              <dt className="flex w-[9.5rem] shrink-0 flex-wrap items-center gap-1.5">
                {shortcut.keys.map((combo, index) => (
                  <Fragment key={combo.join("+")}>
                    {index > 0 && <span className="text-white/40">/</span>}
                    <Combo keys={combo} />
                  </Fragment>
                ))}
                {shortcut.mac && (
                  <span className="flex w-full items-center gap-1.5 text-[0.72rem] text-faint">
                    Mac
                    <Combo keys={shortcut.mac} />
                  </span>
                )}
              </dt>
              <dd className="text-[0.93rem] leading-snug text-dim transition-colors duration-200 group-hover:text-white">
                {shortcut.does}
              </dd>
            </div>
          ))}
        </dl>

        <p className="mx-auto mt-8 flex max-w-4xl items-start gap-3 px-2 text-[0.88rem] leading-relaxed text-dim">
          <ShieldAlert size={17} className="mt-0.5 shrink-0 text-white" />
          Windows does not deliver a paste to a program running as
          administrator, so nothing is pasted there; the entry is still on the
          clipboard.
        </p>
      </Reveal>
    </Section>
  );
}
