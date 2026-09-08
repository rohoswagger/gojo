"use client"

import { useId, useState, type CSSProperties } from "react"
import { MoveHorizontal } from "lucide-react"

export function NightShiftComparison() {
  const labelId = useId()
  const [split, setSplit] = useState(50)
  const style = { "--night-split": `${split}%` } as CSSProperties

  return (
    <figure className="night-compare" style={style}>
      <div className="night-compare-stage">
        <img
          className="night-compare-image night-compare-off"
          src="/screenshots/settings-nightshift.png"
          width={681}
          height={589}
          loading="lazy"
          alt="Gojo Night Shift settings without a warm display tint"
        />
        <div className="night-compare-warm" aria-hidden="true">
          <img
            className="night-compare-image"
            src="/screenshots/settings-nightshift.png"
            width={681}
            height={589}
            alt=""
          />
        </div>

        <span className="night-compare-label night-compare-label-on">Night Shift on</span>
        <span className="night-compare-label night-compare-label-off">Off</span>

        <div className="night-compare-divider" aria-hidden="true">
          <span><MoveHorizontal /></span>
        </div>

        <label id={labelId} className="sr-only" htmlFor={`${labelId}-range`}>
          Adjust the Night Shift comparison
        </label>
        <input
          id={`${labelId}-range`}
          className="night-compare-range"
          type="range"
          min="0"
          max="100"
          value={split}
          aria-labelledby={labelId}
          aria-valuetext={`${split}% Night Shift on`}
          onChange={(event) => setSplit(Number(event.currentTarget.value))}
        />
      </div>
      <figcaption>Drag the divider to compare the same screen with Night Shift off and on.</figcaption>
    </figure>
  )
}
