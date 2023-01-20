#!/usr/bin/env bash
#
#  Installation script for guided Orchestrator installation.
#
#  For now, this is a severely restricted script that we will extend
#  as needed. Our thanks goes out to Tailscale for their install
#  script which we heavily leaned on for "inspiration". For license
#  compatibility, the use of this source code is therefore governed
#  by the same BSD-style license as theirs, you can find the license
#  text at the bottom of this script.
#
#  We use CamelCase function names to lessen the chance of a clash
#  with existing commands and to make them stand out as local function
#  names.
#

set -eu

TTY=""
SetTty() {
    case `tty` in
        /dev/*)
            TTY="tty"
            ;;
        *)
            TTY=""
            ;;
    esac
}

Error() {
    # If we'd use color we'd need to figure out the background color first and
    # then go dark or light mode. For now, just bolding things will cause it to
    # stand out enough.
    if [ -n "$TTY" ]; then
        echo -e "\e[1m$*\e[m"
    else
        echo $*
    fi
}

ExitWithUnsupportedOS() {
    Error
    Error "The OS or Linux distribution you are running on is not supported by this installation script. Please"
    Error "proceed manually using the instructions at https://docs.metrist.io/en/latest/orchestrator-installation."
    Error
    exit 1
}

ExitWith() {
    Error
    Error $*
    Error
    exit 1
}

OS=
VERSION=
ARCH=$(uname -m)
PACKAGETYPE=
SUDO=
CURL=
DetectOS() {
    if [ ! -f /etc/os-release ]; then
        ExitWithUnsupportedOS
    fi
    . /etc/os-release
    # Some bits here got lifted 1:1 from the Tailscale script. Most unused but keeping it here
    # as an inventory of sorts. Or a To-Do list.
    case "$ID" in
            ubuntu|pop|neon|zorin)
                OS="ubuntu"
                VERSION="$VERSION_ID"
                PACKAGETYPE="apt"
                ;;
            debian)
                OS="$ID"
                VERSION="$VERSION_ID"
                PACKAGETYPE="apt"
                ;;
            linuxmint)
                VERSION="$VERSION_ID"
                PACKAGETYPE="apt"
                ;;
            elementary)
                OS="ubuntu"
                VERSION="$VERSION_ID"
                PACKAGETYPE="apt"
                ;;
            parrot)
                OS="debian"
                PACKAGETYPE="apt"
                ;;
            raspbian)
                OS="$ID"
                VERSION="$VERSION_ID"
                PACKAGETYPE="apt"
                ;;
            kali)
                OS="debian"
                PACKAGETYPE="apt"
                YEAR="$(echo "$VERSION_ID" | cut -f1 -d.)"
                ;;
            centos)
                OS="$ID"
                VERSION="$VERSION_ID"
                PACKAGETYPE="dnf"
                if [ "$VERSION" = "7" ]; then
                    PACKAGETYPE="yum"
                fi
                ;;
            ol)
                OS="oracle"
                VERSION="$(echo "$VERSION_ID" | cut -f1 -d.)"
                PACKAGETYPE="dnf"
                if [ "$VERSION" = "7" ]; then
                    PACKAGETYPE="yum"
                fi
                ;;
            rhel)
                OS="$ID"
                VERSION="$(echo "$VERSION_ID" | cut -f1 -d.)"
                PACKAGETYPE="dnf"
                if [ "$VERSION" = "7" ]; then
                    PACKAGETYPE="yum"
                fi
                ;;
            fedora)
                OS="$ID"
                VERSION=""
                PACKAGETYPE="dnf"
                ;;
            rocky)
                OS="$ID"
                VERSION="$(echo "$VERSION_ID" | cut -f1 -d.)"
                PACKAGETYPE="dnf"
                ;;
            # rocky|almalinux)
            #     OS="fedora"
            #     VERSION=""
            #     PACKAGETYPE="dnf"
            #     ;;
            amzn)
                OS="amazon-linux"
                VERSION="$VERSION_ID"
                PACKAGETYPE="yum"
                ;;
            xenenterprise)
                OS="centos"
                VERSION="$(echo "$VERSION_ID" | cut -f1 -d.)"
                PACKAGETYPE="yum"
                ;;
            opensuse-leap)
                OS="opensuse"
                VERSION="leap/$VERSION_ID"
                PACKAGETYPE="zypper"
                ;;
            opensuse-tumbleweed)
                OS="opensuse"
                VERSION="tumbleweed"
                PACKAGETYPE="zypper"
                ;;
            arch|archarm|endeavouros)
                OS="arch"
                VERSION="" # rolling release
                PACKAGETYPE="pacman"
                ;;
            manjaro|manjaro-arm)
                OS="manjaro"
                VERSION="" # rolling release
                PACKAGETYPE="pacman"
                ;;
            alpine)
                OS="$ID"
                VERSION="$VERSION_ID"
                PACKAGETYPE="apk"
                ;;
            void)
                OS="$ID"
                VERSION="" # rolling release
                PACKAGETYPE="xbps"
                ;;
            gentoo)
                OS="$ID"
                VERSION="" # rolling release
                PACKAGETYPE="emerge"
                ;;
            *)
                ExitWithUnsupportedOS
                ;;
    esac

    case "$OS" in
        ubuntu)
            if [ "$VERSION" != "20.04" ] && \
                [ "$VERSION" != "22.04" ]; then
                ExitWithUnsupportedOS
            fi
            ;;
        amazon-linux)
            if [ "$VERSION" != "2" ]; then
                ExitWithUnsupportedOS
            fi
            ;;
        rocky)
            if [ "$VERSION" != "8" ]; then
                ExitWithUnsupportedOS
            fi
            ;;
        centos)
            if [ "$VERSION" != "7" ]; then
                ExitWithUnsupportedOS
            fi
            ;;
        rhel)
            if [ "$VERSION" != "7" ]; then
                ExitWithUnsupportedOS
            fi
            ;;
        *)
            ExitWithUnsupportedOS
    esac

    can_root=
    if [ "$(id -u)" = 0 ]; then
        can_root=1
        SUDO=""
    elif type sudo >/dev/null; then
        can_root=1
        SUDO="sudo"
    elif type doas >/dev/null; then
        can_root=1
        SUDO="doas"
    fi
    if [ "$can_root" != "1" ]; then
        Error "This installer needs to run commands as root."
        Error "We tried looking for 'sudo' and 'doas', but couldn't find them."
        Error "Either re-run this script as root, or set up sudo/doas."
        exit 1
    fi

    if type curl >/dev/null; then
        CURL="curl -fsSL"
    elif type wget >/dev/null; then
        CURL="wget -q -O-"
    fi
    if [ -z "$CURL" ]; then
        ExitWithError "The installer needs either curl or wget to download files. Please install either curl or wget to proceed."
    fi

}

SERVICE_NAME="metrist-orchestrator"

EXISTING_CONFIG=
GetExistingConfig() {
    if test -f "/etc/default/$SERVICE_NAME"; then
        EXISTING_CONFIG=`$SUDO cat /etc/default/$SERVICE_NAME`
    fi
}

EXISTING_INSTANCE_NAME=false
INSTANCE_NAME=
GetInstanceName() {
    local PATTERN=$'METRIST_INSTANCE_ID=([^\n$]+)'
    if [[ "$EXISTING_CONFIG" =~ $PATTERN ]]; then
        EXISTING_INSTANCE_NAME=true
    else
        cat <<EOF

    We distinguish collected metrics and error data by "instance name", which can be a hostname,
    a cloud region, or any other tag you want to use for grouping data.

EOF
        echo -n "Please enter the instance name you want to use on this machine: "; read -r INSTANCE_NAME
        echo
    fi

}

EXISTING_API_TOKEN=false
API_TOKEN=
GetAPIToken() {
    local PATTERN=$'METRIST_API_TOKEN=([^\n$]+)'
    if [[ "$EXISTING_CONFIG" =~ $PATTERN ]]; then
        EXISTING_API_TOKEN=true
    else
        cat <<EOF

    In order to be able to report back to the Metrist Backend, you need to provide your API token. You can find your API token in
    the Metrist dashboard at https://app.metrist.io/profile.

EOF
        echo -n "Please enter your API token: "; read -r API_TOKEN
        echo
    fi
}

MaybeWriteApiToken() {
    if [ "$EXISTING_API_TOKEN" != true ] ; then
        cat <<EOF | $SUDO tee -a /etc/default/metrist-orchestrator >/dev/null
# Added by installation script.
METRIST_API_TOKEN=$API_TOKEN
EOF
    else
        echo "API TOKEN already set in unit defaults, not writing"
    fi
}

MaybeWriteInstanceId() {
    if [ "$EXISTING_INSTANCE_NAME" != true ] ; then
        cat <<EOF | $SUDO tee -a /etc/default/metrist-orchestrator >/dev/null
METRIST_INSTANCE_ID=$INSTANCE_NAME
EOF
    else
        echo "Instance ID already set in unit defaults, not writing"
    fi
}

MaybeStopOrchestrator() {
    # Stop the orchestrator if it is already running on this system (upgrade path)

    if systemctl is-active --quiet "$SERVICE_NAME";then
        echo "$SERVICE_NAME exists and is running. Stopping."
        $SUDO systemctl stop $SERVICE_NAME
    fi
}

WriteConfigAndStart() {
    MaybeWriteApiToken
    MaybeWriteInstanceId

    $SUDO systemctl enable --now $SERVICE_NAME
    $SUDO systemctl start $SERVICE_NAME
}

InstallApt() {
    export DEBIAN_FRONTEND=noninteractive
    if ! type gpg >/dev/null; then
        $SUDO apt-get update
        $SUDO apt-get install -y gnupg
    fi

    $SUDO mkdir -p --mode=0755 /usr/share/keyrings
    $CURL "https://github.com/Metrist-Software/orchestrator/blob/main/dist/trustedkeys.gpg?raw=true" | $SUDO tee /usr/share/keyrings/metrist-keyring.gpg >/dev/null
    cd /tmp
    latest=$($CURL https://dist.metrist.io/orchestrator/$OS/$VERSION.$ARCH.latest.txt)
    $CURL "https://dist.metrist.io/orchestrator/$OS/$latest" >$latest
    $SUDO apt-get install -y ./$latest
    WriteConfigAndStart
}

InstallYum() {
    set -x
    if ! type gpg >/dev/null; then
        $SUDO yum update
        $SUDO yum install -y gnupg
    fi

    $SUDO mkdir -p --mode=0755 /usr/share/keyrings
    $CURL "https://github.com/Metrist-Software/orchestrator/blob/main/dist/trustedkeys.gpg?raw=true" | $SUDO tee /usr/share/keyrings/metrist-keyring.gpg >/dev/null
    cd /tmp
    latest=$($CURL https://dist.metrist.io/orchestrator/$OS/$VERSION.$ARCH.latest.txt)
    $CURL "https://dist.metrist.io/orchestrator/$OS/$latest" >$latest
    $SUDO yum localinstall -y ./$latest
    WriteConfigAndStart
}

InstallDnf() {
    if ! type gpg >/dev/null; then
        $SUDO dnf update
        $SUDO dnf install -y gnupg
    fi

    $SUDO mkdir -p --mode=0755 /usr/share/keyrings
    $CURL "https://github.com/Metrist-Software/orchestrator/blob/main/dist/trustedkeys.gpg?raw=true" | $SUDO tee /usr/share/keyrings/metrist-keyring.gpg >/dev/null
    cd /tmp
    latest=$($CURL https://dist.metrist.io/orchestrator/$OS/$VERSION.$ARCH.latest.txt)
    $CURL "https://dist.metrist.io/orchestrator/$OS/$latest" >$latest
    $SUDO dnf install -y ./$latest
    WriteConfigAndStart
}

Main() {
    SetTty
    DetectOS
    GetExistingConfig
    GetAPIToken
    GetInstanceName

    echo "Installing Metrist Orchestrator for $OS $VERSION."

    MaybeStopOrchestrator

    case "$PACKAGETYPE" in
        apt)
            InstallApt
            ;;
        yum)
            InstallYum
            ;;
        dnf)
            InstallDnf
            ;;
        *)
            ExitWith "Unknown package type '$PACKAGETYPE', this should not happen."
    esac

    cat <<EOF




    Installation complete. Metrist Orchestrator should now be running on your system. Please see our documentation
    for further details: https://docs.metrist.io.

    Have a nice day!
EOF
}

Main


# Copyright (c)2022 Metrist Software, Inc. and contributors
# Portions Copyright (c)2021 Tailscale Inc. and contributors
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#
# 1. Redistributions of source code must retain the above copyright notice,
# this list of conditions and the following disclaimer.
#
# 2. Redistributions in binary form must reproduce the above copyright
# notice, this list of conditions and the following disclaimer in the
# documentation and/or other materials provided with the distribution.
#
# 3. Neither the name of the copyright holder nor the names of its
# contributors may be used to endorse or promote products derived from
# this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
# A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
# HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
# SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
# TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
# PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
# LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
# NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
