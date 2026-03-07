#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: seed-brave-profiles.sh [--dry-run] [--seed-sync] [--spec <path>]

Seeds Brave profile scaffolding from a private spec file.

Default spec path:
  <hs-config>/config/brave-profile-seed.json

Recommended setup:
  1) Keep your real manifest in hs-config-private at:
       config/brave-profile-seed.json
  2) Stow/link it into hs-config/config/brave-profile-seed.json
  3) Run this script from hs-config/scripts

Examples:
  seed-brave-profiles.sh --dry-run
  seed-brave-profiles.sh
  seed-brave-profiles.sh --seed-sync
  seed-brave-profiles.sh --spec /path/to/custom-profile-seed.json

Spec schema:
{
  "profiles": [
    {
      "directory": "Default",
      "name": "Main",
      "avatarIcon": "chrome://theme/IDR_PROFILE_AVATAR_79",
      "syncCode": "word1 word2 ..."
    }
  ],
  "lastUsed": "Default"
}

Notes:
  - Keep this spec private (it may include profile naming conventions and sync code).
  - The script does not copy full Brave browser state; it seeds profile scaffold only.
  - Requires Ruby with JSON support (available by default on macOS).
  - Legacy fallback: top-level sync.code is still accepted when profile.syncCode is missing.
EOF
}

DRY_RUN=0
SEED_SYNC=0
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
HS_CONFIG_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
SPEC_FILE="${BRAVE_PROFILE_SPEC_FILE:-${HS_CONFIG_ROOT}/config/brave-profile-seed.json}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --seed-sync)
      SEED_SYNC=1
      shift
      ;;
    --spec)
      SPEC_FILE="$2"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ ! -f "${SPEC_FILE}" ]]; then
  echo "Spec file not found: ${SPEC_FILE}" >&2
  echo "Create it in hs-config-private at config/brave-profile-seed.json (stowed into hs-config/config)." >&2
  exit 1
fi

if [[ "${DRY_RUN}" -ne 1 ]] && pgrep -x "Brave Browser" >/dev/null 2>&1; then
  echo "Brave Browser is running. Quit Brave before seeding profiles." >&2
  exit 1
fi

BRAVE_APP="Brave Browser"
BRAVE_DIR="${HOME}/Library/Application Support/BraveSoftware/Brave-Browser"
LOCAL_STATE="${BRAVE_DIR}/Local State"

mkdir -p "${BRAVE_DIR}"

if [[ ! -f "${LOCAL_STATE}" ]]; then
  cat >"${LOCAL_STATE}" <<'JSON'
{}
JSON
fi

if [[ "${DRY_RUN}" -eq 0 ]]; then
  timestamp="$(date +"%Y-%m-%d-%H%M%S")"
  cp "${LOCAL_STATE}" "${LOCAL_STATE}.backup-${timestamp}"
fi

RUBY_OUTPUT="$(ruby - "${SPEC_FILE}" "${LOCAL_STATE}" "${DRY_RUN}" <<'RB'
require "json"

spec_path = ARGV[0]
local_state_path = ARGV[1]
dry_run = ARGV[2] == "1"

spec = JSON.parse(File.read(spec_path, encoding: "UTF-8"))
profiles = spec.fetch("profiles", [])
raise "Spec must contain a non-empty 'profiles' array" if profiles.empty?

profiles.each do |profile|
  raise "Each profile needs 'directory' and 'name'" unless profile["directory"] && profile["name"]
end

raw_local_state = File.read(local_state_path, encoding: "UTF-8")
local_state = raw_local_state.strip.empty? ? {} : JSON.parse(raw_local_state)

profile_root = local_state["profile"] ||= {}
info_cache = profile_root["info_cache"] ||= {}

profiles.each do |profile|
  directory = profile["directory"]
  name = profile["name"]
  avatar = profile["avatarIcon"]
  profile_sync_code = profile["syncCode"].to_s.strip

  entry = info_cache[directory] ||= {}
  entry["name"] = name
  entry["user_name"] = ""
  entry["is_using_default_name"] = false
  entry["is_ephemeral"] = false
  entry["avatar_icon"] = avatar if avatar

  legacy_sync_code = spec.dig("sync", "code").to_s.strip
  effective_sync_code = profile_sync_code.empty? ? legacy_sync_code : profile_sync_code
  profile["__effective_sync_code"] = effective_sync_code
end

last_used = spec["lastUsed"]
profile_root["last_used"] = last_used if last_used

unless dry_run
  File.write(local_state_path, JSON.pretty_generate(local_state) + "\n")
end

sync_code = spec.dig("sync", "code").to_s.strip
puts ["SYNC", sync_code].join("\t")
profiles.each do |profile|
  puts ["PROFILE", profile["directory"], profile["name"], profile["__effective_sync_code"]].join("\t")
end
RB
)"

PROFILE_LINES=""
while IFS=$'\t' read -r line_type profile_dir profile_name profile_sync_code; do
  case "${line_type}" in
    PROFILE)
      PROFILE_LINES+="${profile_dir}"$'\t'"${profile_name}"$'\t'"${profile_sync_code}"$'\n'
      ;;
  esac
done <<< "${RUBY_OUTPUT}"

while IFS=$'\t' read -r profile_dir profile_name _; do
  [[ -n "${profile_dir}" ]] || continue
  mkdir -p "${BRAVE_DIR}/${profile_dir}"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[dry-run] ${profile_dir} -> ${profile_name}"
  fi
done <<< "${PROFILE_LINES}"

if [[ "${SEED_SYNC}" -eq 1 ]]; then
  seeded_profiles=0
  skipped_profiles=0

  while IFS=$'\t' read -r profile_dir profile_name profile_sync_code; do
    [[ -n "${profile_dir}" ]] || continue

    if [[ -z "${profile_sync_code}" ]]; then
      skipped_profiles=$((skipped_profiles + 1))
      if [[ "${DRY_RUN}" -eq 1 ]]; then
        echo "[dry-run] Skip ${profile_dir} (${profile_name}): no sync code"
      else
        echo "Skip ${profile_dir} (${profile_name}): no sync code"
      fi
      continue
    fi

    seeded_profiles=$((seeded_profiles + 1))

    if [[ "${DRY_RUN}" -eq 1 ]]; then
      echo "[dry-run] Would copy sync code and open setup for ${profile_dir} (${profile_name})."
      continue
    fi

    printf "%s" "${profile_sync_code}" | pbcopy
    /usr/bin/open -n -a "${BRAVE_APP}" --args "--profile-directory=${profile_dir}" "brave://settings/braveSync/setup"

    echo "Opened Brave Sync setup for ${profile_dir} (${profile_name})."
    echo "Sync code copied to clipboard. Paste it, then press Enter for next profile."
    read -r _
  done <<< "${PROFILE_LINES}"

  if [[ "${seeded_profiles}" -eq 0 ]]; then
    if [[ "${DRY_RUN}" -eq 1 ]]; then
      echo "[dry-run] No profiles had sync codes. Set profiles[].syncCode (or legacy sync.code) in spec."
    else
      echo "No profiles had sync codes. Set profiles[].syncCode (or legacy sync.code) in spec." >&2
      exit 1
    fi
  fi

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[dry-run] Sync seeding summary: ${seeded_profiles} profiles with code, ${skipped_profiles} without code."
  else
    echo "Sync seeding summary: ${seeded_profiles} profiles with code, ${skipped_profiles} without code."
  fi
fi

if [[ "${DRY_RUN}" -eq 1 ]]; then
  echo "[dry-run] Completed Brave profile seed simulation."
else
  echo "Brave profile scaffold seeded from private spec."
  echo "Next steps:"
  echo "  1) Launch Brave"
  echo "  2) Verify profile names"
  if [[ "${SEED_SYNC}" -eq 0 ]]; then
    echo "  3) Sign each profile into Brave Sync"
  else
    echo "  3) Paste clipboard sync code in opened Brave Sync pages"
  fi
fi
