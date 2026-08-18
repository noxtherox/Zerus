# TestFlight command-line upload

The repository can export, validate, and upload a signed iOS archive without
opening Xcode or using UI automation:

```sh
pnpm testflight
```

Create the next build first when the request says **new build**:

```sh
pnpm ios:new-build
```

That command advances the last completed build to the next number, or retries
an already-prepared build number if its archive did not finish. It then creates
the signed archive and exports the IPA. Use
`pnpm ios:new-build -- --dry-run` to inspect the next action without changing
or building anything.

The command selects the newest `.xcarchive` in `src-tauri/gen/apple/build`,
exports a signed IPA to `artifacts/testflight/<version>-<build>`, validates it,
then uploads it to App Store Connect. Failed uploads can be retried without
rebuilding; the exported IPA is reused. Before exporting, it refuses archives
whose metadata, embedded app, or configured release version/build disagree.

## One-time App Store Connect setup

1. In App Store Connect, open **Users and Access > Integrations > App Store
   Connect API > Team Keys**.
2. Generate a key with the **Developer** role (or a stronger role only if the
   rest of the release automation needs it). Download the `.p8` file; Apple
   only offers it once.
3. Put the key in Apple's standard private-key directory:

   ```sh
   mkdir -p ~/.appstoreconnect/private_keys
   mv ~/Downloads/AuthKey_YOUR_KEY_ID.p8 ~/.appstoreconnect/private_keys/
   chmod 600 ~/.appstoreconnect/private_keys/AuthKey_YOUR_KEY_ID.p8
   ```

4. Create `.appstoreconnect.local` in the repository root:

   ```dotenv
   ASC_KEY_ID=YOUR_KEY_ID
   ASC_ISSUER_ID=YOUR_ISSUER_ID
   ```

`.appstoreconnect.local`, `artifacts/`, and the private key are not committed.
Never place the `.p8` key in the repository.

## Useful commands

Export and inspect the newest archive without contacting Apple:

```sh
pnpm testflight -- --export-only
```

Upload a particular archive or retry a particular IPA:

```sh
pnpm testflight -- --archive path/to/App.xcarchive
pnpm testflight -- --ipa artifacts/testflight/0.3.3-33/Zerus.ipa
```

Run `pnpm testflight -- --help` for all options.

## Build-number note

Tauri's `tauri ios build --build-number` value is appended to the configured
build number; it does not replace `CFBundleVersion`. Do not use that flag for
an absolute App Store build number.

The canonical build record is `bundle.iOS.bundleVersion` in
`src-tauri/tauri.conf.json`. Advance that value before creating a new App Store
build (build 19 should be followed by 20), then build with `--archive-only` and
without `--build-number`. The generated `project.yml`, archive metadata,
embedded app, and exported IPA must all match; this script checks them before
uploading.
