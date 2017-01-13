#!/bin/bash

# qemu-img create -f qcow2 mac_hdd.img 64G
# echo 1 > /sys/module/kvm/parameters/ignore_msrs
#
# Type the following after boot,
# -v "KernelBooter_kexts"="Yes" "CsrActiveConfig"="103"
#
# printf 'DE:AD:BE:EF:%02X:%02X\n' $((RANDOM%256)) $((RANDOM%256))
#
# no_floppy = 1 is required for OS X guests!
#
# Commit 473a49460db0a90bfda046b8f3662b49f94098eb (qemu) makes "no_floppy = 0"
# for pc-q35-2.3 hardware, and OS X doesn't like this (it hangs at "Waiting for
# DSMOS" message). Hence, we switch to pc-q35-2.4 hardware.
#
# Network device "-device e1000-82545em" can be replaced with "-device vmxnet3"
# for possibly better performance.

set -ex

sudo /bin/bash -x <<'EOF'
ip tuntap show | grep -q tap0
addtap="$?"

set -e

modprobe vfio-pci ids=8086:9cb1
modprobe qxl

echo "8086 9cb1" > /sys/bus/pci/drivers/vfio-pci/new_id
echo 0000:00:14.0 > /sys/bus/pci/devices/0000\:00\:14.0/driver/unbind
echo 0000:00:14.0 > /sys/bus/pci/drivers/vfio-pci/bind

chgrp users /dev/vfio/2
chmod 660 /dev/vfio/2

if [[ $addtap != "0" ]]
then
  ip tuntap add dev tap0 mode tap group users
  ip link set tap0 up promisc on
  brctl addif virbr0 tap0
fi
EOF

qemu-system-x86_64 -enable-kvm -m 6144 -cpu Penryn,kvm=off,vendor=GenuineIntel \
  -machine q35 \
  -smp 4,cores=2 \
  -device isa-applesmc,osk="ourhardworkbythesewordsguardedpleasedontsteal(c)AppleComputerInc" \
  -kernel ./enoch_rev2839_boot \
  -smbios type=2 \
  -device ide-drive,bus=ide.0,drive=MacHDD \
  -drive id=MacHDD,if=none,file=./mac_hdd.img \
  -netdev tap,id=net0,ifname=tap0,script=no,downscript=no \
  -device e1000-82545em,netdev=net0,id=net0,mac=52:54:00:c9:18:27 \
  -monitor stdio \
  -usbdevice tablet -device usb-kbd \
  -device vfio-pci,host=00:14.0 \
  -vga qxl \
  -device virtio-serial-pci \
  -device virtserialport,chardev=spicechannel0,name=com.redhat.spice.0 \
  -chardev spicevmc,id=spicechannel0,name=vdagent \
  -spice unix,addr=/tmp/vm_spice.socket,disable-ticketing

sudo /bin/bash -ex <<'EOF'
echo 0000:00:14.0 > /sys/bus/pci/devices/0000\:00\:14.0/driver/unbind
echo 0000:00:14.0 > /sys/bus/pci/drivers/xhci_hcd/bind
EOF
