# HTCommander Specification Sheet

A professional, editable product datasheet generated from a plain-text
[Typst](https://typst.app/) source. The source lives in version control so it
can be reviewed in pull requests and regenerated on demand.

## Files

| File | Purpose |
|------|---------|
| `spec.typ` | The datasheet source. Edit this to update content or styling. |
| `HTCommander-Spec.pdf` | The generated PDF (produced by the build command below). |

## Editing

Most content you'll want to change lives near the top of `spec.typ`:

- **Metadata** (`#let product`, `#let version`, `#let tagline`, ...) — one line each.
- **Theme colors** (`#let brand`, `#let accent`, ...) — change the palette.
- **Feature lists** — `#feature("Name", "Description")` lines.
- **Platform Support Matrix** — the `#table(...)` block; `yes` / `no` / `part` cells.

The document reuses the app icon from `/src/assets/images/AppIcon.png`, resolved
relative to the repository root — this is why the build command below sets
`--root` to the repo root.

## Building the PDF

1. Install Typst (one small self-contained binary, no LaTeX required):

   - **Windows:** `winget install --id Typst.Typst`
   - **macOS:** `brew install typst`
   - **Linux:** `cargo install typst-cli` or download from the
     [releases page](https://github.com/typst/typst/releases)

2. From this folder, run:

   ```powershell
   typst compile --root ..\.. spec.typ HTCommander-Spec.pdf
   ```

To preview live while editing:

```powershell
typst watch --root ..\.. spec.typ HTCommander-Spec.pdf
```

## Why Typst?

- **Editable & diffable:** source is plain text, so changes review cleanly in git.
- **Polished output:** professional datasheet layout, tables, cover page.
- **No heavy toolchain:** a single binary, fast compiles, no LaTeX install.
