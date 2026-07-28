macos-image-templates
=====================

This is a patched version of `cirruslabs/macos-image-templates` includes
a customized version of packer template for macOS and iOS development
CI virtual machine image.


Prerequisites
-------------

Install Packer by using Homebrew.

```
$ brew install hashicorp/tap/packer
```

To build `vanilla`, which is using Ansible as provisioning tool, install Ansible
and dependencies, and add `.venv/bin` to `PATH`.

```
$ uv venv
$ uv pip install -r requirements.txt
```

Note the the goal is build `xcode-tartelet`, which is based on `xcode`,
which is based on `base`, which is based on `vanilla`.


Usage
-----

Download and place `Xcode_${VERSION}_Apple_silicon.xip` in host `~/Downloads`
directory.

Use following command to build `base` and `xcode` with expected simulator
runtime images.

`IOS_SIMULATOR_VERSION`, `TVOS_SIMULATOR_VERSION`, `WATCHOS_SIMULATOR_VERSION`,
and `VISIONOS_SIMULATOR_VERSION` are build versions of iOS, tvOS, watchOS,
and visionOS simulator runtimes.
Each runtime is downloaded only when its `-var` flag is given.

```
# If necessary, use `packer init` first for each build.

# This template requires manual operation to complete initial macOS installation.
$ packer build templates/vanilla-tahoe.pkr.hcl

$ tart clone tahoe-vanilla tahoe-base
$ packer build -var vm_name=tahoe-base templates/base.pkr.hcl

$ packer build \
-var macos_version=tahoe \
-var xcode_version="[\"$VERSION\"]" \
-var ios_simulator_version=$IOS_SIMULATOR_VERSION \
-var tvos_simulator_version=$TVOS_SIMULATOR_VERSION \
-var watchos_simulator_version=$WATCHOS_SIMULATOR_VERSION \
-var visionos_simulator_version=$VISIONOS_SIMULATOR_VERSION \
-var xcode_components='["MetalToolchain"]' \
templates/xcode.pkr.hcl

# Place additional Tartelet scripts in `data/xcode_tartelet_scripts`
# that need to be baked in.
$ packer build \
-var macos_version=tahoe \
-var xcode_version=$VERSION \
templates/xcode-tartelet.pkr.hcl
```
