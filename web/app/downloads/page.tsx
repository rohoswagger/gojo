import type { Metadata } from "next";
import Link from "next/link";
import { GojoFooter } from "@/components/gojo-footer";
import { GojoHeader } from "@/components/gojo-header";

const DMG = "https://downloads.trygojo.com/Gojo.dmg";
const VERSION = "1.4.0";
const SIZE = "11 MB";
const MIN_OS = "macOS 14 or later";
// Printed by scripts/release.sh and verified against the published artifact.
const SHA256 =
  "9deae91029a1cb07014ed83af3234d184bd4d338e4055e6d0323f53aeb4df58b";

const TITLE = "Download Gojo for Mac";
const DESCRIPTION =
  "Download Gojo for macOS. Signed and notarized, version 1.4.0, with a full three day trial that needs no account and no card.";

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
    body: "Double click the downloaded Gojo.dmg to mount it.",
  },
  {
    n: "Drag Gojo to Applications",
    body: "The window shows Gojo beside your Applications folder. Drag it across.",
  },
  {
    n: "Launch and grant access",
    body: "Gojo asks for Accessibility so it can manage windows and read media keys. Nothing else is requested up front.",
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

            <a className="btn btn-primary download-btn" href={DMG}>
              Download for macOS
            </a>

            <p className="download-spec">
              Version {VERSION} <span aria-hidden="true">&middot;</span> {SIZE}{" "}
              <span aria-hidden="true">&middot;</span> {MIN_OS}
            </p>

            <ul className="download-trust">
              <li>Signed and notarized by Apple</li>
              <li>Dictation runs on device</li>
              <li>Updates install themselves</li>
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
              <code>shasum -a 256 ~/Downloads/Gojo.dmg</code>
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
