import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";

import { Section } from "@/components/section";
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

      {/* Dark hero, then a light body. Same rhythm as every other article
          page on the site, so these stop reading as a separate world. */}
      <div className="article-shell" data-compare="true" data-gojo-editorial="warm">
        <div className="article-top">
          <GojoHeader />

          <main>
              <section className="article-hero">
                <div className="wrap">
                  <nav className="breadcrumb" aria-label="Breadcrumb">
                    <Link href="/">Home</Link>
                    <span aria-hidden="true">/</span>
                    <Link href="/alternatives/">Alternatives</Link>
                  </nav>
                  <h1>
                    {alternative.name} vs Gojo: which fits your Mac?
                  </h1>
                  <p className="article-summary">{alternative.tradeoff}</p>
                  <Versus
                    slug={alternative.slug}
                    name={alternative.name}
                    category={alternative.category}
                  />
                  <div className="article-meta">
                    <span>Updated {updated}</span>
                    <span>Checked against the official {alternative.name} site</span>
                  </div>
                </div>
              </section>
          </main>
        </div>

        <main className="article-main">
          <Section className="cmp-section">
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
                    <strong>Dictation stays on your Mac</strong> — no API key, no account, no audio leaving the device
                  </span>
                </li>
                <li>
                  <Check className="why-tick" aria-hidden="true" />
                  <span>
                    <strong>Six tools in one surface</strong> — media, windows, clipboard, files, calendar, display
                  </span>
                </li>
                <li>
                  <Check className="why-tick" aria-hidden="true" />
                  <span>
                    <strong>Three days free</strong> — every feature unlocked, no account and no card
                  </span>
                </li>
                <li>
                  <Check className="why-tick" aria-hidden="true" />
                  <span>
                    <strong>Signed &amp; notarized</strong> — open source under GPLv3, updates install themselves
                  </span>
                </li>
              </ul>
            </div>
          </Section>

          <Section width="narrow">
            <h2>What {alternative.name} publishes</h2>
            <p>
              Taken from the developer&rsquo;s own product page on {updated}. These
              describe the product, they do not score it.
            </p>
            <ul className="alt-facts">
              {alternative.officialFacts.map((fact) => (
                <li key={fact}>{fact}</li>
              ))}
            </ul>

            <p>
              A specialist wins when its one job is where your day goes. Gojo wins
              when you would rather reach one surface than assemble several
              utilities.
            </p>
          </Section>

          <Section width="narrow" className="alt-faq">
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
              <a className="btn btn-primary" href="https://downloads.trygojo.com/Gojo.dmg">
                Download for macOS
              </a>
              <Link className="btn btn-ghost" href="/#buy">
                See pricing
              </Link>
            </div>
          </Section>

          <Section width="narrow">
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
        </main>
      </div>

      <GojoFooter />
    </>
  );
}
