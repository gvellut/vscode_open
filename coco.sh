#!/usr/bin/env bash



# Script to open files in VSCode (macOS enhanced for specific status output).
# Assumes `code --status` only lists workspace windows.
# Tries to find a non-workspace VSCode window, activate it, and reuse it.
# Falls back to a new window if no suitable existing window is found.

# Function to log to stderr
log_debug() {
    echo "DEBUG: $1" >&2
}

if [ "$#" -eq 0 ]; then
    echo "Usage: $(basename "$0") <file1> [file2 ...]"
    exit 1
fi

# 0. Ensure VSCode process is running before anything else
if ! pgrep -f "Visual Studio Code.app" > /dev/null && \
   ! pgrep -f "Code Helper (Renderer).app" > /dev/null && \
   ! pgrep -f "Code Helper.app" > /dev/null; then
    log_debug "No VSCode process running. Opening files in a new window."
    code --new-window "$@"
    exit 0
fi


# 1. Get "known" workspace window identifiers from `code --status`
status_output=$(code --status 2>/dev/null || true)
known_workspace_identifiers=()

if [ -z "$status_output" ] || ! echo "$status_output" | grep -q "Window ("; then
    log_debug "code --status output is empty or shows no windows. This might mean VSCode is just starting or no workspaces are open according to 'status'."
else
    while IFS= read -r line; do
        if [[ "$line" == *"|  Window ("* ]]; then
            identifier=$(echo "$line" | sed -n 's/.*|  Window (\([^)]*\)).*/\1/p')
            if [ -n "$identifier" ]; then
                known_workspace_identifiers+=("$identifier")
            fi
        fi
    done < <(echo "$status_output")
fi

log_debug "Known workspace identifiers from code --status (${#known_workspace_identifiers[@]} found):"
for id_val in "${known_workspace_identifiers[@]}"; do
    log_debug " - $id_val"
done


# 2. Use AppleScript to find a VSCode window NOT in the known_workspace_identifiers
#    and activate it.
applescript_command="
on escape_for_shell(the_string)
    if the_string is missing value or the_string is \"\" then return \"''\"

    set astid to AppleScript's text item delimiters
    set AppleScript's text item delimiters to \"'\"
    set segments to text items of the_string
    set AppleScript's text item delimiters to \"'\\\\''\"
    set quoted_string to \"'\" & segments as string & \"'\"
    set AppleScript's text item delimiters to astid
    return quoted_string
end escape_for_shell

tell application \"System Events\" to tell process \"Code\"
    try
        try
            activate
            delay 0.2
        on error e
            log \"echo 'DEBUG_AS: Error during VSCode activate: \" & (my escape_for_shell(e as string)) & \"' >&2\"
            return false
        end try

        set knownIdentifiers to {"
# Inject bash array into AppleScript list of strings
first_id=true
for id_val in "${known_workspace_identifiers[@]}"; do
    if [ "$first_id" = false ]; then
        applescript_command+=","
    fi
    escaped_id_val_as=$(printf '%s\n' "$id_val" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
    applescript_command+="\"$escaped_id_val_as\""
    first_id=false
done
applescript_command+="}

        set activated_other_window to false
        set window_to_activate to null
        set window_to_activate_index to null
        set all_windows_list to {}

        try
            set all_windows_list to windows
        on error err_get_windows
            set msg to \"DEBUG_AS: Critical error getting list of VSCode windows: \" & (my escape_for_shell(err_get_windows as string))
            log \"echo \" & (my escape_for_shell(msg)) & \" >&2\"
            return false
        end try
        
        if (count of all_windows_list) > 0 then
            repeat with w_index from 1 to (count of all_windows_list)
                set w to item w_index of all_windows_list
                set current_window_title to \"\"

                try
                    set current_window_title to name of w
                    if current_window_title is \"\" or current_window_title is missing value then
                       log \"'DEBUG_AS: Window \" & w_index & \" has an empty or missing title.' >&2\"
                    else

                        set escaped_title_for_log to my escape_for_shell(current_window_title)
                        log \"'DEBUG_AS: Checking window title (\" & w_index & \"): \" & escaped_title_for_log & \"' >&2\"
                    end if
                on error err_msg number err_num
                    set escaped_err_msg to my escape_for_shell(\"Error getting name for window \" & w_index & \": \" & err_msg & \" (\" & err_num & \")\")
                    log \"echo 'DEBUG_AS: \" & escaped_err_msg & \"' >&2\"
                    cycle
                end try

                set is_known_workspace to false
                if current_window_title is not \"\" and current_window_title is not missing value then
                    repeat with known_id in knownIdentifiers
                        if current_window_title contains (known_id as string) then
                            set is_known_workspace to true
                            exit repeat
                        end if
                    end repeat
                else
                    log \"echo 'DEBUG_AS: Window (\" & w_index & \") with empty/missing title is being considered a non-workspace.' >&2\"
                end if

                if not is_known_workspace then
                    set window_to_activate to w
                    set window_to_activate_index to w_index
                    if current_window_title is not \"\" and current_window_title is not missing value then
                         set escaped_candidate_title_for_log to my escape_for_shell(current_window_title)
                         log \"echo 'DEBUG_AS: Found candidate window (\" & w_index & \"): \" & escaped_candidate_title_for_log & \"' >&2\"
                    else
                         log \"echo 'DEBUG_AS: Found candidate window (\" & w_index & \") (it had an empty/missing title).' >&2\"
                    end if
                    exit repeat
                end if
            end repeat
        else
            log \"echo 'DEBUG_AS: No windows found in VSCode (count of all_windows_list is 0).' >&2\"
        end if

        if window_to_activate is not null then
            try
                tell window_to_activate to perform action \"AXRaise\"
                delay 0.2
                set frontmost to true
                delay 0.2
                set windowMenu to menu \"Window\" of menu bar 1
                click menu item (name of window_to_activate) of windowMenu
                delay 0.2
                
                set activated_other_window to true
                try
                    set final_activated_title_as to name of window_to_activate
                    if final_activated_title_as is \"\" or final_activated_title_as is missing value then
                        log \"echo 'DEBUG_AS: Successfully activated candidate window (title was empty/missing post-activation).' >&2\"
                    else
                        log \"echo 'DEBUG_AS: Successfully activated window: \" & (my escape_for_shell(final_activated_title_as)) & \"' >&2\"
                    end if
                on error
                    log \"echo 'DEBUG_AS: Successfully activated candidate window (but could not get its name post-activation).' >&2\"
                end try
            on error err_set_index number err_set_idx_num
                 set escaped_err_set_idx to my escape_for_shell(\"Error setting index (activating) for candidate window: \" & err_set_index & \" (\" & err_set_idx_num & \")\")
                 log \"echo 'DEBUG_AS: \" & escaped_err_set_idx & \"' >&2\"
                 set activated_other_window to false
            end try
        else
            log \"echo 'DEBUG_AS: No suitable window (window_to_activate) was identified by AppleScript.' >&2\"
        end if

        return activated_other_window

    on error main_outer_error
        set msg to \"DEBUG_AS: Critical top-level AppleScript error within tell block: \" & (my escape_for_shell(main_outer_error as string))
        log \"echo \" & (my escape_for_shell(msg)) & \" >&2\"
        return false
    end try
end tell
"

# Execute AppleScript
activation_success_str=$(osascript -e "$applescript_command")
osascript_exit_code=$?

log_debug "AppleScript activation string result (stdout): '$activation_success_str'"
log_debug "osascript exit code: $osascript_exit_code"

if [ $osascript_exit_code -ne 0 ]; then
    log_debug "osascript command itself failed. Assuming activation failed."
    activation_success_bool="false"
else
    if [ "$activation_success_str" = "true" ]; then
        activation_success_bool="true"
    else
        activation_success_bool="false"
    fi
fi

# 3. Decide how to open files
if [ "$activation_success_bool" = "true" ]; then
    log_debug "Decision: Found and activated a suitable VSCode window. Reusing it."
    sleep 0.2
    echo "Opening files in reused VSCode window: $@"
    code --reuse-window "$@"
else
    log_debug "Decision: No suitable non-workspace VSCode window found/activated, or an error occurred. Opening in a new window."
    echo "Opening files in a new VSCode window: $@"
    code --new-window "$@"
fi


exit 0