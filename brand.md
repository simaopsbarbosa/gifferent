# brand direction

## approved foundation

- name: gifferent.
- personality: quietly playful, minimal, and quick.
- mark: develop the loop-frame concept first: simple geometry expressing looping motion inside a capture frame. it must work in a tiny menu bar icon and as a larger app identity. animated ascii effects and dithering effects are the main concept to be explored.
- palette: mostly monochrome with a warm orange accent.
- presence: use small, occasional brand accents inside capture and recording UI. the product must still look native to macOS.
- sound: subtle and optional. sounds confirm meaningful actions; no sound is required to understand a state.

## selected direction and unused alternatives

1. **loop frame:** an open loop made of two clean arcs inside a crop frame. the frame can briefly close when recording starts.
2. **return stroke:** one continuous geometric path that turns back on itself, forming a compact `g`-like loop without becoming a literal lettermark.
3. **two-frame orbit:** two offset rounded frames imply successive GIF frames and a circular return. a small accent dot marks the current frame.

the architect selected **loop frame** for the first candidate. the other concepts are reference options, not parallel implementation work. this is a concept brief, not approved artwork. create black-and-white small-size studies first and inspect at menu bar size. add warm orange only after the silhouette works. provide light and dark variants and a high-contrast option. do not lift Augusta Labs or Cloudflare assets, proportions, or icon designs.

first-round monochrome studies are available in the [accessible contact sheet](Brand/Studies/index.html), with tradeoffs in [review notes](Brand/Studies/review-notes.md). these are review material only; none is approved artwork.

the architect selected study c, the vertical loop, for a second round of refinement. this selects a direction to explore, not final artwork; keep the original study and document any changes and tradeoffs.

the architect selected variant b, with directional ends, to proceed to final-art exploration. the second-round [accessible comparison sheet](Brand/Studies/round-two/index.html) records all three monochrome refinements. this selection does not approve final artwork, orange values, motion, or sound.

round-three [final-art explorations](Brand/Studies/round-three/index.html) refine variant b into three silhouettes, each shown in monochrome and with a provisional warm-orange accent. all artwork, color, motion, and sound choices remain open for architect review.

the architect selected 03, compact orbit, to move into detailed final-art review. this is a refinement direction only; do not treat its silhouette or provisional orange sample as approved artwork or color.

the accessible [detail-round comparison](Brand/Studies/detail-round/index.html) refines 03 into three menu-bar and app-icon treatments. all three remain review studies; no silhouette or orange value has final approval.

the architect selected detail-round 02, breathing room, to proceed toward final-art approval. the 16 px break and provisional orange treatment still need review; this selection does not approve final artwork, color, motion, or sound.

the [final-art review](Brand/Studies/final-art-review/index.html) compares three provisional orange accents on the selected geometry. the architect requested an adjustment to the gap at 16 px and selected warm orange `#D45D21` to continue into palette review. both remain provisional: the gap needs another comparison, and the orange is not an approved palette value. final artwork, palette, usage rules, motion, and optional sound remain subject to architect approval.

the accessible [gap review](Brand/Studies/gap-review/index.html) compares 0.7 px, 1.0 px, and 1.36 px gaps at 16 px, with proportional examples through 256 px and light, dark, and high-contrast contexts. it carries `#D45D21` forward only as the provisional palette-review starting point. no gap, final artwork, or palette value is approved.

the architect selected the 0.7 px gap at 16 px to continue into palette and final-art exploration. this chooses the next study direction; it does not approve the production mark or exact palette.

the accessible [palette review](Brand/Studies/palette-review/index.html) holds that gap constant across a monochrome reference and three provisional warm oranges. its [review notes](Brand/Studies/palette-review/review-notes.md) document contrast tradeoffs and why flat black/white ratios do not establish appearance over translucent macOS materials. no palette, final artwork, or usage rules are approved.

the architect approved the static orange mark shown in the [production-mark review sheet](Brand/Studies/production-mark-review/index.html): compact orbit 03, breathing-room treatment 02, 0.7 px curve-to-tip gap at 16 px, and direction tips in `#D45D21`. the optional motion concept remains unapproved. production assets are [light appearance](Brand/mark-light.svg) and [dark appearance](Brand/mark-dark.svg); the approved orange direction tips sit on a monochrome frame and loop.

## interface rules

- use native macOS hierarchy, materials, typography, focus rings, menus, dialogs, and keyboard behavior as the base. custom chrome stays around capture selection, preview progress, and small brand moments.
- distinguish idle, choosing, ready, recording, processing, compressed, saved, copied, and error states with clear text and shape. color and sound are secondary.
- keep the selected region legible over bright, dark, and moving backgrounds. the magnifier shows the exact pixels under a dragged corner and never appears in the output.
- motion is brief and purposeful: selection snaps into place, recording begins with one clear beat, the preview resolves without a long spinner, and successful copy/save gets a short confirmation. respect reduced motion and low power mode.
- optimize for keyboard use and VoiceOver. every icon needs an accessible name; every sound has a visible equivalent; every interaction works without hover.
- use destination names with native symbols on optimizer controls; do not bundle third-party destination marks unless written permission is obtained.

## copy examples

| state | preferred text |
| --- | --- |
| ready | `record` |
| recording | `recording · 00:08` |
| processing | `making gif` |
| copy success | `copied` |
| save success | `saved` |
| size goal missed | `couldn't reach 10 mb` |
| permission needed | `allow screen recording to continue` |

all examples are provisional until tested for clarity in the real UI. keep prose lowercase except proper names and exact technical identifiers. do not add decorative copy to fill space.

## pending brand decisions

- validate the approved static mark against real macOS menu-bar materials and accessibility settings.
- keep orange `#D45D21` on the direction tips; frame and loop adapt to light and dark appearance.
- decide whether to develop the optional motion concept; sound remains open.
- choose whether sound resembles a soft click, a light digital pop, or another direction.
