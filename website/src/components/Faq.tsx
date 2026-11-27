"use client";

import { useState } from "react";
import { Plus } from "lucide-react";
import { Reveal, Section, SectionHeading } from "./ui";

const QUESTIONS = [
  {
    q: "Is PasteHive free?",
    a: "Yes. It is open source under the MIT license.",
  },
  {
    q: "Does my clipboard go through a server?",
    a: "No. Devices connect to each other directly on the local network. There is no PasteHive server.",
  },
  {
    q: "Does it work over the internet, away from home?",
    a: "No. Both devices have to be on the same local network.",
  },
  {
    q: "Can I copy on Windows and paste on a Mac or an Android phone?",
    a: "Yes, for text and pictures, once the devices are paired. On Android, pictures arrive in the list but cannot yet be put on the clipboard.",
  },
  {
    q: "Does it replace the Windows clipboard history (Win+V) or Apple’s Universal Clipboard?",
    a: "It works alongside them. PasteHive adds search, filters, pinning and sync between Windows, macOS and Android, which those do not cover together.",
  },
  {
    q: "How much battery does it use?",
    a: "On a Windows laptop the idle app measured about 1.8% of one CPU core. On a phone, keeping sync on in the background costs more; switch sync off when you do not need it.",
  },
  {
    q: "Does it capture passwords?",
    a: "It records whatever is copied. Use Pause Capturing before copying something you do not want kept, or delete the entry afterwards.",
  },
];

export function Faq() {
  const [open, setOpen] = useState<number | null>(0);

  return (
    <Section id="faq" labelledBy="faq-title">
      <SectionHeading id="faq-title" eyebrow="FAQ" title="Questions, answered." />

      <Reveal className="mx-auto max-w-3xl">
        <ul className="flex flex-col gap-2">
          {QUESTIONS.map((item, index) => {
            const expanded = open === index;
            return (
              <li
                key={item.q}
                className={`rounded-2xl border transition-colors duration-300 ${
                  expanded
                    ? "border-white/25 bg-white/[0.06]"
                    : "border-white/10 hover:border-white/25 hover:bg-white/[0.03]"
                }`}
              >
                <h3>
                  <button
                    type="button"
                    id={`faq-q-${index}`}
                    aria-expanded={expanded}
                    aria-controls={`faq-a-${index}`}
                    onClick={() => setOpen(expanded ? null : index)}
                    className="group flex w-full items-center justify-between gap-4 rounded-2xl px-5 py-4 text-left text-[1.02rem] font-medium"
                  >
                    {item.q}
                    <span
                      className={`flex h-8 w-8 shrink-0 items-center justify-center rounded-full border transition duration-300 ease-out-soft ${
                        expanded
                          ? "rotate-45 border-white bg-white text-black"
                          : "border-white/25 text-white/80 group-hover:border-white/60 group-hover:text-white"
                      }`}
                    >
                      <Plus size={16} />
                    </span>
                  </button>
                </h3>
                {/* Rows animate from 0fr to 1fr: the answer opens to its own
                    height with no script measuring it. */}
                <div
                  id={`faq-a-${index}`}
                  role="region"
                  aria-labelledby={`faq-q-${index}`}
                  className={`grid transition-[grid-template-rows,opacity] duration-300 ease-out-soft ${
                    expanded
                      ? "grid-rows-[1fr] opacity-100"
                      : "grid-rows-[0fr] opacity-0"
                  }`}
                >
                  <div className="overflow-hidden" inert={!expanded}>
                    <p className="px-5 pb-5 pr-14 text-[0.95rem] leading-relaxed text-dim">
                      {item.a}
                    </p>
                  </div>
                </div>
              </li>
            );
          })}
        </ul>
      </Reveal>
    </Section>
  );
}
