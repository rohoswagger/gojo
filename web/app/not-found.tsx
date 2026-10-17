import Link from "next/link";

import { GojoFooter } from "@/components/gojo-footer";
import { GojoHeader } from "@/components/gojo-header";
import { Section } from "@/components/section";
import { Button } from "@/components/ui/button";
import { GOJO_RELEASE } from "@/lib/release";

export default function NotFound() {
  return (
    <div className="marketing-shell not-found-shell" data-gojo-editorial="warm">
      <title>Page not found | Gojo</title>
      <GojoHeader />

      <main id="main-content" tabIndex={-1} className="not-found-main">
        <Section width="narrow" className="not-found-content px-0 py-0 sm:px-0 sm:py-0">
          <h1>Page not found.</h1>
          <p>The page you are looking for does not exist or has moved.</p>

          <div className="not-found-actions">
            <Button asChild size="lg" className="btn btn-primary">
              <Link href="/">Back to home</Link>
            </Button>
            <Button asChild variant="outline" size="lg">
              <a
                href={GOJO_RELEASE.downloadUrl}
                data-funnel-event="download_cta_clicked"
                data-funnel-placement="not_found"
              >
                Download Gojo
              </a>
            </Button>
          </div>

          <nav className="not-found-links" aria-label="More Gojo pages">
            <Link href="/features/">Features</Link>
            <Link href="/blog/">Blog</Link>
            <Link href="/alternatives/">Alternatives</Link>
          </nav>
        </Section>
      </main>

      <GojoFooter />
    </div>
  );
}
