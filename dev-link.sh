#!/bin/bash

# Development symlink script for phoenix-dots
# Creates symlinks from repo to ~/.config for live development

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[1;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$HOME/.config"
BACKUP_DIR="$HOME/.config-backup-phoenix-dots-$(date +%Y%m%d_%H%M%S)"

# Folders to symlink (relative to dots/.config)
LINK_TARGETS=("hypr" "quickshell")

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}   phoenix-dots dev-link setup   ${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --link       Create symlinks (default)"
    echo "  --unlink     Remove symlinks and restore backups"
    echo "  --status     Show current link status"
    echo "  --no-backup  Skip backup of existing configs"
    echo "  -h, --help   Show this help"
    echo ""
    echo "This script symlinks config folders from the repo to ~/.config"
    echo "for live development. Changes in either location reflect immediately."
}

check_status() {
    echo -e "${BLUE}Current symlink status:${NC}"
    echo ""
    for target in "${LINK_TARGETS[@]}"; do
        config_path="$CONFIG_DIR/$target"
        repo_path="$SCRIPT_DIR/dots/.config/$target"
        
        if [ -L "$config_path" ]; then
            link_target=$(readlink -f "$config_path")
            if [ "$link_target" = "$repo_path" ]; then
                echo -e "  ${GREEN}✓${NC} $target -> linked to repo"
            else
                echo -e "  ${YELLOW}⚠${NC} $target -> symlink exists but points elsewhere: $link_target"
            fi
        elif [ -d "$config_path" ]; then
            echo -e "  ${YELLOW}○${NC} $target -> regular directory (not linked)"
        elif [ -e "$config_path" ]; then
            echo -e "  ${RED}✗${NC} $target -> exists but not a directory"
        else
            echo -e "  ${RED}✗${NC} $target -> does not exist"
        fi
    done
    echo ""
}

do_link() {
    local skip_backup=$1
    
    echo -e "${BLUE}Creating symlinks...${NC}"
    echo ""
    
    local needs_backup=false
    for target in "${LINK_TARGETS[@]}"; do
        config_path="$CONFIG_DIR/$target"
        if [ -e "$config_path" ] && [ ! -L "$config_path" ]; then
            needs_backup=true
            break
        fi
    done
    
    if [ "$needs_backup" = true ] && [ "$skip_backup" != true ]; then
        echo -e "${YELLOW}Backing up existing configs to: $BACKUP_DIR${NC}"
        mkdir -p "$BACKUP_DIR"
    fi
    
    for target in "${LINK_TARGETS[@]}"; do
        config_path="$CONFIG_DIR/$target"
        repo_path="$SCRIPT_DIR/dots/.config/$target"
        
        # Check if repo source exists
        if [ ! -d "$repo_path" ]; then
            echo -e "  ${RED}✗${NC} $target: source not found in repo"
            continue
        fi
        
        # Already correctly linked
        if [ -L "$config_path" ]; then
            link_target=$(readlink -f "$config_path")
            if [ "$link_target" = "$repo_path" ]; then
                echo -e "  ${GREEN}✓${NC} $target: already linked"
                continue
            else
                echo -e "  ${YELLOW}⚠${NC} $target: removing existing symlink"
                rm "$config_path"
            fi
        fi
        
        # Backup and remove existing directory
        if [ -d "$config_path" ]; then
            if [ "$skip_backup" != true ]; then
                echo -e "  ${YELLOW}↗${NC} $target: backing up existing config"
                mv "$config_path" "$BACKUP_DIR/$target"
            else
                echo -e "  ${RED}!${NC} $target: removing existing config (no backup)"
                rm -rf "$config_path"
            fi
        fi
        
        # Create symlink
        ln -s "$repo_path" "$config_path"
        if [ $? -eq 0 ]; then
            echo -e "  ${GREEN}✓${NC} $target: linked"
        else
            echo -e "  ${RED}✗${NC} $target: failed to create symlink"
        fi
    done
    
    echo ""
    echo -e "${GREEN}Done!${NC} Changes in the repo will now reflect in ~/.config immediately."
    echo -e "${BLUE}Tip:${NC} Run 'hyprctl reload' or restart quickshell to see changes."
}

do_unlink() {
    echo -e "${BLUE}Removing symlinks...${NC}"
    echo ""
    
    # Find latest backup
    local latest_backup=$(ls -dt "$HOME"/.config-backup-phoenix-dots-* 2>/dev/null | head -1)
    
    for target in "${LINK_TARGETS[@]}"; do
        config_path="$CONFIG_DIR/$target"
        
        if [ -L "$config_path" ]; then
            rm "$config_path"
            echo -e "  ${GREEN}✓${NC} $target: symlink removed"
            
            # Try to restore from backup
            if [ -n "$latest_backup" ] && [ -d "$latest_backup/$target" ]; then
                mv "$latest_backup/$target" "$config_path"
                echo -e "  ${GREEN}↩${NC} $target: restored from backup"
            fi
        elif [ -d "$config_path" ]; then
            echo -e "  ${YELLOW}○${NC} $target: not a symlink, skipping"
        else
            echo -e "  ${YELLOW}○${NC} $target: does not exist"
        fi
    done
    
    echo ""
    echo -e "${GREEN}Done!${NC} Symlinks removed."
}

# Parse arguments
ACTION="link"
SKIP_BACKUP=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --link)
            ACTION="link"
            shift
            ;;
        --unlink)
            ACTION="unlink"
            shift
            ;;
        --status)
            ACTION="status"
            shift
            ;;
        --no-backup)
            SKIP_BACKUP=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            show_help
            exit 1
            ;;
    esac
done

case $ACTION in
    link)
        do_link $SKIP_BACKUP
        ;;
    unlink)
        do_unlink
        ;;
    status)
        check_status
        ;;
esac
