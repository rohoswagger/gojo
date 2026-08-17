import { SparklesIcon, ZapIcon, ShieldIcon } from "lucide-react"

import { HeroCentered } from "@/components/hero-centered"
import { FeatureGrid } from "@/components/feature-grid"

export default function Home() {
  return (
    <main>
      <HeroCentered
        eyebrow="Placeholder toolchain check"
        title="This is a placeholder page"
        description="It exists to prove the Next.js static export, Tailwind v4 build, and swagui registry components compile together. Real landing page copy comes later."
        primaryAction={{ label: "Placeholder action", href: "#" }}
        secondaryAction={{ label: "Learn more", href: "#" }}
      />
      <FeatureGrid
        eyebrow="Placeholder section"
        title="Placeholder feature grid"
        description="Swap this copy and these icons for the real feature set."
        features={[
          {
            icon: <SparklesIcon />,
            title: "Placeholder feature one",
            description: "Description text goes here once real copy is written.",
          },
          {
            icon: <ZapIcon />,
            title: "Placeholder feature two",
            description: "Description text goes here once real copy is written.",
          },
          {
            icon: <ShieldIcon />,
            title: "Placeholder feature three",
            description: "Description text goes here once real copy is written.",
          },
        ]}
      />
    </main>
  )
}
