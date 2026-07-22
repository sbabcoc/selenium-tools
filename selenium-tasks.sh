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

set -e

BOM_DIR=~/code/selenium-bom
FOUNDATION_DIR=~/code/Selenium-Foundation
MANAGER_DIR=~/code/selenium-grid-manager

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
    local prev_version=""
    local mismatch=false
    for i in "${!PROJECTS[@]}"; do
        local dir="${PROJECTS[$i]}"
        local name="${PROJECT_NAMES[$i]}"
        local version=$(get_base_version "$dir")
        echo "  $name: $version"
        if [ -n "$prev_version" ] && [ "$version" != "$prev_version" ]; then
            mismatch=true
        fi
        prev_version=$version
    done
    if $mismatch; then
        echo "WARNING: Version mismatch detected across projects"
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

cmd_release() {
    local version=$1
    [ -n "$version" ] || die "Version required. Usage: selenium-tasks.sh release <version>"

    check_ready

    echo "=== Releasing version $version ==="

    # selenium-bom
    echo "--- selenium-bom ---"
    cd "$BOM_DIR"
    git tag "v$version"
    git push origin "v$version"
    ./gradlew install
    ./gradlew publish closeAndReleaseStagingRepositories

    # selenium-foundation
    echo "--- Selenium-Foundation ---"
    cd "$FOUNDATION_DIR"
    git tag "v$version"
    git push origin "v$version"
    ./gradlew install publish closeAndReleaseStagingRepositories -Pprofile=selenium3 -x test -x testNG
    ./gradlew install publish closeAndReleaseStagingRepositories -Pprofile=selenium4 -x test -x testNG

    # selenium-grid-manager
    echo "--- selenium-grid-manager ---"
    cd "$MANAGER_DIR"
    git tag "v$version"
    git push origin "v$version"
    ./gradlew install publish closeAndReleaseStagingRepositories -Pprofile=selenium3 -x test
    ./gradlew install publish closeAndReleaseStagingRepositories -Pprofile=selenium4 -x test

    # install SNAPSHOT versions for new dev cycle
    echo "--- Installing SNAPSHOT versions for dev cycle ---"
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
    *)
        echo "Usage: selenium-tasks.sh <command> [options]"
        echo ""
        echo "Commands:"
        echo "  release <version>  Tag, publish, and start new dev cycle for all three projects"
        echo "  install            Install all three projects to local Maven in dependency order"
        echo "  versions           Report current base versions of all three projects"
        echo "  branch <name>      Create and push a named feature branch in all three projects"
        echo "  sync               Pull all three projects, switch to main, delete merged local branches"
        exit 1
        ;;
esac