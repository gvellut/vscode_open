# VSCode Open

## Install the code CLI tool

In VSCode, open the Command Palette (Cmd+Shift+P), type 'shell command', and run the *Shell Command: Install 'code' command in PATH* command.

## Permissions

- *Privacy & Security > Full Disk Access > Finder*: Add if not there (found in `/System/Library/CoreServices/Finder.app`)
- *Privacy & Security > Accessibility > Finder*: Add if not there (also:  VSCode + terminal for command-line open + testing)
- *Privacy & Security > Automation > Finder* (System Events) (also: VSCode + terminal for command-line open + testing). Will be asked when first needed if never set. Otherwise, there will be some error (if explicitly unset).

Note:

```
tccutil reset AppleEvents  => reset automation menu
... Accessibility
... SystemPolicyAllFiles (full disk access)
```

## Shortcuts

Create a menu item called `Open in VSCode` in *Right-click > Quick Actions* menu in Finder:

- Set script execution: 

`chmod u+x coco.sh`

- In Shortcuts, action type *Run Shell Script*:

`<full path>/coco.sh "<Shortcut Input (File Path)>"` (quotes to handles file names with spaces)

![](https://github.com/gvellut/vscode_open/blob/master/shortcuts_screenshot.png "Shortcuts")

- Pass Input as Arguments (doesn't matter: passed explicitly ; Or set to "as arguments" and use $@ in the text area ie input to the shell script defined in Shortcuts)

- Activate shortcut in *Login items > Extensions > Finder*
