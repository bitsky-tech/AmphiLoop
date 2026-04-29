#!/bin/bash
# sync-skills.sh — Sync skills from source repositories defined in manifest.ini.
#
# Manifest is skill-centric: each [section] names a skill and declares its
# source repo, ref, and path.  Skills sharing a repo+ref are downloaded once.
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
# Requires: curl, tar, python3 (only for --readme and --latest)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MANIFEST="$PLUGIN_ROOT/skills/manifest.ini"
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

if [[ ! -f "$MANIFEST" ]]; then
    echo "Error: manifest not found at $MANIFEST"
    exit 1
fi

# ── INI parser ───────────────────────────────────────────
# Populates parallel arrays indexed by skill position.
SKILL_NAMES=()
SKILL_REPOS=()
SKILL_REFS=()
SKILL_PATHS=()
SKILL_PRESERVES=()

trim() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

parse_manifest() {
    local idx=-1
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%%#*}"
        line="$(trim "$line")"
        [[ -z "$line" ]] && continue

        if [[ "$line" =~ ^\[([^]]+)\]$ ]]; then
            idx=$(( idx + 1 ))
            SKILL_NAMES+=("${BASH_REMATCH[1]}")
            SKILL_REPOS+=("")
            SKILL_REFS+=("")
            SKILL_PATHS+=("")
            SKILL_PRESERVES+=("")
            continue
        fi

        (( idx < 0 )) && continue

        if [[ "$line" =~ ^([a-z_]+)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local val
            val="$(trim "${BASH_REMATCH[2]}")"
            case "$key" in
                repo)     SKILL_REPOS[$idx]="$val" ;;
                ref)      SKILL_REFS[$idx]="$val" ;;
                path)     SKILL_PATHS[$idx]="$val" ;;
                preserve) SKILL_PRESERVES[$idx]="$val" ;;
            esac
        fi
    done < "$1"
}

parse_manifest "$MANIFEST"

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

# ── Archive cache ────────────────────────────────────────
# Downloads each repo+ref once; subsequent calls return the cached path.
CACHE_DIR=$(mktemp -d)
trap 'rm -rf "$CACHE_DIR"' EXIT

get_archive() {
    local repo="$1" ref="$2"
    local key="${repo//\//_}__${ref//\//_}"
    local marker="$CACHE_DIR/${key}.dir"
    local fail_marker="$CACHE_DIR/${key}.failed"

    [[ -f "$fail_marker" ]] && return 1

    if [[ -f "$marker" ]]; then
        cat "$marker"
        return 0
    fi

    local tarball="$CACHE_DIR/${key}.tar.gz"
    local http_code
    http_code=$(download_tarball "$repo" "$ref" "$tarball")

    if [[ "$http_code" != "200" ]]; then
        echo "  Error: HTTP $http_code for ${repo}@${ref}" >&2
        touch "$fail_marker"
        return 1
    fi

    local extract_dir="$CACHE_DIR/$key"
    mkdir -p "$extract_dir"
    tar -xzf "$tarball" -C "$extract_dir"
    rm -f "$tarball"

    local top_dir
    top_dir=$(find "$extract_dir" -mindepth 1 -maxdepth 1 -type d ! -name '_*' | head -1)
    echo "$top_dir" > "$marker"
    echo "$top_dir"
}

# ── README table generation ──────────────────────────────
generate_readme_table() {
    local readme="$SKILLS_DIR/README.md"
    if [[ ! -f "$readme" ]]; then
        echo "Error: $readme not found"
        return 1
    fi

    echo "Generating skill table ..."

    local table
    table=$(python3 -c "
import configparser, json, sys, urllib.request

c = configparser.ConfigParser()
c.read(sys.argv[1])

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
            raw = data.get('description') or ''
            desc = raw.split('.')[0].strip().rstrip('.')
            desc_cache[repo] = desc
            return desc
    except Exception:
        desc_cache[repo] = ''
        return ''

rows = [
    '| Skill | Source Repo | Description |',
    '|-------|------------|-------------|',
]
for skill in c.sections():
    repo = c[skill]['repo']
    desc = fetch_description(repo)
    repo_link = f'[\`{repo}\`](https://github.com/{repo})'
    rows.append(f'| {skill} | {repo_link} | {desc} |')

print('\n'.join(rows))
" "$MANIFEST")

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
    local name="$1" source_path="$2" preserve_raw="$3" extracted="$4"
    local skill_dir="$SKILLS_DIR/$name"
    local source_dir="$extracted/$source_path"

    echo "  ── $name  (${source_path})"

    if [[ ! -d "$source_dir" ]]; then
        echo "     Error: path '$source_path' not found in archive"
        return 1
    fi

    local source_files
    source_files=$(cd "$source_dir" && find . -type f | sort)

    if $DRY_RUN; then
        echo "     [dry-run] Files that would be synced:"
        echo "$source_files" | sed 's|^\./|       |'
        if [[ -n "$preserve_raw" ]]; then
            echo "     [dry-run] Preserved: $preserve_raw"
        fi
        return 0
    fi

    # Backup preserved paths
    local backup_dir
    backup_dir=$(mktemp -d)
    if [[ -n "$preserve_raw" ]]; then
        IFS=',' read -ra PATHS <<< "$preserve_raw"
        for p in "${PATHS[@]}"; do
            p="$(trim "$p")"
            [[ -z "$p" ]] && continue
            if [[ -e "$skill_dir/$p" ]]; then
                mkdir -p "$(dirname "$backup_dir/$p")"
                cp -R "$skill_dir/$p" "$backup_dir/$p"
            fi
        done
    fi

    rm -rf "$skill_dir"
    mkdir -p "$skill_dir"
    cp -R "$source_dir"/. "$skill_dir"/

    if [[ "$(ls -A "$backup_dir" 2>/dev/null)" ]]; then
        cp -R "$backup_dir"/. "$skill_dir"/
    fi
    rm -rf "$backup_dir"

    local file_count
    file_count=$(echo "$source_files" | wc -l | tr -d ' ')
    echo "     Synced $file_count file(s)"
    if [[ -n "$preserve_raw" ]]; then
        echo "     Preserved: $preserve_raw"
    fi
}

# ── Main ─────────────────────────────────────────────────
echo "AmphiLoop skill sync"
echo "Manifest: $MANIFEST"
echo ""

synced=0
failed=0
found=false
last_header=""

# Pre-resolve --latest refs (once per unique repo)
SKILL_ACTUAL_REFS=()
for ((i = 0; i < ${#SKILL_NAMES[@]}; i++)); do
    SKILL_ACTUAL_REFS+=("${SKILL_REFS[$i]}")
done

if $USE_LATEST; then
    for ((i = 0; i < ${#SKILL_NAMES[@]}; i++)); do
        repo="${SKILL_REPOS[$i]}"
        resolved=""
        for ((j = 0; j < i; j++)); do
            if [[ "${SKILL_REPOS[$j]}" == "$repo" ]]; then
                resolved="${SKILL_ACTUAL_REFS[$j]}"
                break
            fi
        done
        if [[ -n "$resolved" ]]; then
            SKILL_ACTUAL_REFS[$i]="$resolved"
        else
            latest=$(resolve_latest_tag "$repo") || true
            if [[ -n "$latest" ]]; then
                echo "Resolved $repo latest release: $latest (pinned: ${SKILL_REFS[$i]})"
                SKILL_ACTUAL_REFS[$i]="$latest"
            else
                echo "Warning: no releases for $repo, using pinned: ${SKILL_REFS[$i]}"
            fi
        fi
    done
    echo ""
fi

for ((i = 0; i < ${#SKILL_NAMES[@]}; i++)); do
    name="${SKILL_NAMES[$i]}"
    repo="${SKILL_REPOS[$i]}"
    ref="${SKILL_ACTUAL_REFS[$i]}"
    src_path="${SKILL_PATHS[$i]}"
    preserve="${SKILL_PRESERVES[$i]}"

    if [[ -n "$TARGET_SKILL" && "$name" != "$TARGET_SKILL" ]]; then
        continue
    fi
    found=true

    # Print repo header once per repo+ref group
    header="${repo}@${ref}"
    new_repo=false
    if [[ "$header" != "$last_header" ]]; then
        new_repo=true
        echo "━━━ ${header} ━━━"
        last_header="$header"
    fi

    extracted=$(get_archive "$repo" "$ref") || {
        if $new_repo; then
            echo "  Error: download failed. Check repo/ref."
            echo ""
        fi
        failed=$((failed + 1))
        continue
    }

    if $new_repo && ! $DRY_RUN; then
        echo "  Downloaded archive"
    fi

    if sync_skill_from_archive "$name" "$src_path" "$preserve" "$extracted"; then
        synced=$((synced + 1))
    else
        failed=$((failed + 1))
    fi
done

echo ""

if ! $found && [[ -n "$TARGET_SKILL" ]]; then
    echo "Error: skill '$TARGET_SKILL' not found in manifest"
    exit 1
fi

echo "=== SYNC COMPLETE: $synced succeeded, $failed failed ==="
