-- Use only Finder's public scripting dictionary, scoped to this newly built volume.
on run arguments
    set mountPath to item 1 of arguments
    set installerFolder to POSIX file mountPath as alias
    tell application "/System/Library/CoreServices/Finder.app"
        set installerFolder to item installerFolder
        open installerFolder
        tell container window of installerFolder
            set current view to icon view
            set toolbar visible to false
            set statusbar visible to false
            set bounds to {160, 160, 840, 600}
            tell the icon view options of container window of installerFolder
                set arrangement to not arranged
                set icon size to 96
                set text size to 14
                set background picture to file ".background:background.png" of installerFolder
            end tell
            set position of item "Redstone Desktop.app" to {170, 240}
            set position of item "Applications" to {510, 240}
            close
        end tell
        set extension hidden of item "Redstone Desktop.app" of installerFolder to true
        update installerFolder without registering applications
    end tell
end run
