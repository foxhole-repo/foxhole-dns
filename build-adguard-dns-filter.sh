#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${FOXHOLE_DNS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
OUT_DIR="${OUT_DIR:-$ROOT_DIR}"
WORK_DIR="${WORK_DIR:-$(mktemp -d)}"
SOURCE_REPO="${SOURCE_REPO:-https://github.com/AdguardTeam/AdGuardSDNSFilter.git}"
SOURCE_REF="${SOURCE_REF:-HEAD}"
SING_BOX_BIN="${SING_BOX_BIN:-sing-box}"
SING_BOX_VERSION="${SING_BOX_VERSION:-1.13.11}"
MIN_APP_VERSION="${MIN_APP_VERSION:-1.0.0-beta1}"
FILTER_NAME="${FILTER_NAME:-adguard-dns-filter.srs}"
MANIFEST_NAME="${MANIFEST_NAME:-manifest.json}"
SOURCE_INFO_NAME="${SOURCE_INFO_NAME:-source-info.json}"
REQUIRE_SIGNATURE="${FOXHOLE_DNS_REQUIRE_SIGNATURE:-true}"
SIGNING_KEY_PATH="${FOXHOLE_DNS_SIGNING_KEY:-}"
SIGNING_KEY_PEM="${FOXHOLE_DNS_SIGNING_KEY_PEM:-}"

cleanup() {
  if [[ "${KEEP_WORK_DIR:-false}" != "true" && -d "$WORK_DIR" ]]; then
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

need() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'Missing required command: %s\n' "$1" >&2
    exit 1
  }
}

need git
need jq
need openssl
need sha256sum
need node

if [[ ! -x "$SING_BOX_BIN" ]] && ! command -v "$SING_BOX_BIN" >/dev/null 2>&1; then
  printf 'Missing required sing-box command: %s\n' "$SING_BOX_BIN" >&2
  exit 1
fi

if ! command -v yarn >/dev/null 2>&1; then
  need corepack
fi

run_yarn() {
  if command -v yarn >/dev/null 2>&1; then
    yarn "$@"
  else
    corepack yarn "$@"
  fi
}

run_with_retries() {
  local attempts="${FOXHOLE_DNS_BUILD_ATTEMPTS:-3}"
  local delay_seconds="${FOXHOLE_DNS_BUILD_RETRY_DELAY_SECONDS:-30}"
  local attempt=1

  while true; do
    if "$@"; then
      return 0
    fi
    if (( attempt >= attempts )); then
      return 1
    fi
    printf 'Command failed, retrying in %s seconds (%s/%s): %s\n' \
      "$delay_seconds" "$attempt" "$attempts" "$*" >&2
    sleep "$delay_seconds"
    attempt=$((attempt + 1))
  done
}

mkdir -p "$OUT_DIR" "$WORK_DIR"

SOURCE_DIR="$WORK_DIR/AdGuardSDNSFilter"
if [[ "$SOURCE_REF" == "HEAD" ]]; then
  git clone --depth 1 "$SOURCE_REPO" "$SOURCE_DIR"
else
  git init "$SOURCE_DIR"
  git -C "$SOURCE_DIR" remote add origin "$SOURCE_REPO"
  git -C "$SOURCE_DIR" fetch --depth 1 origin "$SOURCE_REF"
  git -C "$SOURCE_DIR" checkout --detach FETCH_HEAD
fi

SOURCE_COMMIT="$(git -C "$SOURCE_DIR" rev-parse HEAD)"

if [[ -f "$SOURCE_DIR/package.json" ]]; then
  (
    cd "$SOURCE_DIR"
    run_yarn install --frozen-lockfile || run_yarn install
    run_with_retries run_yarn run build
  )
fi

INPUT_FILE="$SOURCE_DIR/Filters/filter.txt"
if [[ ! -s "$INPUT_FILE" ]]; then
  printf 'Missing built AdGuard input filter: %s\n' "$INPUT_FILE" >&2
  exit 1
fi

ARTIFACT_PATH="$OUT_DIR/$FILTER_NAME"
"$SING_BOX_BIN" rule-set convert --type adguard --output "$ARTIFACT_PATH" "$INPUT_FILE"

INPUT_SHA256="$(sha256sum "$INPUT_FILE" | awk '{print $1}')"
ARTIFACT_SHA256="$(sha256sum "$ARTIFACT_PATH" | awk '{print $1}')"
ARTIFACT_SIZE="$(wc -c < "$ARTIFACT_PATH" | tr -d ' ')"
GENERATED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

printf '%s  %s\n' "$ARTIFACT_SHA256" "$FILTER_NAME" > "$OUT_DIR/$FILTER_NAME.sha256"

jq -n \
  --arg generated_at "$GENERATED_AT" \
  --arg source_repo "$SOURCE_REPO" \
  --arg source_commit "$SOURCE_COMMIT" \
  --arg input_sha256 "$INPUT_SHA256" \
  --arg file "$FILTER_NAME" \
  --arg sha256 "$ARTIFACT_SHA256" \
  --arg sing_box_version "$SING_BOX_VERSION" \
  --arg min_app_version "$MIN_APP_VERSION" \
  --argjson size "$ARTIFACT_SIZE" \
  '{
    schema: 1,
    name: "foxhole-adguard-dns-filter",
    format: "sing-box-srs",
    generated_at: $generated_at,
    source: {
      name: "AdGuardSDNSFilter",
      repo: $source_repo,
      commit: $source_commit,
      license: "GPL-3.0",
      input_path: "Filters/filter.txt",
      input_sha256: $input_sha256
    },
    artifact: {
      file: $file,
      size: $size,
      sha256: $sha256
    },
    compatibility: {
      sing_box_version: $sing_box_version,
      min_app_version: $min_app_version
    }
  }' > "$OUT_DIR/$MANIFEST_NAME"

jq -n \
  --arg generated_at "$GENERATED_AT" \
  --arg source_repo "$SOURCE_REPO" \
  --arg source_commit "$SOURCE_COMMIT" \
  --arg input_sha256 "$INPUT_SHA256" \
  --arg file "$FILTER_NAME" \
  --arg sha256 "$ARTIFACT_SHA256" \
  --arg sing_box_version "$SING_BOX_VERSION" \
  --arg min_app_version "$MIN_APP_VERSION" \
  --argjson size "$ARTIFACT_SIZE" \
  '{
    schema: 1,
    generated_at: $generated_at,
    source: {
      name: "AdGuardSDNSFilter",
      repo: $source_repo,
      commit: $source_commit,
      license: "GPL-3.0",
      input_path: "Filters/filter.txt",
      input_sha256: $input_sha256
    },
    artifact: {
      file: $file,
      size: $size,
      sha256: $sha256
    },
    compatibility: {
      sing_box_version: $sing_box_version,
      min_app_version: $min_app_version
    }
  }' > "$OUT_DIR/$SOURCE_INFO_NAME"

SIGNATURE_PATH="$OUT_DIR/$MANIFEST_NAME.sig"
TEMP_KEY_PATH=""
if [[ -n "$SIGNING_KEY_PEM" ]]; then
  TEMP_KEY_PATH="$WORK_DIR/manifest.private.pem"
  umask 077
  printf '%s\n' "$SIGNING_KEY_PEM" > "$TEMP_KEY_PATH"
  SIGNING_KEY_PATH="$TEMP_KEY_PATH"
fi

if [[ -n "$SIGNING_KEY_PATH" ]]; then
  openssl dgst -sha256 -sign "$SIGNING_KEY_PATH" -out "$SIGNATURE_PATH" "$OUT_DIR/$MANIFEST_NAME"
elif [[ "$REQUIRE_SIGNATURE" == "true" ]]; then
  printf 'Missing signing key. Set FOXHOLE_DNS_SIGNING_KEY or FOXHOLE_DNS_SIGNING_KEY_PEM.\n' >&2
  exit 1
else
  printf 'unsigned-local-build\n' > "$SIGNATURE_PATH"
fi

printf 'Generated %s (%s bytes, sha256=%s)\n' "$FILTER_NAME" "$ARTIFACT_SIZE" "$ARTIFACT_SHA256"
