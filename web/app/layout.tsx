import type { Metadata } from "next";
import { Instrument_Serif, Inter_Tight } from "next/font/google";
import "./globals.css";

// The rest of the site runs on system stacks (see app/skin.css). The blog is
// the one surface with its own display voice, so these two faces load here —
// next/font self-hosts them into the static export — and are referenced only
// from app/blog-paper.css. Inter Tight is the grotesque that holds together at
// -0.04em display tracking; Instrument Serif supplies the italic counterpoint
// in poster headlines.
const interTight = Inter_Tight({
  subsets: ["latin"],
  variable: "--font-grotesk",
  display: "swap",
});

const instrumentSerif = Instrument_Serif({
  subsets: ["latin"],
  weight: "400",
  style: "italic",
  variable: "--font-editorial",
  display: "swap",
});

export const metadata: Metadata = {
  metadataBase: new URL("https://trygojo.com"),
  icons: {
    icon: [
      { url: "/favicon.ico", type: "image/x-icon", sizes: "256x256" },
      { url: "/favicon.svg", type: "image/svg+xml", sizes: "any" },
    ],
    shortcut: "/favicon.ico",
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" className={`${interTight.variable} ${instrumentSerif.variable}`}>
      <body>{children}</body>
    </html>
  );
}
