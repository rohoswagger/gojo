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
  ["Release", "Version 1.5.1", "Current public build"],
  ["Compatibility", "macOS 14 or later", "Native Apple Silicon app"],
  ["Trial", "Three days", "No account or card"],
  ["Distribution", "Direct download", "Signed and notarized"],
]

const reviewChecks = [
  {
    label: "Start with the wedge",
    title: "Dictate into a real app",
    body: "Use on-device dictation in Notes, an editor, or another ordinary text field.",
  },
  {
    label: "Test the promise",
    title: "Take it offline",
    body: "Repeat the dictation test with Wi-Fi disabled to verify the local workflow.",
  },
  {
    label: "Explore the surface",
    title: "Try a second tool",
    body: "Use window snapping, clipboard history, or the drag-and-drop file shelf from the notch.",
  },
  {
    label: "Check the permission",
    title: "Review Accessibility",
    body: "Check the Accessibility request against window management, media-key handling, the global dictation shortcut, and inserting dictated text into other apps.",
  },
]

export default function PressPage() {
  return (
    <div className="article-shell press-page" data-gojo-editorial="warm">
      <div className="press-top">
        <GojoHeader overlay />
        <section className="press-hero" aria-labelledby="press-title">
          <div className="press-hero-copy">
            <p className="press-eyebrow">Gojo reviewer kit</p>
            <h1 id="press-title">Everything you need to test Gojo.</h1>
            <p className="press-lede">
              Product facts, assets, pricing, and a practical review path for the Mac app that
              puts private dictation and everyday tools in the notch.
            </p>
            <div className="press-actions">
              <a className="btn btn-primary" href="https://downloads.trygojo.com/Gojo.dmg">
                Download the trial
              </a>
              <a className="press-ghost-action" href="/assets/demo.mp4">
                Watch the demo <span aria-hidden="true">↗</span>
              </a>
            </div>
            <p className="press-trust">No card · No account · Dictation runs on device</p>
          </div>

          <figure className="press-demo">
            <div className="press-demo-bar" aria-hidden="true">
              <span />
              <span />
              <span />
              <b>Gojo in the notch</b>
            </div>
            <video controls playsInline preload="metadata" poster="/assets/demo-poster.jpg">
              <source src="/assets/demo.mp4" type="video/mp4" />
            </video>
            <figcaption>The shipping app, not a product mockup.</figcaption>
          </figure>
        </section>
      </div>

      <main className="press-content">
        <section className="press-facts" aria-label="Product facts">
          {facts.map(([label, value, note], index) => (
            <article key={label}>
              <span className="press-fact-number" aria-hidden="true">
                0{index + 1}
              </span>
              <p>{label}</p>
              <strong>{value}</strong>
              <small>{note}</small>
            </article>
          ))}
        </section>

        <section className="press-story" aria-labelledby="what-it-does">
          <div className="press-section-heading">
            <p className="press-kicker">The short version</p>
            <h2 id="what-it-does">One notch. Six daily tools.</h2>
          </div>
          <div className="press-story-copy">
            <p>
              On-device dictation processes audio locally and types into the active text field.
              Gojo also includes window snapping, clipboard history, a drag-and-drop file shelf,
              music controls, and display tools. Optional connected services are separate features
              a user chooses to enable.
            </p>
            <aside className="press-copy-block" aria-label="Copy-ready product description">
              <span>Copy-ready description</span>
              <p>
                “Gojo is a native macOS 14+ app that puts on-device dictation, window controls,
                clipboard history, file staging, media, and display tools in the MacBook notch.”
              </p>
            </aside>
          </div>
        </section>

        <section className="press-review" aria-labelledby="review-title">
          <div className="press-section-heading">
            <p className="press-kicker">A useful review</p>
            <h2 id="review-title">Four tests that reveal the product.</h2>
            <p>About fifteen minutes, one ordinary text field, and an optional offline pass.</p>
          </div>
          <ol className="press-review-grid">
            {reviewChecks.map((check, index) => (
              <li key={check.title}>
                <span className="press-review-number">0{index + 1}</span>
                <div>
                  <p>{check.label}</p>
                  <h3>{check.title}</h3>
                  <span>{check.body}</span>
                </div>
              </li>
            ))}
          </ol>
        </section>

        <section className="press-assets" aria-labelledby="assets-title">
          <div className="press-section-heading">
            <p className="press-kicker">Ready to use</p>
            <h2 id="assets-title">Assets and source material.</h2>
          </div>
          <div className="press-assets-grid">
            <a
              className="press-image-asset"
              href="/assets/og.jpg"
              download="gojo-product-preview.jpg"
            >
              <Image
                src="/assets/og.jpg"
                width={1200}
                height={630}
                alt="Gojo product preview"
              />
              <span>
                <strong>Product image</strong>
                1200 × 630 JPG <b aria-hidden="true">↓</b>
              </span>
            </a>
            <div className="press-link-list">
              <a href="/assets/demo.mp4">
                <span>Product demo video</span>
                <b aria-hidden="true">↗</b>
              </a>
              <a href="https://downloads.trygojo.com/Gojo.dmg">
                <span>Current signed download</span>
                <b aria-hidden="true">↓</b>
              </a>
              <a href="/privacy/">
                <span>Privacy policy</span>
                <b aria-hidden="true">→</b>
              </a>
              <a href="https://github.com/rohoswagger/gojo">
                <span>GPLv3 source code</span>
                <b aria-hidden="true">↗</b>
              </a>
            </div>
          </div>
        </section>

        <section className="press-pricing" aria-labelledby="pricing-title">
          <div>
            <p className="press-kicker">Pricing at a glance</p>
            <h2 id="pricing-title">Monthly or lifetime. One Mac or three.</h2>
          </div>
          <div>
            <p>
              Personal access for one Mac is $2.99 monthly or an introductory $9.99 lifetime
              purchase, regularly $14.99. Multi-Mac access for up to three Macs is $4.99 monthly or
              an introductory $19.99 lifetime purchase, regularly $24.99.
            </p>
            <Link href="/#buy">Check current pricing <span aria-hidden="true">→</span></Link>
          </div>
        </section>

        <p className="press-disclosure">
          This kit is published by Gojo for factual reference. Reviewers should test the product
          independently and disclose any material relationship under their publication and
          platform rules.
        </p>
      </main>

      <GojoFooter />
    </div>
  )
}
