"use client"

import * as React from "react"

/**
 * Accessible tab widget for the pricing section, ported from docs/index.html
 * lines 366-401. Reproduces the original's ARIA + keyboard behaviour
 * (ArrowLeft/ArrowRight/Home/End, roving tabindex, aria-selected, hidden
 * panels) exactly, split into a provider + leaf components so the tab list
 * (nested in `.buy-head`) and the panels (a sibling of `.buy-head` under
 * `.wrap`) can stay in their original DOM positions while sharing state.
 * The page around this stays a server component; only this interactive
 * piece is a client island.
 */

type Tab = { id: string; controls: string; name: string; device: string }

type PricingTabsContextValue = {
  tabs: Tab[]
  activeId: string
  activate: (index: number, moveFocus: boolean) => void
  tabRefs: React.MutableRefObject<(HTMLButtonElement | null)[]>
}

const PricingTabsContext = React.createContext<PricingTabsContextValue | null>(null)

function usePricingTabsContext() {
  const ctx = React.useContext(PricingTabsContext)
  if (!ctx) {
    throw new Error("PricingTabList/PricingPanels must be used within PricingTabsProvider")
  }
  return ctx
}

function PricingTabsProvider({
  tabs,
  children,
}: {
  tabs: Tab[]
  children: React.ReactNode
}) {
  const [activeId, setActiveId] = React.useState(tabs[0]?.id ?? "")
  const tabRefs = React.useRef<(HTMLButtonElement | null)[]>([])

  const activate = React.useCallback(
    (index: number, moveFocus: boolean) => {
      const tab = tabs[index]
      if (!tab) return
      setActiveId(tab.id)
      if (moveFocus) tabRefs.current[index]?.focus()
    },
    [tabs]
  )

  return (
    <PricingTabsContext.Provider value={{ tabs, activeId, activate, tabRefs }}>
      {children}
    </PricingTabsContext.Provider>
  )
}

function PricingTabList({ ariaLabel }: { ariaLabel: string }) {
  const { tabs, activeId, activate, tabRefs } = usePricingTabsContext()

  function handleKeyDown(event: React.KeyboardEvent<HTMLButtonElement>, index: number) {
    let nextIndex = index
    if (event.key === "ArrowRight") nextIndex = (index + 1) % tabs.length
    else if (event.key === "ArrowLeft") nextIndex = (index - 1 + tabs.length) % tabs.length
    else if (event.key === "Home") nextIndex = 0
    else if (event.key === "End") nextIndex = tabs.length - 1
    else return

    event.preventDefault()
    activate(nextIndex, true)
  }

  return (
    <div className="pricing-tabs" role="tablist" aria-label={ariaLabel}>
      {tabs.map((tab, index) => {
        const selected = tab.id === activeId
        return (
          <button
            key={tab.id}
            ref={(el) => {
              tabRefs.current[index] = el
            }}
            className="pricing-tab"
            id={tab.id}
            type="button"
            role="tab"
            aria-selected={selected}
            aria-controls={tab.controls}
            tabIndex={selected ? 0 : -1}
            onClick={() => activate(index, false)}
            onKeyDown={(event) => handleKeyDown(event, index)}
          >
            <span className="pricing-tab-name">{tab.name}</span>
            <span className="pricing-tab-separator" aria-hidden="true">
              &middot;
            </span>
            <span className="pricing-tab-device">{tab.device}</span>
          </button>
        )
      })}
    </div>
  )
}

function PricingPanels({ children }: { children: React.ReactNode }) {
  return <div className="pricing-panels">{children}</div>
}

function PricingPanel({
  id,
  labelledBy,
  controlledBy,
  children,
}: {
  id: string
  labelledBy: string
  /** id of the tab that controls this panel */
  controlledBy: string
  children: React.ReactNode
}) {
  const { activeId } = usePricingTabsContext()
  return (
    <div
      className="pricing-panel"
      id={id}
      role="tabpanel"
      aria-labelledby={labelledBy}
      hidden={controlledBy !== activeId}
    >
      {children}
    </div>
  )
}

export { PricingTabsProvider, PricingTabList, PricingPanels, PricingPanel }
export type { Tab as PricingTab }
