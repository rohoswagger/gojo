import type { Metadata } from "next"

import { GojoFooter } from "@/components/gojo-footer"
import { GojoHeader } from "@/components/gojo-header"

export const metadata: Metadata = {
  title: "Privacy",
  description: "How the Gojo website, purchases, and optional analytics handle information.",
  alternates: { canonical: "https://trygojo.com/privacy/" },
}

export default function PrivacyPage() {
  return (
    <>
      <GojoHeader />
      <main className="mx-auto w-full max-w-3xl px-6 py-16 sm:px-8 sm:py-24">
        <p className="text-muted-foreground font-mono text-xs tracking-[0.16em] uppercase">Gojo</p>
        <h1 className="mt-4 text-4xl font-semibold tracking-tight text-foreground sm:text-5xl">Privacy</h1>
        <p className="text-muted-foreground mt-5 text-sm">Last updated September 21, 2026</p>

        <div className="legal-content mt-12">
          <p>
            This notice explains how information is handled when you visit trygojo.com, buy a Gojo license,
            or use services connected to Gojo. Gojo is built around keeping dictation on your Mac whenever
            you use its on-device dictation options.
          </p>

          <h2>Website analytics</h2>
          <p>
            The website may send anonymous page views and download or pricing-button clicks to PostHog when
            analytics is enabled. These events include the page path, the destination of the clicked link,
            and the selected plan where relevant. Query strings and URL fragments are removed before an event
            is sent. A random temporary browser-session identifier in sessionStorage separates one visit from
            another without using your email, license information, device identifiers, cookies, or a stable
            identifier across browser sessions.
          </p>
          <p>
            When you open a Stripe checkout from the website, that pseudonymous session identifier is sent to
            Stripe as a client_reference_id. If payment completes, Stripe returns it to Gojo through a signed
            webhook so Gojo can record a limited purchase_completed event in PostHog. That event may include
            checkout mode, payment status, currency, purchase amount, and whether the purchase was connected
            to a website session. It does not include your email, payment details, Stripe customer identifier,
            license key, or Checkout Session identifier.
          </p>
          <p>
            Like most web services, PostHog and Cloudflare can receive standard request metadata, such as an
            IP address, browser information, and request time, when your browser loads the site or sends an
            event. We use this information to understand site performance and whether visitors reach a
            download or purchase path.
          </p>

          <h2>Purchases and licenses</h2>
          <p>
            Purchases are processed by Stripe. Stripe handles the payment information you provide under its
            own privacy notice. Gojo and its license service use the information needed to complete a purchase,
            provide your license, and validate or recover that license. We do not receive your full payment-card
            number.
          </p>

          <h2>Gojo on your Mac</h2>
          <p>
            Gojo&apos;s on-device dictation options process audio locally on your Mac. Gojo also includes optional
            features that can connect to services you choose, such as a music service or an optional cloud
            dictation provider. When you choose one of those features, the information required for that feature
            is handled by the selected service under its terms and privacy practices.
          </p>

          <h2>How we use information</h2>
          <ul>
            <li>Operate, secure, and improve the website and license service.</li>
            <li>Deliver purchases, licenses, updates, and support.</li>
            <li>Understand aggregated website usage and conversion paths.</li>
            <li>Meet legal obligations and prevent abuse or fraud.</li>
          </ul>

          <h2>Sharing</h2>
          <p>
            We share information only with service providers that help operate Gojo, including Cloudflare for
            website delivery, Stripe for payments, PostHog for the optional website analytics described above,
            and the services you explicitly choose to connect. We may also disclose information when required
            by law or to protect Gojo, its users, or others.
          </p>

          <h2>Retention and choices</h2>
          <p>
            We retain information only for as long as needed for the purposes in this notice, including license
            administration, security, accounting, and legal requirements. You can avoid website analytics by
            blocking analytics requests in your browser. You can avoid an optional connected service by not
            enabling that feature.
          </p>

          <h2>Changes</h2>
          <p>
            We may update this notice as Gojo changes. The date above will show when it was last revised.
            Continued use after an update means you accept the revised notice to the extent permitted by law.
          </p>

          <h2>Questions</h2>
          <p>
            For privacy questions, open an issue in the <a href="https://github.com/rohoswagger/gojo">Gojo GitHub repository</a>.
            Please do not include sensitive information in a public issue.
          </p>
        </div>
      </main>
      <GojoFooter />
    </>
  )
}
