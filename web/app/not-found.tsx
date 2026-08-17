import Link from "next/link";

export default function NotFound() {
  return (
    <>
      <div className="shell">
        <header className="site-header">
          <Link className="brand" href="/" aria-label="Gojo home">
            <svg
              viewBox="0 0 256 172.29"
              fill="currentColor"
              aria-hidden="true"
            >
              <path
                fillRule="evenodd"
                d="M 130.53 162.06 C 165.62 159.7 195.71 134.68 195.71 134.68 C 246 84.7 246 84.64 245.03 83.6 C 244 82.5 218.71 57.19 217.83 57.52 C 217 57.8 168.66 106.43 166.92 107.91 C 152 120 134.68 122.36 134.68 122.36 C 110 124 88.69 110.52 88.69 110.52 C 82 105 81.57 104.46 81.57 104.46 C 78 101 72.78 101.1 72.78 101.1 C 68 101.5 45.4 123.25 45.4 123.25 C 45.4 123.58 67 144 67.47 143.49 C 90 162 130.53 162.06 130.53 162.06 Z M 37.83 114.87 C 38 115 86.54 66.41 86.54 66.41 C 102 51 132.1 49.61 132.1 49.61 C 165 51.5 169.68 64.16 169.68 64.16 C 182 75 185.76 71.15 185.76 71.15 C 192 69 209.8 49.54 209.8 49.54 C 210 49 208.27 46.9 208.27 46.9 C 204 43 168.13 17.81 168.13 17.81 C 130 -2 86.5 16.02 86.5 16.02 C 50 33 10.17 87.44 10.17 87.44 C 10 88 37.83 114.87 37.83 114.87 Z"
              />
            </svg>
            Gojo
          </Link>
          <nav className="nav" aria-label="Site">
            <Link className="ghost-link" href="/#features">
              Features
            </Link>
            <Link className="ghost-link" href="/#buy">
              Pricing
            </Link>
            <a className="ghost-link" href="https://downloads.trygojo.com/Gojo.dmg">
              Download
            </a>
          </nav>
        </header>

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
        </main>
      </div>

      <footer className="footer footer-sitemap">
        <div className="footer-bottom">
          <Link className="brand" href="/" aria-label="Gojo home">
            <svg
              viewBox="0 0 256 172.29"
              fill="currentColor"
              aria-hidden="true"
            >
              <path
                fillRule="evenodd"
                d="M 130.53 162.06 C 165.62 159.7 195.71 134.68 195.71 134.68 C 246 84.7 246 84.64 245.03 83.6 C 244 82.5 218.71 57.19 217.83 57.52 C 217 57.8 168.66 106.43 166.92 107.91 C 152 120 134.68 122.36 134.68 122.36 C 110 124 88.69 110.52 88.69 110.52 C 82 105 81.57 104.46 81.57 104.46 C 78 101 72.78 101.1 72.78 101.1 C 68 101.5 45.4 123.25 45.4 123.25 C 45.4 123.58 67 144 67.47 143.49 C 90 162 130.53 162.06 130.53 162.06 Z M 37.83 114.87 C 38 115 86.54 66.41 86.54 66.41 C 102 51 132.1 49.61 132.1 49.61 C 165 51.5 169.68 64.16 169.68 64.16 C 182 75 185.76 71.15 185.76 71.15 C 192 69 209.8 49.54 209.8 49.54 C 210 49 208.27 46.9 208.27 46.9 C 204 43 168.13 17.81 168.13 17.81 C 130 -2 86.5 16.02 86.5 16.02 C 50 33 10.17 87.44 10.17 87.44 C 10 88 37.83 114.87 37.83 114.87 Z"
              />
            </svg>
            Gojo
          </Link>
          <span className="foot-copy">&copy; 2026 Gojo</span>
        </div>
      </footer>
    </>
  );
}
