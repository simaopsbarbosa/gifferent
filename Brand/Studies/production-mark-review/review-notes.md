# production-mark review

## approved static mark

the architect approved the static orange mark: vertical loop direction, compact orbit 03, breathing-room treatment 02, a 0.7 px curve-to-tip gap at 16 px, and warm orange `#D45D21` direction tips. production SVGs are available as `Brand/mark-light.svg` and `Brand/mark-dark.svg`. this approval covers the static mark; it does not approve the optional motion study or sound.

## fixed geometry in this round

all sizes use the same 64 × 64 viewBox and the same vector paths. only the displayed size changes: 16, 24, 32, and 512 px. stroke width is 3.5 viewBox units, equivalent to 0.875, 1.3125, 1.75, and 28 px at those sizes. the orange sample colors the direction tips only; the frame and loop remain monochrome.

the 0.7 px gap is a geometric target at 16 px, not a promise that every display scaler preserves a blank pixel. subpixel coverage, antialiasing, and menu-bar material can change the visible break. inspect on the target macOS versions and real menu bars before approval.

## contrast and limitations

`#D45D21` has a flat sRGB contrast ratio of 3.90:1 against white and 5.39:1 against black. monochrome `#111111` on white is approximately 18.88:1; white on black is 21:1. the orange tip is a small graphic detail rather than text and is never the sole status signal. macOS menu-bar materials can be translucent and tinted by desktop content; these flat ratios do not establish contrast on every wallpaper, display, scale factor, or increased-contrast state. the sheet includes pure black/white high-contrast surfaces as boundary samples.

## static and motion study

static artwork is the default in every preview. the optional, user-triggered motion panel demonstrates one restrained concept: a thin frame briefly closes around the loop and returns to the open frame in a single 240 ms beat. it does not loop, change the tips, or imply an approved recording animation. it is disabled when macOS requests reduced motion. no sound is included or proposed here.

## implementation and validation notes

- the SVGs provide black-frame/light-surface and white-frame/dark-surface variants; the orange direction tips stay `#D45D21` in both.
- flat contrast samples do not establish appearance on translucent menu-bar materials. validate the mark at real menu-bar sizes and accessibility settings on supported macOS versions.
- the optional one-shot motion study, motion timing, and sound remain unapproved.

