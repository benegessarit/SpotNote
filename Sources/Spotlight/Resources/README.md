# Spotlight resources

SpotNote's editor asks AppKit for **MonoLisa** by PostScript name
`MonoLisa-Regular`. MonoLisa is a licensed font, so it is **not** bundled or
redistributed here — install it into `~/Library/Fonts` (regular + bold/italic
weights) and the editor resolves it system-wide. Bold/italic styling derives
from the installed weights via `NSFontManager` trait conversion in the code
stylers.

When MonoLisa is not installed, the editor falls back to the bundled
`IBMPlexMono-Regular.ttf` (so the HUD never drops to Inter or a proportional
system font), then to the system monospaced face. `FontLoader.registerBundledFonts()`
registers bundled `.ttf` / `.otf` files process-locally before the editor asks
for the font.

Bundled fallback font:

- `IBMPlexMono-Regular.ttf` or `IBMPlexMono-Regular.otf`
- Optional matching weights, such as `IBMPlexMono-Bold.ttf`

Installing the bundled fallback (only needed if you change which fallback ships):

```bash
brew install --cask font-ibm-plex
# then copy the installed IBM Plex Mono regular file into this directory:
cp ~/Library/Fonts/IBMPlexMono-Regular.ttf \
   Sources/Spotlight/Resources/
```
