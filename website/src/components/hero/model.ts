/**
 * The story the hero tells, as data.
 *
 * Four things are copied in turn (text, a picture, a link, a colour). Each
 * act runs through the same phases: the item is selected and copied on one
 * device, travels to the others, lands in their history, and is pasted on a
 * desktop from the glass panel that drops from the top middle of the screen.
 *
 * The lists never reset. Copying something that is already in the history
 * moves it to the top (the app does the same), so after the fourth act the
 * state is the one the first act started from and the loop has no seam.
 */

export type Kind = "text" | "image" | "link" | "color" | "file" | "email";
export type DeviceId = "win" | "mac" | "phone";
export type DesktopId = "win" | "mac";
export type Layout = "wide" | "compact";

export type Phase =
  | "select"
  | "copy"
  | "travel"
  | "arrive"
  | "open"
  | "paste"
  | "rest";

export interface Item {
  id: string;
  kind: Kind;
  title: string;
  /** Short form for the chip that flies between devices. */
  short: string;
  meta: string;
  /** Which desktop copies it when all three devices are on stage. */
  source: DesktopId;
}

export const DEVICE_NAMES: Record<DeviceId, string> = {
  win: "OFFICE-PC",
  mac: "Sam’s MacBook",
  phone: "Sam’s phone",
};

export const SWATCH = "#FF6B9D";

/** The four acts, in order. Sources alternate between the two desktops. */
export const ACTS: Item[] = [
  {
    id: "text",
    kind: "text",
    title: "Meeting moved to 3 pm, room 4B",
    short: "Meeting moved to 3 pm…",
    meta: "30 characters",
    source: "win",
  },
  {
    id: "image",
    kind: "image",
    title: "Image",
    short: "Image",
    meta: "1920 × 1080",
    source: "mac",
  },
  {
    id: "link",
    kind: "link",
    title: "https://flutter.dev/docs",
    short: "flutter.dev/docs",
    meta: "flutter.dev",
    source: "win",
  },
  {
    id: "color",
    kind: "color",
    title: SWATCH,
    short: SWATCH,
    meta: "Color",
    source: "mac",
  },
];

/** Older entries that sit below the four acts in every history. */
const OLDER: Item[] = [
  {
    id: "file",
    kind: "file",
    title: "summary.pdf",
    short: "summary.pdf",
    meta: "in report",
    source: "win",
  },
  {
    id: "email",
    kind: "email",
    title: "sam@example.com",
    short: "sam@example.com",
    meta: "Email",
    source: "mac",
  },
];

export const ITEMS: Record<string, Item> = Object.fromEntries(
  [...ACTS, ...OLDER].map((item) => [item.id, item]),
);

export const PHASES: Phase[] = [
  "select",
  "copy",
  "travel",
  "arrive",
  "open",
  "paste",
  "rest",
];

/** How long each phase lasts, in milliseconds. One act is 4.9 s. */
export const PHASE_MS: Record<Phase, number> = {
  select: 700,
  copy: 350,
  travel: 800,
  arrive: 500,
  open: 1250,
  paste: 450,
  rest: 850,
};

export interface SceneState {
  act: number;
  phase: Phase;
  lists: Record<DeviceId, string[]>;
}

/**
 * History as it stands after the fourth act: newest first. The file is only
 * on the computer it was copied on, because files are never synced.
 */
const SYNCED_ORDER = ["color", "link", "image", "text", "email"];
const RESTING: Record<DeviceId, string[]> = {
  win: ["color", "link", "image", "text", "file", "email"],
  mac: SYNCED_ORDER,
  phone: SYNCED_ORDER,
};

export const INITIAL_STATE: SceneState = {
  act: 0,
  phase: "select",
  lists: RESTING,
};

const toFront = (list: string[], id: string) => [
  id,
  ...list.filter((entry) => entry !== id),
];

/** The frame shown when motion is reduced: the first act, panel open. */
export const STATIC_STATE: SceneState = {
  act: 0,
  phase: "open",
  lists: {
    win: toFront(RESTING.win, "text"),
    mac: toFront(RESTING.mac, "text"),
    phone: toFront(RESTING.phone, "text"),
  },
};

/** With one desktop on stage, it both copies and opens the panel. */
export function sourceOf(act: number, layout: Layout): DesktopId {
  return layout === "compact" ? "win" : ACTS[act].source;
}

export function targetOf(act: number, layout: Layout): DesktopId {
  if (layout === "compact") return "win";
  return ACTS[act].source === "win" ? "mac" : "win";
}

export function devicesOf(layout: Layout): DeviceId[] {
  return layout === "compact" ? ["win", "phone"] : ["win", "mac", "phone"];
}

const after = (phase: Phase, other: Phase) =>
  PHASES.indexOf(phase) >= PHASES.indexOf(other);

export const isAtOrAfter = after;

export function advance(state: SceneState, layout: Layout): SceneState {
  const index = PHASES.indexOf(state.phase);
  if (index === PHASES.length - 1) {
    return {
      ...state,
      act: (state.act + 1) % ACTS.length,
      phase: "select",
    };
  }

  const phase = PHASES[index + 1];
  const item = ACTS[state.act];
  const source = sourceOf(state.act, layout);
  let lists = state.lists;

  if (phase === "copy") {
    // Copied: the entry is in the history of the device it was copied on.
    lists = { ...lists, [source]: toFront(lists[source], item.id) };
  } else if (phase === "arrive") {
    // Synced: it is now in every other device's history too.
    lists = { ...lists };
    for (const device of devicesOf(layout)) {
      if (device !== source) lists[device] = toFront(lists[device], item.id);
    }
  }

  return { ...state, phase, lists };
}
