import type { Metadata } from "next";
import "./globals.css";
import FunnelAnalytics from "@/components/funnel-analytics";
import { coastalDisplay } from "@/lib/coastal-font";

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
      <body className={coastalDisplay.variable}>
        {children}
        <FunnelAnalytics />
      </body>
    </html>
  );
}
