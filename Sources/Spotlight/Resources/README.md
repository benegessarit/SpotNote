# Spotlight resources

SpotNote's editor asks AppKit for IBM Plex Mono by PostScript name
`IBMPlexMono`. The app bundles `IBMPlexMono-Regular.ttf` here so the HUD does
not silently fall back to Inter or the generic system font on machines without
IBM Plex Mono installed system-wide. `FontLoader.registerBundledFonts()`
registers bundled `.ttf` / `.otf` files process-locally before the editor asks
for the font.

- `IBMPlexMono-Regular.ttf` or `IBMPlexMono-Regular.otf`
- Optional matching weights, such as `IBMPlexMono-Bold.ttf`

Easiest install:

```bash
brew install --cask font-ibm-plex
# then copy the installed IBM Plex Mono regular file into this directory:
cp ~/Library/Fonts/IBMPlexMono-Regular.ttf \
   Sources/Spotlight/Resources/
```
