#!/bin/sh
# Script (purge-wrangler.sh), by mac_editor @ egpu.io (mayankk2308@gmail.com)
# Version 2.0.0
script_ver="2.0.0"

# --------------- ENVIRONMENT SETUP ---------------

# operation to perform ["" "patch" "uninstall" "recover" "check-patch" "version" "help"]
operation="$1"

# only for devs who know what they're doing ["" "-f" "-nc"]
advanced_operation="$2"

# Avoid clearing screen
if [[ "$advanced_operation" != "-nc" ]]
then
  clear
fi
echo
echo "---------- PURGE-WRANGLER ($script_ver) ----------"
echo

# Kext paths
ext_path="/System/Library/Extensions/"
agc_path="$ext_path"AppleGraphicsControl.kext
sub_agw_path="/Contents/PlugIns/AppleGPUWrangler.kext/Contents/MacOS/AppleGPUWrangler"
agw_bin="$agc_path$sub_agw_path"

# Backup paths
support_dir="/Library/Application Support/Purge-Wrangler/"
backup_kext_dir="$support_dir"Kexts/
backup_agc="$backup_kext_dir"AppleGraphicsControl.kext
backup_agw_bin="$backup_agc$sub_agw_path"
manifest="$support_dir"manifest.wglr
scratch_file="$support_dir"AppleGPUWrangler.p
patch_status=""

# IOThunderboltSwitchType reference
iotbswitchtype_ref="494F5468756E646572626F6C74537769746368547970653"
sys_iotbswitchtype=""

# System information
macos_ver=`sw_vers -productVersion`
macos_build=`sw_vers -buildVersion`

# Script help
usage()
{
  echo "
  Usage:

    ./purge-wrangler.sh [params] [advanced-params]

    Basics:

      No arguments: Apply patch.

      patch: Apply patch. Useful for providing advanced options.

      uninstall: Repatch kext to default.

      recover: Recover system from backup.

      check-patch: Check if patch has been applied.

      version: See current script version.

      help: See script help.

    Advanced Options:

      -f: Force override checks and manifest.

      -nc: Avoid clear screen on invocation."
}

# --------------- SYSTEM CHECKS ---------------

# Check superuser access
check_sudo()
{
  if [[ "$(id -u)" != 0 ]]
  then
    echo "This script requires superuser access. Please run with 'sudo'.\n"
    exit
  fi
}

# Check system integrity protection status
check_sys_integrity_protection()
{
  if [[ `csrutil status | grep -i enabled` ]]
  then
    if [[ ! `csrutil status | grep -i kext | grep -i disabled` ]]
    then
      echo "
      System Integrity Protection needs to be disabled before proceeding.

      Boot into recovery, launch Terminal and execute: 'csrutil disable'\n"
      exit
    fi
  fi
}

# Check version of macOS High Sierra
check_macos_version()
{
  if [[ "$macos_ver" == "10.13" ||  "$macos_ver" == "10.13.1" || "$macos_ver" == "10.13.2" || "$macos_ver" == "10.13.3" ]]
  then
    echo "
    This version of macOS does not require the patch.\n"
    exit
  fi
}

# Check thunderbolt version/availability
# Credit: learex @ github.com / fr34k @ egpu.io
check_sys_iotbswitchtype()
{
  tb="$(system_profiler SPThunderboltDataType | grep Speed)"
  if [[ "$tb[@]" =~ "20" ]]
  then
    sys_iotbswitchtype="$iotbswitchtype_ref"2
  elif [[ "$tb[@]" =~ "10" ]]
  then
    sys_iotbswitchtype="$iotbswitchtype_ref"1
  else
    echo "Unsupported/Invalid version of thunderbolt or none provided."
    exit
  fi
}

# Patch check
check_patch()
{
  if [[ `hexdump -ve '1/1 "%.2X"' "$agw_bin" | grep "$sys_iotbswitchtype"` ]]
  then
    patch_status=1
  else
    patch_status=0
  fi
}

# Check if older install exists
check_legacy_script_install()
{
  old_install_file="$support_dir"AppleGraphicsControl.kext
  if [[ -d "$old_install_file" ]]
  then
    echo "\nInstallation from v1.x.x of the script detected.\n"
    if [[ "$patch_status" == 0 ]]
    then
      echo "Safely removing older installation...\n"
      rm -r "$support_dir"
      echo "Re-running script...\n"
      sleep 3
      "$0" "$operation"
    else
      echo "
      Please use the recover command on the older version of

      the script before proceeding.\n"
    fi
    exit
  fi
}

# Hard checks
check_sudo
check_sys_integrity_protection
check_macos_version
check_sys_iotbswitchtype
check_patch
check_legacy_script_install

# --------------- OS MANAGEMENT ---------------

# Reboot sequence/message
prompt_reboot()
{
  echo "System ready. Restart now to apply changes."
}

# Rebuild kernel cache
invoke_kext_caching()
{
  echo "Rebuilding kext cache...\n"
  touch "$ext_path"
  kextcache -q -update-volume /
}

# Repair kext and binary permissions
repair_permissions()
{
  echo "Repairing permissions...\n"
  chmod 700 "$agw_bin"
  chown -R root:wheel "$agc_path"
  invoke_kext_caching
}

# --------------- BACKUP SYSTEM ---------------

# Write manifest file
# Line 1: Unpatched Kext SHA -- Kext in Backup directory
# Line 2: Patched Kext (in /S/L/E) SHA -- Kext in original location
# Line 3: macOS Version
# Line 4: macOS Build No.
write_manifest()
{
  override="$1"
  if [[ "$override" != "-f" ]]
  then
    unpatched_kext_sha=`shasum -a 512 -b "$backup_agw_bin" | awk '{ print $1 }'`
    patched_kext_sha=`shasum -a 512 -b "$agw_bin" | awk '{ print $1 }'`
    echo "$unpatched_kext_sha\n$patched_kext_sha\n$macos_ver\n$macos_build" > "$manifest"
  fi
}

# Primary procedure
execute_backup()
{
  mkdir -p "$backup_kext_dir"
  rsync -r "$agc_path" "$backup_kext_dir"
}

# Backup procedure
backup_system()
{
  echo "Backing up...\n"
  if [[ -s "$backup_agc" && -s "$manifest" ]]
  then
    manifest_macos_ver=`sed "3q;d" "$manifest"`
    manifest_macos_build=`sed "4q;d" "$manifest"`
    if [[ "$manifest_macos_ver" == "$macos_ver" && "$manifest_macos_build" == "$macos_build" ]]
    then
      echo "Backup already exists.\n"
    else
      echo "Different build/version of macOS detected. Updating backup..."
      rm -r "$backup_agc"
      execute_backup
    fi
  else
    execute_backup
    echo "Backup complete.\n"
  fi
}

# --------------- PATCHING SYSTEM ---------------

# Primary patching mechanism
generic_patcher()
{
  offending_hex="$1"
  patched_hex="$2"
  hexdump -ve '1/1 "%.2X"' "$agw_bin" |
  sed "s/$offending_hex/$patched_hex/g" |
  xxd -r -p > "$scratch_file"
  rm "$agw_bin"
  mv "$scratch_file" "$agw_bin"
  repair_permissions
}

# In-place re-patcher
uninstall()
{
  override="$1"
  if [[ -d "$support_dir" || "$override" == "-f" ]]
  then
    echo "Uninstalling...\n"
    generic_patcher "$sys_iotbswitchtype" "$iotbswitchtype_ref"3
    echo "Uninstallation Complete.\n"
    prompt_reboot
  else
    echo "No installation found. No action taken."
    exit
  fi
}

# Patch TB3 block
apply_patch()
{
  echo "Patching...\n"
  generic_patcher "$iotbswitchtype_ref"3 "$sys_iotbswitchtype"
  echo "Patch Complete.\n"
  prompt_reboot
}

# --------------- RECOVERY SYSTEM ---------------

# Recovery procedure
start_recovery()
{
  if [[ -s "$backup_agc" ]]
  then
    echo "Recovering...\n"
    rm -r "$agc_path"
    rsync -r "$backup_kext_dir"* "$ext_path"
    rm -r "$support_dir"
    repair_permissions
    echo "Recovery complete.\n"
    prompt_reboot
  else
    echo "Could not find valid backup. Recovery failed."
  fi
}

# --------------- INPUT MANAGER ---------------

# Option handlers
if [[ "$operation" == "" || "$operation" == "patch" ]]
then
  backup_system
  apply_patch
  write_manifest ""
elif [[ "$operation" == "uninstall" ]]
then
  uninstall "$2"
  write_manifest "$2"
elif [[ "$operation" == "recover" ]]
then
  start_recovery
elif [[ "$operation" == "help" ]]
then
  printf '\e[8;31;80t'
  usage
elif [[ "$operation" == "check-patch" ]]
then
  if [[ "$patch_status" == 0 ]]
  then
    echo "No system modifications detected."
  else
    echo "System has been patched."
  fi
elif [[ "$operation" == "version" ]]
then
  echo "Version: $script_ver"
else
  echo "Invalid option. Type sudo ./purge-wrangler.sh help for more information."
fi

echo
