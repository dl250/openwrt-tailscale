#!/bin/bash
# this script is used to build tailscale apk package openwrt
# it is expected to be run in a docker container with openwrt 25.12 sdk
# it is designed for https://github.com/GuNanOvO/openwrt-tailscale project only
# and may not work properly in other environments
# author: GuNanOvO <gunanovo@gmail.com>
# repo: https://github.com/GuNanOvO/openwrt-tailscale
# date: 2026/2/26

set -e
cd /builder

# initialize feeds and install golang
./scripts/feeds update packages > /dev/null
./scripts/feeds install golang > /dev/null

mkdir -p /builder/package/lang
# ln -sf /builder/feeds/packages/lang/golang /builder/package/lang/golang

# remove original tailscale package
rm -rf /builder/package/tailscale
mkdir -p /builder/package/tailscale
# copy optimized tailscale package
# see https://github.com/GuNanOvO/openwrt-tailscale/tree/main/package/tailscale for details
cp -r /builder/tailscale/. /builder/package/tailscale/

# make defconfig to generate .config with default settings, which is required for go build
make defconfig > /dev/null 2>&1

# check go binary
[ -f /builder/go/bin/go ] || { echo "Error: Go binary missing"; exit 1; }

# use the pre-prepared go binary 
# avoid dependency resolution and installation during build
# which can be time-consuming and may fail due to network issues
# mkdir for go binary and link it to staging dir for go build
mkdir -p /builder/staging_dir/hostpkg/lib/go-1.26/bin
ln -sf /builder/go/bin/go /builder/staging_dir/hostpkg/lib/go-1.26/bin/go
ln -sf /builder/go/bin/gofmt /builder/staging_dir/hostpkg/lib/go-1.26/bin/gofmt
if [ -d /builder/staging_dir/hostpkg/lib/go-cross/bin ]; then
    ln -sf /builder/go/bin/go /builder/staging_dir/hostpkg/lib/go-cross/bin/go
fi

# 不要注释掉缓存！只需要修正软链接到正确的“深度路径”：
# 25.12 SDK 期望的路径是 lib/go-x.xx/bin

echo "Using $(/builder/go/bin/go version)"

# build tailscale package
make package/tailscale/compile V=s

# check package build result
if PKG=$(find bin/packages -name "tailscale_*.apk" -type f 2>/dev/null | head -1); then
    PKG=$(dirname "$PKG")
    echo "Build Success: APK Package generated"
    ls -lh "$PKG"
else
    echo "Error: No build product found"
    echo "Build Failed"
    exit 1
fi

# change to package directory for index generation and signing
cd $PKG

# sign the apk package
/builder/staging_dir/host/bin/abuild-sign -k /builder/keys/key-build.rsa *.apk

# generate index for apk repository
/builder/staging_dir/host/bin/apk index -o packages.adb *.apk

# sign the index file
/builder/staging_dir/host/bin/abuild-sign -k /builder/keys/key-build.rsa packages.adb

# check if the index file and signature file is generated
if [ -f packages.adb ] && [ -f packages.adb.asc ]; then
    echo "Index Generation and Signing Success: packages.adb and packages.adb.asc generated"
    ls -lh "$PKG"
else
    echo "Error: Package signing failed, packages.adb or packages.adb.asc not found or empty"
    exit 1
fi