#!/bin/sh
#
# USB runtime powermanagement test for PCI xHCI controller
# Author: Mathias Nyman
#
# needs to be run with sudo or as root
#
# enables autosuspend for all xhci connected usb devices and xhci controller.
# check if devices and controller suspended, returns 0 on success, 1 on failure
#
# If succes, usb devices and xhci controller are left runtime suspended

set -e

FAIL=0

print_devinfo() {
    PREFIX=$1
    DEVPATH=$2
    if [ -f $DEVPATH/devnum ]; then
	DEVINFO="$BUSNUM-$(cat $DEVPATH/devpath) Device $(cat $DEVPATH/devnum)"

	if [ -f $DEVPATH/manufacturer ]; then
	    DEVINFO="$DEVINFO $(cat $DEVPATH/manufacturer)"
	fi
	if [ -f $DEVPATH/product ]; then
	    DEVINFO="$DEVINFO $(cat $DEVPATH/product)"
	fi
    else
	DEVINFO=$DEVPATH
    fi
    echo  "  $PREFIX\t $DEVINFO"
}


# Find the two (USB2 and USB3) buses that are controlled by xhci
for BUSPATH in /sys/bus/usb/devices/usb*; do
    if [ "$(cat $BUSPATH/product)" = "xHCI Host Controller" ]; then
	BUSNUM=$(cat $BUSPATH/busnum)
	echo "\nusb$BUSNUM bus controlled by xhci";
	echo "Enable autosuspend for bus$BUSNUM and its devices:"

	# for every device + the bus + (host) under that xhci bus
	# set HOSTPATH after all devies and both buses are set to auto
	for DEVPATH in /sys/bus/usb/devices/$BUSNUM* $BUSPATH $HOSTPATH; do
	    PM_CONTROL=$DEVPATH/power/control

	    # set to power/control to auto if it exists
	    if [ -f $PM_CONTROL ]; then
		echo auto > $PM_CONTROL
		print_devinfo "$(cat $PM_CONTROL)" $DEVPATH

		if [ "$(cat $PM_CONTROL)" != "auto" ]; then
		    FAIL=1
		fi
	    fi
	done  #for every device under that bus
	if [ $FAIL -eq 1 ]; then
	    echo "FAILED\t\t to set autosuspend to \"auto\" for some devices"
#	    exit $FAIL
	fi

	echo "\nGive 1 second time to suspend, check runtime status:"
	sleep 1

	# check that devices actually suspended
	for DEVPATH in /sys/bus/usb/devices/$BUSNUM* $BUSPATH; do
	    RT_STATUS=$DEVPATH/power/runtime_status
	    if [ -f $RT_STATUS ]; then
		print_devinfo "$(cat $RT_STATUS)" $DEVPATH
		if [ "$(cat $RT_STATUS)" != "suspended" ]; then
		    FAIL=1
		fi
	    fi
	done

	if [ $FAIL -eq 1 ]; then
	    echo "FAILED\t some devices are not suspended, remove them?"
#	    exit $FAIL
	fi

	# if hostpath is set both buses are suspended, suspend host.
	if [ -n "$HOSTPATH" ]; then
	    if [ $FAIL -eq 0 ]; then
		echo "Successfully suspended both xhci buses and their devices"
	    fi
	    # get controller D state, just to print it out
	    if [ -f $HOSTPATH/firmware_node/power_state ]; then
		D_STATE=$(cat $HOSTPATH/firmware_node/power_state)
	    fi

	    # is xhci host controller suspended?
	    if [ "$(cat $HOSTPATH/power/runtime_status)" = "suspended" ]; then
		echo "\nSUCCESS\t xHCI host at $HOSTPATH suspended, in $D_STATE state"
	    else
		echo "\nFAIL\t xHCI host at $HOSTPATH not suspended, in $D_STATE state"
		FAIL=1;
	    fi
	    #unset HOSTPATH
	else # only first bus suspended, set hostpath.
	    HOSTPATH=$(dirname $(readlink -f $BUSPATH))
	fi
    fi
done

exit $FAIL
