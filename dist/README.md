# Orchestrator distribution packages

The contents of this directory and its subdirectories are to create distribution packages for Metrist Orchestrator.
Canonical versions of these packages are built by us and available at http://dist.metrist.io but you may want to
build your own or add new distribution targets.

## Versioning

Distribution packages are tagged with four version elements:

* The Mix version, taken from Orchestrator's [`mix.exs`](../mix.exs);
* The target (distribution and distribution version, for example `ubuntu-20.04`);
* The time the package was built (yymmddhhmm);
* The Git short rev of this repository.

The latter element is just informational, updates to Orchestrator packages will be indicated through mix version bumps.

The latest version is indicated by a file `&lt;dist>-&lt;ver>.&lt;arch>latest.txt`. A complete example:

In `https://dist.metrist.io/orchestrator/ubuntu`, you can find>

* `metrist-orchestrator_0.1.0-ubuntu-22.04-611a16f_amd64.deb`, the 0.1.0 version package for Ubuntu 22.04
* `metrist-orchestrator_0.1.0-ubuntu-22.04-611a16f_amd64.deb.asc`, its signature
* `ubuntu-22.04.x86_64.latest.txt`, containing the full filename of the debian package above.

## Signing

Packages are signed with GnuPG and the signatures are uploaded as usual, with `.asc` files. See [SIGNING.md](SIGNING.md)
for details.

## Basic Flow

We use a Docker container per target to build an Orchestrator release. The release is then wrapped in a
platform-native package using [fpm](https://fpm.readthedocs.io/) and uploaded to the AWS S3 bucket behind
our distribution website.

### Scripts

[dist/build.sh](dist/build.sh) is the top-level script which you call with a platform ('ubuntu') and a version
('20.04'). The script will invoke the correct base container (which contains the target-specific versions of
Erlang, Elixir and fpm) to build and package Orchestrator.

[dist/do-build.sh](dist/do-build.sh) is the script that is invoked inside the container by the main build script. It
executes the build/package steps and drops any artefacts created in the `pkg/` directory in the Orchestrator
source tree.

The main build script then signs and uploads the release.

A helper script [dist/build-base.sh](dist/build-base.sh) builds the Docker containers we use. It, too, gets
invoked with the platform and version as arguments. It will upload containers to our [public container repository
in AWS](https://gallery.ecr.aws/metrist).

## Per-target directories

Every target has configuration and package elements in `dist/<distribution>/<version>`. Three elements are required:

* `Dockerfile` - this describes the container build for that particular version.
* `fpm.cmd` - the `fpm` command line arguments specific for this target. At least the `-t` type specification
  is expected here.
* `inc` - a directory structure to include into the package. Scripts, configuration, documentation can be put here.
