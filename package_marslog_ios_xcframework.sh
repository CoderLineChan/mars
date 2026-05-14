#!/bin/bash

if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
cd "$script_dir"

echo "=== 生成 iOS arm64 + arm64/x86_64-simulator xcframework ==="
echo "脚本目录: $script_dir"

framework_name="mars"
default_device_framework="mars/cmake_build/MarsLog_iOS/iphoneos/Darwin.out/$framework_name.framework"
default_simulator_arm64_framework="mars/cmake_build/MarsLog_iOS/iphonesimulator-arm64/Darwin.out/$framework_name.framework"
default_simulator_x86_64_framework="mars/cmake_build/MarsLog_iOS/iphonesimulator-x86_64/Darwin.out/$framework_name.framework"
default_simulator_framework="mars/cmake_build/MarsLog_iOS/iphonesimulator-universal/Darwin.out/$framework_name.framework"

usage() {
    echo "用法:"
    echo "  $0"
    echo "  $0 <真机.framework> <模拟器.framework> [输出目录]"
    echo ""
    echo "示例:"
    echo "  $0"
    echo "  $0 mars/cmake_build/iOS/Darwin.out/mars.framework mars/cmake_build/iOSSimulator/Darwin.out/mars.framework"
    echo "  $0 ./device/mars.framework ./simulator/mars.framework ./MarsLog_iOS/Frameworks"
}

find_first_framework() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        return 0
    fi
    find "$dir" -maxdepth 2 -name "*.framework" -type d | head -1
}

find_first_existing_framework() {
    local framework_path
    for framework_path in "$@"; do
        if [ -d "$framework_path" ]; then
            echo "$framework_path"
            return 0
        fi
    done
}

copy_header() {
    local src="$1"
    local dst_subdir="$2"
    local headers_dir="$3"

    mkdir -p "$headers_dir/$dst_subdir"
    cp "$src" "$headers_dir/$dst_subdir/$(basename "$src")"
}

write_framework_info_plist() {
    local framework_path="$1"
    local platform="$2"
    local sdk_name="$3"

    cat > "$framework_path/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$framework_name</string>
    <key>CFBundleIdentifier</key>
    <string>com.tencent.mars.$framework_name</string>
    <key>CFBundleName</key>
    <string>$framework_name</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>$platform</string>
    </array>
    <key>DTPlatformName</key>
    <string>$sdk_name</string>
</dict>
</plist>
EOF
}

copy_arm64_binary() {
    local src="$1"
    local dst="$2"

    if lipo -info "$src" 2>&1 | grep -q "Non-fat file"; then
        lipo "$src" -verify_arch arm64
        cp "$src" "$dst"
    else
        lipo "$src" -thin arm64 -output "$dst"
    fi
}

copy_binary() {
    local src="$1"
    local dst="$2"

    cp "$src" "$dst"
}

make_xlog_framework() {
    local build_dir="$1"
    local platform="$2"
    local arch="$3"
    local framework_path="$4"

    echo "开始构建 $platform $arch Xlog framework: $framework_path"
    rm -rf "$build_dir"
    mkdir -p "$build_dir"

    pushd "$build_dir" > /dev/null
    cmake ../../.. \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_TOOLCHAIN_FILE=../../../ios.toolchain.cmake \
        -DIOS_PLATFORM="$platform" \
        -DIOS_ARCH="$arch" \
        -DENABLE_ARC=0 \
        -DENABLE_BITCODE=0 \
        -DENABLE_VISIBILITY=1
    make -j8
    make install
    popd > /dev/null

    local install_path="$build_dir/Darwin.out"
    local zstd_lib="$build_dir/zstd/libzstd.a"
    local output_lib="$install_path/$framework_name"

    libtool -static -no_warning_for_no_symbols \
        -o "$output_lib" \
        "$install_path/libcomm.a" \
        "$install_path/libmars-boost.a" \
        "$install_path/libxlog.a" \
        "$zstd_lib"

    rm -rf "$framework_path"
    mkdir -p "$framework_path/Headers"
    cp "$output_lib" "$framework_path/$framework_name"
    if [ "$platform" = "OS" ]; then
        write_framework_info_plist "$framework_path" "iPhoneOS" "iphoneos"
    else
        write_framework_info_plist "$framework_path" "iPhoneSimulator" "iphonesimulator"
    fi

    copy_header "mars/comm/verinfo.h" "comm" "$framework_path/Headers"
    copy_header "mars/comm/autobuffer.h" "comm" "$framework_path/Headers"
    copy_header "mars/comm/http.h" "comm" "$framework_path/Headers"
    copy_header "mars/comm/time_utils.h" "comm" "$framework_path/Headers"
    copy_header "mars/comm/strutil.h" "comm" "$framework_path/Headers"
    copy_header "mars/comm/string_cast.h" "comm" "$framework_path/Headers"
    copy_header "mars/comm/comm_data.h" "comm" "$framework_path/Headers"
    copy_header "mars/comm/projdef.h" "comm" "$framework_path/Headers"
    copy_header "mars/comm/socket/local_ipstack.h" "comm" "$framework_path/Headers"
    copy_header "mars/comm/socket/nat64_prefix_util.h" "comm" "$framework_path/Headers"
    copy_header "mars/comm/has_member.h" "comm" "$framework_path/Headers"
    copy_header "mars/comm/objc/scope_autoreleasepool.h" "comm" "$framework_path/Headers"
    copy_header "mars/comm/objc/ThreadOperationQueue.h" "comm" "$framework_path/Headers"
    copy_header "mars/comm/xlogger/preprocessor.h" "xlog" "$framework_path/Headers"
    copy_header "mars/comm/xlogger/xloggerbase.h" "xlog" "$framework_path/Headers"
    copy_header "mars/comm/xlogger/xlogger.h" "xlog" "$framework_path/Headers"
    copy_header "mars/log/appender.h" "xlog" "$framework_path/Headers"
    copy_header "mars/log/xlogger_interface.h" "xlog" "$framework_path/Headers"
}

make_universal_simulator_framework() {
    local arm64_framework="$1"
    local x86_64_framework="$2"
    local output_framework="$3"

    echo "合并模拟器 framework: $output_framework"
    rm -rf "$output_framework"
    mkdir -p "$(dirname "$output_framework")"
    cp -R "$arm64_framework" "$output_framework"

    lipo -create \
        "$arm64_framework/$framework_name" \
        "$x86_64_framework/$framework_name" \
        -output "$output_framework/$framework_name"

    write_framework_info_plist "$output_framework" "iPhoneSimulator" "iphonesimulator"
}

device_framework="${1:-}"
simulator_framework="${2:-}"
output_dir="${3:-MarsLog_iOS/Frameworks}"

if [ -z "$device_framework" ]; then
    device_framework="$default_device_framework"
    make_xlog_framework "mars/cmake_build/MarsLog_iOS/iphoneos" "OS" "arm64" "$device_framework"
fi

if [ -z "$simulator_framework" ]; then
    simulator_framework="$default_simulator_framework"
    make_xlog_framework "mars/cmake_build/MarsLog_iOS/iphonesimulator-arm64" "SIMULATOR64" "arm64" "$default_simulator_arm64_framework"
    make_xlog_framework "mars/cmake_build/MarsLog_iOS/iphonesimulator-x86_64" "SIMULATOR64" "x86_64" "$default_simulator_x86_64_framework"
    make_universal_simulator_framework "$default_simulator_arm64_framework" "$default_simulator_x86_64_framework" "$simulator_framework"
fi

if [ -z "$device_framework" ]; then
    device_framework="$(find_first_existing_framework \
        "mars/cmake_build/iOS/Darwin.out/mars.framework" \
        "mars/cmake_build/iphoneos/Darwin.out/mars.framework" \
        "device/mars.framework" \
        "./device/mars.framework")"
fi

if [ -z "$simulator_framework" ]; then
    simulator_framework="$(find_first_existing_framework \
        "mars/cmake_build/iOSSimulator/Darwin.out/mars.framework" \
        "mars/cmake_build/Simulator/Darwin.out/mars.framework" \
        "mars/cmake_build/iphonesimulator/Darwin.out/mars.framework" \
        "simulator/mars.framework" \
        "./simulator/mars.framework")"
fi

if [ -z "$device_framework" ] || [ -z "$simulator_framework" ]; then
    usage
    if [ -n "$device_framework" ]; then
        echo "已自动找到真机 framework: $device_framework"
    else
        echo "未自动找到真机 framework"
    fi
    if [ -n "$simulator_framework" ]; then
        echo "已自动找到模拟器 framework: $simulator_framework"
    else
        echo "未自动找到模拟器 framework"
    fi
    echo "错误: 需要分别提供真机 framework 和模拟器 framework"
    exit 1
fi

if [ ! -d "$device_framework" ]; then
    echo "错误: 真机 framework 不存在: $device_framework"
    exit 1
fi

if [ ! -d "$simulator_framework" ]; then
    echo "错误: 模拟器 framework 不存在: $simulator_framework"
    exit 1
fi

framework_name="$(basename "$device_framework" .framework)"
simulator_framework_name="$(basename "$simulator_framework" .framework)"

if [ "$framework_name" != "$simulator_framework_name" ]; then
    echo "错误: 真机和模拟器 framework 名称不一致: $framework_name / $simulator_framework_name"
    exit 1
fi

write_framework_info_plist "$device_framework" "iPhoneOS" "iphoneos"
write_framework_info_plist "$simulator_framework" "iPhoneSimulator" "iphonesimulator"

device_binary="$device_framework/$framework_name"
simulator_binary="$simulator_framework/$framework_name"

if [ ! -f "$device_binary" ]; then
    echo "错误: 找不到真机二进制文件: $device_binary"
    exit 1
fi

if [ ! -f "$simulator_binary" ]; then
    echo "错误: 找不到模拟器二进制文件: $simulator_binary"
    exit 1
fi

echo "真机 framework: $device_framework"
lipo -info "$device_binary"
echo "模拟器 framework: $simulator_framework"
lipo -info "$simulator_binary"

lipo "$device_binary" -verify_arch arm64
lipo "$simulator_binary" -verify_arch arm64
lipo "$simulator_binary" -verify_arch x86_64

temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/${framework_name}.xcframework.XXXXXX")"
cleanup() {
    rm -rf "$temp_dir"
}
trap cleanup EXIT

device_output="$temp_dir/ios-arm64/$framework_name.framework"
simulator_output="$temp_dir/ios-arm64_x86_64-simulator/$framework_name.framework"

mkdir -p "$(dirname "$device_output")" "$(dirname "$simulator_output")" "$output_dir"
cp -R "$device_framework" "$device_output"
cp -R "$simulator_framework" "$simulator_output"

echo "处理二进制..."
copy_arm64_binary "$device_binary" "$device_output/$framework_name"
copy_binary "$simulator_binary" "$simulator_output/$framework_name"

xcframework_path="$output_dir/$framework_name.xcframework"
temp_xcframework_path="$temp_dir/output/$framework_name.xcframework"
mkdir -p "$(dirname "$temp_xcframework_path")"

xcodebuild -create-xcframework \
    -framework "$device_output" \
    -framework "$simulator_output" \
    -output "$temp_xcframework_path"

rm -rf "$xcframework_path"
mv "$temp_xcframework_path" "$xcframework_path"

echo "验证结果:"
find "$xcframework_path" -name "*.framework" -type d
plutil -p "$xcframework_path/Info.plist"

echo "转换完成: $xcframework_path"
