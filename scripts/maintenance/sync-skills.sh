#!/bin/bash
# sync-skills.sh — Sync skills from source repositories defined in manifest.json.
#
# Manifest is repo-centric: each repo has a ref (tag/branch) and a list of
# skills to extract. One tarball download per repo, multiple skills extracted.
#
# Usage:
#   sync-skills.sh [OPTIONS] [SKILL_NAME]
#
# Options:
#   --check       Dry-run: show what would change without modifying files
#   --latest      Ignore pinned ref, resolve to each repo's latest release tag
#   --readme      Update the skill table in skills/README.md (fetches repo descriptions)
#   SKILL_NAME    Sync only the named skill (default: sync all)
#
# Examples:
#   sync-skills.sh                     # sync all skills at pinned versions
#   sync-skills.sh bridgic-browser     # sync only bridgic-browser
#   sync-skills.sh --check             # preview without writing
#   sync-skills.sh --latest            # sync all to latest release
#   sync-skills.sh --readme            # update skill table in README
#
# Requires: curl, tar, python3

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MANIFEST="$PLUGIN_ROOT/skills/manifest.json"
SKILLS_DIR="$PLUGIN_ROOT/skills"

# ── Parse args ───────────────────────────────────────────
DRY_RUN=false
USE_LATEST=false
UPDATE_README=false
TARGET_SKILL=""

for arg in "$@"; do
    case "$arg" in
        --check)  DRY_RUN=true ;;
        --latest) USE_LATEST=true ;;
        --readme) UPDATE_README=true ;;
        -*)       echo "Unknown option: $arg"; exit 1 ;;
        *)        TARGET_SKILL="$arg" ;;
    esac
done

if [ ! -f "$MANIFEST" ]; then
    echo "Error: manifest not found at $MANIFEST"
    exit 1
fi

# ── GitHub helpers ───────────────────────────────────────
resolve_latest_tag() {
    local repo="$1"
    curl -sfL ${GITHUB_TOKEN:+-H "Authorization: token $GITHUB_TOKEN"} \
        "https://api.github.com/repos/${repo}/releases/latest" \
        | python3 -c "import sys,json; print(json.load(sys.stdin)['tag_name'])" 2>/dev/null
}

download_tarball() {
    local repo="$1" ref="$2" dest="$3"
    curl -sL -o "$dest" -w "%{http_code}" \
        ${GITHUB_TOKEN:+-H "Authorization: token $GITHUB_TOKEN"} \
        "https://api.github.com/repos/${repo}/tarball/${ref}"
}

# ── README table generation ──────────────────────────────
generate_readme_table() {
    local readme="$SKILLS_DIR/README.md"
    if [ ! -f "$readme" ]; then
        echo "Error: $readme not found"
        return 1
    fi

    echo "Generating skill table ..."

    local table
    table=$(python3 -c "
import json, sys, urllib.request

with open(sys.argv[1]) as f:
    m = json.load(f)

desc_cache = {}

def fetch_description(repo):
    if repo in desc_cache:
        return desc_cache[repo]
    try:
        url = f'https://api.github.com/repos/{repo}'
        req = urllib.request.Request(url)
        token = '${GITHUB_TOKEN:-}'
        if token:
            req.add_header('Authorization', f'token {token}')
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read())
            # Take only the first sentence or the English part
            raw = data.get('description') or ''
            desc = raw.split('.')[0].strip().rstrip('.')
            desc_cache[repo] = desc
            return desc
    except Exception:
        desc_cache[repo] = ''
        return ''

rows = [
    '| Skill | Source Repo | Ref | Description |',
    '|-------|------------|-----|-------------|',
]
for r in m['repos']:
    repo = r['repo']
    ref = r['ref']
    desc = fetch_description(repo)
    for s in r['skills']:
        name = s['name']
        repo_link = f'[\`{repo}\`](https://github.com/{repo})'
        ref_display = f'\`{ref}\`'
        rows.append(f'| {name} | {repo_link} | {ref_display} | {desc} |')

print('\n'.join(rows))
" "$MANIFEST")

    # Replace content between markers in README
    python3 -c "
import sys

readme_path = sys.argv[1]
table_content = sys.argv[2]

with open(readme_path, 'r') as f:
    content = f.read()

begin = '<!-- BEGIN SKILL TABLE -->'
end = '<!-- END SKILL TABLE -->'

i_begin = content.index(begin) + len(begin)
i_end = content.index(end)

new_content = content[:i_begin] + '\n' + table_content + '\n' + content[i_end:]

with open(readme_path, 'w') as f:
    f.write(new_content)
" "$readme" "$table"

    echo "Updated: $readme"
}

if $UPDATE_README; then
    generate_readme_table
    exit 0
fi

# ── Sync one skill from an already-extracted archive ─────
sync_skill_from_archive() {
    local name="$1" source_path="$2" preserve_raw="$3" extracted="$4" repo="$5" ref="$6"
    local skill_dir="$SKILLS_DIR/$name"
    local source_dir="$extracted/$source_path"

    echo "  ── $name  (${source_path})"

    if [ ! -d "$source_dir" ]; then
        echo "     Error: path '$source_path' not found in archive"
        return 1
    fi

    local source_files
    source_files=$(cd "$source_dir" && find . -type f | sort)

    if $DRY_RUN; then
        echo "     [dry-run] Files that would be synced:"
        echo "$source_files" | sed 's|^\./|       |'
        if [ -n "$preserve_raw" ]; then
            echo "     [dry-run] Preserved local paths: ${preserve_raw//|/, }"
        fi
        return 0
    fi

    # Backup preserved paths
    local backup_dir
    backup_dir=$(mktemp -d)
    if [ -n "$preserve_raw" ]; then
        IFS='|' read -ra PRESERVE_PATHS <<< "$preserve_raw"
        for p in "${PRESERVE_PATHS[@]}"; do
            [ -z "$p" ] && continue
            local full_path="$skill_dir/$p"
            if [ -e "$full_path" ]; then
                local backup_path="$backup_dir/$p"
                mkdir -p "$(dirname "$backup_path")"
                cp -R "$full_path" "$backup_path"
            fi
        done
    fi

    # Clean target and copy source
    rm -rf "$skill_dir"
    mkdir -p "$skill_dir"
    cp -R "$source_dir"/. "$skill_dir"/

    # Restore preserved paths
    if [ "$(ls -A "$backup_dir" 2>/dev/null)" ]; then
        cp -R "$backup_dir"/. "$skill_dir"/
    fi
    rm -rf "$backup_dir"

    local file_count
    file_count=$(echo "$source_files" | wc -l | tr -d ' ')
    echo "     Synced $file_count file(s)"
    if [ -n "$preserve_raw" ]; then
        echo "     Preserved: ${preserve_raw//|/, }"
    fi
}

# ── Main ─────────────────────────────────────────────────
echo "AmphiLoop skill sync"
echo "Manifest: $MANIFEST"
echo ""

synced=0
failed=0

# Iterate repos via python3, one JSON line per repo
python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    m = json.load(f)
for r in m['repos']:
    skills = []
    for s in r['skills']:
        preserve = '|'.join(s.get('preserve', []))
        skills.append(f\"{s['name']}\t{s['source_path']}\t{preserve}\")
    skills_block = '\n'.join(skills)
    print(f\"{r['repo']}\t{r['ref']}\t{len(r['skills'])}\")
    print(skills_block)
" "$MANIFEST" | {

while IFS=$'\t' read -r repo ref skill_count; do
    # Check if any skill in this repo matches the target filter
    skills_data=()
    has_target=false
    for ((i = 0; i < skill_count; i++)); do
        IFS=$'\t' read -r s_name s_path s_preserve
        skills_data+=("$s_name"$'\t'"$s_path"$'\t'"$s_preserve")
        if [ -z "$TARGET_SKILL" ] || [ "$s_name" = "$TARGET_SKILL" ]; then
            has_target=true
        fi
    done

    if ! $has_target; then
        continue
    fi

    # Resolve latest if requested
    actual_ref="$ref"
    if $USE_LATEST; then
        latest=$(resolve_latest_tag "$repo") || true
        if [ -n "$latest" ]; then
            echo "Resolved $repo latest release: $latest (pinned: $ref)"
            actual_ref="$latest"
        else
            echo "Warning: no releases for $repo, using pinned: $ref"
        fi
    fi

    echo "━━━ ${repo}@${actual_ref} ━━━"

    # Download tarball once per repo
    tmpdir=$(mktemp -d)
    tarball="$tmpdir/archive.tar.gz"
    http_code=$(download_tarball "$repo" "$actual_ref" "$tarball")

    if [ "$http_code" != "200" ]; then
        echo "  Error: download failed (HTTP $http_code). Check repo/ref."
        rm -rf "$tmpdir"
        failed=$((failed + skill_count))
        continue
    fi

    if ! $DRY_RUN; then
        echo "  Downloaded archive"
    fi

    # Extract once
    tar -xzf "$tarball" -C "$tmpdir"
    extracted=$(find "$tmpdir" -mindepth 1 -maxdepth 1 -type d ! -name '_*' | head -1)

    # Sync each skill from this repo
    for entry in "${skills_data[@]}"; do
        IFS=$'\t' read -r s_name s_path s_preserve <<< "$entry"
        if [ -n "$TARGET_SKILL" ] && [ "$s_name" != "$TARGET_SKILL" ]; then
            continue
        fi
        if sync_skill_from_archive "$s_name" "$s_path" "$s_preserve" "$extracted" "$repo" "$actual_ref"; then
            synced=$((synced + 1))
        else
            failed=$((failed + 1))
        fi
    done

    rm -rf "$tmpdir"
    echo ""
done

if [ "$synced" -eq 0 ] && [ "$failed" -eq 0 ] && [ -n "$TARGET_SKILL" ]; then
    echo "Error: skill '$TARGET_SKILL' not found in manifest"
    exit 1
fi

echo "=== SYNC COMPLETE: $synced succeeded, $failed failed ==="

}
