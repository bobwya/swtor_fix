#! /bin/bash


# Declare global constants
declare -r      G_VARIABLE_REGEX="^[_[:alpha:]][_[:alnum:]]*$" \
				G_GITHUB_SWTOR_FIX_URL="https://github.com/bobwya/swtor_fix/raw/master/swtor_fix.exe"
declare -r      SCRIPT_PATH="$(readlink -f "${0}")"
export			SCRIPT_NAME="$(basename "${SCRIPT_PATH}")"

# cleanup ()
function cleanup()
{
	wineserver -k
	unset -v WINEDEBUG
}

function handle_error()
{
	printf "%s: %s: %s\n" "${SCRIPT_NAME}" "${FUNCNAME[1]}()" "${1}" >&2
	if [[ ! -z "${2}" ]]; then
		trap '' ABRT INT QUIT KILL TERM
		cleanup
		exit ${2}
	fi
}

function trap_exit()
{
	handle_error "Cleaning up" 0
}

# Where is my WINEPREFIX?
function find_wineprefix_directory()
{
	(($# != 0)) && handle_error "invalid argument count ${#} (0)" 1

	if [[ -z "${WINEPREFIX}" || ! -d "${WINEPREFIX}" ]]; then
		export WINEPREFIX="${PWD%/drive_c/*}"
		export WINEPREFIX="${PWD%/drive_c}"
	fi
	printf "%s\n" "${WINEPREFIX}"
	if [[ ! -d "${WINEPREFIX}" ]]; then
		handle_error "unable to locate current WINEPREFIX directory" 1
	fi
	return
}

# Find SWTOR game install directory - using launcher.exe (note: use non-case specific paths to support NTFS)
function find_launcher_directory()
{
	(($# > 1)) && handle_error "invalid argument count ${#} (0-1)" 1

	local __launcher_path
	__launcher_path="$(find "${WINEPREFIX}" -regextype posix-extended -executable -type f -iregex "(.*Star Wars\-The Old Republic\/|.\/)launcher\.exe")"
	__launcher_path="(readlink -f "${__launcher_path}")"
	__launcher_directory="$(dirname "${__launcher_path}")"
	if [[ ! -z "${1}" && ("${1}" =~ ${G_VARIABLE_REGEX}) ]]; then
		local -n __launcher_directory_reference="${1}"
		__launcher_directory_reference="${__launcher_directory}"
	else
		echo "${__launcher_directory}"
	fi
	[[ -d "${__launcher_directory}" ]]
}

# Find main SWTOR game executable launcher.exe (note: use non-case specific paths to support NTFS)
function find_launcher_executable_path()
{
	(($# > 1)) && handle_error "invalid argument count ${#} (0-1)" 1

	local __launcher_path
	__launcher_path="$(find "${WINEPREFIX}" -regextype posix-extended -executable -type f -iregex "(.*Star Wars\-The Old Republic\/|.\/)launcher\.exe")"
	__launcher_path="$(readlink -f "${__launcher_path}")"
	if [[ ! -z "${1}" && ("${1}" =~ ${G_VARIABLE_REGEX}) ]]; then
		local -n __launcher_path_reference="${1}"
		__launcher_path_reference="${__launcher_path}"
	else
		echo "${__launcher_path}"
	fi
	[[ -f "${__launcher_path}" ]]
}

# Find SWTOR game settings file path (note: use non-case specific paths to support NTFS)
function find_launcher_settings_file()
{
	(( ($# < 1) || ($# > 2) )) && handle_error "invalid argument count ${#} (1-2)" 1

	local __launcher_directory="${1}"
	if [[ ! -d "${__launcher_directory}" ]]; then
		handle_error "invalid \"${__launcher_directory}\" game directory specified" 1
	fi

	local __launcher_settings_file=$( find "${__launcher_directory}" -mindepth 1 -maxdepth 1 -type f -iname "launcher.settings")
	if [[ ! -z "${2}" && ("${2}" =~ ${G_VARIABLE_REGEX}) ]]; then
		local -n launcher_settings_reference="${2}"
		launcher_settings_reference="${__launcher_settings_file}"
	else
		echo "${__launcher_settings_file}"
	fi
	[[ -f "${__launcher_settings_file}" ]]
}

# Get value of specified setting name in SWTOR game launcher settings file
function get_launcher_settings_file_value()
{
	(( ($# < 2) || ($# > 3) )) && handle_error "invalid argument count ${#} (2-3)" 1

	function get_launcher_setting()
	{
		local __setting_name="${1}" __value="${2:-2}"

		sed -n 's/^.*\"\('"${__setting_name}"'\)\"[[:blank:]]*:[[:blank:]]*\(.*\)/\'"${__value}"'\l/gp' "${__launcher_settings_file}" \
			| sed '{s/\r$//;s/^"\|"$//g}'
	}

	local __launcher_settings_file="${1}" __setting_name="${2}" __setting_value __test_setting_name
	if [[ ! -f "${__launcher_settings_file}" ]]; then
		handle_error "invalid \"${__launcher_settings_file}\" launcher settings file specified"
		return 1
	fi
	__test_setting_name=$(get_launcher_setting "${__setting_name}" 1)
	__setting_value=$(get_launcher_setting "${__setting_name}")
	if [[ ! -z "${3}" && ("${3}" =~ ${G_VARIABLE_REGEX}) ]]; then
		local -n setting_value_reference="${3}"
		setting_value_reference="${__setting_value}"
	else
		echo "${__setting_value}"
	fi
	[[ "${__test_setting_name}" == "${__setting_name}" ]]
}

# Set value of specified setting name in SWTOR game launcher settings file
function set_launcher_settings_file_value()
{
	(($# != 3)) && handle_error "invalid argument count ${#} (3)" 1

	local __launcher_settings_file="${1}" __setting_name="${2}" new_settings_value="${3}"
	if [[ ! -f "${__launcher_settings_file}" ]]; then
		handle_error "invalid \"${__launcher_settings_file}\" launcher settings file specified"
		return 1
	fi

	if		sed -i 's/\("'"${__setting_name}"'"[[:blank:]]*:[[:blank:]]*\).*$/\1"'"${new_settings_value}"'"/g' "${__launcher_settings_file}" \
		||  sed -i '$i, "'"${__setting_name}"'": "'"${new_settings_value}"'"' "${__launcher_settings_file}"
	then
		return 0
	fi
	handle_error "sed operation failed to insert new setting: \"${__setting_name}\":\"${new_settings_value}\" ; into launcher settings file: \"${__launcher_settings_file}\"" 1
}

# Change PatchMode from BitRunner (BR) to Non-Streaming Mode (SSN) - (note: use non-case specific paths to support NTFS)
function turn_off_bitrunner()
{
	(($# != 1)) && handle_error "invalid argument count ${#} (1)" 1

	local __launcher_settings_file="${1}"
	if [[ ! -f "${__launcher_settings_file}" ]]; then
		handle_error "invalid \"${__launcher_settings_file}\" launcher settings file specified"
		return 1
	fi
	# Turn off Bit Runner (BR) patchmode!
	local success=1
	if ! set_launcher_settings_file_value "${__launcher_settings_file}" "PatchingMode" "{ \"swtor\": \"SSN\" }"; then
		handle_error "failed to patch launcher settings file \"${__launcher_settings_file}\" to enable non-streaming (SSN) PatchMode"
		success=0
	fi
	if ! set_launcher_settings_file_value "${__launcher_settings_file}" "bitraider_disable" "true"; then
		handle_error "failed to patch launcher settings file \"${__launcher_settings_file}\" to disable BitRaider PatchMode"
		success=0
	fi
	((success)) && printf "Successfully disabled BitRaider PatchMode\n"
}

# Detect all BitRunner (BR) asset directories and purge these (note: use non-case specific paths to support NTFS)
function purge_bitrunner_assets()
{
	(($# != 1)) && handle_error "invalid argument count ${#} (1)" 1

	local __launcher_directory="${1}"
	local windows_directory unix_directory br_assets

	for unix_directory in "assets" "bitraider" "movies"; do
		windows_directory="$(find . -mindepth 1 -maxdepth 1 -type d -iname "${unix_directory}" -printf '%f\n')"
		windows_directory="${__launcher_directory}/${windows_directory}"
		[[ ! -d {windows_directory} ]] && continue

		br_assets="${br_assets}${br_assets:+ }${windows_directory}"
		if ! rm -rf "${windows_directory}"; then
			break
		fi
	done
	if (( $? != 0 )); then
		handle_error "Failed to remove directory \"${windows_directory}\" ; unable complete operation to fully enable non-streaming (SSN) PatchMode"
		return 1
	elif [[ -z "${br_assets}" ]]; then
		printf "No BitRaider (BR) asset directories detected - completed enabling non-streaming (SSN) PatchMode\n" "${br_assets}"
	else
		printf "Successfully removed BitRaider (BR) asset directories: \"%s\" ; completed enabling non-streaming (SSN) PatchMode\n" "${br_assets}"
	fi
	return 0
}

main()
{
	trap "trap_exit" ABRT INT QUIT KILL TERM

	local launcher_directory launcher_executable_path launcher_settings_file virtual_desktops
	find_wineprefix_directory

	export WINEDEBUG=-all

	# If running Virtual Desktop mode - force mouse warping/grab
	virtual_desktops=$( wine reg query 'HKEY_CURRENT_USER\Software\Wine\Explorer' /v 'Desktop' /s | awk '{ if ($0 ~ "Number of matches found:") { gsub("[^[:digit:]]+", "", $NF); printf("%s", $NF); exit } }' )
	if ((virtual_desktops)); then
		printf "%s\n" "Using a Wine Virtual Desktop - automatically fixing mouse grab..."
		wine reg add 'HKEY_CURRENT_USER\Software\Wine\DirectInput' /v 'MouseWarpOverride' /t 'REG_SZ' /d 'force' /f
		wine reg add 'HKEY_CURRENT_USER\Software\Wine\X11 Driver' /v 'GrabFullscreen' /t 'REG_SZ' /d 'Y' /f
	fi

	printf "%s\n" "Using winetricks to install required libraries..."
	# Install and set up components in WINEPREFIX (if they are not already installed).
	winetricks -q msvcp90=native d3dx9 vcrun2008 msls31 winhttp

	if ! find_launcher_executable_path "launcher_executable_path"; then
		handle_error "launcher executable \"${launcher_executable_path}\" is not a valid Windows executable file!" 1
	fi
	launcher_directory="$(dirname "${launcher_executable_path}")"
	launcher_executable="$(basename "${launcher_executable_path}")"
	if ! find_launcher_settings_file "${launcher_directory}" "launcher_settings_file"; then
		handle_error "failed to detect settings file: \"${launcher_settings_file}\"; in: \"${launcher_directory}\" - main game directory" 1
	fi
	if ! get_launcher_settings_file_value "${launcher_settings_file}" "PatchingMode" "setting_value"; then
		printf "%s\n%s\n%s\n" \
			"The launcher has never been run.  Running the launcher for the first time." \
			"1.  If the launcher fails:  This is good! Please re-run this script. It will turn off BitRaider the second time around." \
			"2.  If the launcher succeeds:  The first time, there is no need to run this script again.  Please run the installer directly next time!" >&2
	else
		if [[ "${setting_value}" == '{ "swtor": "SSN" }' ]]; then
			printf "%s\n" "Non-streaming (SSN) PatchMode is already enabled - no action required..."
		else
			turn_off_bitrunner "${launcher_settings_file}"
			purge_bitrunner_assets "${launcher_directory}"
		fi

		# Check if we have swtor_fix.exe, and download it if we don't.
		# This can be placed anywhere on the system, and must be run parallel to the game.
		[[ -f "swtor_fix.exe" ]] || wget -c -O "swtor_fix.exe" "G_GITHUB_SWTOR_FIX_URL"

		# Start swtor_fix in the background...
		wine swtor_fix.exe 60 &
		sleep 1
	fi

	# Start main game in main thread...
	pushd "${launcher_directory}" || handle_error "pushd failed, unable to move to directory: \"${launcher_directory}\"" 1
	wine start "${launcher_executable}"
	popd || handle_error "popd failed" 1

	# Then wait for background swtor_fix.exe process to finish...
	wait $!

	# Clean up after ourselves.
	cleanup
}

main