import { MotionConfig } from "motion/react";
import { Download } from "@/components/Download";
import { Faq } from "@/components/Faq";
import { Features } from "@/components/Features";
import { ClosingCall, Footer } from "@/components/Footer";
import { Hero } from "@/components/Hero";
import { HowItWorks } from "@/components/HowItWorks";
import { Nav } from "@/components/Nav";
import { Privacy } from "@/components/Privacy";
import { Shortcuts } from "@/components/Shortcuts";

export default function Home() {
  return (
    // "user": with reduced motion switched on, things appear in place
    // instead of moving. The app does the same.
    <MotionConfig reducedMotion="user">
      <a
        href="#how-it-works"
        className="fixed left-3 top-3 z-[60] -translate-y-20 rounded-full bg-white px-4 py-2 text-sm font-semibold text-black transition-transform focus-visible:translate-y-0"
      >
        Skip to content
      </a>
      <Nav />
      <main>
        <Hero />
        <HowItWorks />
        <Features />
        <Download />
        <Privacy />
        <Shortcuts />
        <Faq />
        <ClosingCall />
      </main>
      <Footer />
    </MotionConfig>
  );
}
