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

## interface rules

- use native macOS hierarchy, materials, typography, focus rings, menus, dialogs, and keyboard behavior as the base. custom chrome stays around capture selection, preview progress, and small brand moments.
- distinguish idle, choosing, ready, recording, processing, compressed, saved, copied, and error states with clear text and shape. color and sound are secondary.
- keep the selected region legible over bright, dark, and moving backgrounds. the magnifier shows the exact pixels under a dragged corner and never appears in the output.
- motion is brief and purposeful: selection snaps into place, recording begins with one clear beat, the preview resolves without a long spinner, and successful copy/save gets a short confirmation. respect reduced motion and low power mode.
- optimize for keyboard use and VoiceOver. every icon needs an accessible name; every sound has a visible equivalent; every interaction works without hover.
- use destination logos only when permitted by their brand guidelines, keep them subordinate to the file-size label, and provide a text name for accessibility.

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

- review loop-frame sketches and approve the final mark.
- choose exact warm orange values for light and dark appearance.
- choose whether sound resembles a soft click, a light digital pop, or another direction.
- approve the final artwork, motion, and usage rules before any agent treats them as fixed.
