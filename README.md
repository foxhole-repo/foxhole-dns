# Foxhole DNS

This repository is the public update channel for Foxhole DNS rule-set data.

The Android app must not download a mutable `raw.githubusercontent.com/main` file and trust it directly. Foxhole downloads `manifest.json`, verifies `manifest.json.sig` with the public key embedded in the app, downloads the referenced `.srs` artifact, verifies its size and SHA-256, writes it to a temporary file, and then atomically replaces the previous verified rule set.

If any verification step fails, the app keeps using the bundled fallback or the last verified local rule set. VPN startup must not depend on this repository being reachable.

## Published files

- `manifest.json` describes the generated rule-set artifact and its source commit.
- `manifest.json.sig` is a signature over the exact `manifest.json` bytes.
- `manifest.public.pem` is the public key used by Foxhole app builds to verify `manifest.json.sig`.
- `adguard-dns-filter.srs` is sing-box DNS rule-set data.
- `adguard-dns-filter.srs.sha256` contains the SHA-256 of the `.srs` artifact.
- `source-info.json` records the upstream source and generated artifact metadata.
- `LICENSES.md` documents the source and generated-data licensing.
- `build-adguard-dns-filter.sh` builds the files above from the upstream AdGuard DNS filter.

The `.srs` file is not executable code. It is a signed DNS rule-set data file for sing-box. It is not a DEX, JAR, native library, plugin, script, or runtime backend.

## Official endpoints

Default app manifest URL:

```text
https://foxhole-repo.github.io/foxhole-dns/manifest.json
```

Repository URL:

```text
https://github.com/foxhole-repo/foxhole-dns
```

The app should let users configure the manifest URL, while keeping this URL as the default official source.

## Build model

The scheduled GitHub Actions workflow:

1. Checks out this repository.
2. Downloads a pinned sing-box release.
3. Clones `AdguardTeam/AdGuardSDNSFilter`.
4. Records the exact upstream commit.
5. Builds `Filters/filter.txt`.
6. Converts it with `sing-box rule-set convert --type adguard`.
7. Computes SHA-256 and file size.
8. Writes `manifest.json` and `source-info.json`.
9. Signs `manifest.json`.
10. Publishes the generated files to GitHub Pages and as release assets.
11. Keeps short-lived workflow artifacts for 7 days.
12. Deletes old DNS releases and their tags, keeping the latest 5 releases as an audit/history backup.

## Signing

The workflow expects a repository secret named `FOXHOLE_DNS_SIGNING_KEY_PEM`.

Use a P-256 ECDSA private key in PEM format:

```sh
openssl ecparam -name prime256v1 -genkey -noout -out manifest.private.pem
openssl ec -in manifest.private.pem -pubout -out manifest.public.pem
```

Store only the private key as the GitHub Actions secret. Embed `manifest.public.pem` in the app build that verifies `manifest.json.sig`.

The signature format is the binary output of:

```sh
openssl dgst -sha256 -sign manifest.private.pem -out manifest.json.sig manifest.json
```

## Verification

Each generated release is verifiable from public metadata:

- `manifest.json` records the upstream repository, commit, input path, input SHA-256, artifact size, and artifact SHA-256.
- `manifest.json.sig` signs the exact `manifest.json` bytes.
- `adguard-dns-filter.srs.sha256` verifies the published rule-set artifact.
- `source-info.json` repeats the source and artifact provenance in a review-friendly form.

Reviewers can verify a published update with:

```sh
openssl dgst -sha256 -verify manifest.public.pem -signature manifest.json.sig manifest.json
sha256sum -c adguard-dns-filter.srs.sha256
```

The checked-in seed artifact is the app's current bundled fallback. Scheduled workflow output replaces the seed files on GitHub Pages and in release assets with a freshly generated, signed rule set.

## Update policy

The workflow runs on manual dispatch and on a 72-hour schedule. This keeps DNS filtering data reasonably current without turning the app into a high-frequency remote-update client.

GitHub Pages is the primary official update channel. GitHub Releases are an audit/history backup for signed snapshots and provenance data, not the app's primary download source. The repository keeps only the latest 5 DNS releases and removes older `dns-rules-*` tags together with their releases. Generated workflow artifacts are retained for 7 days.

Foxhole treats this repository as a transparent source for optional DNS filtering data:

- The app includes a bundled fallback rule set.
- Updates are opt-in.
- The update source is configurable.
- Downloaded files are data files, not executable code.
- The app verifies the signed manifest, artifact size, and SHA-256 before use.
- Failed updates fall back to bundled or last verified data.

Foxhole does not send installed app lists, user exceptions, DNS logs, filtering statistics, or browsing history to this repository.
