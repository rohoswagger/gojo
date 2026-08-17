import type { NextConfig } from "next"

const nextConfig: NextConfig = {
  // Static export: this site has no server runtime to pay for. Output lands
  // in ./out and is served as static assets on Cloudflare Workers.
  output: "export",
  // The export target has no Next image optimiser.
  images: { unoptimized: true },
  // Cloudflare static assets serve /path as /path/index.html.
  trailingSlash: true,
}

export default nextConfig
