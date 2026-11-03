# region selection refinement plan

## status and intent

documentation plan, 2026-11-01; no product code is changed by this document. this is a focused refinement of iteration 1 capture selection, subject to the existing [delivery gates](delivery-plan.md) and [definition of done](definition-of-done.md).

keep the selection overlay's layout and appearance. remove the redundant `select a window` label from the window picker while retaining `choose a window` as its empty value. make drag intent on an existing region predictable: dragging a corner resizes that corner and shows the magnifier; dragging inside the region moves it without showing the magnifier. dragging outside the existing region continues to draw a new region with the magnifier.

## current behavior and integration seam

[CaptureSelectionOverlayView.swift](../Sources/Selection/CaptureSelectionOverlayView.swift) layers a full-display region-creation drag behind the selected-region outline, which has separate move and corner-resize gestures. the picker currently has both the `select a window` accessibility title and `choose a window` empty option. selection geometry already provides bounded move and corner-resize operations in [SelectionGeometry.swift](../Sources/Selection/SelectionGeometry.swift).

the observed bug is consistent with competing gesture routing: a drag beginning at or near a visible corner can be handled by the full-display creation gesture instead of the corner gesture. implementation should make the start point choose exactly one operation and preserve its magnifier policy for the full drag.

inspect the working tree and current overlay behavior again before implementation. keep changes within the selection controls, gesture routing, and directly relevant tests; do not redesign the overlay or capture pipeline.

## observable behavior and acceptance scenarios

1. opening the overlay preserves the current controls and placement. the window picker has no separate `select a window` label, and its unselected value remains `choose a window`.
2. from a valid selected region, dragging any visible corner changes only the corresponding corner, keeps the opposite corner anchored subject to display bounds, and shows the magnifier during the drag. releasing commits the adjusted region and hides the magnifier.
3. dragging from the interior of a selected region translates the whole region, preserves its size, clamps it to the display, and never shows the magnifier. releasing commits the moved region.
4. dragging outside the selected region starts a new region, replacing the old one only after a valid drag completes, and shows the magnifier. a too-small or cancelled creation does not leave a malformed selection.
5. dragging on the corner hit target takes resize precedence and cannot also create or move a region. interior movement cannot trigger creation. test points near, but outside, the corner hit target to ensure the gesture boundary is intentional.
6. selection remains valid at display edges and under supported display scale factors; confirmation continues to select the expected display-local geometry.
7. keyboard and VoiceOver users retain named, reachable controls and selected-region dimensions. gesture affordances do not become the only way to select a display, window, or region.

## implementation sequence

1. **establish hit areas and routing.** document the corner target dimensions and use one explicit gesture-intent decision at drag start, with corner handles taking priority, then interior move, then empty-space creation. avoid simultaneous competing parent/child drags. keep coordinate conversion in display-local points.
2. **preserve operation-specific feedback.** resize and creation update `magnifierPoint`; move clears/keeps it nil. clear drag draft and magnifier state on every end and cancellation path. commit only valid geometry and leave the last valid selection intact when a draft fails.
3. **remove picker redundancy.** remove the redundant picker title while retaining its menu style, identifier, binding behavior, and `choose a window` placeholder. verify accessible naming remains useful with VoiceOver; the visual controls stay otherwise unchanged.
4. **add focused coverage.** test gesture intent selection and geometry transitions at corners, interior, and outside points at the lowest practical layer. keep existing geometry and UI journey coverage; extend UI acceptance to adjust an existing region corner and move its interior, checking the selected dimensions/position and magnifier state where the UI harness can observe it.
5. **verify and update.** run focused selection unit/integration checks, relevant quality checks, and the selected UI journey on the final candidate. perform real-Mac observation of magnifier visibility, pointer hit behavior, and control accessibility; report unavailable UI bootstrap evidence without retrying unchanged failures. update this plan and source-of-truth docs if implementation reveals a real product ambiguity.

## failure, cancellation, and scope

- invalid or sub-minimum geometry does not replace the last valid selection.
- pointer release always clears transient draft and magnifier state, including when geometry conversion fails.
- Escape and overlay cancellation continue through the existing coordinator cancellation path.
- no permission, capture, recording, encoding, privacy, or temporary-file behavior changes.
- edge-drag resizing is not specified here; preserve current behavior unless implementation testing shows it is needed to make the requested corner and interior paths reliable, then record a product question before expanding scope.

## evidence

record focused check commands and outcomes, the final UI acceptance result, and real-Mac visual/accessibility observations with machine and OS. this interaction does not change a measured performance path; do not claim a performance improvement.
