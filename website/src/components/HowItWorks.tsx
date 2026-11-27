"use client";

import { useEffect, useRef, useState, type ReactNode } from "react";
import { AnimatePresence, motion, useInView } from "motion/react";
import {
  Check,
  FileX,
  ImageIcon,
  Lock,
  Network,
  ShieldQuestion,
  Unplug,
  Wifi,
} from "lucide-react";
import { usePrefersReducedMotion } from "@/lib/hooks";
import { AppleIcon, WindowsIcon } from "./icons";
import { Card, Reveal, Section, SectionHeading } from "./ui";

const STEPS = [
  {
    title: "Put your devices on the same network",
    body: "Wi-Fi or wired. Devices find each other there and talk directly.",
  },
  {
    title: "Switch on Sync over Local Network",
    body: "Open Sync Settings on each device: the button at the bottom left of the panel, or the tray menu.",
  },
  {
    title: "Choose the other device and press Connect",
    body: "It appears under Nearby Devices on its own. There is no key to type and no account to create.",
  },
  {
    title: "Check the six-digit code, then Accept",
    body: "The other device shows the request with a code. When both show the same one, press Accept.",
  },
];

const NOTES = [
  {
    icon: ShieldQuestion,
    text: "The first time sync is switched on, Windows asks whether to let the app through the firewall and macOS asks for access to the local network. Sync needs both to be allowed.",
  },
  {
    icon: Unplug,
    text: "Networks that keep devices apart, such as guest Wi-Fi and some office networks, will not work.",
  },
  {
    icon: ImageIcon,
    text: "Text and pictures are synced. Pictures larger than 5 MB as PNG stay on the device where they were copied.",
  },
  {
    icon: FileX,
    text: "Files are never sent: a path means nothing on another machine. A device that is off or away when something is deleted does not hear about it.",
  },
];

/** 0-3 are the four steps; 4 is the result, shown under step four. */
const LAST = 4;
const CODE = "482913";

function Switch({ on }: { on: boolean }) {
  return (
    <span
      aria-hidden="true"
      className={`relative block h-[22px] w-[38px] shrink-0 rounded-full border transition-colors duration-300 ${
        on ? "border-white bg-white" : "border-white/25 bg-white/10"
      }`}
    >
      <span
        className={`absolute left-[2px] top-[2px] h-4 w-4 rounded-full transition-transform duration-300 ease-out-soft ${
          on ? "translate-x-4 bg-black" : "bg-white/70"
        }`}
      />
    </span>
  );
}

function Code() {
  return (
    <span
      className="flex items-center gap-[3px] font-mono text-base font-semibold"
      aria-label={`Code ${CODE.slice(0, 3)} ${CODE.slice(3)}`}
    >
      {CODE.split("").map((digit, index) => (
        <motion.span
          key={index}
          aria-hidden="true"
          initial={{ opacity: 0, y: 8 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.12 + index * 0.06, duration: 0.3 }}
          className={`flex h-8 w-[22px] items-center justify-center rounded-md border border-white/20 bg-white/10 ${
            index === 3 ? "ml-1.5" : ""
          }`}
        >
          {digit}
        </motion.span>
      ))}
    </span>
  );
}

function Pane({
  icon,
  name,
  syncOn,
  bodyKey,
  children,
}: {
  icon: ReactNode;
  name: string;
  syncOn: boolean;
  bodyKey: string;
  children: ReactNode;
}) {
  return (
    <div className="flex flex-col gap-3 rounded-2xl border border-white/[0.14] bg-[rgb(20_20_26/0.6)] p-3.5 shadow-[inset_0_1px_0_rgb(255_255_255/0.3)]">
      <div className="flex items-center gap-2 text-sm font-medium">
        <span className="text-white/80">{icon}</span>
        {name}
      </div>
      <div className="flex items-center justify-between gap-3 rounded-xl bg-white/[0.08] px-3 py-2.5 text-[0.82rem]">
        Sync over Local Network
        <Switch on={syncOn} />
      </div>
      <div className="relative h-[124px]">
        <AnimatePresence mode="wait" initial={false}>
          <motion.div
            key={bodyKey}
            initial={{ opacity: 0, y: 8 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -6, transition: { duration: 0.15 } }}
            transition={{ duration: 0.3, ease: [0.22, 1, 0.36, 1] }}
            className="absolute inset-0 flex flex-col justify-center gap-2.5"
          >
            {children}
          </motion.div>
        </AnimatePresence>
      </div>
    </div>
  );
}

const Quiet = ({ children }: { children: ReactNode }) => (
  <p className="text-[0.82rem] leading-snug text-dim">{children}</p>
);

const GroupLabel = ({ children }: { children: ReactNode }) => (
  <p className="text-[0.72rem] font-semibold text-white/70">{children}</p>
);

function Connected({ peer }: { peer: string }) {
  return (
    <>
      <GroupLabel>Syncing With</GroupLabel>
      <div className="flex items-center gap-2 rounded-xl bg-white/[0.08] px-3 py-2.5 text-[0.85rem]">
        <span className="flex h-[18px] w-[18px] items-center justify-center rounded-full bg-white text-black">
          <Check size={12} strokeWidth={3.2} />
        </span>
        {peer}
        <span className="ml-auto text-[0.75rem] text-dim">Connected</span>
      </div>
    </>
  );
}

function FakeButton({ children, press }: { children: ReactNode; press?: boolean }) {
  return (
    <motion.span
      animate={press ? { scale: [1, 1, 0.92, 1] } : undefined}
      transition={{ duration: 1.6, times: [0, 0.7, 0.82, 1] }}
      className="rounded-full bg-white px-3.5 py-1.5 text-[0.78rem] font-semibold text-black"
    >
      {children}
    </motion.span>
  );
}

function PairingDemo({ step }: { step: number }) {
  const on = step >= 1;

  return (
    <div
      role="img"
      aria-label="Two devices pairing: both switch sync on, one asks to connect, both show the same six-digit code, the other accepts, and they are connected."
      className="relative"
    >
      <div aria-hidden="true" className="grid grid-cols-1 gap-3 sm:grid-cols-2">
        <Pane
          icon={<WindowsIcon className="h-3.5 w-3.5" />}
          name="OFFICE-PC"
          syncOn={on}
          bodyKey={`pc-${step}`}
        >
          {step === 0 && (
            <Quiet>Switch on to find your other devices on this network.</Quiet>
          )}
          {step === 1 && <Quiet>Looking for devices…</Quiet>}
          {step === 2 && (
            <>
              <GroupLabel>Nearby Devices</GroupLabel>
              <div className="flex items-center justify-between gap-2 rounded-xl bg-white/[0.08] py-2 pl-3 pr-2 text-[0.85rem]">
                Sam’s MacBook
                <FakeButton press>Connect</FakeButton>
              </div>
            </>
          )}
          {step === 3 && (
            <>
              <Quiet>Waiting for “Sam’s MacBook” to accept…</Quiet>
              <Code />
            </>
          )}
          {step === LAST && <Connected peer="Sam’s MacBook" />}
        </Pane>

        <Pane
          icon={<AppleIcon className="h-3.5 w-3.5" />}
          name="Sam’s MacBook"
          syncOn={on}
          bodyKey={`mac-${step === 2 ? 1 : step}`}
        >
          {step === 0 && (
            <Quiet>Switch on to find your other devices on this network.</Quiet>
          )}
          {(step === 1 || step === 2) && <Quiet>Looking for devices…</Quiet>}
          {step === 3 && (
            <>
              <Quiet>
                Accept only if this code is also showing on that device:
              </Quiet>
              <div className="flex flex-wrap items-center justify-between gap-2">
                <Code />
                <FakeButton press>Accept</FakeButton>
              </div>
            </>
          )}
          {step === LAST && <Connected peer="OFFICE-PC" />}
        </Pane>
      </div>

      <div
        aria-hidden="true"
        className="mt-3 flex items-center justify-center gap-2 rounded-full border border-white/10 bg-white/[0.04] px-4 py-2 text-[0.78rem] text-dim"
      >
        <AnimatePresence mode="wait" initial={false}>
          <motion.span
            key={step === LAST ? "encrypted" : "network"}
            initial={{ opacity: 0, y: 6 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -6, transition: { duration: 0.15 } }}
            className="flex items-center gap-2"
          >
            {step === LAST ? (
              <>
                <Lock size={14} className="text-white" />
                Connected directly, encrypted. Nothing leaves your network.
              </>
            ) : (
              <>
                <Wifi size={14} className="text-white" />
                Both devices on the same local network
              </>
            )}
          </motion.span>
        </AnimatePresence>
      </div>
    </div>
  );
}

const STEP_MS = 2600;
const RESULT_MS = 3400;

export function HowItWorks() {
  const ref = useRef<HTMLDivElement>(null);
  const inView = useInView(ref, { amount: 0.35 });
  const reduced = usePrefersReducedMotion();
  const [step, setStep] = useState(0);
  const [auto, setAuto] = useState(true);

  const playing = auto && inView && !reduced;
  useEffect(() => {
    if (!playing) return;
    const timer = setTimeout(
      () => setStep((current) => (current + 1) % (LAST + 1)),
      step === LAST ? RESULT_MS : STEP_MS,
    );
    return () => clearTimeout(timer);
  }, [playing, step]);

  // With reduced motion nothing plays by itself: show the result.
  const shown = reduced && auto ? LAST : step;
  const active = Math.min(shown, STEPS.length - 1);

  return (
    <Section id="how-it-works" labelledBy="how-title">
      <SectionHeading
        id="how-title"
        eyebrow="How it works"
        title="Pair once. Then just copy."
      >
        Sync is off until you switch it on, and no network port is opened
        before then. Pairing takes four steps.
      </SectionHeading>

      <div
        ref={ref}
        className="grid grid-cols-1 items-center gap-6 lg:grid-cols-[minmax(0,5fr)_minmax(0,6fr)] lg:gap-10"
      >
        <Reveal>
          <ol className="flex flex-col gap-2">
            {STEPS.map((item, index) => {
              const current = index === active;
              return (
                <li key={item.title}>
                  <button
                    type="button"
                    aria-current={current ? "step" : undefined}
                    onClick={() => {
                      setAuto(false);
                      setStep(index);
                    }}
                    className={`group relative flex w-full gap-4 overflow-hidden rounded-2xl border p-4 text-left transition duration-300 ease-out-soft ${
                      current
                        ? "border-white/25 bg-white/[0.08]"
                        : "border-transparent hover:border-white/15 hover:bg-white/[0.04]"
                    }`}
                  >
                    <span
                      className={`flex h-8 w-8 shrink-0 items-center justify-center rounded-full border font-mono text-sm transition duration-300 ${
                        current
                          ? "border-white bg-white text-black"
                          : "border-white/25 text-white/70 group-hover:border-white/60 group-hover:text-white"
                      }`}
                    >
                      {index + 1}
                    </span>
                    <span>
                      <span className="block font-medium">{item.title}</span>
                      <span className="mt-1 block text-[0.92rem] leading-relaxed text-dim">
                        {item.body}
                      </span>
                    </span>
                    {current && playing && (
                      <motion.span
                        key={shown}
                        aria-hidden="true"
                        initial={{ scaleX: 0 }}
                        animate={{ scaleX: 1 }}
                        transition={{
                          duration: (shown === LAST ? RESULT_MS : STEP_MS) / 1000,
                          ease: "linear",
                        }}
                        className="absolute inset-x-0 bottom-0 h-px origin-left bg-white/70"
                      />
                    )}
                  </button>
                </li>
              );
            })}
          </ol>
        </Reveal>

        <Reveal delay={0.1}>
          <Card className="p-4 sm:p-5">
            <PairingDemo step={shown} />
          </Card>
          <p className="mt-4 flex items-start gap-2.5 px-1 text-[0.92rem] leading-relaxed text-dim">
            <Network size={17} className="mt-1 shrink-0 text-white" />
            From then on, what you copy on either one is put on the other’s
            clipboard and added to its list. Pair a third device with any
            member of the group and it syncs with all of them.
          </p>
        </Reveal>
      </div>

      <Reveal className="mt-12">
        <h3 className="mb-4 font-mono text-xs uppercase tracking-[0.22em] text-faint">
          Things to know
        </h3>
        <ul className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
          {NOTES.map((note) => (
            <li
              key={note.text}
              className="rounded-2xl border border-white/10 p-4 text-[0.88rem] leading-relaxed text-dim transition-colors duration-300 hover:border-white/25 hover:text-white/85"
            >
              <note.icon size={18} className="mb-3 text-white" />
              {note.text}
            </li>
          ))}
        </ul>
      </Reveal>
    </Section>
  );
}
