import type { Metadata } from "next";
import "./globals.css";

// No webfonts on purpose. site.css sets --body/--display/--mono to system
// stacks (ui-sans-serif, SF Pro, ui-rounded), so loading Geist here would
// ship font files nothing references.

export const metadata: Metadata = {
  metadataBase: new URL("https://trygojo.com"),
  icons: {
    icon: "/favicon.svg",
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <head>
        <link rel="stylesheet" href="/site.css" />
      </head>
      <body>{children}</body>
    </html>
  );
}
