import type { Metadata } from "next"

import { GojoFooter } from "@/components/gojo-footer"
import { GojoHeader } from "@/components/gojo-header"

export const metadata: Metadata = {
  title: "Terms",
  description: "Terms for downloading, purchasing, and using Gojo.",
  alternates: { canonical: "https://trygojo.com/terms/" },
}

export default function TermsPage() {
  return (
    <>
      <GojoHeader />
      <main className="mx-auto w-full max-w-3xl px-6 py-16 sm:px-8 sm:py-24">
        <p className="text-muted-foreground font-mono text-xs tracking-[0.16em] uppercase">Gojo</p>
        <h1 className="mt-4 text-4xl font-semibold tracking-tight text-foreground sm:text-5xl">Terms</h1>
        <p className="text-muted-foreground mt-5 text-sm">Last updated September 18, 2026</p>

        <div className="legal-content mt-12">
          <p>
            These terms apply when you download, buy, or use Gojo. By doing so, you agree to them. If you do
            not agree, do not use Gojo.
          </p>

          <h2>Using Gojo</h2>
          <p>
            Gojo is a macOS application. You may use it only on devices you own or control, in line with these
            terms and applicable law. You are responsible for how you use features that interact with your Mac,
            other apps, files, clipboard, audio, or connected services.
          </p>

          <h2>Licenses and payments</h2>
          <p>
            Paid plans grant the access described at purchase. A subscription remains active while your payment
            is current. A lifetime license is a one-time purchase for the scope stated on the purchase page.
            Payment processing is provided by Stripe. Taxes, cancellation, renewal, refund, and payment issues
            are handled as shown during checkout and as required by applicable law.
          </p>
          <p>
            Do not share, resell, transfer, or bypass a commercial license or its activation process. We may
            suspend or revoke commercial-license access for fraud, abuse, or a material breach of these terms.
            Nothing here limits rights granted under the GPLv3 where it applies.
          </p>

          <h2>Optional connected services</h2>
          <p>
            Some Gojo features can work with third-party services you choose. Those services are governed by
            their own terms, availability, and privacy practices. You are responsible for your accounts,
            permissions, and content when you enable a connected service.
          </p>

          <h2>Open-source software</h2>
          <p>
            Gojo includes open-source software and is available under the GNU General Public License v3.0.
            The license for the source code is available in the <a href="https://github.com/rohoswagger/gojo/blob/main/LICENSE">Gojo repository</a>.
            These terms do not limit rights granted by that license where it applies.
          </p>

          <h2>Updates and availability</h2>
          <p>
            We may change, update, or stop parts of Gojo. We do not promise that every feature or connected
            service will always be available. Keep your Mac and Gojo updated, and back up information that
            matters to you.
          </p>

          <h2>Disclaimers</h2>
          <p>
            Gojo is provided on an “as is” and “as available” basis to the fullest extent permitted by law.
            We do not guarantee that it will be uninterrupted, error-free, or suitable for every use. Nothing
            in these terms excludes rights that cannot be excluded under applicable law.
          </p>

          <h2>Limitation of liability</h2>
          <p>
            To the fullest extent permitted by law, Gojo is not liable for indirect, incidental, special,
            consequential, or punitive damages, or for loss of data, profits, or goodwill arising from your use
            of Gojo. Where liability cannot be excluded, it is limited to the amount you paid for Gojo in the
            twelve months before the event giving rise to the claim.
          </p>

          <h2>Changes</h2>
          <p>
            We may revise these terms. The date above shows the latest revision. If a change is material, we
            will take reasonable steps to provide notice. Continued use after the effective date means you
            accept the revised terms to the extent permitted by law.
          </p>

          <h2>Questions</h2>
          <p>
            For questions about these terms, open an issue in the <a href="https://github.com/rohoswagger/gojo">Gojo GitHub repository</a>.
            Please do not include payment or other sensitive information in a public issue.
          </p>
        </div>
      </main>
      <GojoFooter />
    </>
  )
}
