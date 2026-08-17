import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { FaqAccordion } from "@/components/faq-accordion";
import { CtaBand } from "@/components/cta-band";
import { Section } from "@/components/section";
import { SiteFooterLegacy } from "@/components/site-footer-legacy";
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
      <div className="article-shell">
        <div className="article-top">
          <div className="shell">
            <header className="site-header">
              <Link className="brand" href="/" aria-label="Gojo home">
                Gojo
              </Link>
              <nav className="nav" aria-label="Primary">
                <Link href="/blog/">Blog</Link>
                <Link href="/alternatives/">Alternatives</Link>
                <Link className="ghost-link" href="/downloads/">
                  Download
                </Link>
              </nav>
            </header>

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
                  <div className="article-meta">
                    <span>Updated {updated}</span>
                    <span>Checked against the official {alternative.name} site</span>
                  </div>
                </div>
              </section>
            </main>
          </div>
        </div>

        <main className="article-main">
          {/* The decision, as two cards rather than paragraphs. */}
          <Section width="default" className="alt-choice">
            <div className="alt-choice-grid">
              <Card>
                <CardHeader>
                  <Badge variant="secondary">{alternative.category}</Badge>
                  <CardTitle>{alternative.name}</CardTitle>
                </CardHeader>
                <CardContent>
                  <p>Choose it for {alternative.bestFor}.</p>
                  <Button asChild variant="outline" size="sm">
                    <a href={alternative.officialUrl} rel="external noopener">
                      Official site
                    </a>
                  </Button>
                </CardContent>
              </Card>

              <Card className="alt-choice-gojo">
                <CardHeader>
                  <Badge>MacBook notch workspace</Badge>
                  <CardTitle>Gojo</CardTitle>
                </CardHeader>
                <CardContent>
                  <p>Choose it for {alternative.gojoFit}.</p>
                  <Button asChild size="sm">
                    <Link href="/">See what it does</Link>
                  </Button>
                </CardContent>
              </Card>
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

            <h2>Side by side</h2>
            <dl className="alt-rows">
              <div>
                <dt>Built for</dt>
                <dd>{alternative.bestFor}</dd>
                <dd className="alt-rows-gojo">{alternative.gojoFit}</dd>
              </div>
              <div>
                <dt>Shape</dt>
                <dd>{alternative.category}</dd>
                <dd className="alt-rows-gojo">Focused notch workspace</dd>
              </div>
              <div>
                <dt>Try it</dt>
                <dd>Check the developer&rsquo;s current page</dd>
                <dd className="alt-rows-gojo">
                  3-day free trial with no card required
                </dd>
              </div>
            </dl>
            <p>
              A specialist wins when its one job is where your day goes. Gojo wins
              when you would rather reach one surface than assemble several
              utilities.
            </p>
          </Section>

          <FaqAccordion
            title="Questions"
            items={[
              {
                question: `Is Gojo an alternative to ${alternative.name}?`,
                answer: `Yes, when you want ${alternative.gojoFit}. ${alternative.tradeoff}`,
              },
              {
                question: `Who should choose ${alternative.name}?`,
                answer: `${alternative.name} is best for ${alternative.bestFor}.`,
              },
            ]}
          />

          <CtaBand
            title="Try Gojo for three days."
            description="Every feature unlocked. No account, no card."
            primaryAction={{
              label: "Download for macOS",
              href: "https://downloads.trygojo.com/Gojo.dmg",
            }}
            secondaryAction={{ label: "See pricing", href: "/#buy" }}
          />

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

      <SiteFooterLegacy />
    </>
  );
}
