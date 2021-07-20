#!/bin/bash
set -e
set -o xtrace

PROJECT_DIR=$(dirname "$(readlink -f "$0")")/../

cd ${PROJECT_DIR}
mkdir build
cd build

rootfs_path=/
architecture=arm

# Install packages
sudo apt update
sudo apt install -y wget unzip binfmt-support g++-8-arm-linux-gnueabihf
sudo apt install -y build-essential pkg-config libgtest-dev qtbase5-dev libqt5core5a libqt5network5 libqt5gui5 libqt5widgets5 libqt5concurrent5 libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev gstreamer1.0-plugins-good libgstreamer-plugins-bad1.0-0 libmosquitto-dev libmosquittopp-dev libeigen3-dev libmsgpack-dev avahi-utils libraspberrypi-dev

### Install OpenCV 4.4 from https://github.com/dlime/Faster_OpenCV_4_Raspberry_Pi
sudo apt-get install -y libjpeg-dev libpng-dev libtiff-dev libgtk-3-dev libavcodec-extra libavformat-dev libswscale-dev libv4l-dev libxvidcore-dev libx264-dev libjasper1 libjasper-dev libatlas-base-dev gfortran libeigen3-dev libtbb-dev python3-dev python3-numpy
git clone https://github.com/dlime/Faster_OpenCV_4_Raspberry_Pi.git
sudo cp -r Faster_OpenCV_4_Raspberry_Pi/debs/ ${rootfs_path}/opt/OpenCV/
${QEMU_COMMAND} "cd /opt/OpenCV/ && dpkg -i OpenCV*.deb"
${QEMU_COMMAND} "ldconfig"
rm -rf Faster_OpenCV_4_Raspberry_Pi
sudo rm -r ${rootfs_path}/opt/OpenCV/

# Fix pkgconfig
sudo sed -i 's|prefix=/usr/local|prefix=/usr|' ${rootfs_path}/usr/lib/pkgconfig/opencv4.pc

# Fix path to lib
qtextrax=${rootfs_path}/usr/lib/arm-linux-gnueabihf/cmake/Qt5Gui/Qt5GuiConfigExtras.cmake
sudo sed -i 's|_qt5gui_find_extra_libs(EGL \"EGL\" \"\" \"/usr/include/libdrm\")|_qt5gui_find_extra_libs(EGL \"EGL\" \"'${rootfs_path}'\" \"/usr/include/libdrm\")|' ${qtextrax}
sudo sed -i 's|_qt5gui_find_extra_libs(OPENGL \"GLESv2\" \"\" \"\")|_qt5gui_find_extra_libs(OPENGL \"GLESv2\" \"'${rootfs_path}'\" \"\")|' ${qtextrax}

# Enable services
sudo systemctl enable ssh

# Install RPIMoCap service
sudo cp ${PROJECT_DIR}/scripts/rpiclient.service ${rootfs_path}/etc/systemd/system/rpiclient.service
systemctl enable rpiclient

ROOTFS=/media/$USER/rootfs/
INSTALL_PATH=${ROOTFS}/opt/rpimocap/
PROJECT_DIR=$(dirname "$(readlink -f "$0")")/../

echo "Running RPIMoCap client deploy script from ${PROJECT_DIR} to ${INSTALL_PATH}"

#TODO check this step
sudo ln -sfn /usr/arm-linux-gnueabihf/lib/ld-linux-armhf.so.3 /lib/ld-linux-armhf.so.3

RPATH_FLAGS="-DCMAKE_SKIP_BUILD_RPATH=FALSE -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=TRUE"
TOOLCHAIN_FLAGS="-DCMAKE_TOOLCHAIN_FILE=${PROJECT_DIR}/scripts/rpi_toolchain.cmake"

export CXX=/usr/bin/arm-linux-gnueabihf-g++-8
export CC=/usr/bin/arm-linux-gnueabihf-gcc-8

export PKG_CONFIG_DIR=
export PKG_CONFIG_LIBDIR="${ROOTFS}/usr/lib/arm-linux-gnueabihf/pkgconfig/":"${ROOTFS}/usr/lib/pkgconfig":"${ROOTFS}/usr/share/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="${ROOTFS}"

sudo mkdir -m 666 -p $INSTALL_PATH
cd ${PROJECT_DIR}
rm -r build-cross
mkdir -p build-cross
cd build-cross
cmake -DRASPBERRY_ROOT_FS=${ROOTFS} -DCMAKE_INSTALL_PREFIX=${INSTALL_PATH} -DCMAKE_BUILD_TYPE=Release -DENABLE_SIM=OFF -DENABLE_TESTS=OFF ${RPATH_FLAGS} ${TOOLCHAIN_FLAGS} ../RPIMoCap/

make -j 4
sudo make install
sudo chmod -R 777 ${INSTALL_PATH}

