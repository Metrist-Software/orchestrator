#!/usr/bin/env bash
#
#  Build the code in $1 and tag it with distribution $2 and version $3
#
set -e
set -vx

ls
pwd
base=$(cd $1; /bin/pwd)
dist=$2
ver=$3
rel=$base/dist/$dist/$ver

mix local.hex --force
mix local.rebar --force

# install runner
runnerdist=https://monitor-distributions.canarymonitor.com
latest=$(curl $runnerdist/runner-latest.txt)
echo "Installing runner version $latest"
curl $runnerdist/runner-${latest}-linux-x64.zip >/tmp/runner.zip
unzip -o /tmp/runner.zip -d $base/priv/runner

cd $base
tag=$(git rev-parse --short HEAD)
mix do deps.get, compile, release

orch_ver=$(cat _build/prod/rel/orchestrator/releases/start_erl.data |awk '{print $2}')

dest=/tmp/pkgbuild
[ -e $dest ] && rm -rf $dest
mkdir -p $dest

pkg_dest=/tmp/pkgout
[ -e $pkg_dest ] && rm -rf $pkg_dest
mkdir -p $pkg_dest



# Copy the binary over
mkdir -p $dest/usr/bin
cp _build/prod/rel/bakeware/orchestrator $dest/usr/bin/metrist-orchestrator


# Copy anything else we want to include over. We remove `.gitkeep` files
# because that is cleaner
(cd $rel/inc; cp -rv . $dest/; find $dest/ -name .gitkeep |xargs rm)

# Build the package. Distribution-method specific arguments MUST
# be in the `fpm.cmd` file in the rel directory. At a minimum, this
# should contain something like "-t deb"
cd $dest
fpm --verbose -s dir \
    $(cat $rel/fpm.cmd) \
    --license "APSLv2" \
    --vendor "Metrist Software, Inc." \
    --provides metrist-orchestrator \
    -m "Metrist Software, Inc. <support@metrist.io>" \
    -n metrist-orchestrator \
    -v $orch_ver-$dist-$ver-$tag \
    -a native \
    -p $pkg_dest \
    .

pkg=$(cd $pkg_dest; ls)

mkdir -p $base/pkg
cp $pkg_dest/$pkg $base/pkg
echo $pkg >$base/pkg/$dist-$ver
