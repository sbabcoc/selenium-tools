#!/bin/bash
# selenium-tasks.sh — Release and maintenance utility for the Selenium UI Tools projects
# Usage: selenium-tasks.sh <command> [options]
#
# Commands:
#   release <version>  Tag, publish, and start new dev cycle for all three projects
#   install            Install all three projects to local Maven in dependency order
#   versions           Report current base versions of all three projects
#   branch <name>      Create and push a named feature branch in all three projects
#   sync               Pull all three projects, switch to main, delete merged local branches
#   sandbox            Wipe and repopulate a standalone selenium-grid-manager runtime sandbox

set -e

BOM_DIR=~/code/selenium-bom
FOUNDATION_DIR=~/code/Selenium-Foundation
MANAGER_DIR=~/code/selenium-grid-manager
SANDBOX_DIR=~/code/sandbox
M2_MANAGER_REPO=~/.m2/repository/com/nordstrom/ui-tools/selenium-grid-manager

PROJECTS=("$BOM_DIR" "$FOUNDATION_DIR" "$MANAGER_DIR")
PROJECT_NAMES=("selenium-bom" "Selenium-Foundation" "selenium-grid-manager")

#
# Utility functions
#

die() {
    echo "ERROR: $1" >&2
    exit 1
}

get_base_version() {
    local dir=$1
    cd "$dir"
    if [ "$dir" = "$BOM_DIR" ]; then
        ./gradlew properties -q 2>/dev/null \
            | grep "^version:" \
            | awk '{print $2}'
    else
        ./gradlew properties -Pprofile=selenium4 -q 2>/dev/null \
            | grep "^version:" \
            | awk '{print $2}' \
            | sed 's/-s[34]//'
    fi
}

check_on_main() {
    local dir=$1
    local name=$2
    cd "$dir"
    local branch=$(git rev-parse --abbrev-ref HEAD)
    [ "$branch" = "main" ] || die "$name is on branch '$branch', not 'main'"
}

check_clean() {
    local dir=$1
    local name=$2
    cd "$dir"
    git diff --quiet && git diff --cached --quiet \
        || die "$name has uncommitted changes"
}

check_up_to_date() {
    local dir=$1
    local name=$2
    cd "$dir"
    git fetch origin -q
    local behind=$(git rev-list HEAD..origin/main --count)
    [ "$behind" = "0" ] || die "$name is $behind commits behind origin/main — pull first"
    local ahead=$(git rev-list origin/main..HEAD --count)
    [ "$ahead" = "0" ] || die "$name has $ahead unpushed commits"
}

check_ready() {
    echo "=== Checking project readiness ==="
    for i in "${!PROJECTS[@]}"; do
        local dir="${PROJECTS[$i]}"
        local name="${PROJECT_NAMES[$i]}"
        check_on_main "$dir" "$name"
        check_clean "$dir" "$name"
        check_up_to_date "$dir" "$name"
        echo "  $name — OK"
    done
}

#
# Commands
#

cmd_versions() {
    echo "=== Current versions ==="
    local versions=()
    local lagging=()
    local highest_base=""
    for i in "${!PROJECTS[@]}"; do
        local dir="${PROJECTS[$i]}"
        local name="${PROJECT_NAMES[$i]}"
        local version=$(get_base_version "$dir")
        echo "  $name: $version"
        versions[$i]=$version

        local base=$(echo "$version" | sed 's/-SNAPSHOT$//')
        if [ -z "$highest_base" ] || [ "$(printf '%s\n%s' "$base" "$highest_base" | sort -V | tail -1)" = "$base" ] && [ "$base" != "$highest_base" ]; then
            highest_base=$base
        fi
    done

    local mismatch=false
    for i in "${!PROJECTS[@]}"; do
        local base=$(echo "${versions[$i]}" | sed 's/-SNAPSHOT$//')
        if [ "$base" != "$highest_base" ]; then
            mismatch=true
            lagging+=("${PROJECTS[$i]}:${PROJECT_NAMES[$i]}")
        fi
    done

    if $mismatch; then
        echo "WARNING: Version mismatch detected across projects"
        echo ""
        echo "To reconcile, advance the lagging project(s) to the current dev cycle:"
        for entry in "${lagging[@]}"; do
            local dir="${entry%%:*}"
            local name="${entry##*:}"
            echo "  cd $dir && git commit --allow-empty -m \"Advance to next development cycle to match dependent projects\" && git push origin main"
        done
    fi
}

cmd_install() {
    echo "=== Installing all projects to local Maven ==="

    echo "--- selenium-bom ---"
    cd "$BOM_DIR"
    ./gradlew install

    echo "--- Selenium-Foundation ---"
    cd "$FOUNDATION_DIR"
    ./gradlew install -Pprofile=selenium3 -x test -x testNG
    ./gradlew install -Pprofile=selenium4 -x test -x testNG

    echo "--- selenium-grid-manager ---"
    cd "$MANAGER_DIR"
    ./gradlew install -Pprofile=selenium3 -x test
    ./gradlew install -Pprofile=selenium4 -x test

    echo "=== Install complete ==="
}

cmd_branch() {
    local branch=$1
    [ -n "$branch" ] || die "Branch name required. Usage: selenium-tasks.sh branch <name>"

    check_ready

    echo "=== Creating branch '$branch' in all projects ==="
    for i in "${!PROJECTS[@]}"; do
        local dir="${PROJECTS[$i]}"
        local name="${PROJECT_NAMES[$i]}"
        cd "$dir"
        git checkout -b "$branch"
        git push -u origin "$branch"
        echo "  $name — branch '$branch' created and pushed"
    done
    echo "=== Branch '$branch' ready in all projects ==="
}

cmd_sync() {
    echo "=== Syncing all projects ==="
    for i in "${!PROJECTS[@]}"; do
        local dir="${PROJECTS[$i]}"
        local name="${PROJECT_NAMES[$i]}"
        cd "$dir"

        # switch to main
        git checkout main
        git pull origin main
        git fetch --tags --force origin

        # delete merged local branches
        local merged=$(git branch --merged main | grep -v '^\*\|main' | tr -d ' ')
        if [ -n "$merged" ]; then
            echo "$merged" | xargs git branch -d
            echo "  $name — deleted merged branches: $merged"
        else
            echo "  $name — no merged branches to delete"
        fi
    done
    echo "=== Sync complete ==="
}

cmd_sandbox() {
    echo "=== Setting up sandbox ==="

    local base_version
    base_version=$(get_base_version "$MANAGER_DIR")
    [ -n "$base_version" ] || die "Could not determine selenium-grid-manager version"

    # -s3/-s4 belongs before -SNAPSHOT (e.g. 1.2.3-s4-SNAPSHOT), not after —
    # base_version already has any -s3/-s4 stripped, but -SNAPSHOT (if present)
    # is still on the end, so split it off before reassembling
    local stem="$base_version"
    local snapshot_suffix=""
    if [[ "$base_version" == *-SNAPSHOT ]]; then
        stem="${base_version%-SNAPSHOT}"
        snapshot_suffix="-SNAPSHOT"
    fi

    local s3_version="${stem}-s3${snapshot_suffix}"
    local s4_version="${stem}-s4${snapshot_suffix}"
    local s3_jar="$M2_MANAGER_REPO/$s3_version/selenium-grid-manager-$s3_version.jar"
    local s4_jar="$M2_MANAGER_REPO/$s4_version/selenium-grid-manager-$s4_version.jar"

    [ -f "$s3_jar" ] || die "S3 artifact not found: $s3_jar (run 'install' first)"
    [ -f "$s4_jar" ] || die "S4 artifact not found: $s4_jar (run 'install' first)"

    echo "Wiping and recreating $SANDBOX_DIR"
    rm -rf "$SANDBOX_DIR"
    mkdir -p "$SANDBOX_DIR"
    cp "$s3_jar" "$s4_jar" "$SANDBOX_DIR/"

    echo "Bootstrapping runtime from S4 jar..."
    cd "$SANDBOX_DIR"
    java -jar "$(basename "$s4_jar")"

    echo "=== Sandbox ready at $SANDBOX_DIR ==="
}

cmd_release() {
    local version=$1
    [ -n "$version" ] || die "Version required. Usage: selenium-tasks.sh release <version>"

    check_ready

    echo "=== Releasing version $version ==="

    # selenium-bom
    echo "--- selenium-bom ---"
    cd "$BOM_DIR"
    ./gradlew -PartifactVersion="$version" updateReadme updateSinceAnnotations checkSincePlaceholders
    if ! git diff --quiet || ! git diff --cached --quiet; then
        git add -u
        git commit -m "Update version refs and resolve placeholders for $version"
        git push origin main
    fi
    git tag "v$version"
    git push origin "v$version"
    ./gradlew install
    ./gradlew publish closeAndReleaseStagingRepositories

    # selenium-foundation
    echo "--- Selenium-Foundation ---"
    cd "$FOUNDATION_DIR"
    ./gradlew -PartifactVersion="$version" updateReadme updateSinceAnnotations checkSincePlaceholders
    if ! git diff --quiet || ! git diff --cached --quiet; then
        git add -u
        git commit -m "Update version refs and resolve placeholders for $version"
        git push origin main
    fi
    git tag "v$version"
    git push origin "v$version"
    ./gradlew install publish closeAndReleaseStagingRepositories -Pprofile=selenium3 -x test -x testNG
    ./gradlew install publish closeAndReleaseStagingRepositories -Pprofile=selenium4 -x test -x testNG

    # selenium-grid-manager
    echo "--- selenium-grid-manager ---"
    cd "$MANAGER_DIR"
    ./gradlew -PartifactVersion="$version" updateReadme updateSinceAnnotations checkSincePlaceholders
    if ! git diff --quiet || ! git diff --cached --quiet; then
        git add -u
        git commit -m "Update version refs and resolve placeholders for $version"
        git push origin main
    fi
    git tag "v$version"
    git push origin "v$version"
    ./gradlew install publish closeAndReleaseStagingRepositories -Pprofile=selenium3 -x test
    ./gradlew install publish closeAndReleaseStagingRepositories -Pprofile=selenium4 -x test

    # install released versions locally
    echo "--- Installing versions ---"
    cmd_install

    echo "=== Release $version complete ==="
    cmd_versions
}

#
# Main
#

COMMAND=$1
shift || true

case "$COMMAND" in
    release)  cmd_release "$@" ;;
    install)  cmd_install ;;
    versions) cmd_versions ;;
    branch)   cmd_branch "$@" ;;
    sync)     cmd_sync ;;
    sandbox)  cmd_sandbox ;;
    *)
        echo "Usage: selenium-tasks.sh <command> [options]"
        echo ""
        echo "Commands:"
        echo "  release <version>  Tag, publish, and start new dev cycle for all three projects"
        echo "  install            Install all three projects to local Maven in dependency order"
        echo "  versions           Report current base versions of all three projects"
        echo "  branch <name>      Create and push a named feature branch in all three projects"
        echo "  sync               Pull all three projects, switch to main, delete merged local branches"
        echo "  sandbox            Wipe and repopulate a standalone selenium-grid-manager runtime sandbox"
        exit 1
        ;;
esac
