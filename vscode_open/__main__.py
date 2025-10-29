#!/usr/bin/env python3

import logging
import re
import shlex
import subprocess
import sys

import AppKit
import click
import psutil
import Quartz
import ScriptingBridge

# --- Basic Setup ---
logging.basicConfig(level=logging.DEBUG, format="DEBUG: %(message)s", stream=sys.stderr)


def log_debug(message):
    """Helper function to log debug messages."""
    logging.debug(message)


def run_command(command):
    """Runs a command and returns its stdout, stderr, and return code."""
    try:
        process = subprocess.run(
            shlex.split(command), capture_output=True, text=True, check=False
        )
        return process.stdout, process.stderr, process.returncode
    except FileNotFoundError:
        log_debug(f"Command not found: {command.split()[0]}")
        return "", f"Command not found: {command.split()[0]}", 127
    except Exception as e:
        log_debug(f"An unexpected error occurred while running '{command}': {e}")
        return "", str(e), 1


def is_vscode_running():
    """
    Checks if any VSCode-related processes are running by inspecting their
    command line for the main application path.
    """
    target_pattern = "Visual Studio Code.app"
    for proc in psutil.process_iter(["cmdline"]):
        try:
            if not proc.info["cmdline"]:
                continue
            if any(target_pattern in cmd_part for cmd_part in proc.info["cmdline"]):
                return True
        except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess):
            continue
    return False


def find_reusable_window_from_status():
    """
    Parses `code --status` to find a reusable window.

    A window is considered reusable if its title is listed in the process list
    but NOT in the "Workspace Stats:" section. The "Welcome" window is ignored.

    Returns:
        bool: True if a suitable window is found, False otherwise.
    """
    status_output, stderr, retcode = run_command("code --status")
    if retcode != 0:
        log_debug(f"Failed to run 'code --status'. Stderr: {stderr.strip()}")
        return False

    all_window_titles = get_vscode_window_names_cg()

    workspace_titles = []
    in_workspace_stats_section = False

    # Regex to capture titles from the two different sections
    workspace_stats_pattern = re.compile(r"\|\s+Window \((.*)\)")

    for line in status_output.splitlines():
        if "Workspace Stats:" in line:
            in_workspace_stats_section = True
            continue

        if in_workspace_stats_section:
            match = workspace_stats_pattern.search(line)
            if match:
                workspace_titles.append(match.group(1).strip())

    all_window_titles = sorted(all_window_titles)
    workspace_titles = sorted(workspace_titles)

    # Use a set for efficient lookup
    workspace_title_set = set(workspace_titles)

    log_debug(f"Found {len(all_window_titles)} total windows.")
    log_debug(f"Found {len(workspace_title_set)} declared workspaces.")

    # Find a window that exists in the process list but not the workspace list
    for title in all_window_titles:
        if title == "Welcome":
            log_debug("Ignoring 'Welcome' window.")
            continue

        if title not in workspace_title_set:
            log_debug(f"Found reusable window: '{title}' (not in workspace list).")
            return True

    log_debug("No reusable window found after comparing with Workspace Stats.")
    return False


def activate_vscode():
    """Brings the VSCode application to the foreground using AppKit."""
    apps = AppKit.NSRunningApplication.runningApplicationsWithBundleIdentifier_(
        "com.microsoft.VSCode"
    )
    if apps:
        app = apps[0]
        app.activateWithOptions_(AppKit.NSApplicationActivateIgnoringOtherApps)
        log_debug("Successfully activated the VSCode application.")
        return True
    log_debug("Could not find the running VSCode application to activate.")
    return False


# need permission for VScode or Terminal or Finder (where run) :
# Automation > System Events
def get_vscode_window_names_sb():
    system_events = ScriptingBridge.SBApplication.applicationWithBundleIdentifier_(
        "com.apple.systemevents"
    )

    vscode_process = system_events.processes().objectWithName_("Code")

    if not vscode_process.exists():
        return []

    return [window.name() for window in vscode_process.windows()]


# need permission for VScode or Terminal or Finder (where run) :
# Automation > System Events
def get_vscode_window_names_as():
    """
    Executes an AppleScript to get the names of all open Visual Studio Code windows.
    The necessary 'subprocess' module is imported inside the function.

    Returns:
        list[str]: A list of window titles. Returns an empty list on error
                   or if no windows are found.
    """
    import subprocess

    applescript = """
    tell application "System Events"
        if not (exists process "Code") then return ""
        tell process "Code"
            try
                return name of every window
            on error
                return ""
            end try
        end tell
    end tell
    """
    try:
        proc = subprocess.run(
            ["osascript", "-e", applescript], capture_output=True, text=True, check=True
        )
        output = proc.stdout.strip()
        if not output:
            return []
        return output.split(", ")
    except (subprocess.CalledProcessError, FileNotFoundError):
        return []


# need permission for VScode or Terminal or Finder (where run) :
# Screen & Audio recording
# for kCGWindowName
def get_vscode_window_names_cg():
    window_list = Quartz.CGWindowListCopyWindowInfo(
        Quartz.kCGWindowListOptionOnScreenOnly, Quartz.kCGNullWindowID
    )

    vscode_windows = [
        win for win in window_list if "code" in win.get("kCGWindowOwnerName").lower()
    ]
    log_debug(f"Found {len(vscode_windows)} on-screen VSCode windows via CoreGraphics.")

    if not vscode_windows:
        return False

    return [window.get("kCGWindowName", "").strip() for window in vscode_windows]


@click.command()
@click.option(
    "-f",
    "--file",
    "files_to_open",
    multiple=True,
    type=click.Path(exists=True, dir_okay=True, resolve_path=True),
    help="File or directory to open in VSCode. Can be specified multiple times.",
)
def main(files_to_open):
    """
    Checks for a reusable VSCode window and opens files.
    If no files are specified, it only reports if a reusable window exists.
    """
    if not is_vscode_running():
        log_debug("No VSCode process running.")
        if files_to_open:
            log_debug("Opening files in a new window.")
            subprocess.run(["code", "--new-window", *files_to_open], check=False)
        else:
            print("VSCode is not running.")
        sys.exit(0)

    reusable_window_exists = find_reusable_window_from_status()

    if not files_to_open:
        if reusable_window_exists:
            print("A reusable non-workspace VSCode window was found.")
        else:
            print("No reusable non-workspace VSCode window was found.")
        sys.exit(0)

    quoted_files = " ".join(shlex.quote(f) for f in files_to_open)
    if reusable_window_exists:
        log_debug(
            "Decision: A reusable non-workspace window exists. Activating and reusing."
        )
        print(f"Opening files in a reused VSCode window: {quoted_files}")
        activate_vscode()
        subprocess.run(["code", "--reuse-window", *files_to_open], check=False)
    else:
        log_debug(
            "Decision: No suitable non-workspace window found. Opening in a new window."
        )
        print(f"Opening files in a new VSCode window: {quoted_files}")
        subprocess.run(["code", "--new-window", *files_to_open], check=False)

    sys.exit(0)


if __name__ == "__main__":
    main()
