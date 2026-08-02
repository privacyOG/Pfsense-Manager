# Phase 3 accessibility and release foundation

This phase establishes the first maintainability and accessibility baseline for pfSense Manager.

## Included

- logical start-to-end destructive confirmation gestures for both LTR and RTL layouts
- TalkBack and screen-reader activation through standard button semantics
- keyboard activation with Enter or Space and a visible focus treatment
- scalable confirmation controls and scroll-safe bottom sheets for large text
- localized cancellation text using the existing application localization layer
- targeted widget regression coverage for LTR, RTL, semantics, keyboard input, large text and Arabic
- immutable commit pins for reusable GitHub Actions used by CI and production release workflows
- a focused accessibility test gate before the complete Flutter suite
- full-project analyzer enforcement in the production release workflow
- migration of the release publisher from the unsupported Node 20 v2 line to the Node 24 v3 line

## Deferred architectural work

Typed API DTO adoption and consolidation of the legacy service surface remain separate changes. Keeping those refactors out of this PR makes the accessibility behaviour and release-pipeline changes independently reviewable and reversible.
