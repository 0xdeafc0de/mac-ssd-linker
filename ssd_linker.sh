#!/usr/bin/env bash
# =============================================================================
# mac-ssd-linker: Transparently offload large Mac directories to external SSD
#                 using symlinks — no home dir migration needed.
# =============================================================================

set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

# ── Helpers ───────────────────────────────────────────────────────────────────
info()    { echo -e "${CYAN}ℹ ${NC}$*"; }
ok()      { echo -e "${GREEN}✔ ${NC}$*"; }
warn()    { echo -e "${YELLOW}⚠ ${NC}$*"; }
error()   { echo -e "${RED}✖ ${NC}$*" >&2; }
heading() { echo -e "\n${BOLD}${BLUE}══ $* ══${NC}"; }
hr()      { echo -e "${BLUE}────────────────────────────────────────────────────${NC}"; }

human_size() {
    local path="$1"
    if [[ -e "$path" ]]; then
        du -sh "$path" 2>/dev/null | awk '{print $1}'
    else
        echo "0B"
    fi
}

is_symlink() { [[ -L "$1" ]]; }

confirm() {
    local prompt="$1"
    local reply
    echo -en "${YELLOW}? ${NC}${prompt} [y/N]: "
    read -r reply
    [[ "$reply" =~ ^[Yy]$ ]]
}

# ── Banner ────────────────────────────────────────────────────────────────────
print_banner() {
    echo -e "${BOLD}${BLUE}"
    echo "  ███████╗███████╗██████╗     ██╗     ██╗███╗   ██╗██╗  ██╗███████╗██████╗ "
    echo "  ██╔════╝██╔════╝██╔══██╗    ██║     ██║████╗  ██║██║ ██╔╝██╔════╝██╔══██╗"
    echo "  ███████╗███████╗██║  ██║    ██║     ██║██╔██╗ ██║█████╔╝ █████╗  ██████╔╝"
    echo "  ╚════██║╚════██║██║  ██║    ██║     ██║██║╚██╗██║██╔═██╗ ██╔══╝  ██╔══██╗"
    echo "  ███████║███████║██████╔╝    ███████╗██║██║ ╚████║██║  ██╗███████╗██║  ██║"
    echo "  ╚══════╝╚══════╝╚═════╝     ╚══════╝╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝"
    echo -e "${NC}"
    echo -e "  ${CYAN}Transparently offload Mac directories to external SSD via symlinks${NC}"
    echo -e "  ${CYAN}No home dir migration · Fully reversible · Apps see no difference${NC}"
    hr
}

# ── Detect external volumes ───────────────────────────────────────────────────
detect_ssds() {
    heading "Available External Volumes"
    local volumes=()
    while IFS= read -r vol; do
        # Skip macOS system/recovery volumes
        [[ "$vol" == /Volumes/Macintosh\ HD* ]] && continue
        [[ "$vol" == /Volumes/Recovery* ]]       && continue
        [[ "$vol" == /Volumes/com.apple* ]]      && continue
        volumes+=("$vol")
    done < <(find /Volumes -maxdepth 1 -mindepth 1 -type d 2>/dev/null)

    if [[ ${#volumes[@]} -eq 0 ]]; then
        error "No external volumes found. Please connect your external SSD and try again."
        exit 1
    fi

    echo ""
    local i=1
    for vol in "${volumes[@]}"; do
        local free total used_pct
        free=$(df -h "$vol" 2>/dev/null | awk 'NR==2{print $4}')
        total=$(df -h "$vol" 2>/dev/null | awk 'NR==2{print $2}')
        used_pct=$(df -h "$vol" 2>/dev/null | awk 'NR==2{print $5}')
        printf "  ${BOLD}[%d]${NC} %-40s  ${GREEN}%s free${NC} / %s total  (%s used)\n" \
               "$i" "$(basename "$vol")" "$free" "$total" "$used_pct"
        i=$((i+1))
    done

    echo ""
    echo -en "${YELLOW}? ${NC}Select volume [1-$((i-1))]: "
    read -r choice
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice >= i )); then
        error "Invalid choice."; exit 1
    fi

    SELECTED_SSD="${volumes[$((choice-1))]}"
    LINKER_BASE="${SELECTED_SSD}/MacMini_Offload"
    ok "Selected: ${BOLD}${SELECTED_SSD}${NC}"
    mkdir -p "$LINKER_BASE"
}

# ── Directory catalog ─────────────────────────────────────────────────────────
# Format: "label|source_path|suggested_ssd_subdir"
CATALOG=(
    "Documents         |${HOME}/Documents                                |Documents"
    "Downloads         |${HOME}/Downloads                                |Downloads"
    "Movies            |${HOME}/Movies                                   |Movies"
    "Music             |${HOME}/Music                                    |Music"
    "Pictures          |${HOME}/Pictures                                 |Pictures"
    "Desktop           |${HOME}/Desktop                                  |Desktop"
    "Xcode DerivedData |${HOME}/Library/Developer/Xcode/DerivedData      |Xcode_DerivedData"
    "iOS Device Support|${HOME}/Library/Developer/Xcode/iOS DeviceSupport|Xcode_iOSDevSupport"
    "Simulator Runtimes|${HOME}/Library/Developer/CoreSimulator/Cryptex  |Xcode_SimRuntimes"
    "Docker volumes    |${HOME}/Library/Containers/com.docker.docker     |Docker"
    "npm cache         |${HOME}/.npm                                     |npm_cache"
    "Homebrew cache    |${HOME}/Library/Caches/Homebrew                  |Homebrew_cache"
    "pip cache         |${HOME}/Library/Caches/pip                       |pip_cache"
    "Virtualenvs       |${HOME}/.virtualenvs                             |virtualenvs"
    "pyenv versions    |${HOME}/.pyenv/versions                          |pyenv_versions"
    "nvm node versions |${HOME}/.nvm/versions                            |nvm_versions"
    "Rust toolchains   |${HOME}/.rustup/toolchains                       |rustup_toolchains"
    "Go cache          |${HOME}/go                                       |go_workspace"
    "VMs (Parallels)   |${HOME}/Parallels                                |Parallels_VMs"
    "VMs (UTM)         |${HOME}/Library/Containers/com.utmapp.UTM        |UTM_VMs"
)

# ── Show status ───────────────────────────────────────────────────────────────
show_status() {
    heading "Internal Storage Overview"
    local used avail total pct
    used=$(df -h /  | awk 'NR==2{print $3}')
    avail=$(df -h / | awk 'NR==2{print $4}')
    total=$(df -h / | awk 'NR==2{print $2}')
    pct=$(df -h /   | awk 'NR==2{print $5}')
    echo -e "  Internal SSD: ${BOLD}${used}${NC} used / ${total} total  (${pct})  — ${GREEN}${avail} free${NC}"

    heading "Directory Status"
    printf "\n  %-22s %-10s %-12s %s\n" "LABEL" "SIZE" "STATUS" "PATH"
    hr
    local idx=0
    for entry in "${CATALOG[@]}"; do
        local label src dst
        label=$(echo "$entry" | cut -d'|' -f1 | xargs)
        src=$(echo "$entry"   | cut -d'|' -f2 | xargs)
        dst=$(echo "$entry"   | cut -d'|' -f3 | xargs)

        local size status
        if [[ ! -e "$src" ]]; then
            size="—"; status="${YELLOW}absent${NC}"
        elif is_symlink "$src"; then
            local target; target=$(readlink "$src")
            size=$(human_size "$src")
            status="${GREEN}→ SSD${NC}"
            # override dst label to show actual link target basename
            dst="→ $(basename "$target")"
        else
            size=$(human_size "$src")
            status="${BLUE}local${NC}"
        fi

        printf "  ${BOLD}[%2d]${NC} %-22s %-10s " "$((idx+1))" "$label" "$size"
        echo -en "$status"
        printf "  %s\n" "$src"
        idx=$((idx+1))
    done
    echo ""
}

# ── Migrate + symlink a single directory ─────────────────────────────────────
link_dir() {
    local label="$1" src="$2" ssd_subdir="$3"
    local dst="${LINKER_BASE}/${ssd_subdir}"

    heading "Linking: ${label}"

    # Already a symlink?
    if is_symlink "$src"; then
        warn "${src} is already a symlink → $(readlink "$src")"
        return 0
    fi

    # Source doesn't exist — create empty dir on SSD and symlink
    if [[ ! -e "$src" ]]; then
        warn "Source does not exist yet. Will create empty dir on SSD and symlink."
        mkdir -p "$dst"
        ln -s "$dst" "$src"
        ok "Created empty → ${dst}"
        return 0
    fi

    local src_size
    src_size=$(du -sh "$src" 2>/dev/null | awk '{print $1}')
    info "Source size: ${BOLD}${src_size}${NC}"
    info "SSD destination: ${BOLD}${dst}${NC}"

    # Safety: enough space on SSD?
    local src_bytes ssd_free_bytes
    src_bytes=$(du -sk "$src" 2>/dev/null | awk '{print $1}')
    ssd_free_bytes=$(df -k "$SELECTED_SSD" | awk 'NR==2{print $4}')
    if (( src_bytes >= ssd_free_bytes )); then
        error "Not enough free space on SSD (need ~${src_size}). Skipping."
        return 1
    fi

    confirm "Copy '${label}' to SSD and replace with symlink?" || { info "Skipped."; return 0; }

    # If dst already has content, merge/abort
    if [[ -e "$dst" ]]; then
        warn "Destination already exists on SSD: ${dst}"
        confirm "Destination exists. Overwrite/merge with rsync?" || { info "Skipped."; return 0; }
    fi

    # Copy to SSD
    info "Copying to SSD (this may take a while)…"
    rsync -a --info=progress2 "${src}/" "${dst}/"
    ok "Copy complete."

    # Backup original dir name, then replace with symlink
    local backup="${src}.bak_$(date +%Y%m%d%H%M%S)"
    info "Renaming original → ${backup}"
    mv "$src" "$backup"

    ln -s "$dst" "$src"
    ok "Symlink created: ${src} → ${dst}"

    confirm "Verify & remove backup '${backup}'?" && {
        rm -rf "$backup"
        ok "Backup removed."
    } || warn "Backup kept at: ${backup}"
}

# ── Restore (un-symlink) ──────────────────────────────────────────────────────
unlink_dir() {
    local label="$1" src="$2"

    heading "Restoring: ${label}"

    if ! is_symlink "$src"; then
        warn "${src} is not a symlink. Nothing to restore."
        return 0
    fi

    local ssd_target; ssd_target=$(readlink "$src")
    local size; size=$(human_size "$src")
    info "SSD source: ${ssd_target}  (${size})"

    confirm "Copy '${label}' back to internal SSD and remove symlink?" || { info "Skipped."; return 0; }

    # Check internal space
    local src_bytes int_free_bytes
    src_bytes=$(du -sk "$ssd_target" 2>/dev/null | awk '{print $1}')
    int_free_bytes=$(df -k / | awk 'NR==2{print $4}')
    if (( src_bytes >= int_free_bytes )); then
        error "Not enough free space on internal SSD. Skipping."
        return 1
    fi

    rm "$src"                              # remove symlink
    mkdir -p "$src"
    rsync -a --info=progress2 "${ssd_target}/" "${src}/"
    ok "Restored: ${src}"

    confirm "Remove copy from external SSD (${ssd_target})?" && {
        rm -rf "$ssd_target"
        ok "SSD copy removed."
    } || warn "SSD copy kept at: ${ssd_target}"
}

# ── Interactive menu ──────────────────────────────────────────────────────────
main_menu() {
    while true; do
        show_status

        echo -e "  ${BOLD}Actions:${NC}"
        echo -e "  ${CYAN}[l]${NC} Link selected dir(s) to SSD"
        echo -e "  ${CYAN}[r]${NC} Restore selected dir(s) back to internal"
        echo -e "  ${CYAN}[a]${NC} Link ALL non-linked dirs (batch mode)"
        echo -e "  ${CYAN}[s]${NC} Refresh status"
        echo -e "  ${CYAN}[q]${NC} Quit"
        echo ""
        echo -en "${YELLOW}? ${NC}Choose action: "
        read -r action

        case "$action" in
            l|L)
                echo -en "${YELLOW}? ${NC}Enter number(s) to link (space-separated): "
                read -ra nums
                for n in "${nums[@]}"; do
                    if ! [[ "$n" =~ ^[0-9]+$ ]] || (( n < 1 || n > ${#CATALOG[@]} )); then
                        warn "Invalid index: $n"; continue
                    fi
                    local entry="${CATALOG[$((n-1))]}"
                    local label src dst
                    label=$(echo "$entry" | cut -d'|' -f1 | xargs)
                    src=$(echo "$entry"   | cut -d'|' -f2 | xargs)
                    dst=$(echo "$entry"   | cut -d'|' -f3 | xargs)
                    link_dir "$label" "$src" "$dst"
                done
                ;;
            r|R)
                echo -en "${YELLOW}? ${NC}Enter number(s) to restore (space-separated): "
                read -ra nums
                for n in "${nums[@]}"; do
                    if ! [[ "$n" =~ ^[0-9]+$ ]] || (( n < 1 || n > ${#CATALOG[@]} )); then
                        warn "Invalid index: $n"; continue
                    fi
                    local entry="${CATALOG[$((n-1))]}"
                    local label src
                    label=$(echo "$entry" | cut -d'|' -f1 | xargs)
                    src=$(echo "$entry"   | cut -d'|' -f2 | xargs)
                    unlink_dir "$label" "$src"
                done
                ;;
            a|A)
                warn "Batch mode: will prompt for each non-linked directory that exists."
                for entry in "${CATALOG[@]}"; do
                    local label src dst
                    label=$(echo "$entry" | cut -d'|' -f1 | xargs)
                    src=$(echo "$entry"   | cut -d'|' -f2 | xargs)
                    dst=$(echo "$entry"   | cut -d'|' -f3 | xargs)
                    [[ -e "$src" ]] && ! is_symlink "$src" && link_dir "$label" "$src" "$dst"
                done
                ok "Batch complete."
                ;;
            s|S) continue ;;
            q|Q) info "Goodbye!"; exit 0 ;;
            *)   warn "Unknown action: $action" ;;
        esac
    done
}

# ── Entry point ───────────────────────────────────────────────────────────────
print_banner

# Require macOS
if [[ "$(uname)" != "Darwin" ]]; then
    error "This script is designed for macOS only."
    exit 1
fi

detect_ssds
main_menu
