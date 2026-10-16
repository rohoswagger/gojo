import type { Metadata } from "next";
import Link from "next/link";
import { GojoFooter } from "@/components/gojo-footer";
import { GojoHeader } from "@/components/gojo-header";

const VERSION = "1.5.1";
const DMG = `https://downloads.trygojo.com/Gojo-${VERSION}.dmg`;
const SIZE = "17 MB";
const MIN_OS = "macOS 14 or later";
// Printed by scripts/release.sh and verified against the published artifact.
const SHA256 =
  "510c5e9d8c3732a1cd8c91925d2c4a15d586d51e5468a985632bd2ada1a3b814";

const TITLE = "Download Gojo for Mac";
const DESCRIPTION =
  "Download Gojo for macOS. Signed and notarized, version 1.5.1, with a full three day trial that needs no account and no card.";

export const metadata: Metadata = {
  title: `${TITLE} | Gojo`,
  description: DESCRIPTION,
  alternates: { canonical: "https://trygojo.com/downloads/" },
  openGraph: {
    title: `${TITLE} | Gojo`,
    description: DESCRIPTION,
    type: "website",
    url: "https://trygojo.com/downloads/",
    images: [{ url: "https://trygojo.com/assets/og.jpg" }],
  },
  twitter: {
    card: "summary_large_image",
    title: `${TITLE} | Gojo`,
    description: DESCRIPTION,
    images: ["https://trygojo.com/assets/og.jpg"],
  },
};

const jsonLd = {
  "@context": "https://schema.org",
  "@type": "SoftwareApplication",
  name: "Gojo",
  operatingSystem: MIN_OS,
  applicationCategory: "UtilitiesApplication",
  softwareVersion: VERSION,
  fileSize: SIZE,
  downloadUrl: DMG,
  installUrl: "https://trygojo.com/downloads/",
  url: "https://trygojo.com",
  offers: {
    "@type": "Offer",
    price: "0",
    priceCurrency: "USD",
    description: "Three day trial, no account and no card required.",
  },
};

const steps = [
  {
    n: "Open the disk image",
    body: `Double click the downloaded Gojo-${VERSION}.dmg to mount it.`,
  },
  {
    n: "Drag Gojo to Applications",
    body: "The window shows Gojo beside your Applications folder. Drag it across.",
  },
  {
    n: "Launch and grant access",
    body: "Onboarding offers optional camera, calendar, and reminder access, then Accessibility and a music source. Accessibility enables window controls, media-key handling, and dictation insertion. Local dictation also needs microphone access and a model download in Settings.",
  },
];

export default function DownloadsPage() {
  return (
    <>
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }}
      />
      <GojoHeader />

      <div className="shell download-shell">
        <main>
          <section className="download-hero">
            <h1>Download Gojo</h1>
            <p className="download-sub">
              One hover from your notch to dictation, windows, clipboard, files,
              media and display controls. Free for three days, no account and no
              card.
            </p>

            <a className="btn btn-primary download-btn" href={DMG} data-funnel-event="download_cta_clicked">
              Download for macOS
            </a>

            <p className="download-spec">
              Version {VERSION} <span aria-hidden="true">&middot;</span> {SIZE}{" "}
              <span aria-hidden="true">&middot;</span> {MIN_OS} <span aria-hidden="true">&middot;</span> Apple Silicon
            </p>

            <ul className="download-trust">
              <li>Developer ID signed and notarized by Apple</li>
              <li>Local dictation runs on device</li>
              <li>Updates through Sparkle</li>
            </ul>
          </section>
        </main>
      </div>

      <main className="download-main">
        <div className="download-body">
          <section aria-labelledby="install-title">
            <h2 id="install-title">Installing</h2>
            <ol className="download-steps">
              {steps.map((s) => (
                <li key={s.n}>
                  <h3>{s.n}</h3>
                  <p>{s.body}</p>
                </li>
              ))}
            </ol>
          </section>

          <section aria-labelledby="verify-title">
            <h2 id="verify-title">Verifying the download</h2>
            <p>
              Gojo is signed with a Developer ID certificate and notarized by
              Apple, so macOS checks it for you before the first launch. To
              confirm the file yourself, compare its checksum.
            </p>
            <pre className="download-code">
              <code>{`shasum -a 256 ~/Downloads/Gojo-${VERSION}.dmg`}</code>
            </pre>
            <p className="download-hash-label">Expected for {VERSION}</p>
            <p className="download-hash">{SHA256}</p>
          </section>

          <section aria-labelledby="after-title">
            <h2 id="after-title">After the trial</h2>
            <p>
              The trial unlocks every feature for three days. Keeping Gojo is a
              one time purchase or a subscription, on one Mac or up to three.
            </p>
            <p className="download-actions">
              <Link className="btn btn-primary" href="/#buy">
                See pricing
              </Link>
              <Link className="download-link" href="/features/">
                Browse the feature library
              </Link>
            </p>
          </section>
        </div>
      </main>

      <GojoFooter />
    </>
  );
}
