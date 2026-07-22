# Refreshing the Callsign Country Data

HTCommander resolves the country / DXCC entity of any callsign fully offline,
even when the (optional) US FCC license database is not installed. This works
thanks to a small, built-in lookup table derived from AD1C's **Amateur Radio
Country Files** (<https://www.country-files.com>).

The table is bundled directly into the app as a gzip-compressed JSON asset, so
it is **not** downloaded at runtime — it ships with the application and is
loaded into memory at startup.

- **Asset:** `src/assets/callsign/cty.json.gz`
- **Build tool:** `src/tools/build_cty.py`
- **Reader:** `src/lib/callsign/callsign_country.dart`

The country data changes only occasionally (new DXCC entities, prefix
reassignments, special-event callsigns). Refresh it whenever you want to pick up
the latest `cty.csv`, typically as part of preparing a release.

## Prerequisites

- Python 3 (no third-party packages required — only the standard library).
- Internet access to download `cty.csv` from country-files.com.

## Refresh Steps

1. Open a terminal in the `src/tools` directory:

   ```powershell
   cd src\tools
   ```

2. Download the latest data and rebuild the bundled asset:

   ```powershell
   python build_cty.py --download --out ..\assets\callsign\cty.json.gz
   ```

   The tool prints a summary, for example:

   ```text
   Downloading https://www.country-files.com/bigcty/cty.csv ...
     301,364 bytes
   Countries : 340
   Prefixes  : 7,224
   Exact     : 21,169
   Raw JSON  : 369,299 bytes
   Gzipped   : 95,604 bytes -> ...\src\assets\callsign\cty.json.gz
   ```

3. Verify the lookup still works:

   ```powershell
   cd ..
   flutter test test\callsign_country_test.dart
   ```

4. Commit the regenerated asset:

   ```powershell
   git add src/assets/callsign/cty.json.gz
   git commit -m "Update callsign country data"
   ```

## Building From a Local File

If you already have a `cty.csv` (or want to use the standard contest file
instead of the larger "Big CTY" file), skip the download and point the tool at
your local copy:

```powershell
python build_cty.py --csv .\cty.csv --out ..\assets\callsign\cty.json.gz
```

You can also override the download URL:

```powershell
python build_cty.py --download --url https://www.country-files.com/bigcty/cty.csv --out ..\assets\callsign\cty.json.gz
```

## Notes

- **Size impact:** the asset is roughly ~95 KB compressed — negligible compared
  to the ~22 MB optional FCC license database.
- **Data source format:** `cty.csv` lines are
  `PrimaryPrefix,CountryName,DXCC,Continent,CQZone,ITUZone,Lat,Lon,GMT,AliasList;`
  where the alias list is space-separated. A token beginning with `=` is an
  exact full callsign; other tokens are prefixes. Override modifiers
  (`(cq)`, `[itu]`, `<lat/lon>`, `{continent}`, `~tz~`) are stripped by the build
  tool because country lookups key on the entity, which those overrides never
  change.
- **Attribution:** the Amateur Radio Country Files are maintained by Jim Reisert
  AD1C and are free to use. Keep the attribution string emitted in the asset.
