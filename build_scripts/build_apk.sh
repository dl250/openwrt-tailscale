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
# if PKG=$(find bin/packages -name "tailscale_*.apk" -type f | head -1); then
#     echo "pkg: $PKG"
#     PKG_DIR=$(cd "$(dirname "$PKG")" && pwd)
#     echo "pkg dir: $PKG_DIR"
#     echo "Build Success: APK Package generated"
#     ls -lh "$PKG_DIR"
# else
#     echo "Error: No build product found"
#     echo "Build Failed"
#     exit 1
# fi
# 自动定位 APK 目录 (更健壮的 find)
PKG_PATH=$(find bin/packages -name "tailscale*.apk" | head -n 1)
[ -z "$PKG_PATH" ] && { echo "Error: No APK found"; exit 1; }

PKG_DIR=$(dirname "$(realpath "$PKG_PATH")")
echo "Found packages in: $PKG_DIR"

# change to package directory for index generation and signing
cd $PKG_DIR

# sign the apk package
# 假设你的私钥是 key-build，包名是 my-pkg.apk
/builder/staging_dir/host/bin/apk adbsign --allow-untrusted --sign-key /builder/keys/key-build.rsa.priv *.apk

# generate index for apk repository
/builder/staging_dir/host/bin/apk index --allow-untrusted -o packages.adb *.apk

# sign the index file
/builder/staging_dir/host/bin/apk adbsign --allow-untrusted --sign-key /builder/keys/key-build.rsa.priv packages.adb

# check if the index file and signature file is generated
if [ -f packages.adb ] && [ -f packages.adb.asc ]; then
    echo "Index Generation and Signing Success: packages.adb and packages.adb.asc generated"
    ls -lh
else
    echo "Error: Package signing failed, packages.adb or packages.adb.asc not found or empty"
    exit 1
fi