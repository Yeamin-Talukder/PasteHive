import {
  CloudOff,
  FolderOpen,
  KeyRound,
  type LucideIcon,
  Radio,
  SearchCheck,
} from "lucide-react";
import type { ReactNode } from "react";
import { Card, Reveal, Section, SectionHeading } from "./ui";

interface Fact {
  icon: LucideIcon;
  title: string;
  body: ReactNode;
  /** A limit rather than a promise. Shown just as plainly. */
  caveat?: boolean;
}

const Mono = ({ children }: { children: ReactNode }) => (
  <code className="rounded-md bg-white/10 px-1.5 py-0.5 font-mono text-[0.82em] text-white/90">
    {children}
  </code>
);

const FACTS: Fact[] = [
  {
    icon: CloudOff,
    title: "No cloud, no account, no telemetry.",
    body: "Your clipboard goes only to devices you have accepted, directly over your own network. There is no PasteHive server.",
  },
  {
    icon: KeyRound,
    title: "Encrypted in transit.",
    body: (
      <>
        Each connection does a fresh <Mono>X25519</Mono> key exchange, derives
        its keys from that and the group’s key together (
        <Mono>HKDF-SHA256</Mono>), and encrypts every message with{" "}
        <Mono>ChaCha20-Poly1305</Mono>. A device without the group’s key can
        neither join nor read.
      </>
    ),
  },
  {
    icon: Radio,
    title: "Visible on your network while sync is on.",
    body: (
      <>
        Devices announce themselves by name over UDP (port <Mono>45817</Mono>,
        multicast group <Mono>239.255.77.67</Mono> and broadcast) so that
        others on the same network can find them. What you copy is sent only
        to devices you have accepted.
      </>
    ),
    caveat: true,
  },
  {
    icon: FolderOpen,
    title: "Stored on your device, unencrypted.",
    body: (
      <>
        History is kept in <Mono>history.json</Mono> in the app’s support
        folder as plain text, copied pictures as PNG files in an{" "}
        <Mono>images</Mono> folder beside it (at most 40 unpinned ones), and
        the group’s key in <Mono>sync.json</Mono>. Anyone with access to your
        user account can read them.
      </>
    ),
    caveat: true,
  },
  {
    icon: SearchCheck,
    title: "Not independently reviewed.",
    body: "The protocol is assembled from standard parts but was written for this app and has not had a security audit. Do not rely on it for secrets you could not afford to leak.",
    caveat: true,
  },
];

export function Privacy() {
  return (
    <Section id="privacy" labelledBy="privacy-title">
      <SectionHeading
        id="privacy-title"
        eyebrow="Privacy and security"
        title="Your clipboard stays on your network."
      >
        What PasteHive does to protect it, and, just as plainly, what it does
        not do.
      </SectionHeading>

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-6">
        {FACTS.map((fact, index) => (
          <Reveal
            key={fact.title}
            delay={(index % 3) * 0.07}
            className={index < 2 ? "lg:col-span-3" : "lg:col-span-2"}
          >
            <Card as="article" className="h-full p-6 sm:p-7">
              <div className="mb-5 flex items-center justify-between">
                <span className="flex h-11 w-11 items-center justify-center rounded-2xl border border-white/15 bg-white/[0.07] transition duration-300 ease-out-soft group-hover/card:-translate-y-0.5 group-hover/card:border-white/40">
                  <fact.icon size={20} />
                </span>
                <span
                  className={`rounded-full border px-2.5 py-1 font-mono text-[0.66rem] uppercase tracking-[0.14em] ${
                    fact.caveat
                      ? "border-dashed border-white/35 text-white/70"
                      : "border-white/60 text-white"
                  }`}
                >
                  {fact.caveat ? "Know this" : "By design"}
                </span>
              </div>
              <h3 className="mb-2.5 text-[1.15rem] font-semibold leading-snug tracking-[-0.015em]">
                {fact.title}
              </h3>
              <p className="text-[0.93rem] leading-relaxed text-dim">
                {fact.body}
              </p>
            </Card>
          </Reveal>
        ))}
      </div>
    </Section>
  );
}
