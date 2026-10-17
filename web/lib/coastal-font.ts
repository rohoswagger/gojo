import localFont from "next/font/local"

export const coastalDisplay = localFont({
  src: [
    { path: "../public/fonts/instrument-serif/regular.ttf", weight: "400", style: "normal" },
    { path: "../public/fonts/instrument-serif/italic.ttf", weight: "400", style: "italic" },
  ],
  variable: "--font-coastal",
  display: "swap",
})
