# Spotlight resources

`FontLoader.registerBundledFonts()` registers every bundled `.ttf` / `.otf`
process-locally at launch, before any view asks for a face by PostScript
name. `.custom`/`NSFont(name:)` fall back SILENTLY on a wrong PostScript
name, so never rename these files casually.

Bundled fonts:

- `LilexNerdFontMono-Regular.ttf` / `LilexNerdFontMono-Bold.ttf`
  (PostScript `LilexNFM-Regular` / `LilexNFM-Bold`) — the EDITOR body,
  the same mono face David's nvim renders in (Ghostty `font-family`,
  IBM Plex Mono letterforms + ligatures). `SpotNoteFont.editor()` asks
  for it and falls back to the system monospaced face; bold/italic
  derive in-family via `NSFontManager` trait conversion.
- `Inter-Regular.otf` / `Inter-Medium.otf` (PostScript `Inter-Regular` /
  `Inter-Medium`) — ALL Raycast-parity chrome text via `RaycastFont`
  (the live Raycast app ships Inter in its frontend bundle).

The PNGs are exact @raycast/icons v0.4.7 rasters (white-on-transparent,
128px, rendered from the package path data) plus composed glyphs that the
public icon set lacks (`RaycastTextSearch`); sibling `.svg` files keep the
source geometry.
