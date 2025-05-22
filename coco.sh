#!/bin/bash

# Script to open files in VSCode based on existing instance states (macOS enhanced).

if [ "$#" -eq 0 ]; then
    echo "Usage: $(basename "$0") <file1> [file2 ...]"
    echo "Description: Opens specified files in VSCode."
    echo " - If no VSCode instance is running, opens files in a new instance."
    echo " - If all running instances have a folder/workspace open, opens files in a new instance."
    echo " - If an instance exists with only files open (no folder/workspace),"
    echo "   it attempts to activate that window and then opens files as tabs in it."
    exit 1
fi

# Get VSCode status.
# The '|| true' prevents script exit if code --status returns non-zero (e.g., no instances)
status_output=$(code --status 2>/dev/null || true)

# 1. Check if any VSCode instance is running.
if ! echo "$status_output" | grep -q "Window ("; then
    echo "No VSCode instance running. Opening files in a new window."
    code --new-window "$@"
    exit 0
fi

# 2. Find the first "file-only" window, if any.
# A "file-only" window line contains "(parent folder:"
# We'll try to activate this one.
file_only_window_line=$(echo "$status_output" | grep "Window (" | grep "(parent folder:" | head -n 1)
target_file_path_for_activation=""

if [ -n "$file_only_window_line" ]; then
    echo "Debug: Found file-only window line: $file_only_window_line"
    # Attempt to extract the file path. Example line:
    # Window (3): /Users/myuser/somefile.txt (parent folder: /Users/myuser/)
    # We want "/Users/myuser/somefile.txt"
    # This regex tries to get the path after "Window (N): " and before " (" or end of line.
    # Using awk is a bit more robust for splitting.
    target_file_path_for_activation=$(echo "$file_only_window_line" | awk -F': ' '{print $2}' | awk '{print $1}')

    if [ -z "$target_file_path_for_activation" ]; then
        echo "Warning: Could not reliably parse file path from file-only window line."
        file_only_window_line="" # Treat as if no suitable window found
    else
        echo "Identified target file-only window via file: $target_file_path_for_activation"
    fi
fi


# 3. Decide how to open the files based on findings.
if [ -n "$file_only_window_line" ] && [ -n "$target_file_path_for_activation" ]; then
    echo "Attempting to activate VSCode window associated with: $target_file_path_for_activation"

    # Prepare the AppleScript command.
    # It will try to match based on the document path.
    # Using basename as a fallback for title matching if document path fails.
    target_file_basename=$(basename "$target_file_path_for_activation")

    # Note: AppleScript's `path of document` might be empty for some windows or not exactly matching.
    # Title matching (`name of window`) can be a fallback.
    # VSCode titles for files are often "filename — Visual Studio Code".
    # We escape double quotes for the AppleScript string within the bash script.
    applescript_command="
    tell application \"Visual Studio Code\"
        activate -- Bring VSCode to front first
        set found_and_activated to false
        repeat with w in windows
            try
                set win_doc_path to path of document of w
                if win_doc_path is \"$target_file_path_for_activation\" then
                    set index of w to 1 -- Bring this specific window to front
                    set found_and_activated to true
                    exit repeat
                end if
            on error
                -- Window might not have a document (e.g., empty window) or path property error
                -- Try matching by name (title) as a fallback
                if name of w contains \"$target_file_basename\" then
                    set index of w to 1
                    set found_and_activated to true
                    exit repeat
                end if
            end try
        end repeat
        return found_and_activated
    end tell
    "

    activation_success=$(osascript -e "$applescript_command" 2>/dev/null)

    if [ "$activation_success" = "true" ]; then
        echo "Successfully activated the target file-only VSCode window."
        # Give a very brief moment for the OS to switch focus
        sleep 0.2
        echo "Reusing activated window for: $@"
        code --reuse-window "$@"
    else
        echo "Could not activate the specific file-only window (or it was closed). Opening in a new window."
        code --new-window "$@"
    fi
else
    # This means all existing windows are project/folder windows, or no instances running (handled earlier)
    echo "No suitable file-only window found, or all are project/workspaces. Opening files in a new window."
    code --new-window "$@"
fi

exit 0