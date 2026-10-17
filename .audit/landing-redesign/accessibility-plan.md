# Accessibility and readability pass

User asks for readability and accessibility across the board, then explicitly rules out a solid hero-copy background. Preserve the visible beach, use less hero text, and increase text size. Do not add a text panel.

Baseline. axe-core 4.10.3 reported zero definite WCAG A/AA violations on the homepage, but left eleven photo/gradient contrast nodes unresolved. This is not a pass for photographic contrast. Hero terms were11px, pricing12px and selector labels11px. Independent source audit found10px footer labels, small shared nav targets, missing skip links and duplicate main landmarks on secondary routes.

Fix sequence. Keep the hero headline, one short sentence, trial action and one trial line. Remove the redundant hero price line. Raise small body and control text. Put the header into normal flow so larger text and wrapping navigation cannot overlap the hero. Preserve the beach photo and its existing wash. Give selector controls opaque contrast-safe backgrounds. Keep fixed preview geometry and round buttons. Fix shared keyboard focus, navigation targets, footer hierarchy and skip destinations through existing shared rendering paths. Correct duplicate main landmarks without moving visual wrappers.

Verify with rebuilt artifacts, axe-core in T3, actual keyboard navigation, content-target focus, contrast calculations for solid surfaces, sampled photographic contrast,320px reflow,200% text sizing and all four screenshot selections. Do not infer compliance from an empty automated violations list. No app dependency, production deployment or native app change.
