#!/usr/bin/env bash
#
# Build the Fleux release manifest for an AnyKernel3 package and (optionally)
# publish it next to the package as a GitLab release asset.
#
# Usage:
#   scripts/release.sh --tag v∞ --zip Fleux-∞.zip \
#       [--kernel-version 4.19.325-Fleux-∞] \
#       [--devices "fleur miel fleur_p miel_p"] [--channel stable] [--build-id 10] \
#       [--ref lineage-24.0] [--notes FILE] [--allow-version-mismatch] [--publish]
#
# Without --publish it only writes fleux-manifest.json next to this repo.
# With --publish it uploads the zip + manifest and creates the GitLab release.
# Publishing reads the token from a `gitlab` git remote, or from $GITLAB_TOKEN.
# The token is never printed.
#
# The manifest is merged by tag (previous releases are preserved).  Publishing
# fails when the built kernel release does not match the tag's LOCALVERSION, or
# when a tag such as v10 does not match -Fleux-V10, or v∞ does not match -Fleux-∞.
set -euo pipefail

PROJECT="${FLEUX_PROJECT:-daliboss/fleux}"
TAG=""
ZIP=""
CHANNEL="stable"
BUILD_ID=""
KERNEL_VERSION=""
DEVICES="fleur miel fleur_p miel_p"
REF="lineage-24.0"
NOTES=""
PUBLISH=0
ALLOW_VERSION_MISMATCH=0
MANIFEST="fleux-manifest.json"

usage() {
  cat <<'EOF'
Build the Fleux release manifest for an AnyKernel3 package and (optionally)
publish it next to the package as a GitLab release asset.

Usage:
  scripts/release.sh --tag v∞ --zip Fleux-∞.zip \
      [--kernel-version 4.19.325-Fleux-∞] \
      [--devices "fleur miel fleur_p miel_p"] [--channel stable] [--build-id 10] \
      [--ref lineage-24.0] [--notes FILE] [--allow-version-mismatch] [--publish]

Without --publish it only writes fleux-manifest.json next to this repo.
With --publish it uploads the zip + manifest and creates the GitLab release.
Publishing reads the token from a `gitlab` git remote, or from $GITLAB_TOKEN.
The token is never printed.

The manifest is merged by tag (previous releases are preserved).  Publishing
fails when the built kernel release does not match the tag's LOCALVERSION, or
when a tag such as v10 does not match -Fleux-V10, or v∞ does not match -Fleux-∞.
Use --notes FILE to attach a Markdown changelog to the GitLab release; the
Fleux app renders that description in its update screen.
EOF
  exit "${1:-0}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --tag)            TAG="$2"; shift 2 ;;
    --zip)            ZIP="$2"; shift 2 ;;
    --channel)        CHANNEL="$2"; shift 2 ;;
    --build-id)       BUILD_ID="$2"; shift 2 ;;
    --kernel-version) KERNEL_VERSION="$2"; shift 2 ;;
    --devices)        DEVICES="$2"; shift 2 ;;
    --project)        PROJECT="$2"; shift 2 ;;
    --ref)            REF="$2"; shift 2 ;;
    --notes)          NOTES="$2"; shift 2 ;;
    --manifest)       MANIFEST="$2"; shift 2 ;;
    --allow-version-mismatch) ALLOW_VERSION_MISMATCH=1; shift ;;
    --publish)        PUBLISH=1; shift ;;
    -h|--help)        usage 0 ;;
    *) echo "unknown argument: $1" >&2; usage 1 ;;
  esac
done

[ -n "$TAG" ] || { echo "--tag is required" >&2; exit 1; }
[ -n "$ZIP" ] || { echo "--zip is required" >&2; exit 1; }
[ -f "$ZIP" ] || { echo "zip not found: $ZIP" >&2; exit 1; }
if [ -n "$NOTES" ] && [ ! -f "$NOTES" ]; then
  echo "notes file not found: $NOTES" >&2
  exit 1
fi

ASSET_NAME="$(basename "$ZIP")"
SIZE="$(wc -c < "$ZIP" | tr -d ' ')"
SHA256="$(sha256sum "$ZIP" | cut -d' ' -f1)"
if [ -z "$KERNEL_VERSION" ]; then
  # `make kernelversion` drops CONFIG_LOCALVERSION; prefer the full release
  # string that the running device will report in uname -r.
  for f in out/include/config/kernel.release include/config/kernel.release; do
    if [ -f "$f" ]; then KERNEL_VERSION="$(cat "$f")"; break; fi
  done
  [ -n "$KERNEL_VERSION" ] || KERNEL_VERSION="$(make -s kernelrelease 2>/dev/null || true)"
  [ -n "$KERNEL_VERSION" ] || KERNEL_VERSION="$(make -s kernelversion 2>/dev/null || true)"
  [ -n "$KERNEL_VERSION" ] || KERNEL_VERSION="unknown"
fi

# --- version consistency ---------------------------------------------------
# The Fleux app identifies the running kernel by its uname release string
# (e.g. 4.19.325-Fleux-V9), so the tagged tree, the built image and the tag
# name all have to agree.  v7 shipped -Fleux-V6-SuSFS-HotFix and v8 shipped
# -Fleux-V7 because LOCALVERSION was bumped after tagging.
TAG_LOCALVERSION=""
if git rev-parse -q --verify "refs/tags/$TAG^{commit}" >/dev/null 2>&1; then
  TAG_LOCALVERSION="$(git show "$TAG^{commit}:arch/arm64/configs/fleur_defconfig" 2>/dev/null \
    | sed -n 's/^CONFIG_LOCALVERSION="\(.*\)"$/\1/p' | head -n1)"
fi

version_error() {
  echo "release: $*" >&2
  if [ "$ALLOW_VERSION_MISMATCH" -eq 1 ]; then
    echo "release: --allow-version-mismatch given, continuing" >&2
  else
    echo "release: refusing to write metadata; fix the tree/tag or pass --allow-version-mismatch" >&2
    exit 1
  fi
}

if [ -n "$TAG_LOCALVERSION" ] && [ "$KERNEL_VERSION" != "unknown" ]; then
  case "$KERNEL_VERSION" in
    *"$TAG_LOCALVERSION") : ;;
    *) version_error "built kernel '$KERNEL_VERSION' does not carry tag '$TAG' LOCALVERSION '$TAG_LOCALVERSION'" ;;
  esac
fi

if printf '%s' "$TAG" | grep -Eq '^v[0-9]+$' && [ -n "$TAG_LOCALVERSION" ]; then
  NUMERIC_TAG="${TAG#v}"
  case "$TAG_LOCALVERSION" in
    *"Fleux-V$NUMERIC_TAG") : ;;
    *) version_error "tag '$TAG' should build -Fleux-V$NUMERIC_TAG but its LOCALVERSION is '$TAG_LOCALVERSION'" ;;
  esac
fi

if [ "$TAG" = "v∞" ] && [ -n "$TAG_LOCALVERSION" ]; then
  case "$TAG_LOCALVERSION" in
    *"Fleux-∞") : ;;
    *) version_error "tag '$TAG' should build -Fleux-∞ but its LOCALVERSION is '$TAG_LOCALVERSION'" ;;
  esac
fi

python3 - "$MANIFEST" "$PROJECT" "$TAG" "$CHANNEL" "$BUILD_ID" \
          "$KERNEL_VERSION" "$DEVICES" "$ASSET_NAME" "$SIZE" "$SHA256" <<'PY'
import json, os, sys, datetime
(manifest, project, tag, channel, build_id, kernel_version, devices,
 asset_name, size, sha256) = sys.argv[1:]

data = {"schema": 1, "project": project, "releases": []}
if os.path.exists(manifest):
    try:
        with open(manifest) as f:
            old = json.load(f)
        if isinstance(old, dict):
            data["schema"] = old.get("schema", 1)
            data["project"] = old.get("project", project)
            data["releases"] = [r for r in old.get("releases", [])
                                if isinstance(r, dict)]
    except (ValueError, OSError) as exc:
        print("warning: ignoring unreadable %s (%s)" % (manifest, exc),
              file=sys.stderr)

entry = {
    "tag": tag,
    "channel": channel,
    "buildId": int(build_id) if build_id else 0,
    "upstream": True,
    "kernelVersion": kernel_version,
    "devices": [d for d in devices.split() if d],
    "assets": [{
        "name": asset_name,
        "size": int(size),
        "sha256": sha256,
        "kind": "anykernel3",
    }],
}

for i, rel in enumerate(data["releases"]):
    if rel.get("tag") == tag:
        data["releases"][i] = entry
        break
else:
    data["releases"].append(entry)

data["releases"].sort(key=lambda r: (r.get("buildId", 0), r.get("tag", "")))
data["generated"] = datetime.date.today().isoformat()

with open(manifest, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
print("wrote %s (%d releases; size=%s sha256=%s)" %
      (manifest, len(data["releases"]), size, sha256))
PY

if [ "$PUBLISH" -ne 1 ]; then
  echo "manifest written to $MANIFEST (use --publish to publish)"
  exit 0
fi

TOKEN="${GITLAB_TOKEN:-}"
if [ -z "$TOKEN" ]; then
  CRED="$(git remote get-url gitlab 2>/dev/null | sed -E 's#https://([^@]+)@.*#\1#' || true)"
  TOKEN="${CRED#*:}"
fi
[ -n "$TOKEN" ] || { echo "no GitLab token (set GITLAB_TOKEN or add a 'gitlab' remote)" >&2; exit 1; }

API="https://gitlab.com/api/v4/projects/$(printf '%s' "$PROJECT" | sed 's#/#%2F#')"

# Project uploads are only reachable anonymously via the
# /-/project/<id>/uploads/<secret>/<name> form; the /<namespace>/<project>/uploads/
# form returned by the uploads API returns 404 to anonymous clients.
PROJECT_ID="$(curl -sS --header "PRIVATE-TOKEN: $TOKEN" "$API" \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)["id"])')"

upload() { # upload <file> -> anonymous public URL
  local rel
  rel="$(curl -sS --max-time 900 --header "PRIVATE-TOKEN: $TOKEN" \
           --form "file=@$1" "$API/uploads" \
         | python3 -c 'import sys,json; print(json.load(sys.stdin)["url"])')"
  printf 'https://gitlab.com/-/project/%s%s\n' "$PROJECT_ID" "$rel"
}

echo "uploading $ASSET_NAME ..."
ZIP_URL="$(upload "$ZIP")"
echo "  -> $ZIP_URL"
echo "uploading manifest ..."
MAN_URL="$(upload "$MANIFEST")"
echo "  -> $MAN_URL"

BODY="$(python3 - "$TAG" "$ASSET_NAME" "$ZIP_URL" "$MAN_URL" "$REF" "$NOTES" <<'PY'
import json, sys
tag, asset, zip_url, man_url, ref, notes_path = sys.argv[1:]
body = {
    "name": tag,
    "tag_name": tag,
    "ref": ref,
    "assets": {"links": [
        {"name": asset, "url": zip_url},
        {"name": "fleux-manifest.json", "url": man_url},
    ]},
}
if notes_path:
    with open(notes_path, encoding="utf-8") as f:
        description = f.read().strip()
    if description:
        body["description"] = description
print(json.dumps(body))
PY
)"

echo "creating release $TAG ..."
code="$(printf '%s' "$BODY" | curl -sS -o /tmp/fleux-release-resp.json -w '%{http_code}' \
        --header "PRIVATE-TOKEN: $TOKEN" --header "Content-Type: application/json" \
        --data @- "$API/releases")"

case "$code" in
  201) echo "release $TAG published" ;;
  409) echo "release $TAG already exists. Add the two asset links manually, or delete and re-create it." >&2; exit 2 ;;
  *)   echo "release create failed (HTTP $code):" >&2; cat /tmp/fleux-release-resp.json >&2; exit 1 ;;
esac
