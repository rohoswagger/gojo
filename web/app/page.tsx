import type { Metadata } from "next"
import Image from "next/image"

import { ClipboardList, FolderOpen, LayoutGrid, Mic, Music, Sunset } from "lucide-react";
import { AutoplayVideo } from "@/components/autoplay-video"
import { GojoFooter } from "@/components/gojo-footer"
import { GojoHeader } from "@/components/gojo-header"
import { FeatureShowcase, FeatureShowcaseCard, FeatureShowcaseMedia, FeatureShowcaseFloat, FeatureShowcaseCaption } from "@/components/feature-showcase"
import { NightShiftComparison } from "@/components/night-shift-comparison"
import { TrackedLink } from "@/components/tracked-link"
import {
  PricingTabsProvider,
  PricingTabList,
  PricingPanels,
  PricingPanel,
} from "@/components/pricing-tabs"

// ---------------------------------------------------------------------------
// Metadata + JSON-LD, reproduced verbatim from the old docs/index.html head.
// The one deliberate change is `softwareVersion`: the source has a stale
// "1.0.0"; the app now ships 1.4.0, so the JSON-LD reflects that.
// ---------------------------------------------------------------------------

export const metadata: Metadata = {
  title: "Gojo - Your Mac, one hover away",
  description:
    "Gojo puts private on-device dictation, windows, clipboard, files, media, and system controls one hover away in your MacBook notch.",
  alternates: {
    canonical: "https://trygojo.com/",
  },
  openGraph: {
    title: "Gojo - Your Mac, one hover away",
    description:
      "Dictate anywhere, move windows, recover copied text, stage files, control music, and more from your MacBook notch.",
    type: "website",
    url: "https://trygojo.com/",
    images: [
      {
        url: "https://trygojo.com/assets/og.jpg",
        width: 1200,
        height: 630,
        alt: "Gojo running as a MacBook notch control surface.",
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    title: "Gojo - Your Mac, one hover away",
    description:
      "Private local dictation and the Mac tools you reach for, together in your MacBook notch.",
    images: ["https://trygojo.com/assets/og.jpg"],
  },
}

const jsonLd = {
  "@context": "https://schema.org",
  "@type": "SoftwareApplication",
  name: "Gojo",
  applicationCategory: "UtilitiesApplication",
  operatingSystem: "macOS 14+",
  description:
    "Gojo is a MacBook productivity hub for private on-device dictation, window management, clipboard history, file staging, media, and system controls.",
  url: "https://trygojo.com/",
  softwareVersion: "1.4.0",
  featureList: [
    "Private on-device voice dictation",
    "Window snapping and management",
    "Clipboard history",
    "Drag-and-drop file shelf",
    "Music and media controls",
    "Display and system controls",
  ],
  offers: [
    {
      "@type": "Offer",
      name: "Gojo Personal Monthly",
      price: "2.99",
      priceCurrency: "USD",
      availability: "https://schema.org/InStock",
      url: "https://trygojo.com/#buy",
    },
    {
      "@type": "Offer",
      name: "Gojo Personal Lifetime",
      price: "9.99",
      priceCurrency: "USD",
      availability: "https://schema.org/InStock",
      url: "https://trygojo.com/#buy",
    },
    {
      "@type": "Offer",
      name: "Gojo Multi-Mac Monthly",
      price: "4.99",
      priceCurrency: "USD",
      availability: "https://schema.org/InStock",
      url: "https://trygojo.com/#buy",
    },
    {
      "@type": "Offer",
      name: "Gojo Multi-Mac Lifetime",
      price: "19.99",
      priceCurrency: "USD",
      availability: "https://schema.org/InStock",
      url: "https://trygojo.com/#buy",
    },
  ],
}

const pricingTabs = [
  { id: "pricing-tab-personal", controls: "pricing-panel-personal", name: "Personal", device: "1 Mac" },
  { id: "pricing-tab-multi", controls: "pricing-panel-multi", name: "Multi-Mac", device: "3 Macs" },
]

export default function Home() {
  return (
    <>
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }}
      />

      <div className="shell hero-shell">
        {/* The header sits inside the hero panel and over the photograph
            rather than on a bar above it. */}
        <GojoHeader overlay home />

        <main className="hero">
          <h1>
            <span className="line">Everything you reach for,</span>
            <span className="line">
              right in the <span className="glow">notch</span>.
            </span>
          </h1>
          <p className="sub">
            Dictation, window snapping, clipboard history, a file shelf, music and screen warmth.
            One surface, always a hover away.
          </p>

          <div className="stage">
            <AutoplayVideo
              className="demo-video"
              src="/assets/demo.mp4"
              poster="/assets/demo-poster.jpg"
            />
          </div>

          <div className="cta">
            <TrackedLink
              className="btn btn-primary"
              href="https://downloads.trygojo.com/Gojo.dmg"
              eventName="download_started"
              eventProperties={{ source: "homepage_hero", app_version: "1.4.0" }}
            >
              <svg width="15" height="15" viewBox="0 0 16 16" fill="none" aria-hidden="true">
                <path
                  d="M8 1v9m0 0L4.5 6.5M8 10l3.5-3.5M2 13h12"
                  stroke="currentColor"
                  strokeWidth="1.6"
                  strokeLinecap="round"
                  strokeLinejoin="round"
                />
              </svg>
              Try it free for 3 days
            </TrackedLink>
          </div>
          <p className="meta">
            No card, no account &middot; Dictation runs on device &middot; macOS 14 or later
          </p>
        </main>
      </div>

      <FeatureShowcase
        id="features"
        className="home-features"
        aria-label="The six tools"
        title="Six tools. One notch."
        description="The everyday jobs you reach for separate apps to do, together in Gojo."
        columns={2}
      >
        <FeatureShowcaseCard id="act-dictation">
          <FeatureShowcaseMedia className="aspect-[8/5]">
            <FeatureShowcaseFloat className="max-w-none">
              <Image
                src="/screenshots/dictation-models.png"
                width={460}
                height={171}
                sizes="(max-width: 639px) 85vw, (max-width: 1279px) 42vw, 530px"
                alt="Gojo’s downloaded dictation models, with Parakeet selected."
              />
            </FeatureShowcaseFloat>
          </FeatureShowcaseMedia>
          <FeatureShowcaseCaption icon={<Mic />} title="Dictation that stays on your Mac.">
            Hold a shortcut, speak, and release to insert your words. Download a local model once and dictate offline in any text field.
          </FeatureShowcaseCaption>
          <TrackedLink className="feature-comparison" href="/blog/local-voice-dictation-mac/" eventName="feature_comparison_clicked" eventProperties={{ feature: "dictation", comparison_type: "native_feature" }}>Compare with Apple Dictation <span aria-hidden="true">→</span></TrackedLink>
        </FeatureShowcaseCard>
        <FeatureShowcaseCard id="act-media">
          <FeatureShowcaseMedia className="aspect-[8/5]">
            <FeatureShowcaseFloat className="max-w-none">
              <Image
                src="/screenshots/media.png"
                width={654}
                height={196}
                sizes="(max-width: 639px) 85vw, (max-width: 1279px) 42vw, 530px"
                alt="Gojo’s media tab showing album artwork, a scrubber and playback controls."
              />
            </FeatureShowcaseFloat>
          </FeatureShowcaseMedia>
          <FeatureShowcaseCaption icon={<Music />} title="Your music, out of the way.">
            Skip, shuffle and seek from the notch without bringing your music app forward. Artwork and playback controls follow what is playing.
          </FeatureShowcaseCaption>
          <TrackedLink className="feature-comparison" href="/alternatives/boring-notch/" eventName="feature_comparison_clicked" eventProperties={{ feature: "media", comparison_type: "competitor" }}>Compare with Boring Notch <span aria-hidden="true">→</span></TrackedLink>
        </FeatureShowcaseCard>
        <FeatureShowcaseCard id="act-clipboard">
          <FeatureShowcaseMedia className="aspect-[8/5]">
            <FeatureShowcaseFloat className="max-w-none">
              <Image
                src="/screenshots/clipboard.png"
                width={694}
                height={197}
                sizes="(max-width: 639px) 85vw, (max-width: 1279px) 42vw, 530px"
                alt="Gojo’s searchable clipboard history."
              />
            </FeatureShowcaseFloat>
          </FeatureShowcaseMedia>
          <FeatureShowcaseCaption icon={<ClipboardList />} title="Find what you copied.">
            Search your clipboard history from the notch. Gojo skips items that supported password managers mark as private.
          </FeatureShowcaseCaption>
          <TrackedLink className="feature-comparison" href="/alternatives/maccy/" eventName="feature_comparison_clicked" eventProperties={{ feature: "clipboard", comparison_type: "competitor" }}>Compare with Maccy <span aria-hidden="true">→</span></TrackedLink>
        </FeatureShowcaseCard>
        <FeatureShowcaseCard id="act-windows">
          <FeatureShowcaseMedia className="aspect-[8/5]">
            <FeatureShowcaseFloat className="max-w-none">
              <Image
                src="/screenshots/windows.png"
                width={661}
                height={209}
                sizes="(max-width: 639px) 85vw, (max-width: 1279px) 42vw, 530px"
                alt="Gojo’s window previews and keyboard-labelled snap layouts."
              />
            </FeatureShowcaseFloat>
          </FeatureShowcaseMedia>
          <FeatureShowcaseCaption icon={<LayoutGrid />} title="See it. Switch to it. Snap it.">
            Preview a window before switching, then snap it into halves, thirds or a full-screen layout. Each layout shows its keyboard shortcut.
          </FeatureShowcaseCaption>
          <TrackedLink className="feature-comparison" href="/alternatives/rectangle/" eventName="feature_comparison_clicked" eventProperties={{ feature: "windows", comparison_type: "competitor" }}>Compare with Rectangle <span aria-hidden="true">→</span></TrackedLink>
        </FeatureShowcaseCard>
        <FeatureShowcaseCard id="act-shelf">
          <FeatureShowcaseMedia className="aspect-[8/5]">
            <FeatureShowcaseFloat className="max-w-none">
              <Image
                src="/screenshots/shelf.png"
                width={649}
                height={196}
                sizes="(max-width: 639px) 85vw, (max-width: 1279px) 42vw, 530px"
                alt="Gojo’s file shelf with staged files and an AirDrop target."
              />
            </FeatureShowcaseFloat>
          </FeatureShowcaseMedia>
          <FeatureShowcaseCaption icon={<FolderOpen />} title="A place to set files down.">
            Drag files to the notch while you move between folders, desktops and apps. Drop them into their destination or send them with AirDrop.
          </FeatureShowcaseCaption>
          <TrackedLink className="feature-comparison" href="/blog/best-file-shelf-apps-mac/" eventName="feature_comparison_clicked" eventProperties={{ feature: "file_shelf", comparison_type: "competitor" }}>Compare with Dropover <span aria-hidden="true">→</span></TrackedLink>
        </FeatureShowcaseCard>
        <FeatureShowcaseCard id="act-display">
          <FeatureShowcaseMedia className="aspect-[8/5]">
            <FeatureShowcaseFloat className="home-display-float max-w-[11rem] sm:max-w-[17rem]">
              <NightShiftComparison />
            </FeatureShowcaseFloat>
          </FeatureShowcaseMedia>
          <FeatureShowcaseCaption icon={<Sunset />} title="Warmer screen after dark.">
            Set your screen warmth from the notch and let it follow your schedule. Sunset times are calculated on your Mac using the location you choose.
          </FeatureShowcaseCaption>
          <TrackedLink className="feature-comparison" href="/alternatives/flux/" eventName="feature_comparison_clicked" eventProperties={{ feature: "display", comparison_type: "competitor" }}>Compare with f.lux <span aria-hidden="true">→</span></TrackedLink>
        </FeatureShowcaseCard>
      </FeatureShowcase>

      <section className="customize-story" aria-labelledby="customize-heading">
        <div className="wrap customize-layout">
          <div className="customize-copy">
            <h2 id="customize-heading">Make it yours.</h2>
            <p>
              
                
                Use all six or use one. Turn off what you do not need and reorder the rest, and the
                notch stops showing it, tabs included.
              
              
            </p>
          </div>

          <div className="customize-extras">
            <p className="extras-lede">Also in the notch, if you switch them on:</p>
            <ul className="extras-list">
              <li>
                Spotlight-replacement search on <kbd>⌥</kbd>
                <kbd>Space</kbd>
              </li>
              <li>Calendar and next-event glance</li>
              <li>Battery and charge state</li>
              <li>Camera mirror for checking your framing</li>
              <li>Shortcuts you already built</li>
              <li>Brightness and volume HUDs</li>
            </ul>
          </div>
        </div>
      </section>

      <section className="content-band" id="buy" aria-labelledby="buy-heading">
        <div className="wrap">
          <PricingTabsProvider tabs={pricingTabs}>
            <div className="buy-head">
              <h2 id="buy-heading">Pricing</h2>
              <p className="buy-sub">
                
                One Mac or up to three. Every plan includes the full app and all future updates.
              
              </p>
              <PricingTabList ariaLabel="Choose a device plan" />
            </div>

            <PricingPanels>
              <PricingPanel
                id="pricing-panel-personal"
                labelledBy="pricing-tab-personal"
                controlledBy="pricing-tab-personal"
              >
                <div className="plan plan-monthly">
                  <span className="plan-tag plan-tag-monthly">Pay monthly</span>
                  <div className="plan-name">Subscription</div>
                  <div className="plan-figure">
                    <span className="plan-amount alt">$2.99</span>
                    <span className="plan-per">/ month</span>
                  </div>
                  <p className="plan-copy">
                    Stay flexible with full access on one Mac. Cancel anytime.
                  </p>
                  <TrackedLink className="btn btn-monthly" href="https://buy.stripe.com/5kQfZhgUU2gI59o4FMeAg05" eventName="checkout_started" eventProperties={{ billing_period: "monthly", license_scope: "personal", price_usd: 2.99 }}>
                    Choose subscription
                  </TrackedLink>
                </div>

                <div className="plan plan-lifetime">
                  <span className="plan-tag">Best value &middot; Save 33%</span>
                  <div className="plan-name">Lifetime</div>
                  <div className="plan-figure">
                    <span className="sr-only">Originally $14.99, now $9.99 one time</span>
                    <span className="plan-original" aria-hidden="true">
                      $14.99
                    </span>
                    <span className="plan-amount" aria-hidden="true">
                      $9.99
                    </span>
                    <span className="plan-per" aria-hidden="true">
                      one time
                    </span>
                  </div>
                  <p className="plan-copy">
                    Pay once and keep Gojo on one Mac, including future updates.
                  </p>
                  <TrackedLink className="btn btn-buy" href="https://buy.stripe.com/fZu5kD3446wY31gb4aeAg04" eventName="checkout_started" eventProperties={{ billing_period: "lifetime", license_scope: "personal", price_usd: 9.99 }}>
                    Get lifetime access
                  </TrackedLink>
                </div>
              </PricingPanel>

              <PricingPanel
                id="pricing-panel-multi"
                labelledBy="pricing-tab-multi"
                controlledBy="pricing-tab-multi"
              >
                <div className="plan plan-monthly">
                  <span className="plan-tag plan-tag-monthly">Pay monthly</span>
                  <div className="plan-name">Subscription</div>
                  <div className="plan-figure">
                    <span className="plan-amount alt">$4.99</span>
                    <span className="plan-per">/ month</span>
                  </div>
                  <p className="plan-copy">
                    Stay flexible across up to three Macs. Cancel anytime.
                  </p>
                  <TrackedLink className="btn btn-monthly" href="https://buy.stripe.com/5kQcN5gUU7B245kgoueAg03" eventName="checkout_started" eventProperties={{ billing_period: "monthly", license_scope: "multi_mac", price_usd: 4.99 }}>
                    Choose subscription
                  </TrackedLink>
                </div>

                <div className="plan plan-lifetime">
                  <span className="plan-tag">Best value &middot; Save 20%</span>
                  <div className="plan-name">Lifetime</div>
                  <div className="plan-figure">
                    <span className="sr-only">Originally $24.99, now $19.99 one time</span>
                    <span className="plan-original" aria-hidden="true">
                      $24.99
                    </span>
                    <span className="plan-amount" aria-hidden="true">
                      $19.99
                    </span>
                    <span className="plan-per" aria-hidden="true">
                      one time
                    </span>
                  </div>
                  <p className="plan-copy">
                    Pay once. Keep every feature and future update on up to three Macs.
                  </p>
                  <TrackedLink className="btn btn-buy" href="https://buy.stripe.com/9B64gzfQQ7B26ds1tAeAg02" eventName="checkout_started" eventProperties={{ billing_period: "lifetime", license_scope: "multi_mac", price_usd: 19.99 }}>
                    Get lifetime access
                  </TrackedLink>
                </div>
              </PricingPanel>
            </PricingPanels>
          </PricingTabsProvider>
        </div>
      </section>

      <GojoFooter />
    </>
  )
}
