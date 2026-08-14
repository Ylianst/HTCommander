# Updating the CA Root Certificate Bundle

HTCommander downloads the optional callsign databases (FCC / ISED) over HTTPS
from GitHub. To keep those downloads working on machines whose operating-system
trust store is outdated or broken, the app ships a bundled set of Mozilla CA
root certificates and falls back to them when the system store cannot verify the
server's certificate chain.

- **Asset:** `src/assets/certs/cacert.pem`
- **Source:** Mozilla CA bundle, extracted by the curl project
  (<https://curl.se/docs/caextract.html>)
- **Registered in:** `src/pubspec.yaml` (under `flutter: assets:`)
- **Consumer:** `src/lib/services/callsign_lookup_service.dart`

## How the bundle is used

Both the manifest fetch and the database download try the **default** HTTP
client first — the one that uses the machine's own trust store. Only if that
raises a `HandshakeException` (i.e. the OS store can't verify the chain) does the
code retry with a `SecurityContext` that trusts the bundled roots:

- Normal machines succeed on the first try; the bundle is never touched.
- Corporate / antivirus TLS-inspection proxies succeed on the first try, because
  their private root lives in the OS store (the Mozilla bundle alone would not
  trust it).
- Machines with a stale or corrupt OS root store fail the first try and succeed
  on the fallback against the bundled roots.

Certificate verification is **never** disabled in either path.

## When to refresh

`cacert.pem` is a point-in-time snapshot of Mozilla's trusted roots. Refresh it
periodically — a good time is when preparing a release — so newly added roots
are present and removed/expired roots are dropped.

## Prerequisites

- Internet access to download the bundle from `curl.se`.

## Refresh Steps

1. Download the latest bundle over the existing asset:

   ```powershell
   Invoke-WebRequest -Uri "https://curl.se/ca/cacert.pem" `
     -OutFile "src\assets\certs\cacert.pem"
   ```

2. Sanity-check the file — confirm the header date is recent and it contains a
   plausible number of certificates:

   ```powershell
   Select-String -Path "src\assets\certs\cacert.pem" -Pattern "Certificate data from Mozilla" `
     | Select-Object -First 1
   (Select-String -Path "src\assets\certs\cacert.pem" -Pattern "BEGIN CERTIFICATE").Count
   ```

   Expect a header such as `## Certificate data from Mozilla as of: ...` and a
   count of roughly 120–150 certificates.

3. (Optional but recommended) Verify the download against the SHA-256 published
   on <https://curl.se/docs/caextract.html>. The `cacert.pem` header also embeds
   a `## SHA256:` line for the file's own contents:

   ```powershell
   (Get-FileHash "src\assets\certs\cacert.pem" -Algorithm SHA256).Hash.ToLower()
   ```

4. Rebuild the app so the updated asset is bundled, and confirm a callsign
   database download still succeeds.

## Notes

- **Do not** hand-edit `cacert.pem`; always replace it with a full bundle from
  curl.se so the format stays consistent.
- The file is PEM text (`-----BEGIN CERTIFICATE-----` blocks) and is safe to
  commit; it contains only public root certificates.
- **Attribution:** the bundle is derived from Mozilla's root certificate store
  and repackaged by the curl project. Keep the header comments intact.
