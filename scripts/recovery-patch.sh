set -e

# Credits to @salvogiangri UN1CA
HEX_PATCH()
{
    #_CHECK_NON_EMPTY_PARAM "FILE" "$1" || return 1
    #_CHECK_NON_EMPTY_PARAM "FROM" "$2" || return 1
    #_CHECK_NON_EMPTY_PARAM "TO" "$3" || return 1

    local FILE="$1"
    local FROM="$2"
    local TO="$3"

    if [ ! -f "$FILE" ]; then
        #LOGE "File not found: ${FILE//$WORK_DIR/}"
        return 1
    fi

    FROM="$(tr "[:upper:]" "[:lower:]" <<< "$FROM")"
    TO="$(tr "[:upper:]" "[:lower:]" <<< "$TO")"

    if ! xxd -p -c 0 "$FILE" | grep -q "$FROM"; then
        echo "No \"$FROM\" match in $FILE"
        return 1
    fi

    echo "Patching \"$FROM\" to \"$TO\" in $FILE"
    xxd -p -c 0 "$FILE" | sed "s/$FROM/$TO/" | xxd -r -p > "$FILE.tmp"
    mv "$FILE.tmp" "$FILE"

    return 0
}

if [ ! -f "$1" ]; then
  echo "cannot find file."
  exit 1
fi

OUT_FILE="$(realpath $1)"

echo "Dest file is $OUT_FILE"

TMP_DIR="$(mktemp -d)"
cd "$TMP_DIR"

magiskboot unpack "$OUT_FILE"
mkdir ramdisk_tmp; cd ramdisk_tmp
magiskboot cpio '../ramdisk.cpio' 'extract system/bin/recovery system/bin/recovery'
magiskboot cpio '../ramdisk.cpio' 'extract system/lib64/libselinux.so system/lib64/libselinux.so'
magiskboot cpio '../ramdisk.cpio' 'extract prop.default prop.default'

# Recovery patches for Samsung TP1A (A05s) recovery images

# Make SELinux permissive
# FILE: system/lib64/libselinux.so

# Function: security_setenforce
# From: mov w19, w0
# To: mov w19, wzr

HEX_PATCH "system/lib64/libselinux.so" "55d03bd5f303002a" "55d03bd5f3031f2a"

# Bypass package signature verification
# FILE: system/bin/recovery

# Function: InstallPackage
# From:
#   bl 0x001f8110
#   tbz w0, #0x0, 0x001f7784
# To:
#   bl 0x001f8110
#   tbnz w0, #0x0, 0x001f7784

HEX_PATCH "system/bin/recovery" "8e02009440050036" "8e02009440050037"

# Disregard missing ZIP metadata
# FILE: system/bin/recovery

# Function: ReadMetadataFromPackage
# From: mov w19, wzr
# To: mov w19, #0x1

HEX_PATCH "system/bin/recovery" "f3031f2ad5000014" "33008052d5000014"
HEX_PATCH "system/bin/recovery" "f3031f2a950200b9c6ffff17" "33008052950200b9c6ffff17"

# Allow fastbootd
# FILE: system/bin/recovery

# Function: getFastbootdPermission
# From: mov w0, wzr
# To: mov w0, #0x1

HEX_PATCH "system/bin/recovery" "c2f90394e0031f2a" "c2f9039420008052"

# Enable ADB by default
sed -i 's/persist\.sys\.usb\.config\=mtp/persist\.sys\.usb\.config\=mtp\,adb/g' "prop.default"
sed -i 's/ro\.adb\.secure\=1/ro\.adb\.secure\=0/g' "prop.default"
sed -i 's/ro\.debuggable\=0/ro\.debuggable\=1/g' "prop.default"

magiskboot cpio '../ramdisk.cpio' 'add 755 system/bin/recovery system/bin/recovery'
magiskboot cpio '../ramdisk.cpio' 'add 644 system/lib64/libselinux.so system/lib64/libselinux.so'
magiskboot cpio '../ramdisk.cpio' 'add 644 prop.default prop.default'

cd ..
magiskboot repack "$OUT_FILE" recovery.img
mv recovery.img "$OUT_FILE"
