#!/usr/bin/env bash
# /* ---- 💫 https://github.com/JaKooLit 💫 ---- */  ##
# Waybar profiles - bundles a waybar LAYOUT (config) + STYLE (css) under one name

IFS=$'\n\t'

# Define directories
waybar_layouts="$HOME/.config/waybar/configs"
waybar_styles="$HOME/.config/waybar/style"
waybar_config="$HOME/.config/waybar/config"
waybar_style="$HOME/.config/waybar/style.css"
profiles_dir="$HOME/.config/waybar/profiles"
SCRIPTSDIR="$HOME/.config/hypr/scripts"
rofi_config="$HOME/.config/rofi/config-waybar-profile.rasi"

MARKER="👉"
ACT_NEW="➕   Save current as new profile"
ACT_UPDATE="💾   Update a profile with current"
ACT_RENAME="✏️   Rename a profile"
ACT_DELETE="🗑️   Delete a profile"

logfile="$HOME/.cache/waybar-profiles.log"

mkdir -p "$profiles_dir"

notify() {
    log "NOTIFY: $1 | $2"
    notify-send -a "Waybar Profiles" -i "preferences-desktop-theme" "$1" "$2"
}

log() {
    printf '%s %s\n' "$(date '+%H:%M:%S')" "$1" >>"$logfile"
    # keep the log from growing without bound
    if [[ $(wc -l <"$logfile" 2>/dev/null || echo 0) -gt 500 ]]; then
        tail -n 200 "$logfile" >"$logfile.tmp" && mv "$logfile.tmp" "$logfile"
    fi
}

# ---------- current state ----------
current_layout() { basename "$(readlink -f "$waybar_config")"; }
current_style() { basename "$(readlink -f "$waybar_style")" .css; }

# ---------- profile io ----------
list_profiles() {
    find -L "$profiles_dir" -maxdepth 1 -type f -name '*.profile' -printf '%f\n' 2>/dev/null |
        sed 's/\.profile$//' | sort
}

profile_layout() { sed -n 's/^layout=//p' "$profiles_dir/$1.profile" | head -1; }
profile_style() { sed -n 's/^style=//p' "$profiles_dir/$1.profile" | head -1; }

write_profile() {
    # $1 = profile name, saves whatever is active right now
    cat >"$profiles_dir/$1.profile" <<EOF
# waybar profile - written by WaybarProfiles.sh
layout=$(current_layout)
style=$(current_style)
EOF
}

# ---------- rofi helpers ----------
rofi_menu() {
    # $1 = message, rest via stdin
    rofi -i -dmenu -config "$rofi_config" -mesg "$1" -selected-row "${SELECTED_ROW:-0}"
}

rofi_prompt() {
    # $1 = message, $2 = placeholder. Returns the typed text.
    # The list is empty here, so plain Return has no entry to accept. Rofi only
    # accepts typed ("custom") input on Control+Return by default, which would make
    # Return look like it does nothing - so rebind Return onto accept-custom.
    local typed
    typed=$(: | rofi -dmenu -config "$rofi_config" -mesg "$1" -p "$2" \
        -theme-str "mainbox { children: [ \"inputbar\", \"message\" ]; }
                    listview { enabled: false; }
                    entry { placeholder: \"  $2, then press Enter\"; }" \
        -kb-accept-entry "Control+j,Control+m" \
        -kb-accept-custom "Return,KP_Enter,Control+Return")
    log "PROMPT($2) returned: [$typed]"
    printf '%s' "$typed"
}

sanitize() {
    # strip surrounding whitespace and anything that would break a filename
    printf '%s' "$1" | sed 's|[/\\]|-|g; s/^[[:space:]]*//; s/[[:space:]]*$//'
}

pick_profile() {
    # $1 = message. Echoes chosen profile name, empty if cancelled.
    local msg="$1" choice
    mapfile -t names < <(list_profiles)
    [[ ${#names[@]} -eq 0 ]] && return 1
    choice=$(printf '%s\n' "${names[@]}" | rofi -i -dmenu -config "$rofi_config" -mesg "$msg")
    printf '%s' "$choice"
}

# ---------- actions ----------
apply_profile() {
    local name="$1" layout style
    layout=$(profile_layout "$name")
    style=$(profile_style "$name")

    if [[ ! -f "$waybar_layouts/$layout" ]]; then
        notify "Profile '$name' is broken" "Layout not found: $layout"
        exit 1
    fi
    if [[ ! -f "$waybar_styles/$style.css" ]]; then
        notify "Profile '$name' is broken" "Style not found: $style"
        exit 1
    fi

    ln -sf "$waybar_layouts/$layout" "$waybar_config"
    ln -sf "$waybar_styles/$style.css" "$waybar_style"
    notify "Profile applied: $name" "$layout  •  $style"
    "${SCRIPTSDIR}/Refresh.sh" &
}

new_profile() {
    local name
    name=$(sanitize "$(rofi_prompt " Saving: $(current_layout)  •  $(current_style)" "Name this profile")")
    [[ -z "$name" ]] && exit 0

    if [[ -f "$profiles_dir/$name.profile" ]]; then
        local ans
        ans=$(printf 'No, keep it\nYes, overwrite\n' |
            rofi -i -dmenu -config "$rofi_config" -mesg " Profile '$name' already exists. Overwrite it?")
        [[ "$ans" != "Yes, overwrite" ]] && exit 0
    fi

    write_profile "$name"
    notify "Profile saved: $name" "$(current_layout)  •  $(current_style)"
}

update_profile() {
    local name
    name=$(pick_profile " Overwrite which profile with the current setup?") || {
        notify "No profiles yet" "Use ➕ to save your current setup first."
        exit 0
    }
    [[ -z "$name" ]] && exit 0
    write_profile "$name"
    notify "Profile updated: $name" "$(current_layout)  •  $(current_style)"
}

rename_profile() {
    local name new
    name=$(pick_profile " Rename which profile?") || {
        notify "No profiles yet" "Use ➕ to save your current setup first."
        exit 0
    }
    [[ -z "$name" ]] && exit 0

    new=$(sanitize "$(rofi_prompt " Renaming '$name'" "New name")")
    [[ -z "$new" || "$new" == "$name" ]] && exit 0

    if [[ -f "$profiles_dir/$new.profile" ]]; then
        notify "Rename failed" "A profile named '$new' already exists."
        exit 1
    fi

    mv "$profiles_dir/$name.profile" "$profiles_dir/$new.profile"
    notify "Renamed" "$name  →  $new"
}

delete_profile() {
    local name ans
    name=$(pick_profile " Delete which profile?") || {
        notify "No profiles yet" "Nothing to delete."
        exit 0
    }
    [[ -z "$name" ]] && exit 0

    ans=$(printf 'No, cancel\nYes, delete it\n' |
        rofi -i -dmenu -config "$rofi_config" \
            -mesg " Delete profile '$name'? (only the profile, not the layout/style files)")
    [[ "$ans" != "Yes, delete it" ]] && exit 0

    rm -f "$profiles_dir/$name.profile"
    notify "Profile deleted" "$name"
}

# ---------- main ----------
main() {
    local cur_layout cur_style choice
    cur_layout=$(current_layout)
    cur_style=$(current_style)

    # first run: seed a profile from whatever is currently active
    if [[ -z "$(list_profiles)" ]]; then
        write_profile "Default"
    fi

    mapfile -t options < <(list_profiles)

    # mark the profile matching the live symlinks
    SELECTED_ROW=0
    for i in "${!options[@]}"; do
        if [[ "$(profile_layout "${options[i]}")" == "$cur_layout" &&
            "$(profile_style "${options[i]}")" == "$cur_style" ]]; then
            options[i]="$MARKER ${options[i]}"
            SELECTED_ROW=$i
            break
        fi
    done

    options+=("$ACT_NEW" "$ACT_UPDATE" "$ACT_RENAME" "$ACT_DELETE")

    choice=$(printf '%s\n' "${options[@]}" |
        rofi_menu " Active:  $cur_layout  •  $cur_style")

    log "MENU returned: [$choice]"
    [[ -z "$choice" ]] && exit 0

    # Matched on the trailing text, not the whole label, so an emoji or whitespace
    # difference in what rofi echoes back can't silently fall through to apply_profile.
    case "$choice" in
    *"Save current as new profile") new_profile ;;
    *"Update a profile with current") update_profile ;;
    *"Rename a profile") rename_profile ;;
    *"Delete a profile") delete_profile ;;
    *)
        local name="${choice#"$MARKER "}"
        if [[ ! -f "$profiles_dir/$name.profile" ]]; then
            log "ERROR: no profile file for [$name]"
            notify "Unrecognized menu entry" "Not a saved profile: $name"
            exit 1
        fi
        apply_profile "$name"
        ;;
    esac
}

# Kill Rofi if already running before execution
if pgrep -x "rofi" >/dev/null; then
    pkill rofi
    sleep 0.1
fi

main
