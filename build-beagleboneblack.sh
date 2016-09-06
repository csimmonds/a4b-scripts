#!/bin/bash

DEVICE_DIR=device/beagleboard/beagleboneblack

# The number of CPU cores to use for Android compilation. Default is
# all of them, but you can override by setting CORES
if [ -z $CORES ]; then
	CORES=$(getconf _NPROCESSORS_ONLN)
fi

if [ -z $ANDROID_BUILD_TOP ]; then
	echo "Please 'source build/envsetup.sh' and run 'lunch' first"
	exit
fi

if [ $TARGET_PRODUCT != "beagleboneblack" -a $TARGET_PRODUCT != "beagleboneblack_sd" ]; then
	echo "Please select product beagleboneblack or beagleboneblack_sd"
	exit
fi

if [ `javac -version |& cut -d " " -f 2 | cut -b 1-3` != "1.7" ]; then
        echo "Missing JDK or not version 1.7"
        exit
fi

echo "Building $TARGET_PRODUCT using $CORES cpu cores"
echo ""
echo "Building kernel"
cd $ANDROID_BUILD_TOP/ti-kernel
if [ $? != 0 ]; then echo "ERROR"; exit; fi

if [ ! -d patches/a4b ]; then
	mkdir patches/a4b
	cp $ANDROID_BUILD_TOP/$DEVICE_DIR/ti-kernel-patches/config-android-4.1 patches/defconfig 
#	if [ $? != 0 ]; then echo "ERROR"; exit; fi
#	cp  $ANDROID_BUILD_TOP/$DEVICE_DIR/ti-kernel-patches/0001-Add-reboot-reason-driver-for-am33xx.patch patches/a4b
#	if [ $? != 0 ]; then echo "ERROR"; exit; fi
#	patch -p1 < $ANDROID_BUILD_TOP/$DEVICE_DIR/ti-kernel-patches/0001-Add-a4b-patch.patch
#	if [ $? != 0 ]; then echo "ERROR"; exit; fi
fi

AUTO_BUILD=1 ./build_kernel.sh
if [ $? != 0 ]; then echo "ERROR"; exit; fi

# Append the dtb to zImage because the Android build doesn't know about dtbs
cd KERNEL
cat arch/arm/boot/zImage arch/arm/boot/dts/am335x-boneblack-emmc-overlay.dtb > zImage-dtb
if [ $? != 0 ]; then echo "ERROR"; exit; fi

cp zImage-dtb $ANDROID_BUILD_TOP/$DEVICE_DIR
if [ $? != 0 ]; then echo "ERROR"; exit; fi

# Grab all the kernel modules
mkdir $ANDROID_BUILD_TOP/$DEVICE_DIR/modules
MODULES=`find -name "*.ko"`
for f in $MODULES; do
	cp $f $ANDROID_BUILD_TOP/$DEVICE_DIR/modules/`basename $f`
	if [ $? != 0 ]; then echo "ERROR"; exit; fi
done

echo "Building device tree overlays"
cd $ANDROID_BUILD_TOP/bb.org-overlays
make DTC=../ti-kernel/KERNEL/scripts/dtc/dtc
if [ $? != 0 ]; then echo "ERROR"; exit; fi
mkdir $ANDROID_BUILD_TOP/$DEVICE_DIR/dtbo
cp src/arm/*.dtbo $ANDROID_BUILD_TOP/$DEVICE_DIR/dtbo
if [ $? != 0 ]; then echo "ERROR"; exit; fi

echo "Building U-Boot"
cd $ANDROID_BUILD_TOP/u-boot
# The Android prebuilt gcc fails to build U-Boot, so use the Linaro gcc which
# was installed to build the ti-kernel
. ../ti-kernel/.CC
make CROSS_COMPILE=$CC am335x_evm_config
if [ $? != 0 ]; then echo "ERROR"; exit; fi
make CROSS_COMPILE=$CC
if [ $? != 0 ]; then echo "ERROR"; exit; fi
cd $ANDROID_BUILD_TOP

echo "Building Android"

make -j${CORES}
if [ $? != 0 ]; then echo "ERROR"; exit; fi

echo "SUCCESS! Everything built for $TARGET_PRODUCT"
