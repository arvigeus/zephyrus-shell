#!/usr/bin/env bash
# Build the current working tree, including uncommitted changes, without network
# access to the shell repository or modifying the source checkout.
set -Eeuo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/build"
git clone --quiet --no-hardlinks -- "$root" "$work/checkout"
# Copy only Git-managed and non-ignored new files; never credentials/build state.
while IFS= read -r -d '' file; do
    if [[ -e $root/$file || -L $root/$file ]]; then printf '%s\0' "$file"; fi
done < <(git -C "$root" ls-files --cached --others --exclude-standard -z) |
    tar -C "$root" --null -T - -cf - |
    tar -xf - -C "$work/checkout"
while IFS= read -r -d '' deleted; do rm -f -- "$work/checkout/$deleted"; done \
    < <(git -C "$root" ls-files --deleted -z)
git -C "$work/checkout" add -A
if ! git -C "$work/checkout" diff --cached --quiet; then
    git -C "$work/checkout" -c commit.gpgsign=false -c user.name='Local package build' \
        -c user.email='local@localhost' commit --quiet -m 'Local working tree snapshot'
fi
cp -- "$work/checkout/PKGBUILD" "$work/build/PKGBUILD"
# Standard Git URL rewriting makes makepkg's VCS fetch local. The same commit
# supplies both metadata and payload. The PKGBUILD needs no custom build mode.
export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0="url.file://$work/checkout.insteadOf"
export GIT_CONFIG_VALUE_0=https://github.com/arvigeus/zephyrus-shell.git
export PKGDEST=${PKGDEST:-$root}
mkdir -p "$PKGDEST"
cd -- "$work/build"
makepkg "$@"
