# Licenses

## Generated DNS Rule Set

`adguard-dns-filter.srs` is generated from:

- Project: AdGuard DNS filter
- Repository: <https://github.com/AdguardTeam/AdGuardSDNSFilter>
- License: GPL-3.0
- Input path: `Filters/filter.txt`

The generated sing-box `.srs` file is derived rule-set data and should be treated as GPL-3.0-covered data from the upstream filter source.

## Build Script and Repository Metadata

The Foxhole build script, workflow, manifest metadata, and documentation in this repository are intended to be distributed under GPL-3.0-or-later, matching the generated filter data's upstream license boundary.

## sing-box

The build uses the `sing-box rule-set convert --type adguard` command to convert AdGuard DNS filter text into sing-box binary rule-set data.

sing-box repository: <https://github.com/SagerNet/sing-box>

The sing-box binary is a build tool and is not shipped to Foxhole users from this repository.

## No Executable App Code

The published `.srs` artifact is DNS filtering data for sing-box. It is not executable application code, not a plugin, and not a runtime backend.
