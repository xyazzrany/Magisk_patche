Magiskboot=bin/magiskboot
BOOTIMAGE="$1"

# Flags
[ -z $KEEPVERITY ] && KEEPVERITY=false
[ -z $KEEPFORCEENCRYPT ] && KEEPFORCEENCRYPT=false
[ -z $PATCHVBMETAFLAG ] && PATCHVBMETAFLAG=false
[ -z $RECOVERYMODE ] && RECOVERYMODE=false
export KEEPVERITY
export KEEPFORCEENCRYPT
export PATCHVBMETAFLAG

#########
# Unpack
#########

CHROMEOS=false

echo "解包boot"
$Magiskboot unpack "$BOOTIMAGE"

case $? in
  0 ) ;;
  1 )
    echo "不支持的boot镜像!"
    ;;
  2 )
    echo "chromeos 镜像"
    ;;
  * )
    echo "无法解包"
    ;;
esac

###################
# Ramdisk Restores
###################

# Test patch status and do restore
echo "检查ramdisk"
if [ -e ramdisk.cpio ]; then
  $Magiskboot cpio ramdisk.cpio test
  STATUS=$?
else
  # Stock A only system-as-root
  STATUS=0
fi
case $((STATUS & 3)) in
  0 )  # Stock boot
    echo "Stock boot image detected"
    SHA1=$($Magiskboot sha1 "$BOOTIMAGE")
    cat $BOOTIMAGE > stock_boot.img
    cp -af ramdisk.cpio ramdisk.cpio.orig
    ;;
  1 )  # Magisk patched
    echo "Magisk patched boot image detected"
    # Find SHA1 of stock boot image
    [ -z $SHA1 ] && SHA1=$($Magiskboot cpio ramdisk.cpio sha1)
    $Magiskboot cpio ramdisk.cpio restore
    cp -af ramdisk.cpio ramdisk.cpio.orig
    rm -f stock_boot.img
    ;;
  2 )  # Unsupported
    echo "Boot image patched by unsupported programs"
    echo "Please restore back to stock boot image"
    ;;
esac

# Work around custom legacy Sony /init -> /(s)bin/init_sony : /init.real setup
INIT=init
if [ $((STATUS & 4)) -ne 0 ]; then
  INIT=init.real
fi

##################
# Ramdisk Patches
##################

echo "修补ramdisk"

echo "KEEPVERITY=$KEEPVERITY" > config
echo "KEEPFORCEENCRYPT=$KEEPFORCEENCRYPT" >> config
echo "PATCHVBMETAFLAG=$PATCHVBMETAFLAG" >> config
echo "RECOVERYMODE=$RECOVERYMODE" >> config
[ ! -z $SHA1 ] && echo "SHA1=$SHA1" >> config

# Compress to save precious ramdisk space

$Magiskboot compress=xz bin/magisk32 magisk32.xz
 
$Magiskboot compress=xz bin/magisk64 magisk64.xz


$Magiskboot cpio ramdisk.cpio \
"add 0750 $INIT bin/magiskinit" \
"mkdir 0750 overlay.d" \
"mkdir 0750 overlay.d/sbin" \
"add 0644 overlay.d/sbin/magisk32.xz magisk32.xz" \
"add 0644 overlay.d/sbin/magisk64.xz magisk64.xz" \
"patch" \
"backup ramdisk.cpio.orig" \
"mkdir 000 .backup" \
"add 000 .backup/.magisk config"

rm -rf ramdisk.cpio.orig config magisk*.xz

#################
# Binary Patches
#################

for dt in dtb kernel_dtb extra; do
  [ -f $dt ] && $Magiskboot dtb $dt patch && echo "Patch fstab in $dt"
done

if [ -f kernel ]; then
  # Remove Samsung RKP
  $Magiskboot hexpatch kernel \
  49010054011440B93FA00F71E9000054010840B93FA00F7189000054001840B91FA00F7188010054 \
  A1020054011440B93FA00F7140020054010840B93FA00F71E0010054001840B91FA00F7181010054

  # Remove Samsung defex
  # Before: [mov w2, #-221]   (-__NR_execve)
  # After:  [mov w2, #-32768]
  $Magiskboot hexpatch kernel 821B8012 E2FF8F12

  # Force kernel to load rootfs
  # skip_initramfs -> want_initramfs
  $Magiskboot hexpatch kernel \
  736B69705F696E697472616D667300 \
  77616E745F696E697472616D667300
fi

#################
# Repack & Flash
#################
echo "打包boot"
$Magiskboot repack "$BOOTIMAGE"  || echo "打包完成"

rm -rf stock_boot.img *kernel* *dtb* ramdisk.cpio*
