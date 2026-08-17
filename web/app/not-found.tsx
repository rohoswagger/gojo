import Link from "next/link";

import { GojoFooter } from "@/components/gojo-footer";
import { GojoHeader } from "@/components/gojo-header";

export default function NotFound() {
  return (
    <>
      <GojoHeader />

      <div className="shell">
        <main className="hero">
          <h1>
            <span className="line">404.</span>
            <span className="line">
              Page <span className="glow">not found</span>.
            </span>
          </h1>
          <p className="sub">
            The page you are looking for does not exist or has moved.
          </p>

          <div className="cta">
            <Link className="btn btn-primary" href="/">
              Back to home
            </Link>
          </div>

          <p className="meta">
            Try the <Link href="/blog/">blog</Link>,{" "}
            <Link href="/features/">features</Link>, or{" "}
            <Link href="/alternatives/">alternatives</Link>.
          </p>
        </main>
      </div>

      <GojoFooter />
    </>
  );
}
