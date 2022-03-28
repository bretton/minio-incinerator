#!/usr/bin/env bash

if [ -z "$BASH_VERSION" ]; then
  >&2 echo "This needs to run in bash"
  exit 1
fi

DATE=$(date "+%Y-%m-%d")

usage()
{
  echo "This packages a CURRENTLY RUNNING VirtualBox environment into a re-usable VirtualBox machine or Vagrant box."
  echo ""
  echo "Usage: mininc export [-hv]"
}

OPTIND=1
while getopts "hv" _o ; do
  case "$_o" in
  h)
    usage
    exit 0
    ;;
  v)
    # shellcheck disable=SC2034
    VERBOSE="YES"
    ;;
  *)
# wasn't running without this commented out
   usage
   exit 1
    ;;
  esac
done

shift "$((OPTIND-1))"

if [ $# -ne 0 ]; then
  usage
  exit 1
fi

set -eE
trap 'echo error: $STEP failed' ERR
# shellcheck disable=SC1091
source "${INCLUDE_DIR}/common.sh"
common_init_vars

step "Load potman config"
read_potman_config potman.ini
# shellcheck disable=SC2154
FREEBSD_VERSION="${config_freebsd_version}"
FBSD="${FREEBSD_VERSION}"
FBSD_TAG=${FREEBSD_VERSION//./_}

step "Check tooling"
ansible --version >/dev/null
git --version >/dev/null
vagrant --version >/dev/null
vboxheadless --version >/dev/null

step "Make sure vagrant plugins are installed"
(vagrant plugin list | grep "vagrant-disksize" >/dev/null)\
  || vagrant plugin install vagrant-disksize

step "Checking if machines to export"
# read the modified output of VBoxManage into an array, one item per line
readarray -t mymachines <<< "$(VBoxManage list runningvms |sed -e 's|" {|,|g' -e 's|"||g' -e 's|}||g')"

# check the length of the array
len="${#mymachines[@]}"

# doing it this rudimentory way because not sure how else to do this
case "${len}" in
  0)
    echo "There are no machines to export. Exiting."
    exit 1
    ;;
  1)
    # shellcheck disable=SC2162 disable=SC2086
    read serverone_name <<< "$(echo ${mymachines[0]} | awk -F, '{print $1}')"
    # shellcheck disable=SC2162 disable=SC2086
    read serverone_friendly_name <<< "$(echo ${serverone_name} | awk -F_ '{print $2}')"
    # shellcheck disable=SC2034 disable=SC2162 disable=SC2086
    read serverone_uuid <<< "$(echo ${mymachines[0]} | awk -F, '{print $2}')"
    ;;
  2)
    # shellcheck disable=SC2162 disable=SC2086
    read serverone_name <<< "$(echo ${mymachines[0]} | awk -F, '{print $1}')"
    # shellcheck disable=SC2162 disable=SC2086
    read serverone_friendly_name <<< "$(echo ${serverone_name} | awk -F_ '{print $2}')"
    # shellcheck disable=SC2034 disable=SC2162 disable=SC2086
    read serverone_uuid <<< "$(echo ${mymachines[0]} | awk -F, '{print $2}')"
    # shellcheck disable=SC2162 disable=SC2086
    read servertwo_name <<< "$(echo ${mymachines[1]} | awk -F, '{print $1}')"
    # shellcheck disable=SC2162 disable=SC2086
    read servertwo_friendly_name <<< "$(echo ${servertwo_name} | awk -F_ '{print $2}')"
    # shellcheck disable=SC2034 disable=SC2162 disable=SC2086
    read servertwo_uuid <<< "$(echo ${mymachines[1]} | awk -F, '{print $2}')"
    ;;
  3)
    # shellcheck disable=SC2162 disable=SC2086
    read serverone_name <<< "$(echo ${mymachines[0]} | awk -F, '{print $1}')"
    # shellcheck disable=SC2162 disable=SC2086
    read serverone_friendly_name <<< "$(echo ${serverone_name} | awk -F_ '{print $2}')"
    # shellcheck disable=SC2034 disable=SC2162 disable=SC2086
    read serverone_uuid <<< "$(echo ${mymachines[0]} | awk -F, '{print $2}')"
    # shellcheck disable=SC2162 disable=SC2086
    read servertwo_name <<< "$(echo ${mymachines[1]} | awk -F, '{print $1}')"
    # shellcheck disable=SC2162 disable=SC2086
    read servertwo_friendly_name <<< "$(echo ${servertwo_name} | awk -F_ '{print $2}')"
    # shellcheck disable=SC2034 disable=SC2162 disable=SC2086
    read servertwo_uuid <<< "$(echo ${mymachines[1]} | awk -F, '{print $2}')"
    # shellcheck disable=SC2162 disable=SC2086
    read serverthree_name <<< "$(echo ${mymachines[2]} | awk -F, '{print $1}')"
    # shellcheck disable=SC2162 disable=SC2086
    read serverthree_friendly_name <<< "$(echo ${serverthree_name} | awk -F_ '{print $2}')"
    # shellcheck disable=SC2034 disable=SC2162 disable=SC2086
    read serverthree_uuid <<< "$(echo ${mymachines[2]} | awk -F, '{print $2}')"
    ;;
  4)
    # shellcheck disable=SC2162 disable=SC2086
    read serverone_name <<< "$(echo ${mymachines[0]} | awk -F, '{print $1}')"
    # shellcheck disable=SC2162 disable=SC2086
    read serverone_friendly_name <<< "$(echo ${serverone_name} | awk -F_ '{print $2}')"
    # shellcheck disable=SC2034 disable=SC2162 disable=SC2086
    read serverone_uuid <<< "$(echo ${mymachines[0]} | awk -F, '{print $2}')"
    # shellcheck disable=SC2162 disable=SC2086
    read servertwo_name <<< "$(echo ${mymachines[1]} | awk -F, '{print $1}')"
    # shellcheck disable=SC2162 disable=SC2086
    read servertwo_friendly_name <<< "$(echo ${servertwo_name} | awk -F_ '{print $2}')"
    # shellcheck disable=SC2034 disable=SC2162 disable=SC2086
    read servertwo_uuid <<< "$(echo ${mymachines[1]} | awk -F, '{print $2}')"
    # shellcheck disable=SC2162 disable=SC2086
    read serverthree_name <<< "$(echo ${mymachines[2]} | awk -F, '{print $1}')"
    # shellcheck disable=SC2162 disable=SC2086
    read serverthree_friendly_name <<< "$(echo ${serverthree_name} | awk -F_ '{print $2}')"
    # shellcheck disable=SC2034 disable=SC2162 disable=SC2086
    read serverthree_uuid <<< "$(echo ${mymachines[2]} | awk -F, '{print $2}')"
    # shellcheck disable=SC2162 disable=SC2086
    read serverfour_name <<< "$(echo ${mymachines[3]} | awk -F, '{print $1}')"
    # shellcheck disable=SC2162 disable=SC2086
    read serverfour_friendly_name <<< "$(echo ${serverfour_name} | awk -F_ '{print $2}')"
    # shellcheck disable=SC2034 disable=SC2162 disable=SC2086
    read serverfour_uuid <<< "$(echo ${mymachines[3]} | awk -F, '{print $2}')"
    ;;
   *)
    echo "Error, mininc is not configured for export of ${len} virtual machines"
    exit 1
    ;;
esac

step "Check if box files exist"
# TODO: check if output dir, currently /tmp, has any *.box files and remove them
# script will give error if existing .box files, no error handling for this yet

step "Package machines"
if [ -n "${serverone_name}" ]; then
    vagrant package --base "${serverone_name}" --output /tmp/"${serverone_friendly_name}".box
fi
if [ -n "${servertwo_name}" ]; then
    vagrant package --base "${servertwo_name}" --output /tmp/"${servertwo_friendly_name}".box
fi
if [ -n "${serverthree_name}" ]; then
    vagrant package --base "${serverthree_name}" --output /tmp/"${serverthree_friendly_name}".box
fi
if [ -n "${serverfour_name}" ]; then
    vagrant package --base "${serverfour_name}" --output /tmp/"${serverfour_friendly_name}".box
fi

# if DEBUG is enabled, dump the variables
if [ "$DEBUG" -eq 1 ]; then
    printf "\n\n"
    echo "Dump of variables"
    echo "================="
    echo "FBSD: $FBSD"
    echo "FBSD_TAG: $FBSD_TAG"
    echo "Version: $VERSION with suffix: $VERSION_SUFFIX"
    printf "\n\n"
    echo "Date: $DATE"
    printf "\n\n"
fi

step "Success"

echo "Don't forget to start VMs again with 'mininc startvms'!"
