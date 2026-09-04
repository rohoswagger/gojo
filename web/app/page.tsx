import type { Metadata } from "next"
import Image from "next/image"
import Link from "next/link"

import { ClipboardList, FolderOpen, LayoutGrid, Mic, Music, Sunset } from "lucide-react";
import { AutoplayVideo } from "@/components/autoplay-video"
import { GojoFooter } from "@/components/gojo-footer"
import { GojoLogo } from "@/components/gojo-logo"
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
        <header className="site-header site-header-overlay">
          <Link className="brand" href="/" aria-label="Gojo home">
            <GojoLogo />
            Gojo
          </Link>
          <nav className="nav" aria-label="Site">
            <a className="ghost-link" href="#features">
              Features
            </a>
            <a className="ghost-link" href="#buy">
              Pricing
            </a>
            <Link className="ghost-link" href="/blog/">
              Blog
            </Link>
          </nav>
          <Link className="btn btn-primary nav-cta" href="/downloads/">
            Download
          </Link>
        </header>

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
            <a className="btn btn-primary" href="https://downloads.trygojo.com/Gojo.dmg">
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
            </a>
          </div>
          <p className="meta">
            No card, no account &middot; Dictation runs on device &middot; macOS 14 or later
          </p>
        </main>
      </div>

      <section className="utility-convergence" aria-labelledby="convergence-heading">
        <div className="wrap convergence-layout">
          <div className="convergence-copy">
            <h2 id="convergence-heading">The apps this replaces.</h2>
            <p>
              
                
                These jobs usually mean a separate utility each, and a separate menu bar icon,
                settings pane and set of shortcuts to go with it. Gojo does all of them from one
                surface you already have.
              
              
            </p>
          </div>

          <div
            className="convergence-visual"
            role="group"
            aria-label="Gojo combines tools commonly handled by several separate Mac utilities"
          >
            <div className="utility-apps">
              <a className="utility-app" href="https://theboring.name/" target="_blank" rel="noopener">
                <Image src="/assets/utilities/boringnotch.png" width={64} height={64} loading="lazy" alt="" />
                <span>Boring Notch</span>
              </a>
              <a
                className="utility-app"
                href="https://apps.apple.com/us/app/maccy/id1527619437?mt=12"
                target="_blank"
                rel="noopener"
              >
                <Image src="/assets/utilities/maccy.png" width={64} height={64} loading="lazy" alt="" />
                <span>Maccy</span>
              </a>
              <a className="utility-app" href="https://justgetflux.com/" target="_blank" rel="noopener">
                <Image src="/assets/utilities/flux.png" width={64} height={64} loading="lazy" alt="" />
                <span>f.lux</span>
              </a>
              <a className="utility-app" href="https://rectangleapp.com/" target="_blank" rel="noopener">
                <Image src="/assets/utilities/rectangle.png" width={64} height={64} loading="lazy" alt="" />
                <span>Rectangle</span>
              </a>
              <a className="utility-app" href="https://dropoverapp.com/" target="_blank" rel="noopener">
                <Image src="/assets/utilities/dropover.png" width={64} height={64} loading="lazy" alt="" />
                <span>Dropover</span>
              </a>
            </div>
            <div className="convergence-lines" aria-hidden="true">
              <i></i>
              <i></i>
              <i></i>
            </div>
            <div className="gojo-core">
              <GojoLogo />
              <strong>Gojo</strong>
              <span>One native workspace</span>
            </div>
          </div>
          <p className="comparison-note">
            Independent feature comparison. Gojo is not affiliated with or endorsed by the products
            shown.
          </p>
        </div>
      </section>

      <section className="feature-acts" id="features" aria-labelledby="features-heading">
        <div className="wrap">
          <header className="acts-intro">
            <h2 id="features-heading">The six tools.</h2>
            <p>
              
                Everything below is the real app running in the notch. One scroll and you have seen
                all of it.
              
            </p>
          </header>
        </div>

        <article className="act act-flagship" aria-labelledby="act-dictation">
          <div className="wrap act-inner">
            <div className="act-copy">
              <p className="act-index" aria-hidden="true">
                <Mic className="act-icon" strokeWidth={1.75} aria-hidden="true" />Dictation
              </p>
              <h3 id="act-dictation">Dictation that never leaves your Mac.</h3>
              <p>
                Hold one shortcut and speak. The words appear wherever your cursor already is, in
                Mail, Slack, a commit message or a search box.
              </p>
              <p className="act-note">
                Speech recognition runs on a model you download once. No API key, no account, and no
                audio ever leaves your Mac. It works on a plane.
              </p>
              <ul className="act-proof">
                <li>
                  Hold <kbd>⌃</kbd>
                  <kbd>⌥</kbd> to talk, release to insert
                </li>
                <li>Choose your model, or swap it later</li>
                <li>Runs offline, on-device, every time</li>
              </ul>
            </div>
            <figure className="act-shot shot-inset">
              <Image
                src="/screenshots/dictation-models.png"
                width={460}
                height={171}
                alt="Gojo's voice model list: Parakeet Unified from FluidAudio, 614 MB, in use on this Mac, with Parakeet v3 available below it."
              />
              <figcaption>
                Models live on your Mac. You can see exactly which one is doing the work.
              </figcaption>
            </figure>
          </div>
        </article>

        <div className="acts-paper">
          <article className="act" aria-labelledby="act-media">
            <div className="wrap act-inner">
              <div className="act-copy">
                <p className="act-index" aria-hidden="true">
                  <Music className="act-icon" strokeWidth={1.75} aria-hidden="true" />Media
                </p>
                <h3 id="act-media">Your music, out of the way.</h3>
                <p>
                  
                Artwork, title and a scrubber sit in the notch. Skip, shuffle and seek whatever is
                playing without raising a window.
              
                </p>
                <ul className="act-proof">
                  <li>Follows your current media source</li>
                  <li>Reorder the controls you actually use</li>
                </ul>
              </div>
              <figure className="act-shot">
                <Image
                  src="/screenshots/media.png"
                  width={654}
                  height={196}
                  loading="lazy"
                  alt="The notch open on the media tab: album art, the track Sunset Linen by LoFi Serenity, a scrubber, and playback controls, with a Spotify badge on the artwork."
                />
              </figure>
            </div>
          </article>

          <article className="act act-flip" aria-labelledby="act-clipboard">
            <div className="wrap act-inner">
              <div className="act-copy">
                <p className="act-index" aria-hidden="true">
                  <ClipboardList className="act-icon" strokeWidth={1.75} aria-hidden="true" />Clipboard
                </p>
                <h3 id="act-clipboard">Everything you have copied, kept.</h3>
                <p>
                  
                Everything you copy is saved and searchable from the notch. Anything a supported
                password manager marks as private is skipped.
              
                </p>
                <ul className="act-proof">
                  <li>Search without opening another app</li>
                  <li>Passwords and secrets stay out of history</li>
                </ul>
              </div>
              <figure className="act-shot">
                <Image
                  src="/screenshots/clipboard.png"
                  width={694}
                  height={197}
                  loading="lazy"
                  alt="The notch open on the clipboard tab: a search field above a list of recently copied text entries."
                />
              </figure>
            </div>
          </article>

          <article className="act" aria-labelledby="act-windows">
            <div className="wrap act-inner">
              <div className="act-copy">
                <p className="act-index" aria-hidden="true">
                  <LayoutGrid className="act-icon" strokeWidth={1.75} aria-hidden="true" />Windows
                </p>
                <h3 id="act-windows">See a window before you switch to it.</h3>
                <p>
                  
                A switcher that shows you the window before you land on it, and a snap grid with the
                shortcut printed under every layout.
              
                </p>
                <ul className="act-proof">
                  <li>
                    Replaces <kbd>⌘</kbd>
                    <kbd>⇥</kbd> with per-window previews
                  </li>
                  <li>Halves, thirds, maximize, and zoom</li>
                </ul>
              </div>
              <figure className="act-shot">
                <Image
                  src="/screenshots/windows.png"
                  width={661}
                  height={209}
                  loading="lazy"
                  alt="The notch open on the windows tab: a list of open apps, a live preview pane for Ghostty, and a grid of six snap layouts each labelled with its keyboard shortcut."
                />
              </figure>
            </div>
          </article>

          <article className="act act-flip" aria-labelledby="act-shelf">
            <div className="wrap act-inner">
              <div className="act-copy">
                <p className="act-index" aria-hidden="true">
                  <FolderOpen className="act-icon" strokeWidth={1.75} aria-hidden="true" />Shelf
                </p>
                <h3 id="act-shelf">A place to set files down.</h3>
                <p>
                  
                Drag files to the notch and they wait while you move between folders, desktops and apps.
                Drag them back out when you get there, or send them straight to AirDrop.
              
                </p>
                <ul className="act-proof">
                  <li>Survives folder, Space, and app switches</li>
                  <li>AirDrop target built into the shelf</li>
                </ul>
              </div>
              <figure className="act-shot">
                <Image
                  src="/screenshots/shelf.png"
                  width={649}
                  height={196}
                  loading="lazy"
                  alt="The notch open on the shelf tab: an AirDrop drop target beside two staged files waiting to be dragged out."
                />
              </figure>
            </div>
          </article>

          <article className="act act-settings" aria-labelledby="act-display">
            <div className="wrap act-inner">
              <div className="act-copy">
                <p className="act-index" aria-hidden="true">
                  <Sunset className="act-icon" strokeWidth={1.75} aria-hidden="true" />Night Shift
                </p>
                <h3 id="act-display">Warmer screen after dark.</h3>
                <p>
                  
                Night Shift on your own schedule, from the notch instead of System Settings. Sunset
                times are worked out on your Mac from a location you set once.
              
                </p>
                <ul className="act-proof">
                  <li>Starts with your Mac, if you want it to</li>
                  <li>Location is used locally and never sent anywhere</li>
                </ul>
              </div>
              <figure className="act-shot shot-window">
                <Image
                  src="/screenshots/settings-nightshift.png"
                  width={681}
                  height={589}
                  loading="lazy"
                  alt="Gojo's Night Shift settings: enable toggle, a 6500K day status, a notch toggle, start-at-login, and sunrise and sunset times for San Francisco."
                />
              </figure>
            </div>
          </article>
        </div>
      </section>


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
                  <a className="btn btn-monthly" href="https://buy.stripe.com/5kQfZhgUU2gI59o4FMeAg05">
                    Choose subscription
                  </a>
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
                  <a className="btn btn-buy" href="https://buy.stripe.com/fZu5kD3446wY31gb4aeAg04">
                    Get lifetime access
                  </a>
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
                  <a className="btn btn-monthly" href="https://buy.stripe.com/5kQcN5gUU7B245kgoueAg03">
                    Choose subscription
                  </a>
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
                  <a className="btn btn-buy" href="https://buy.stripe.com/9B64gzfQQ7B26ds1tAeAg02">
                    Get lifetime access
                  </a>
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
