async function inspectRoute(path, width = 320, textScale = 1) {
  const frame = document.createElement('iframe');
  frame.style.cssText = `position:fixed;left:-10000px;top:0;width:${width}px;height:900px;border:0`;
  const ready = new Promise((resolve, reject) => {
    frame.onload = resolve;
    frame.onerror = () => reject(new Error(`Could not load ${path}`));
  });
  frame.src = `${path}${path.includes('?') ? '&' : '?'}site-audit=${width}-${textScale}`;
  document.body.append(frame);
  try {
    await ready;
    const doc = frame.contentDocument;
    const win = frame.contentWindow;
    if (textScale !== 1) {
      const sizes = [...doc.querySelectorAll('h1,h2,h3,p,a,button,summary,kbd,span,strong,th,td,figcaption')]
        .map(element => [element, parseFloat(win.getComputedStyle(element).fontSize)]);
      for (const [element, size] of sizes) element.style.setProperty('font-size', `${size * textScale}px`, 'important');
    }
    const isScrollable = (element) => {
      for (let node = element.parentElement; node && node !== doc.body; node = node.parentElement) {
        if (['auto', 'scroll'].includes(win.getComputedStyle(node).overflowX)) return true;
      }
      return false;
    };
    const overflow = [];
    for (const element of doc.querySelectorAll('main *,header *,footer *')) {
      const rect = element.getBoundingClientRect();
      const style = win.getComputedStyle(element);
      if (rect.width <= 0 || ['absolute', 'fixed'].includes(style.position) || element.closest('[hidden]') || isScrollable(element)) continue;
      if (rect.left < -0.75 || rect.right > width + 0.75) {
        overflow.push({ tag: element.tagName, className: typeof element.className === 'string' ? element.className : '', text: element.textContent.slice(0, 70), left: rect.left, right: rect.right });
        if (overflow.length === 8) break;
      }
    }
    const heading = doc.querySelector('h1');
    const header = doc.querySelector('.site-header');
    const navTargets = [...doc.querySelectorAll('.site-header a')].map(element => element.getBoundingClientRect().height).filter(value => value > 0);
    const result = {
      path, width, textScale,
      mainCount: doc.querySelectorAll('main').length,
      headingInMain: !!heading?.closest('main'),
      headerOutsideMain: !header?.closest('main'),
      headingFont: heading ? win.getComputedStyle(heading).fontFamily : null,
      headerOverlap: !!(heading && header && heading.getBoundingClientRect().top < header.getBoundingClientRect().bottom - 1),
      minNavTarget: Math.min(...navTargets),
      swaguiButtons: doc.querySelectorAll('[data-slot="button"]').length,
      overflow,
    };
    if (window.__siteAxeSource && textScale === 1) {
      win.eval(window.__siteAxeSource);
      const audit = await win.axe.run(doc, { runOnly: { type: 'tag', values: ['wcag2a', 'wcag2aa', 'wcag21aa', 'wcag22aa'] } });
      result.violations = audit.violations.map(item => ({ id: item.id, impact: item.impact, nodes: item.nodes.slice(0, 6).map(node => ({ target: node.target, summary: node.failureSummary })) }));
      result.manualChecks = audit.incomplete.map(item => ({ id: item.id, nodes: item.nodes.length }));
    }
    return result;
  } finally {
    frame.remove();
  }
}
