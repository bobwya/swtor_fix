Fix for Star Wars: The Old Republic to run under Wine
=========

Wine needs a patch (http://bugs.winehq.org/show_bug.cgi?id=29168) to fix the SW:TOR network code time synchronisation.
The swtor_fix.exe function are:
wait for the main swtor.exe executable to start up.
Stores PID of main swtor.exe executable.
Two threads are forked.
The first thread waits for swtor.exe to end to do cleanup
The second thread continuously updates the process KUSER_SHARED_DATA time fields and copies these fields into swtor.exe process memory.

This code is based on the swtor_fix repository by Artur Wyszyński.
This in turn was based on the original patch for Wine by Carsten Juttner & Xolotl Loki.

Updates to the original swtor_fix repository:
A simple build script for swtor_fix.exe (build.sh)
Improved launcher.sh script (code refactoring, sets required mouse warping override, handles Windows filesystem case insensitivity, trapping exit conditions).
swtor_fix.exe now supports a time parameter (in milliseconds) to set the update interval for the KUSER_SHARED_DATA time fields

Howto Use Repository
=========

```
# Set WINEPREFIX to location of SWTOR WINEPREFIX.
cd "${WINEPREFIX:-${HOME}/.wine}/drive_c"
git clone
./launcher.sh
```