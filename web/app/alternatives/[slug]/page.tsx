import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";

import { Section } from "@/components/section";
import { Button } from "@/components/ui/button";
import { GojoFooter } from "@/components/gojo-footer";
import { GojoHeader } from "@/components/gojo-header";
import { Versus } from "@/components/versus";
import { Check } from "lucide-react";
import { ComparisonTable } from "@/components/comparison-table";
import { comparisonFootnote, comparisonRows } from "@/lib/comparison";
import {
  getAlternative,
  getAlternatives,
  getAlternativesUpdated,
  alternativeArticleSchema,
  alternativeCanonical,
  alternativeDescription,
  alternativeTitle,
} from "@/lib/alternatives";

type Params = { params: Promise<{ slug: string }> };

export function generateStaticParams() {
  return getAlternatives().map((a) => ({ slug: a.slug }));
}

export async function generateMetadata({ params }: Params): Promise<Metadata> {
  const { slug } = await params;
  const alternative = getAlternative(slug);
  if (!alternative) return {};
  const title = alternativeTitle(alternative);
  const description = alternativeDescription(alternative);
  const url = alternativeCanonical(alternative);
  return {
    title,
    description,
    alternates: { canonical: url },
    openGraph: {
      title,
      description,
      type: "article",
      url,
      images: [{ url: "https://trygojo.com/assets/og.jpg" }],
    },
    twitter: {
      card: "summary_large_image",
      title,
      description,
      images: ["https://trygojo.com/assets/og.jpg"],
    },
  };
}

export default async function AlternativePage({ params }: Params) {
  const { slug } = await params;
  const alternative = getAlternative(slug);
  if (!alternative) notFound();
  const updated = getAlternativesUpdated();

  return (
    <>
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{
          __html: JSON.stringify(alternativeArticleSchema(alternative)),
        }}
      />

      <div className="article-shell" data-compare="true" data-gojo-editorial="warm">
        <div className="article-top alternative-shell page-frame">
          <GojoHeader overlay />

          <main id="main-content" tabIndex={-1}>
            <section className="article-hero">
              <div className="wrap alternative-detail-grid">
                <div className="alternative-detail-copy">
                  <nav className="breadcrumb" aria-label="Breadcrumb">
                    <Link href="/">Home</Link>
                    <span aria-hidden="true">/</span>
                    <Link href="/alternatives/">Alternatives</Link>
                  </nav>
                  <h1>
                    {alternative.name} vs Gojo: which fits your Mac?
                  </h1>
                  <p className="article-summary">{alternative.tradeoff}</p>
                  <div className="article-meta">
                    <span>Updated {updated}</span>
                    <span>Checked against the official {alternative.name} site</span>
                  </div>
                </div>
                <Versus
                  slug={alternative.slug}
                  name={alternative.name}
                  category={alternative.category}
                />
              </div>
            </section>
            <div className="article-main">
              <Section className="cmp-section px-0 py-10 sm:px-0 sm:py-12">
                <ComparisonTable
                  slug={alternative.slug}
                  name={alternative.name}
                  category={alternative.category}
                  rows={comparisonRows(alternative)}
                  footnote={comparisonFootnote(alternative, updated)}
                />

                <div className="why">
                  <h2 className="why-title">Why choose Gojo?</h2>
                  <ul className="why-list">
                    <li>
                      <Check className="why-tick" aria-hidden="true" />
                      <span>
                        <strong>Local dictation stays on your Mac.</strong> No API key or audio upload in local mode. Optional cloud mode sends audio to your selected provider.
                      </span>
                    </li>
                    <li>
                      <Check className="why-tick" aria-hidden="true" />
                      <span>
                        <strong>Your daily tools at the notch.</strong> Control media and windows, find clipboard history, stage files, and adjust your display.
                      </span>
                    </li>
                    <li>
                      <Check className="why-tick" aria-hidden="true" />
                      <span>
                        <strong>Three days free.</strong> Every feature unlocked, no account or card.
                      </span>
                    </li>
                    <li>
                      <Check className="why-tick" aria-hidden="true" />
                      <span>
                        <strong>Signed &amp; notarized.</strong> Open source under GPLv3, with automatic updates.
                      </span>
                    </li>
                  </ul>
                </div>
              </Section>

              <Section width="narrow" className="px-0 py-10 sm:px-0 sm:py-12">
                <h2>What {alternative.name} publishes</h2>
                <p>
                  Published on the developer&rsquo;s product page, checked {updated}.
                </p>
                <ul className="alt-facts">
                  {alternative.officialFacts.map((fact) => (
                    <li key={fact}>{fact}</li>
                  ))}
                </ul>
              </Section>

              <Section width="narrow" className="alt-faq px-0 py-10 sm:px-0 sm:py-12">
                <h2>Questions, answered</h2>
                <div className="alt-faq-grid">
                  <article>
                    <h3>Is Gojo an alternative to {alternative.name}?</h3>
                    <p>
                      Yes, when you want {alternative.gojoFit}. {alternative.tradeoff}
                    </p>
                  </article>
                  <article>
                    <h3>Who should choose {alternative.name}?</h3>
                    <p>{alternative.name} is best for {alternative.bestFor}.</p>
                  </article>
                </div>
              </Section>

              <Section width="narrow" className="alt-detail-cta">
                <div>
                  <h2>Try Gojo for three days.</h2>
                  <p>Every feature unlocked. No account, no card.</p>
                </div>
                <div className="alt-detail-cta-actions">
                  <Button asChild size="lg" className="btn btn-primary">
                    <a
                      href="https://downloads.trygojo.com/Gojo.dmg"
                      data-funnel-event="download_cta_clicked"
                      data-funnel-placement="alternative_detail_end"
                    >
                      Download for macOS
                    </a>
                  </Button>
                  <Button asChild size="lg" variant="ghost" className="btn btn-ghost">
                    <Link href="/#buy">See pricing</Link>
                  </Button>
                </div>
              </Section>

              <Section width="narrow" className="px-0 py-10 sm:px-0 sm:py-12">
                <p className="alt-src">
                  Primary source checked {updated}:{" "}
                  <a href={alternative.officialUrl} rel="external noopener">
                    {alternative.name} official site
                  </a>
                  . Features, requirements and pricing change, so verify before
                  buying. Read the longer{" "}
                  <Link href={alternative.relatedComparison}>
                    {alternative.name} comparison
                  </Link>
                  .
                </p>
              </Section>
            </div>
          </main>
        </div>
      </div>

      <GojoFooter />
    </>
  );
}
