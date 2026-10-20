import type { Metadata } from "next"
import Image from "next/image"
import Link from "next/link"
import { ArrowRight, Download, Mic, LockKeyhole, CalendarDays, BatteryCharging, Camera, Command } from "lucide-react"
import { GojoFooter } from "@/components/gojo-footer"
import { GojoHeader } from "@/components/gojo-header"
import { ProductPreview } from "@/components/product-preview"
import { PricingTabsProvider, PricingTabList, PricingPanels, PricingPanel } from "@/components/pricing-tabs"
import styles from "./home.module.css"
import { coastalDisplay } from "@/lib/coastal-font"
import { Button } from "@/components/ui/button"
import { GOJO_RELEASE } from "@/lib/release.mjs"


export const metadata: Metadata = {
  title: "Gojo - MacBook notch workspace",
  description:
    "Gojo brings window controls, clipboard history, a file shelf, music, display controls, and on-device dictation into one MacBook notch workspace.",
  alternates: {
    canonical: "https://trygojo.com/",
  },
  openGraph: {
    title: "Gojo - MacBook notch workspace",
    description:
      "Manage windows, recover copied text, stage files, control music, and use local dictation from your MacBook notch.",
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
    title: "Gojo - MacBook notch workspace",
    description:
      "Windows, clipboard, files, music, display controls, and local dictation in one MacBook notch workspace.",
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
  softwareVersion: GOJO_RELEASE.version,
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

const smallTools = [
  { slug: "calendar", title: "Calendar", icon: CalendarDays },
  { slug: "battery-status", title: "Battery status", icon: BatteryCharging },
  { slug: "camera-mirror", title: "Camera mirror", icon: Camera },
  { slug: "shortcuts", title: "Shortcuts", icon: Command },
]

const faqs = [
  { question: "What happens after the three-day trial?", answer: "Choose a monthly or lifetime license to keep using Gojo. The trial needs no card or account, so there is no trial subscription to cancel." },
  { question: "Will Gojo work on my Mac?", answer: "Gojo requires macOS 14 or later. It is designed around the MacBook notch. Download the full trial to check the fit with your own setup before buying." },
  { question: "Does dictation send my voice to the cloud?", answer: "Local dictation runs on your Mac and works offline after a model download. Optional cloud transcription sends audio to your chosen provider when you enable it." },
  { question: "Which permissions does Gojo need?", answer: "Window management and media key controls use Accessibility access. Dictation asks for microphone access when you use it. You can choose the tools you enable." },
  { question: "What does a lifetime license include?", answer: "The full app and future updates. Personal covers one Mac. Multi-Mac covers up to three Macs. After checkout, use your license key to activate Gojo." },
]

const faqJsonLd = {
  "@context": "https://schema.org",
  "@type": "FAQPage",
  mainEntity: faqs.map(({ question, answer }) => ({
    "@type": "Question", name: question,
    acceptedAnswer: { "@type": "Answer", text: answer },
  })),
}


export default function Home() {
  return (
    <div className={`${styles.home} ${coastalDisplay.variable}`}>
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }} />
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(faqJsonLd) }} />
      <div className={styles.header}><GojoHeader home /></div>
      <main id="main-content" tabIndex={-1}>
        <section className={styles.hero} aria-labelledby="hero-heading">
          <div className={styles.heroCopy}>
            <h1 id="hero-heading">Your Mac.<br /><span>One hover away.</span></h1>
            <p className={styles.lede}>Your everyday tools, right in your MacBook notch.</p>
            <Button asChild size="lg" className="h-auto"><a className={styles.primaryButton} href="https://downloads.trygojo.com/Gojo.dmg" data-funnel-event="download_cta_clicked" data-funnel-placement="hero"><Download size={18} aria-hidden="true" /> Download for Mac</a></Button>
            <div className={styles.heroOffer}>
              <p className={styles.trialTerms}>3 days free</p>
              <a className={styles.heroPrice} href="#buy">Yours for <strong>$9.99</strong> once <ArrowRight size={18} aria-hidden="true" /></a>
            </div>
          </div>
          <ProductPreview />
        </section>
        <section id="features" className={styles.gallery} aria-labelledby="gallery-heading">
          <header className={styles.galleryHeading}><h2 id="gallery-heading">Everything in<br /><span>your notch.</span></h2></header>
          <div className={styles.screenshotGrid}>
            <article><div className={`${styles.screenshotWell} ${styles.musicWell}`}><Image src="/screenshots/media.png" width={1308} height={392} alt="Gojo music player showing album artwork, playback controls and a scrubber." /></div><h3>Music controls</h3><p>Play, pause, skip and seek.</p></article>
            <article><div className={`${styles.screenshotWell} ${styles.clipboardWell}`}><Image src="/screenshots/clipboard.png" width={1388} height={394} alt="Searchable clipboard history in the Gojo notch." /></div><h3>Clipboard history</h3><p>Search what you copied.</p></article>
            <article><div className={`${styles.screenshotWell} ${styles.windowsWell}`}><Image src="/screenshots/windows.png" width={1322} height={418} alt="Gojo window controls showing app choices, snap layouts and keyboard shortcut labels." /></div><h3>Window controls</h3><p>Switch windows and snap them into place.</p></article>
            <article><div className={`${styles.screenshotWell} ${styles.filesWell}`}><Image src="/screenshots/shelf.png" width={1298} height={392} alt="Files staged in Gojo's drag-and-drop shelf." /></div><h3>File shelf</h3><p>Drop files here. Drag them into another app.</p></article>
          </div>
          <div className={styles.galleryCta}><Button asChild size="lg" className="h-auto"><a className={styles.primaryButton} href="https://downloads.trygojo.com/Gojo.dmg" data-funnel-event="download_cta_clicked" data-funnel-placement="features"><Download size={18} aria-hidden="true" /> Try Gojo free</a></Button></div>
        </section>
        <section className={styles.dictation} aria-labelledby="dictation-heading">
          <div className={styles.dictationCopy}>
            <Mic size={29} strokeWidth={1.5} aria-hidden="true" />
            <h2 id="dictation-heading">Private<br />dictation.</h2>
            <p>Hold the shortcut. Speak. Release to insert.</p>
            <div className={styles.shortcut}><kbd>⌃ Control</kbd><span>+</span><kbd>⌥ Option</kbd><span>Hold to talk</span></div>
            <Link href="/features/local-dictation/">Explore local dictation <ArrowRight size={16} aria-hidden="true" /></Link>
          </div>
          <div className={styles.dictationProof}>
            <div className={styles.modelImage}><Image src="/screenshots/dictation-models.png" width={920} height={342} alt="Gojo speech models, with Parakeet Unified selected for on-device dictation." /></div>
            <div className={styles.privacyNote}><LockKeyhole size={20} aria-hidden="true" /><div><h3>Your voice stays on your Mac.</h3><p>Download a model once. Dictate offline.</p></div></div>
          </div>
        </section>
        <section className={styles.displaySection} aria-labelledby="display-heading"><div><h2 id="display-heading">Display<br />comfort.</h2><p>Adjust warmth and schedule Night Shift.</p><Link href="/features/">Explore all Gojo features <ArrowRight size={16} aria-hidden="true" /></Link></div><div className={styles.displayScreenshot}><Image src="/screenshots/settings-nightshift.png" width={681} height={589} alt="Gojo display settings with Night Shift warmth and schedule controls." /></div></section>
        <section className={styles.smallTools} aria-label="More tools for your day">
          {smallTools.map((tool) => <Link key={tool.slug} href={`/features/${tool.slug}/`}><tool.icon size={25} strokeWidth={1.4} aria-hidden="true" /><h3>{tool.title}</h3><ArrowRight size={17} aria-hidden="true" /></Link>)}
        </section>
      <section className={styles.pricing} id="buy" aria-labelledby="buy-heading">
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
                  <Button asChild size="lg" className="h-auto"><a className="btn btn-monthly" href="https://buy.stripe.com/5kQfZhgUU2gI59o4FMeAg05" data-funnel-event="pricing_cta_clicked" data-funnel-plan="personal_monthly" data-funnel-placement="pricing">
                    Choose subscription
                  </a></Button>
                </div>

                <div className="plan plan-lifetime">
                  <span className="plan-tag">Pay once. Keep it.</span>
                  <div className="plan-name">Lifetime</div>
                  <div className="plan-figure">
                    <span className="sr-only">$9.99 one time</span>
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
                  <Button asChild size="lg" className="h-auto"><a className="btn btn-buy" href="https://buy.stripe.com/fZu5kD3446wY31gb4aeAg04" data-funnel-event="pricing_cta_clicked" data-funnel-plan="personal_lifetime" data-funnel-placement="pricing">
                    Get lifetime access
                  </a></Button>
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
                  <Button asChild size="lg" className="h-auto"><a className="btn btn-monthly" href="https://buy.stripe.com/5kQcN5gUU7B245kgoueAg03" data-funnel-event="pricing_cta_clicked" data-funnel-plan="multi_monthly" data-funnel-placement="pricing">
                    Choose subscription
                  </a></Button>
                </div>

                <div className="plan plan-lifetime">
                  <span className="plan-tag">Pay once. Keep it.</span>
                  <div className="plan-name">Lifetime</div>
                  <div className="plan-figure">
                    <span className="sr-only">$19.99 one time</span>
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
                  <Button asChild size="lg" className="h-auto"><a className="btn btn-buy" href="https://buy.stripe.com/9B64gzfQQ7B26ds1tAeAg02" data-funnel-event="pricing_cta_clicked" data-funnel-plan="multi_lifetime" data-funnel-placement="pricing">
                    Get lifetime access
                  </a></Button>
                </div>
              </PricingPanel>
            </PricingPanels>
          </PricingTabsProvider>
        </div>
      </section>

        <section className={styles.faq} aria-labelledby="faq-heading">
          <div><h2 id="faq-heading">Before you download.</h2><p>Want to see the full setup?<br /><Link href="/downloads/">Download and installation guide <ArrowRight size={15} aria-hidden="true" /></Link></p></div>
          <div>{faqs.map((faq) => <details key={faq.question}><summary>{faq.question}</summary><p>{faq.answer}</p></details>)}</div>
        </section>
        <section className={styles.finalCta} aria-labelledby="final-heading"><h2 id="final-heading">Give your notch<br />something to do.</h2><Button asChild size="lg" className="h-auto"><a className={styles.primaryButton} href="https://downloads.trygojo.com/Gojo.dmg" data-funnel-event="download_cta_clicked" data-funnel-placement="footer"><Download size={18} aria-hidden="true" /> Try Gojo free for 3 days</a></Button><p>No card or account. macOS 14 or later.</p></section>
      </main>
      <GojoFooter />
    </div>
  )
}
