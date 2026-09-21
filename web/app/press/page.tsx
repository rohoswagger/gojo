import type { Metadata } from "next"
import Image from "next/image"
import Link from "next/link"

import { GojoFooter } from "@/components/gojo-footer"
import { GojoHeader } from "@/components/gojo-header"

export const metadata: Metadata = {
  title: "Press and reviewer kit | Gojo",
  description:
    "Verified Gojo product facts, review guidance, downloadable assets, pricing, and trial links for journalists and Mac-app creators.",
  alternates: { canonical: "https://trygojo.com/press/" },
  openGraph: {
    title: "Gojo press and reviewer kit",
    description:
      "Product facts, assets, pricing, and a practical review checklist for Gojo, a native MacBook-notch productivity app.",
    type: "website",
    url: "https://trygojo.com/press/",
    images: [{ url: "https://trygojo.com/assets/og.jpg" }],
  },
}

const facts = [
  ["Current release", "Version 1.5.1"],
  ["Compatibility", "macOS 14 or later"],
  ["Trial", "Three-day trial, no account or card"],
  ["Distribution", "Signed and notarized direct download"],
]

const reviewChecks = [
  "Use on-device dictation in Notes, an editor, or another ordinary text field.",
  "Repeat the dictation test with Wi-Fi disabled to verify the local workflow.",
  "Try a second tool such as window snapping, clipboard history, or the file shelf.",
  "Check the Accessibility request against window management, media-key handling, the global dictation shortcut, and inserting dictated text into other apps.",
]

export default function PressPage() {
  return (
    <>
      <GojoHeader />

      <main className="mx-auto max-w-5xl px-6 py-16 sm:py-24">
        <section className="max-w-3xl">
          <p className="mb-4 text-sm font-semibold uppercase tracking-[0.18em] text-brand-content">
            Gojo reviewer kit
          </p>
          <h1 className="text-4xl font-semibold tracking-tight sm:text-6xl">
            Everything needed to test and cover Gojo.
          </h1>
          <p className="mt-6 max-w-2xl text-lg leading-8 text-muted-foreground">
            Gojo is a native Mac app that puts private dictation and everyday productivity tools
            in the MacBook notch. This page keeps the product facts, assets, pricing, and review
            workflow in one place.
          </p>
          <div className="mt-8 flex flex-wrap gap-3">
            <a className="btn btn-primary" href="https://downloads.trygojo.com/Gojo.dmg">
              Download the trial
            </a>
            <a className="btn" href="/assets/demo.mp4">
              Watch the demo
            </a>
          </div>
        </section>

        <section className="mt-16 grid gap-4 sm:grid-cols-2" aria-label="Product facts">
          {facts.map(([label, value]) => (
            <article key={label} className="rounded-3xl border border-black/10 bg-black/[0.025] p-6">
              <p className="text-sm font-medium text-muted-foreground">{label}</p>
              <p className="mt-2 text-xl font-semibold">{value}</p>
            </article>
          ))}
        </section>

        <section className="mt-20 grid gap-10 lg:grid-cols-[1.05fr_0.95fr] lg:items-center">
          <div>
            <h2 className="text-3xl font-semibold tracking-tight">What it does</h2>
            <p className="mt-5 leading-7 text-muted-foreground">
              On-device dictation processes audio locally and types into the active text field.
              Gojo also includes window snapping, clipboard history, a drag-and-drop file shelf,
              music controls, and display tools. Optional connected services are separate features
              a user chooses to enable.
            </p>
            <p className="mt-5 leading-7 text-muted-foreground">
              Copy-ready description: “Gojo is a native macOS 14+ app that puts on-device
              dictation, window controls, clipboard history, file staging, media, and display
              tools in the MacBook notch.”
            </p>
          </div>
          <video
            className="w-full rounded-3xl border border-black/10 shadow-xl"
            controls
            playsInline
            preload="metadata"
            poster="/assets/demo-poster.jpg"
          >
            <source src="/assets/demo.mp4" type="video/mp4" />
          </video>
        </section>

        <section className="mt-20">
          <h2 className="text-3xl font-semibold tracking-tight">A practical review</h2>
          <ol className="mt-6 grid gap-4 sm:grid-cols-2">
            {reviewChecks.map((check, index) => (
              <li key={check} className="rounded-3xl border border-black/10 p-6 leading-7">
                <span className="mb-3 block text-sm font-semibold text-brand-content">
                  Test {index + 1}
                </span>
                {check}
              </li>
            ))}
          </ol>
        </section>

        <section className="mt-20">
          <h2 className="text-3xl font-semibold tracking-tight">Assets</h2>
          <div className="mt-6 grid gap-6 md:grid-cols-2">
            <a
              className="group rounded-3xl border border-black/10 p-5"
              href="/assets/og.jpg"
              download="gojo-product-preview.jpg"
            >
              <Image
                className="rounded-2xl"
                src="/assets/og.jpg"
                width={1200}
                height={630}
                alt="Gojo product preview"
              />
              <span className="mt-4 block font-semibold group-hover:underline">
                Download the 1200 × 630 product image
              </span>
            </a>
            <div className="rounded-3xl border border-black/10 p-6">
              <h3 className="text-xl font-semibold">Product links</h3>
              <ul className="mt-4 space-y-3 leading-7">
                <li><a className="underline" href="/assets/demo.mp4">Product demo video</a></li>
                <li><a className="underline" href="https://downloads.trygojo.com/Gojo.dmg">Current signed download</a></li>
                <li><a className="underline" href="/privacy/">Privacy policy</a></li>
                <li><a className="underline" href="https://github.com/rohoswagger/gojo">GPLv3 source code</a></li>
              </ul>
            </div>
          </div>
        </section>

        <section className="mt-20 rounded-3xl bg-black p-8 text-white sm:p-10">
          <h2 className="text-3xl font-semibold tracking-tight">Pricing at a glance</h2>
          <p className="mt-4 max-w-3xl leading-7 text-white/75">
            Personal access for one Mac is $2.99 monthly or an introductory $9.99 lifetime
            purchase, regularly $14.99. Multi-Mac access for up to three Macs is $4.99 monthly or
            an introductory $19.99 lifetime purchase, regularly $24.99. Reviewers should confirm
            the live pricing page before publication.
          </p>
          <Link className="mt-6 inline-block font-semibold underline" href="/#buy">
            Check current pricing
          </Link>
        </section>

        <p className="mt-10 text-sm leading-6 text-muted-foreground">
          This kit is published by Gojo for factual reference. Reviewers should test the product
          independently and disclose any material relationship under their publication and
          platform rules.
        </p>
      </main>

      <GojoFooter />
    </>
  )
}
