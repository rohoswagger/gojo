"use client"

import Image from "next/image"
import { useState } from "react"
import { ClipboardList, FolderOpen, LayoutGrid, Music } from "lucide-react"
import { Button } from "@/components/ui/button"
import styles from "@/app/home.module.css"

const views = [
  { id: "windows", label: "Windows", icon: LayoutGrid, image: "windows.png", width: 1322, height: 418, alt: "Gojo window controls showing app choices, snap layouts and keyboard shortcut labels." },
  { id: "clipboard", label: "Clipboard", icon: ClipboardList, image: "clipboard.png", width: 1388, height: 394, alt: "Gojo clipboard history with search and recently copied text." },
  { id: "shelf", label: "Files", icon: FolderOpen, image: "shelf.png", width: 1298, height: 392, alt: "Gojo file shelf holding files ready to drag into another app." },
  { id: "media", label: "Music", icon: Music, image: "media.png", width: 1308, height: 392, alt: "Gojo media player with artwork, playback controls and a scrubber." },
]

export function ProductPreview() {
  const [selected, setSelected] = useState(views[3])
  return (
    <div className={styles.preview}>
      <div className={styles.desktop}>
        <div id="product-view" className={styles.notchView}><Image src={`/screenshots/${selected.image}`} width={selected.width} height={selected.height} alt={selected.alt} priority /></div>
      </div>
      <div className={styles.previewControls} role="group" aria-label="Explore Gojo's tools">
        {views.map((view) => <Button key={view.id} variant="ghost" className="font-normal leading-[1.5] transition-none" type="button" aria-pressed={selected.id === view.id} aria-controls="product-view" onClick={() => setSelected(view)}><view.icon className="size-[17px]" size={17} strokeWidth={1.7} aria-hidden="true" />{view.label}</Button>)}
      </div>
    </div>
  )
}
