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
  type = string
}

source "tart-cli" "tart" {
  vm_base_name = "${var.macos_version}-xcode:${var.xcode_version}"
  vm_name      = "${var.macos_version}-xcode-tartelet:${var.xcode_version}"
  cpu_count    = 4
  memory_gb    = 6
  disk_size_gb = 140
  headless     = true
  ssh_password = "admin"
  ssh_username = "admin"
  ssh_timeout  = "120s"
}

build {
  sources = ["source.tart-cli.tart"]

  provisioner "shell" {
    script = "scripts/install-actions-runner.sh"
  }

  provisioner "shell" {
    inline = [
      "source ~/.zprofile",
      "brew update",
      "brew upgrade",
      "brew install xcbeautify swiftformat sentry-cli python@3.13 awscli",
      "brew cleanup --prune=all"
    ]
  }

  provisioner "shell" {
    inline = [
      "mkdir -p ~/.tartelet"
    ]
  }

  provisioner "file" {
    source      = "data/xcode_tartelet_scripts/"
    destination = "~/.tartelet"
  }
}
