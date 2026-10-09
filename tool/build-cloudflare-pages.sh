#!/usr/bin/env bash
# Cloudflare Pages build command for the YɛnKɔ Flutter web frontend.
#
# Run from the repository root (Cloudflare Pages' default working
# directory). Unlike the sibling onb project, YɛnKɔ's Flutter app lives at
# the repo root, not under a mobile/ subdirectory, so this script does not
# `cd` anywhere before building. Publish directory for Cloudflare Pages:
# build/web.
set -euo pipefail

flutter_version="${FLUTTER_VERSION:-3.44.9}"
api_base_url="${YENKO_API_BASE_URL:?Set the Cloudflare Pages YENKO_API_BASE_URL environment variable (your Railway API https origin, e.g. https://yenko-production.up.railway.app) before building.}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

use_local_flutter() {
  command -v flutter >/dev/null 2>&1 && \
    flutter --version 2>/dev/null | grep -q "Flutter ${flutter_version}"
}

if use_local_flutter; then
  flutter_cmd="$(command -v flutter)"
else
  flutter_cache_dir="${HOME:-/tmp}/.cache/yenko/flutter-${flutter_version}"
  flutter_cmd="${flutter_cache_dir}/flutter/bin/flutter"
  if [[ ! -x "$flutter_cmd" ]]; then
    mkdir -p "$flutter_cache_dir"
    curl --fail --location --retry 3 \
      "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${flutter_version}-stable.tar.xz" \
      | tar -xJ -C "$flutter_cache_dir"
  fi
fi

cd "$repo_root"
"$flutter_cmd" config --no-analytics
"$flutter_cmd" pub get
"$flutter_cmd" build web --release --no-web-resources-cdn \
  --dart-define="YENKO_USE_LOCAL_API=true" \
  --dart-define="YENKO_API_BASE_URL=${api_base_url}"
