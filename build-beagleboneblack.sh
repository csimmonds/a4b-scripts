#!/bin/bash

DEVICE_DIR=device/beagleboard/beagleboneblack

if [ -z $ANDROID_BUILD_TOP ]; then
	echo "Please 'source build/envsetup.sh' and run 'lunch' first"
	exit
fi

if [ $TARGET_PRODUCT != "beagleboneblack" -a $TARGET_PRODUCT != "beagleboneblack_sd" ]; then
	echo "Please select product beagleboneblack or beagleboneblack_sd"
	exit
fi

if [ `javac -version |& cut -d " " -f 2 | cut -b 1-3` != "1.6" ]; then
        echo "Missing JDK or not version 1.6"
        exit
fi

echo "Building $TARGET_PRODUCT"

# Patch AOSP
if [ ! -e system/core/patched ]; then
	echo "Patching AOSP"
	cd system/core
	patch -p1 < ../../${DEVICE_DIR}/0001-Fix-CallStack-API.patch
	if [ $? != 0 ]; then echo "ERROR"; exit; fi
	echo "patched" > patched
	cd ../..
fi

echo "Building U-Boot"
cd $ANDROID_BUILD_TOP/u-boot
make CROSS_COMPILE=arm-eabi- am335x_evm_config
if [ $? != 0 ]; then echo "ERROR"; exit; fi
make CROSS_COMPILE=arm-eabi-
if [ $? != 0 ]; then echo "ERROR"; exit; fi

echo "Building kernel"
cd $ANDROID_BUILD_TOP/kernel

make ARCH=arm CROSS_COMPILE=arm-eabi- am335x_evm_android_defconfig
if [ $? != 0 ]; then echo "ERROR"; exit; fi
make -j4 ARCH=arm CROSS_COMPILE=arm-eabi- uImage
if [ $? != 0 ]; then echo "ERROR"; exit; fi
cd $ANDROID_BUILD_TOP
cp kernel/arch/arm/boot/zImage ${DEVICE_DIR}

echo "Building Android (first time)"

make -j8
if [ $? != 0 ]; then echo "ERROR"; exit; fi

echo "Building the SGX drivers"
cd $ANDROID_BUILD_TOP/hardware/ti/sgx
OUT_SAVED=$OUT
unset OUT
make TARGET_PRODUCT=beagleboneblack OMAPES=4.x ANDROID_ROOT_DIR=$ANDROID_BUILD_TOP W=1
if [ $? != 0 ]; then echo "ERROR"; exit; fi
make TARGET_PRODUCT=beagleboneblack OMAPES=4.x ANDROID_ROOT_DIR=$ANDROID_BUILD_TOP install
if [ $? != 0 ]; then echo "ERROR"; exit; fi
OUT=$OUT_SAVED

echo "Building Android (second time)"

cd $ANDROID_BUILD_TOP
make -j8
if [ $? != 0 ]; then echo "ERROR"; exit; fi

echo "SUCCESS! Everything built for $TARGET_PRODUCT"
