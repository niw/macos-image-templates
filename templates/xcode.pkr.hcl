packer {
  required_plugins {
    tart = {
      version = ">= 1.12.0"
      source  = "github.com/cirruslabs/tart"
    }
  }
}

variable "macos_version" {
  type = string
}

variable "xcode_version" {
  type = list(string)
}

variable "ios_simulator_version" {
  type = string
  default = ""
}

variable "tvos_simulator_version" {
  type = string
  default = ""
}

variable "watchos_simulator_version" {
  type = string
  default = ""
}

variable "visionos_simulator_version" {
  type = string
  default = ""
}

variable "xcode_components" {
  type        = list(string)
  default     = []
  description = "Additional Xcode components to download."
}

variable "expected_runtimes_file" {
  type        = string
  default     = ""
  description = "Path to file containing expected simulator runtimes. If empty, runtime verification is skipped."
}

variable "tag" {
  type    = string
  default = ""
}

variable "disk_size" {
  type    = number
  default = 140
}

variable "disk_free_mb" {
  type    = number
  default = 15000
}

source "tart-cli" "tart" {
  vm_base_name = "${var.macos_version}-base"
  // use tag or the last element of the xcode_version list
  vm_name      = "${var.macos_version}-xcode:${var.tag != "" ? var.tag : var.xcode_version[0]}"
  cpu_count    = 4
  memory_gb    = 8
  disk_size_gb = var.disk_size
  headless     = true
  ssh_password = "admin"
  ssh_username = "admin"
  ssh_timeout  = "120s"
}

locals {
  xcode_install_provisioners = [
    for version in reverse(sort(var.xcode_version)) : {
      type = "shell"
      inline = [
        "source ~/.zprofile",
        "sudo xcodes install ${version} --experimental-unxip --path /Users/admin/Downloads/Xcode_${version}_Apple_silicon.xip --select --empty-trash",
        // get selected xcode path, strip /Contents/Developer and move to GitHub compatible locations
        "INSTALLED_PATH=$(xcodes select -p)",
        "CONTENTS_DIR=$(dirname $INSTALLED_PATH)",
        "APP_DIR=$(dirname $CONTENTS_DIR)",
        "sudo mv $APP_DIR /Applications/Xcode_${version}.app",
        "sudo xcode-select -s /Applications/Xcode_${version}.app",
        "xcodebuild -runFirstLaunch",
        "df -h",
      ]
    }
  ]
}

build {
  sources = ["source.tart-cli.tart"]

  // make sure our workaround from base is still valid
  provisioner "shell" {
    inline = [
      "sudo ln -s /Users/admin /Users/runner || true"
    ]
  }

  provisioner "shell" {
    inline = [
      "source ~/.zprofile",
      "brew install xcodes",
      "xcodes version",
    ]
  }

  provisioner "file" {
    sources     = [for version in var.xcode_version : pathexpand("~/Downloads/Xcode_${version}_Apple_silicon.xip")]
    destination = "/Users/admin/Downloads/"
  }

  provisioner "shell" {
    inline = [
      "source ~/.zprofile",
      "df -h",
    ]
  }

  // iterate over all Xcode versions and install them
  // select the latest one as the default
  dynamic "provisioner" {
    for_each = local.xcode_install_provisioners
    labels   = ["shell"]
    content {
      inline = provisioner.value.inline
    }
  }

  provisioner "shell" {
    inline = [
      "source ~/.zprofile",
      "sudo xcode-select -s /Applications/Xcode_${var.xcode_version[0]}.app/Contents/Developer",
    ]
  }

  provisioner "shell" {
    inline = concat(
      ["source ~/.zprofile"],
      // simulator runtimes are downloaded only when a build version is given
      var.ios_simulator_version != "" ? ["xcodebuild -downloadPlatform iOS -buildVersion ${var.ios_simulator_version}"] : [],
      var.tvos_simulator_version != "" ? ["xcodebuild -downloadPlatform tvOS -buildVersion ${var.tvos_simulator_version}"] : [],
      var.watchos_simulator_version != "" ? ["xcodebuild -downloadPlatform watchOS -buildVersion ${var.watchos_simulator_version}"] : [],
      var.visionos_simulator_version != "" ? ["xcodebuild -downloadPlatform visionOS -buildVersion ${var.visionos_simulator_version}"] : []
    )
  }

  provisioner "shell" {
    inline = concat(
      ["source ~/.zprofile"],
      [
        for component in var.xcode_components : "xcodebuild -downloadComponent ${component}"
      ]
    )
  }

  # inspired by https://github.com/actions/runner-images/blob/fb3b6fd69957772c1596848e2daaec69eabca1bb/images/macos/provision/configuration/configure-machine.sh#L33-L61
  provisioner "shell" {
    inline = [
      "source ~/.zprofile",
      "curl -o AppleWWDRCAG3.cer https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer",
      "curl -o DeveloperIDG2CA.cer https://www.apple.com/certificateauthority/DeveloperIDG2CA.cer",
      "curl -o add-certificate.swift https://raw.githubusercontent.com/actions/runner-images/fb3b6fd69957772c1596848e2daaec69eabca1bb/images/macos/provision/configuration/add-certificate.swift",
      "swiftc -suppress-warnings add-certificate.swift",
      "sudo ./add-certificate AppleWWDRCAG3.cer",
      "sudo ./add-certificate DeveloperIDG2CA.cer",
      "rm add-certificate* *.cer"
    ]
  }

  // check there is at least 15GB of free space and fail if not
  provisioner "shell" {
    inline = [
      "source ~/.zprofile",
      "df -h",
      "export FREE_MB=$(df -m | awk '{print $4}' | head -n 2 | tail -n 1)",
      "[[ $FREE_MB -gt ${var.disk_free_mb} ]] && echo OK || exit 1"
    ]
  }

  // some other health checks
  provisioner "shell" {
    inline = [
      "source ~/.zprofile",
      "test -d /Users/runner"
    ]
  }

  # Disable apsd[1][2] daemon as it causes high CPU usage after boot
  #
  # [1]: https://iboysoft.com/wiki/apsd-mac.html
  # [2]: https://discussions.apple.com/thread/4459153
  provisioner "shell" {
    inline = [
      "sudo launchctl unload -w /System/Library/LaunchDaemons/com.apple.apsd.plist"
    ]
  }

  # Wait for the "update_dyld_sim_shared_cache" process[1][2] to finish
  # to avoid wasting CPU cycles after boot
  #
  # [1]: https://apple.stackexchange.com/questions/412101/update-dyld-sim-shared-cache-is-taking-up-a-lot-of-memory
  # [2]: https://stackoverflow.com/a/68394101/9316533
  provisioner "shell" {
    inline = [
      "source ~/.zprofile",
      "xcrun simctl runtime dyld_shared_cache update --all || sleep 180",
      "xcrun simctl list -v"
    ]
  }

  # Compatibility with GitHub Actions Runner Images, where
  # /usr/local/bin belongs to the default user. Also see [2].
  #
  # [1]: https://github.com/actions/runner-images/blob/6bbddd20d76d61606bea5a0133c950cc44c370d3/images/macos/scripts/build/configure-machine.sh#L96
  # [2]: https://github.com/actions/runner-images/discussions/7607
  provisioner "shell" {
    inline = [
      "sudo mkdir -p /usr/local/bin",
      "sudo chown admin /usr/local/bin"
    ]
  }

  // Install setup-info-generator
  provisioner "shell" {
    inline = [
      "source ~/.zprofile",
      "brew install cirruslabs/cli/setup-info-generator"
    ]
  }

  // Copy setup info template
  provisioner "file" {
    source      = "data/setup-info-template.json"
    destination = "~/setup-info-template.json"
  }

  // Generate setup info
  provisioner "shell" {
    inline = [
      "source ~/.zprofile",
      "cat ~/setup-info-template.json | setup-info-generator > ~/actions-runner/.setup_info",
      "rm ~/setup-info-template.json"
    ]
  }
}
