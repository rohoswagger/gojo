import { no, text, unknown, yes } from "@/components/comparison-table"
import type { Cell, ComparisonRow } from "@/components/comparison-table"
import type { Alternative } from "./alternatives"

type Published = {
  checkedNote?: string
  notch?: Cell
  price?: Cell
  trial?: Cell
  minOs?: Cell
  devices?: Cell
  openSource?: Cell
}

const PUBLISHED: Record<string, Published> = {
  droppy: {
    notch: yes("their words: turns the notch into a productivity hub"),
    price: text("$9.99 one-time"),
    minOs: text("macOS 14 or later"),
    devices: text("Two per licence"),
  },
  notchnook: {
    notch: yes("also runs on notchless screens"),
    price: text("$3/month or $25 one-time"),
    minOs: text("macOS 14.6 or later"),
    devices: text("Two on subscription, five one-time"),
  },
  alcove: {
    notch: yes("their words: Dynamic Island for your Mac"),
    price: text("$14.99 one-time"),
    trial: text("72 hours, 14-day refund"),
  },
  dynamiclake: {
    notch: yes("Dynamic Island-style layer"),
  },
  "boring-notch": {
    notch: yes(),
    price: text("Free"),
    openSource: yes(),
  },
  rectangle: {
    notch: no("not a notch workspace"),
    price: text("Free and open source"),
    trial: text("10 days on Rectangle Pro"),
    minOs: text("macOS 10.15 or later"),
    devices: text("Three devices on Rectangle Pro"),
    openSource: yes(),
  },
  maccy: {
    notch: no("focused on clipboard, not the notch"),
    minOs: text("macOS 14 or later"),
    openSource: yes("MIT"),
  },
  raycast: {
    checkedNote: "Pro pricing and trial rechecked against the official billing manual on 2026-10-16.",
    notch: no("not built around a notch interaction"),
    price: text("Free; Pro from $8/month billed annually"),
    trial: text("7 days on Pro"),
  },
  bettertouchtool: {
    // Their page lists a notch drop zone, so this is not a flat "no".
    notch: text("Has a notch drop zone feature"),
    trial: text("45 days"),
  },
  alttab: {
    checkedNote: "Core/Pro pricing and the Pro trial rechecked against the official FAQ on 2026-10-16.",
    notch: no("not a notch workspace"),
    price: text("Free core; Pro from $9.99 one-time"),
    trial: text("14 days on Pro features"),
    openSource: yes(),
  },
  flux: {
    notch: no("not a notch workspace"),
  },
  "karabiner-elements": {
    notch: no("not a notch utility"),
    price: text("Free"),
    openSource: yes(),
  },
}

export function comparisonRows(alternative: Alternative): ComparisonRow[] {
  const pub = PUBLISHED[alternative.slug] ?? {}

  return [
    {
      label: "Product shape",
      gojo: text("Notch workspace with several utilities"),
      alt: text(sentenceCase(alternative.category)),
    },
    {
      label: "Best for",
      gojo: text(sentenceCase(alternative.gojoFit)),
      alt: text(sentenceCase(alternative.bestFor)),
    },
    {
      label: "Lives in the MacBook notch",
      note: "A hoverable surface at the top of the screen",
      gojo: yes(),
      alt: pub.notch ?? unknown,
    },
    {
      label: "Price",
      gojo: text("$9.99 once or $2.99/month, one Mac"),
      alt: pub.price ?? unknown,
    },
    {
      label: "Free trial",
      gojo: text("3 days, no account or card"),
      alt: pub.trial ?? unknown,
    },
    {
      label: "Minimum macOS",
      gojo: text("macOS 14 or later"),
      alt: pub.minOs ?? unknown,
    },
    {
      label: "Macs per licence",
      gojo: text("One, or three on the Multi-Mac plan"),
      alt: pub.devices ?? unknown,
    },
    {
      label: "Open source",
      gojo: yes("GPLv3"),
      alt: pub.openSource ?? unknown,
    },
  ]
}

export function comparisonFootnote(alternative: Alternative, updated: string) {
  const checkedNote = PUBLISHED[alternative.slug]?.checkedNote
  const rechecked = checkedNote ? ` ${checkedNote}` : ""
  return `The ${alternative.name} column is taken from its developer’s own product page, checked ${updated}. “Not published” means the detail was not stated there — not that the feature is missing. Prices and requirements change, so verify before buying.${rechecked}`
}

function sentenceCase(s: string) {
  return s.charAt(0).toUpperCase() + s.slice(1)
}
