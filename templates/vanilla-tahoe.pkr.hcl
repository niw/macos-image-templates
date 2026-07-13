packer {
  required_plugins {
    tart = {
      version = ">= 1.16.0"
      source  = "github.com/cirruslabs/tart"
    }
    ansible = {
      version = "~> 1"
      source = "github.com/hashicorp/ansible"
    }
  }
}

source "tart-cli" "tart" {
  from_ipsw    = "https://updates.cdn-apple.com/2026SummerFCS/fullrestores/140-65618/10445B26-DE2C-43EC-9149-0A831602E74B/UniversalMac_26.6_25G72_Restore.ipsw"
  vm_name      = "tahoe-vanilla"
  cpu_count    = 4
  memory_gb    = 8
  disk_size_gb = 50
  ssh_password = "admin"
  ssh_username = "admin"
  ssh_timeout  = "180s"
  boot_command = [
    # Do manual setup within 5 minutes!
    # Use "Managed by Tart" as full name, "admin" as username and password.
    "<wait300s>",
    # Enable Keyboard navigation
    # This is so that we can navigate the System Settings app using the keyboard
    "<wait10s><leftAltOn><spacebar><leftAltOff>Terminal<wait10s><enter>",
    "<wait10s><wait10s>defaults write NSGlobalDomain AppleKeyboardUIMode -int 3<enter>",
    # Now that the installation is done, open "System Settings"
    # On Tahoe opening System Settings through Spotlight is not very reliable, sometimes opens System information
    "<wait10s>open '/System/Applications/System Settings.app'<enter>",
    "<wait120s>",
    # Navigate to "Sharing"
    "<wait10s><leftCtrlOn><f2><leftCtrlOff><right><right><right><down>Sharing<enter>",
    # Navigate to "Screen Sharing" and enable it
    "<wait10s><tab><tab><tab><tab><tab><spacebar>",
    # Type in the password to allow enabling Screen Sharing
    "<wait10s>admin<enter>",
    # Navigate to "Remote Login" and enable it
    "<wait10s><tab><tab><tab><tab><tab><tab><tab><tab><tab><tab><tab><tab><spacebar>",
    # Quit System Settings
    "<wait10s><leftAltOn>q<leftAltOff>",
    # Disable Gatekeeper (1/2)
    "<wait10s>sudo spctl --global-disable<enter>",
    "<wait10s>admin<enter>",
    # Disable Gatekeeper (2/2)
    # On Tahoe opening System Settings through Spotlight is not very reliable, sometimes opens System information
    "<wait10s>open '/System/Applications/System Settings.app'<enter>",
    "<wait10s><leftCtrlOn><f2><leftCtrlOff><right><right><right><down>Privacy & Security<enter>",
    "<wait10s><leftShiftOn><tab><tab><tab><tab><tab><tab><leftShiftOff>",
    "<wait10s><down><wait1s><down><wait1s><enter>",
    "<wait10s>admin<enter>",
    "<wait10s><leftShiftOn><tab><leftShiftOff><wait1s><spacebar>",
    # Quit System Settings
    "<wait10s><leftAltOn>q<leftAltOff>",
  ]

  // A (hopefully) temporary workaround for Virtualization.Framework's
  // installation process not fully finishing in a timely manner
  create_grace_time = "30s"

  // Keep the recovery partition, otherwise it's not possible to "softwareupdate"
  recovery_partition = "keep"
}

build {
  sources = ["source.tart-cli.tart"]

  provisioner "shell" {
    inline = [
      // Enable passwordless sudo
      "echo admin | sudo -S sh -c \"mkdir -p /etc/sudoers.d/; echo 'admin ALL=(ALL) NOPASSWD: ALL' | EDITOR=tee visudo /etc/sudoers.d/admin-nopasswd\"",
      // Enable auto-login
      //
      // See https://github.com/xfreebird/kcpassword for details.
      "echo '00000000: 1ced 3f4a bcbc ba2c caca 4e82' | sudo xxd -r - /etc/kcpassword",
      "sudo defaults write /Library/Preferences/com.apple.loginwindow autoLoginUser admin",
      // Disable screensaver at login screen
      "sudo defaults write /Library/Preferences/com.apple.screensaver loginWindowIdleTime 0",
      // Disable screensaver for admin user
      "defaults -currentHost write com.apple.screensaver idleTime 0",
      // Prevent the VM from sleeping
      "sudo systemsetup -setsleep Off 2>/dev/null",
      // Launch Safari to populate the defaults
      "/Applications/Safari.app/Contents/MacOS/Safari &",
      "SAFARI_PID=$!",
      "disown",
      "sleep 30",
      "kill -9 $SAFARI_PID",
      // Enable Safari's remote automation
      "sudo safaridriver --enable",
      // Disable screen lock
      //
      // Note that this only works if the user is logged-in,
      // i.e. not on login screen.
      "sysadminctl -screenLock off -password admin",
    ]
  }

  provisioner "shell" {
    inline = [
      # Ensure that Gatekeeper is disabled
      "spctl --status | grep -q 'assessments disabled'"
    ]
  }
}
