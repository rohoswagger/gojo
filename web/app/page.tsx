import type { Metadata } from "next"
import Link from "next/link"

import { ClipboardList, FolderOpen, LayoutGrid, Mic, Music, Sunset } from "lucide-react";
import { AutoplayVideo } from "@/components/autoplay-video"
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

/** The Gojo mark. Reused in the header, the footer, and the utility-convergence diagram. */
function GojoLogo() {
  return (
    <svg viewBox="0 0 256 172.29" fill="currentColor" aria-hidden="true">
      <path
        fillRule="evenodd"
        d="M 130.53 162.06 C 165.62 159.7 195.71 134.68 195.71 134.68 C 246 84.7 246 84.64 245.03 83.6 C 244 82.5 218.71 57.19 217.83 57.52 C 217 57.8 168.66 106.43 166.92 107.91 C 152 120 134.68 122.36 134.68 122.36 C 110 124 88.69 110.52 88.69 110.52 C 82 105 81.57 104.46 81.57 104.46 C 78 101 72.78 101.1 72.78 101.1 C 68 101.5 45.4 123.25 45.4 123.25 C 45.4 123.58 67 144 67.47 143.49 C 90 162 130.53 162.06 130.53 162.06 Z M 37.83 114.87 C 38 115 86.54 66.41 86.54 66.41 C 102 51 132.1 49.61 132.1 49.61 C 165 51.5 169.68 64.16 169.68 64.16 C 182 75 185.76 71.15 185.76 71.15 C 192 69 209.8 49.54 209.8 49.54 C 210 49 208.27 46.9 208.27 46.9 C 204 43 168.13 17.81 168.13 17.81 C 130 -2 86.5 16.02 86.5 16.02 C 50 33 10.17 87.44 10.17 87.44 C 10 88 37.83 114.87 37.83 114.87 Z"
      />
    </svg>
  )
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

      <div className="shell">
        <header className="site-header">
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
            <Link className="ghost-link" href="/downloads/">
              Download
            </Link>
          </nav>
        </header>

        <main className="hero">
          <h1>
            <span className="line">The space around your notch</span>
            <span className="line">
              is doing <span className="glow">nothing</span>.
            </span>
          </h1>
          <p className="sub">
            Hover it and six tools appear. Dictation, windows, clipboard, files, music and screen
            warmth, all without a window opening or another icon in your menu bar.
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
            <h2 id="convergence-heading">One app instead of four.</h2>
            <p>
              Most people end up running a window manager, a clipboard tool, a launcher and a
                screen tinter, each with its own menu bar icon and its own shortcuts. Gojo does
                those jobs in one place you already have.
            </p>
          </div>

          <div
            className="convergence-visual"
            role="group"
            aria-label="Gojo combines tools commonly handled by several separate Mac utilities"
          >
            <div className="utility-apps">
              <a className="utility-app" href="https://theboring.name/" target="_blank" rel="noopener">
                <img src="/assets/utilities/boringnotch.png" width={64} height={64} loading="lazy" alt="" />
                <span>Boring Notch</span>
              </a>
              <a
                className="utility-app"
                href="https://apps.apple.com/us/app/maccy/id1527619437?mt=12"
                target="_blank"
                rel="noopener"
              >
                <img src="/assets/utilities/maccy.png" width={64} height={64} loading="lazy" alt="" />
                <span>Maccy</span>
              </a>
              <a className="utility-app" href="https://justgetflux.com/" target="_blank" rel="noopener">
                <img src="/assets/utilities/flux.png" width={64} height={64} loading="lazy" alt="" />
                <span>f.lux</span>
              </a>
              <a className="utility-app" href="https://rectangleapp.com/" target="_blank" rel="noopener">
                <img src="/assets/utilities/rectangle.png" width={64} height={64} loading="lazy" alt="" />
                <span>Rectangle</span>
              </a>
              <a className="utility-app" href="https://dropoverapp.com/" target="_blank" rel="noopener">
                <img src="/assets/utilities/dropover.png" width={64} height={64} loading="lazy" alt="" />
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
            <h2 id="features-heading">Here is all of it.</h2>
            <p>
              No mockups below. This is the app running in the space around the notch, and it is
              the whole product. One scroll and you have seen everything.
            </p>
          </header>
        </div>

        <article className="act act-flagship" aria-labelledby="act-dictation">
          <div className="wrap act-inner">
            <div className="act-copy">
              <p className="act-index" aria-hidden="true">
                <Mic className="act-icon" strokeWidth={1.75} aria-hidden="true" />Dictation
              </p>
              <h3 id="act-dictation">Talk. Gojo types. Nothing leaves your Mac.</h3>
              <p>
                Hold one shortcut and talk into whatever field you are already in. Mail, Slack, a
                commit message, a search box. The words land where your cursor is.
              </p>
              <p className="act-note">
                Recognition runs on a model you download once and keep. No API key, no account, no
                audio leaving the machine, and it still works on a plane.
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
              <img
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
                <h3 id="act-media">Your music, without covering your work.</h3>
                <p>
                  Artwork, title, and a scrubber sit in the notch. Skip, shuffle, and seek from
                  whatever app is playing, without raising a single window.
                </p>
                <ul className="act-proof">
                  <li>Follows your current media source</li>
                  <li>Reorder the controls you actually use</li>
                </ul>
              </div>
              <figure className="act-shot">
                <img
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
                <h3 id="act-clipboard">The thing you copied five minutes ago.</h3>
                <p>
                  Every copy is kept and searchable from the notch, so you stop re-copying the same
                  link. Anything a supported password manager marks private is skipped outright.
                </p>
                <ul className="act-proof">
                  <li>Search without opening another app</li>
                  <li>Passwords and secrets stay out of history</li>
                </ul>
              </div>
              <figure className="act-shot">
                <img
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
                <h3 id="act-windows">See the window before you switch to it.</h3>
                <p>
                  A switcher that previews what you are about to land on, plus a snap grid with the
                  shortcut printed under every layout, so you pick them up without trying.
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
                <img
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
                <h3 id="act-shelf">Put a file down without losing it.</h3>
                <p>
                  Drag files up to the notch and they wait there while you change folders, desktops,
                  or apps. Drag them back out when you get there, or hand them straight to
                  AirDrop.
                </p>
                <ul className="act-proof">
                  <li>Survives folder, Space, and app switches</li>
                  <li>AirDrop target built into the shelf</li>
                </ul>
              </div>
              <figure className="act-shot">
                <img
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
                <h3 id="act-display">Warm the screen when the day winds down.</h3>
                <p>
                  Night Shift on your own schedule, with a toggle in the notch instead of a trip
                  through System Settings. Sunset times are worked out on your Mac from a location
                  you set once.
                </p>
                <ul className="act-proof">
                  <li>Starts with your Mac, if you want it to</li>
                  <li>Location is used locally and never sent anywhere</li>
                </ul>
              </div>
              <figure className="act-shot shot-window">
                <img
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
            <h2 id="customize-heading">Turn off whatever you will not use.</h2>
            <p>
              Six tools is the ceiling, not the requirement. Turn off what you will never open,
              reorder what you keep, and the notch stops showing it, including the tabs
              themselves.
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
              <h2 id="buy-heading">Keep it if you like it.</h2>
              <p className="buy-sub">
                Start with one Mac, or cover up to three. Every plan includes the full app and every
                future update.
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

          <p className="buy-trust">
            Signed &amp; notarized &middot; Full 3-day trial &middot; Secure Stripe checkout &middot;
            1- and 3-Mac plans
          </p>
        </div>
      </section>

      <footer className="footer footer-sitemap">
        <nav className="footer-cols" aria-label="Footer">
          <div className="footer-col">
            <h2 className="footer-heading">
              <Link href="/features/">Features</Link>
            </h2>
            <ul className="footer-links">
              <li>
                <Link href="/features/local-dictation/">Private on-device dictation</Link>
              </li>
              <li>
                <Link href="/features/media-controls/">Media controls</Link>
              </li>
              <li>
                <Link href="/features/clipboard-history/">Clipboard history</Link>
              </li>
              <li>
                <Link href="/features/window-controls/">Window controls</Link>
              </li>
              <li>
                <Link href="/features/file-shelf/">File shelf</Link>
              </li>
              <li>
                <Link href="/features/display-comfort/">Display comfort controls</Link>
              </li>
              <li>
                <Link href="/features/calendar/">Calendar and reminders</Link>
              </li>
              <li>
                <Link href="/features/battery-status/">Battery status</Link>
              </li>
              <li>
                <Link href="/features/camera-mirror/">Camera mirror</Link>
              </li>
              <li>
                <Link href="/features/shortcuts/">Shortcuts</Link>
              </li>
            </ul>
          </div>
          <div className="footer-col">
            <h2 className="footer-heading">
              <Link href="/alternatives/">Alternatives</Link>
            </h2>
            <ul className="footer-links">
              <li>
                <Link href="/alternatives/droppy/">Droppy alternative</Link>
              </li>
              <li>
                <Link href="/alternatives/notchnook/">NotchNook alternative</Link>
              </li>
              <li>
                <Link href="/alternatives/alcove/">Alcove alternative</Link>
              </li>
              <li>
                <Link href="/alternatives/dynamiclake/">DynamicLake alternative</Link>
              </li>
              <li>
                <Link href="/alternatives/boring-notch/">Boring Notch alternative</Link>
              </li>
              <li>
                <Link href="/alternatives/rectangle/">Rectangle alternative</Link>
              </li>
              <li>
                <Link href="/alternatives/maccy/">Maccy alternative</Link>
              </li>
              <li>
                <Link href="/alternatives/raycast/">Raycast alternative</Link>
              </li>
              <li>
                <Link href="/alternatives/bettertouchtool/">BetterTouchTool alternative</Link>
              </li>
              <li>
                <Link href="/alternatives/alttab/">AltTab alternative</Link>
              </li>
              <li>
                <Link href="/alternatives/flux/">f.lux alternative</Link>
              </li>
              <li>
                <Link href="/alternatives/karabiner-elements/">Karabiner-Elements alternative</Link>
              </li>
            </ul>
          </div>
          <div className="footer-col">
            <h2 className="footer-heading">Gojo</h2>
            <ul className="footer-links">
              <li>
                <Link href="/">Home</Link>
              </li>
              <li>
                <a href="#features">How it works</a>
              </li>
              <li>
                <a href="#buy">Pricing</a>
              </li>
              <li>
                <Link href="/blog/">Blog</Link>
              </li>
              <li>
                <a href="https://downloads.trygojo.com/Gojo.dmg">Download for macOS</a>
              </li>
              <li>
                <a href="https://github.com/rohoswagger/gojo">GitHub</a>
              </li>
            </ul>
          </div>
        </nav>
        <div className="footer-bottom">
          <Link className="brand" href="/" aria-label="Gojo home">
            <GojoLogo />
            Gojo
          </Link>
          <span className="foot-copy">&copy; 2026 Gojo</span>
        </div>
      </footer>
    </>
  )
}
