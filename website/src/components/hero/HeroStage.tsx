"use client";

import { useState } from "react";
import { Pause, Play } from "lucide-react";
import { Scene } from "./Scene";

/**
 * The animated scene, in the layout that suits the screen, with a control to
 * stop it. Both layouts are in the page and CSS shows one, so the first paint
 * is right before any script runs; only the visible one keeps time.
 */
export function HeroStage() {
  const [paused, setPaused] = useState(false);

  return (
    <div className="relative h-full w-full">
      <div
        role="img"
        aria-label="Animation: text, a picture, a link and a colour are copied on a Windows laptop and a Mac in turn. Each one travels to the other devices, appears in their clipboard history, and is pasted from the glass panel that drops from the top middle of the screen. An Android phone receives every entry in its list."
        className="absolute inset-0"
      >
        <div aria-hidden="true" className="absolute inset-0 hidden lg:block">
          <Scene layout="wide" paused={paused} />
        </div>
        <div aria-hidden="true" className="absolute inset-0 lg:hidden">
          <Scene layout="compact" paused={paused} />
        </div>
      </div>

      <button
        type="button"
        onClick={() => setPaused((value) => !value)}
        aria-pressed={paused}
        aria-label={paused ? "Play the animation" : "Pause the animation"}
        title={paused ? "Play the animation" : "Pause the animation"}
        className="absolute right-0 top-0 flex h-8 w-8 items-center justify-center rounded-full border border-white/15 bg-white/[0.06] text-white/70 transition duration-200 hover:border-white/40 hover:bg-white/[0.14] hover:text-white active:scale-90 motion-reduce:hidden lg:top-auto lg:bottom-0"
      >
        {paused ? <Play size={13} /> : <Pause size={13} />}
      </button>
    </div>
  );
}
