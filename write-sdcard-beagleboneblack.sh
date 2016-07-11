#!/bin/bash

DEVICE_DIR=device/beagleboard/beagleboneblack

function version_gt() { test "$(echo "$@" | tr " " "\n" | sort -V | head -n 1)" != "$1"; }

# Format an SD card for Android on BeagelBone Black

if [ $# -ne 1 ]; then
        echo "Usage: $0 [drive]"
        echo "       drive is 'sdb', 'mmcblk0'"
        exit 1
fi

DRIVE=$1

if [ x$TARGET_PRODUCT != "xbeagleboneblack" -a x$TARGET_PRODUCT != "xbeagleboneblack_sd" ]; then
	echo "Please run 'lunch' and select beagleboneblack or beagleboneblack_sd"
	exit
fi

# Check the drive exists in /sys/block
if [ ! -e /sys/block/${DRIVE}/size ]; then
	echo "Drive does not exist"
	exit 1
fi

# Check it is a flash drive (size < 32MiB)
NUM_SECTORS=`cat /sys/block/${DRIVE}/size`
if [ $NUM_SECTORS -eq 0 -o $NUM_SECTORS -gt 16000000 ]; then
	echo "Does not look like an SD card, bailing out"
	exit 1
fi

# Unmount any partitions that have been automounted
if [ $DRIVE == "mmcblk0" ]; then
	sudo umount /dev/${DRIVE}*
	BOOT_PART=/dev/${DRIVE}p1
	SYSTEM_PART=/dev/${DRIVE}p2
	USER_PART=/dev/${DRIVE}p3
	CACHE_PART=/dev/${DRIVE}p4
else
	sudo umount /dev/${DRIVE}[1-9]
	BOOT_PART=/dev/${DRIVE}1
	SYSTEM_PART=/dev/${DRIVE}2
	USER_PART=/dev/${DRIVE}3
	CACHE_PART=/dev/${DRIVE}4
fi

# Overwite existing partiton table with zeros
sudo dd if=/dev/zero of=/dev/${DRIVE} bs=1M count=10
if [ $? -ne 0 ]; then echo "Error: dd"; exit 1; fi

# Create 4 primary partitons on the sd card
#  1: boot:   FAT32, 64 MiB, boot flag
#  2: system: Linux, 512 MiB
#  3: data:   Linux, 3072 MiB
#  4: cache:  Linux, 256 MiB

# Note that the formatting of parameters changed slightly v2.26
SFDISK_VERSION=`sfdisk --version | awk '{print $4}'`
if version_gt $SFDISK_VERSION "2.26"; then
     echo "sfdisk uses new syntax"
	sudo sfdisk /dev/${DRIVE} << EOF
,64M,0x0c,*
,512M,,,
,3072M,,,
,256M,,,
EOF
else
	sudo sfdisk --unit M /dev/${DRIVE} << EOF
,64,0x0c,*
,512,,,
,3072,,,
,256,,,
EOF
fi
if [ $? -ne 0 ]; then echo "Error: sdfisk"; exit 1; fi

# Format p1 with FAT32
sudo mkfs.vfat -F 16 -n boot ${BOOT_PART}
if [ $? -ne 0 ]; then echo "Error: mkfs.vfat"; exit 1; fi


# Copy boot files
echo "Mounting $BOOT_PART"
sudo mount $BOOT_PART /mnt
if [ $? != 0 ]; then echo "ERROR"; exit; fi

mkimage -A arm -O linux -T ramdisk -d ${ANDROID_PRODUCT_OUT}/ramdisk.img uRamdisk
if [ $? != 0 ]; then echo "ERROR"; exit; fi
sudo cp u-boot/MLO /mnt
if [ $? != 0 ]; then echo "ERROR"; exit; fi
sudo cp u-boot/u-boot.img /mnt
if [ $? != 0 ]; then echo "ERROR"; exit; fi
sudo cp uRamdisk /mnt
if [ $? != 0 ]; then echo "ERROR"; exit; fi
sudo cp ${DEVICE_DIR}/uEnv.txt /mnt
if [ $? != 0 ]; then echo "ERROR"; exit; fi
sudo cp kernel/arch/arm/boot/uImage /mnt
if [ $? != 0 ]; then echo "ERROR"; exit; fi
sudo umount /mnt

# Copy disk images
echo "Writing system"
sudo dd if=${ANDROID_PRODUCT_OUT}/system.img of=$SYSTEM_PART bs=1M
if [ $? != 0 ]; then echo "ERROR"; exit; fi
sudo e2label $SYSTEM_PART system
echo "Writing userdata"
sudo dd if=${ANDROID_PRODUCT_OUT}/userdata.img of=$USER_PART bs=1M
if [ $? != 0 ]; then echo "ERROR"; exit; fi
sudo e2label $USER_PART userdata
echo "Writing cache"
sudo dd if=${ANDROID_PRODUCT_OUT}/cache.img of=$CACHE_PART bs=1M
if [ $? != 0 ]; then echo "ERROR"; exit; fi
sudo e2label $CACHE_PART cache

echo "SUCCESS! SD card written with Android 4.4.4_r2. Enjoy"

exit 0
