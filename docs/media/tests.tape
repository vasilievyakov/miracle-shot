# Renders docs/media/tests.gif with VHS (https://github.com/charmbracelet/vhs): `vhs docs/media/tests.tape`
Output docs/media/tests.gif
Set Shell zsh
Set FontFamily "JetBrains Mono"
Set FontSize 15
Set Width 1100
Set Height 300
Set Theme { "background": "#0b0b0c", "foreground": "#f3f0e8", "cursor": "#d4ff3f" }
Set Padding 24
Set PlaybackSpeed 2.0
Type "swift test 2>&1 | grep -E 'Test Suite .*(passed|failed)|Executed' | tail -3"
Sleep 500ms
Enter
Sleep 22s
Type "scripts/build-app.sh 2>&1 | tail -4"
Sleep 500ms
Enter
Sleep 16s
Sleep 2s
