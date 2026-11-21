# Brand Assets

- `AppIcon.appiconset/`, `OpenIsland.iconset/`, and `OpenIsland.icns` package the approved light Ribbon macOS app icon.
- `Source/` holds the original source artwork. `Internal/` contains the existing Scout artwork used inside the app.

## Rebuild the Ribbon app icon

Use the ten approved PNGs from the mitama Browser `apps/browser/assets/AppIcon.appiconset/`. They were resized proportionally from the approved `docs/design/brand/app-icon-light.png` in the mitama-os repository. The original PNG has SHA-256 `1ec0ee613769e5fe93b8b3481677f0de804441644cc931c7df61fddfb53ec71c`.

From the Island repository root, point the first line at that approved Browser iconset. The command uses the original filenames and preserves the existing asset-catalog metadata.

```sh
browser_iconset=/absolute/path/to/mitama-os/apps/browser/assets/AppIcon.appiconset
for slot in Assets/Brand/AppIcon.appiconset/icon_*.png; do
  name=${slot##*/}
  cp "$browser_iconset/$name" "$slot" &&
    cp "$browser_iconset/$name" "Assets/Brand/OpenIsland.iconset/$name" || exit 1
done
iconutil -c icns Assets/Brand/OpenIsland.iconset -o Assets/Brand/OpenIsland.icns
```

The two sets use the same five macOS sizes (16, 32, 128, 256, 512 points), each at 1× and 2×. The asset catalog uses the PNGs and the manually assembled development bundle uses the ICNS via `CFBundleIconFile`.

The committed `Assets/Brand/OpenIsland.icns` is the source of truth for packaging and development launch. Both scripts check that it exists and is nonempty, then copy it as-is. Rebuild it manually using the steps above when the approved artwork changes.

## Legacy sources and generator

`Source/logo.png` retains the original 1280×1280 Scout source. `app-icon-v6.png` is the legacy Bar+Dot app icon master. `scripts/generate_brand_icons.py` still regenerates the existing internal Scout assets and rewrites both app icon sets and the ICNS from that legacy app icon master. After running it for the internal artwork, restore the Ribbon packaging assets using the steps above before packaging the app.
