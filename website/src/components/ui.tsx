"use client";

import type { PointerEvent, ReactNode } from "react";
import { motion } from "motion/react";

/** Fades and lifts its content into place the first time it is scrolled to. */
export function Reveal({
  children,
  delay = 0,
  className,
}: {
  children: ReactNode;
  delay?: number;
  className?: string;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, y: 26 }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={{ once: true, margin: "0px 0px -12% 0px" }}
      transition={{ duration: 0.7, delay, ease: [0.22, 1, 0.36, 1] }}
      className={className}
    >
      {children}
    </motion.div>
  );
}

/**
 * A glass card whose surface catches the light under the pointer. The glow
 * is one layer that only changes position and opacity.
 */
export function Card({
  children,
  className = "",
  as: Tag = "div",
}: {
  children: ReactNode;
  className?: string;
  as?: "div" | "article" | "li";
}) {
  const onMove = (event: PointerEvent<HTMLElement>) => {
    const rect = event.currentTarget.getBoundingClientRect();
    event.currentTarget.style.setProperty("--mx", `${event.clientX - rect.left}px`);
    event.currentTarget.style.setProperty("--my", `${event.clientY - rect.top}px`);
  };

  return (
    <Tag
      onPointerMove={onMove}
      className={`glass-flat group/card relative overflow-hidden rounded-3xl transition-[border-color,transform] duration-300 ease-out-soft hover:border-white/25 focus-within:border-white/25 ${className}`}
    >
      <span
        aria-hidden="true"
        className="pointer-events-none absolute -left-[220px] -top-[220px] h-[440px] w-[440px] translate-x-[var(--mx,-999px)] translate-y-[var(--my,-999px)] rounded-full bg-[radial-gradient(closest-side,rgb(255_255_255/0.13),transparent)] opacity-0 transition-opacity duration-300 group-hover/card:opacity-100"
      />
      <div className="relative h-full">{children}</div>
    </Tag>
  );
}

export function SectionHeading({
  eyebrow,
  title,
  children,
  id,
}: {
  eyebrow: string;
  title: ReactNode;
  children?: ReactNode;
  id: string;
}) {
  return (
    <Reveal className="mx-auto mb-12 max-w-2xl text-center lg:mb-16">
      <p className="mb-4 font-mono text-xs uppercase tracking-[0.22em] text-faint">
        {eyebrow}
      </p>
      <h2
        id={id}
        className="text-[clamp(1.9rem,4vw,3.1rem)] font-semibold leading-[1.06] tracking-[-0.035em] text-balance"
      >
        {title}
      </h2>
      {children && (
        <p className="mt-5 text-[1.05rem] leading-relaxed text-dim text-pretty">
          {children}
        </p>
      )}
    </Reveal>
  );
}

export function Section({
  id,
  labelledBy,
  children,
  className = "",
}: {
  id: string;
  labelledBy: string;
  children: ReactNode;
  className?: string;
}) {
  return (
    <section
      id={id}
      aria-labelledby={labelledBy}
      className={`relative mx-auto w-full max-w-6xl px-4 py-20 lg:py-28 ${className}`}
    >
      {children}
    </section>
  );
}
