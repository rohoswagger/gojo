import type { Metadata } from "next";
import Image from "next/image";
import Link from "next/link";
import { GojoFooter } from "@/components/gojo-footer";
import { GojoHeader } from "@/components/gojo-header";
import { Button } from "@/components/ui/button";
import { GOJO_RELEASE } from "@/lib/release.mjs";

const TITLE = "Download Gojo for Mac";
const DESCRIPTION = `Download Gojo ${GOJO_RELEASE.version} for macOS. Developer ID signed and Apple notarized, with a full three day trial that needs no account and no card.`;

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
  operatingSystem: GOJO_RELEASE.minimumSystemVersion,
  applicationCategory: "UtilitiesApplication",
  softwareVersion: GOJO_RELEASE.version,
  fileSize: `${GOJO_RELEASE.fileSizeBytes} bytes`,
  downloadUrl: GOJO_RELEASE.downloadUrl,
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
    body: `Double click the downloaded ${GOJO_RELEASE.fileName} to mount it.`,
  },
  {
    n: "Drag Gojo to Applications",
    body: "The window shows Gojo beside your Applications folder. Drag it across.",
  },
  {
    n: "Launch and choose permissions",
    body: "Onboarding offers optional camera, calendar, and reminder access, then Accessibility and a music source. Accessibility enables window controls, media-key handling, and dictation insertion. Local dictation also needs microphone access and a model download in Settings.",
  },
];

export default function DownloadsPage() {
  return (
    <div className="marketing-shell download-shell" data-gojo-editorial="warm">
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }}
      />
      <GojoHeader />

      <main id="main-content" tabIndex={-1} className="download-main">
        <section className="download-hero" aria-labelledby="download-title">
          <div className="wrap download-hero-layout">
            <div className="download-hero-copy">
              <h1 id="download-title">Download Gojo</h1>
              <p className="download-sub">
                One hover from your notch to dictation, windows, clipboard, files,
                media and display controls. Free for three days, no account and no
                card.
              </p>

              <Button asChild size="lg" className="btn btn-primary download-btn">
                <a
                  href={GOJO_RELEASE.downloadUrl}
                  data-funnel-event="download_cta_clicked"
                  data-funnel-placement="downloads"
                >
                  Download for macOS
                </a>
              </Button>

              <p className="download-spec">
                Version {GOJO_RELEASE.version} <span aria-hidden="true">&middot;</span>{" "}
                {GOJO_RELEASE.fileSizeLabel} <span aria-hidden="true">&middot;</span>{" "}
                {GOJO_RELEASE.minimumSystemVersion} <span aria-hidden="true">&middot;</span> Apple Silicon
              </p>

              <ul className="download-trust">
                <li>Developer ID signed and Apple notarized</li>
                <li>Local dictation stays on your Mac</li>
                <li>Updates through Sparkle</li>
              </ul>
            </div>
            <figure className="download-product-figure">
              <Image
                src="/screenshots/windows.png"
                width={1322}
                height={418}
                alt="Gojo window controls showing app choices, snap layouts and keyboard shortcuts in the MacBook notch."
                priority
              />
            </figure>
          </div>
        </section>

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
              <code>shasum -a 256 ~/Downloads/{GOJO_RELEASE.fileName}</code>
            </pre>
            <p className="download-hash-label">
              Expected SHA-256 for {GOJO_RELEASE.fileName}
            </p>
            <p className="download-hash">{GOJO_RELEASE.sha256}</p>
          </section>

          <section aria-labelledby="after-title">
            <h2 id="after-title">After the trial</h2>
            <p>
              The trial unlocks every feature for three days. Keeping Gojo is a
              one time purchase or a subscription, on one Mac or up to three.
            </p>
            <p className="download-actions">
              <Button asChild size="lg" className="btn btn-primary">
                <Link href="/#buy">See pricing</Link>
              </Button>
              <Link className="download-link" href="/features/">
                Browse the feature library
              </Link>
            </p>
          </section>
        </div>
      </main>

      <GojoFooter />
    </div>
  );
}
