Fix for Star Wars: The Old Republic to run under Wine
=========

Wine needs a patch to correct system time synchronisation - which is essential to support the SW:TOR network code.
See [Wine Bug 29168 - Multiple games and applications need realtime updates to KSYSTEM_TIME members in KUSER_SHARED_DATA (Star Wars: The Old Republic game client, GO 1.4+ runtime)](http://bugs.winehq.org/show_bug.cgi?id=29168) ...


The **swtor_fix.exe** operation sequence is to:
1. wait for the main **swtor.exe** executable to start up.
2. Stores the PID of main **swtor.exe** executable.
3. Two additional threads are forked off the main swtor.exe thread.
  * The first thread waits for **swtor.exe** to end and then does cleanup.
  * The second thread continuously updates the process **KUSER_SHARED_DATA** time fields and copies these fields into **swtor.exe** process memory.


This code is based on the [**swtor_fix**](https://github.com/aljen/swtor_fix) Github repository by **Artur Wyszyński**.
This in turn was based on the original patch for Wine by **Carsten Juttner** & **Xolotl Loki**.

Updates to the original **swtor_fix** repository contents:
* **launcher.sh** script: code refactoring, sets required mouse warping override, handles Windows filesystem case insensitivity, trapping exit conditions, etc.
* **swtor_fix.exe**: supports a time parameter (in milliseconds) to set the update interval for the **KUSER_SHARED_DATA** time fields.


Howto Use Launcher Script
=========

```
# Set WINEPREFIX to location of SWTOR WINEPREFIX.
cd "${WINEPREFIX:-${HOME}/.wine}/drive_c"
git clone https://github.com/bobwya/swtor_fix.git
cd swtor_fix
./launcher.sh
```
