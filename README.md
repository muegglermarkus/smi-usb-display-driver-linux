# SMI USB Display Driver – Linux Installer

Automated installer for **SMI USB Display drivers** on Linux (Ubuntu 26.04+, Kernel 7.x).

Builds [`evdi`](https://github.com/DisplayLink/evdi) from source, registers it with **DKMS** (so it survives kernel updates), and runs the proprietary SMI `.run` installer automatically.

> **Background:** The SMI installer ships with a broken `dkms.conf` for newer kernels. This script works around that by building evdi manually from the latest GitHub source and creating a corrected DKMS configuration.

---

## Requirements

### System
- Ubuntu 26.04+ (or compatible distro with `apt`)
- Kernel 7.x (tested on `7.0.0-10-generic`)
- `sudo` / root access
- Internet connection (to clone evdi from GitHub)

### Secure Boot
If Secure Boot is enabled, the script will check your MOK (Machine Owner Key) status before proceeding:

- **MOK key missing** → script aborts with setup instructions
- **MOK key not yet enrolled in UEFI** → script asks whether to continue anyway  
  *(driver installs, but USB display won't work until after reboot + MOK enrollment)*
- **MOK key enrolled** → everything works automatically

To enroll your MOK key (if not done yet):

```bash
sudo mokutil --import /var/lib/shim-signed/mok/MOK.der
sudo reboot
# → In the blue UEFI screen: "Enroll MOK" → enter your password
```

If Secure Boot is **disabled**, no MOK setup is needed.

### SMI Driver File
The file `SMIUSBDisplay-driver.x.x.x.x.run` must be downloaded **separately** – it is proprietary and not included in this repository.

1. Visit the SMI support page or your hardware distributor
2. Search for **USB Display Driver** under Support → Drivers
3. Download the `.run` file and place it in the same directory as the install script

---

## Installation

```bash
# 1. Clone this repository
git clone https://github.com/YOUR_USERNAME/smi-usb-display-driver-linux.git
cd smi-usb-display-driver-linux

# 2. Make the script executable
chmod +x SMI-USB-Display-install.sh

# 3. Run as root, passing the path to the SMI .run file
sudo ./SMI-USB-Display-install.sh /path/to/SMIUSBDisplay-driver.x.x.x.x.run
```

### What the script does

| Step | Description |
|------|-------------|
| 0 | Checks Secure Boot status and MOK key enrollment |
| 1 | Installs build dependencies (`build-essential`, `dkms`, `git`, `libdrm-dev`, kernel headers) |
| 2 | Verifies kernel headers are present |
| 3 | Clones `evdi` from GitHub |
| 4 | Builds the `evdi` kernel module from source |
| 5 | Installs the `evdi` module and registers it with DKMS (auto-reinstall on kernel updates) |
| 6 | Runs the proprietary SMI `.run` installer |
| 7 | Cleans up temporary files |

After installation, **reboot your system**:

```bash
sudo reboot
```

---

## Advanced Usage

### Override evdi version

By default the script uses a pinned version. To use a different one:

```bash
EVDI_VERSION=1.15.0 sudo ./SMI-USB-Display-install.sh ./SMIUSBDisplay-driver.x.x.x.x.run
```

---

## Troubleshooting

### Secure Boot: `Key was rejected by service`

This means Secure Boot is active and the MOK key is not yet enrolled in the UEFI firmware.

```bash
# Check Secure Boot status
mokutil --sb-state

# Check if MOK key is already enrolled
mokutil --test-key /var/lib/shim-signed/mok/MOK.der

# Enroll the key (if not yet done)
sudo mokutil --import /var/lib/shim-signed/mok/MOK.der
sudo reboot
# → Blue UEFI screen: "Enroll MOK" → enter password
```

### `evdi` not loaded after install

This is normal if the module was compiled but not yet activated. After reboot it will be loaded automatically. You can verify:

```bash
lsmod | grep evdi
```

### DKMS build fails

Check the DKMS log for details:

```bash
cat /var/lib/dkms/evdi/<VERSION>/build/make.log
```

### Kernel headers not found

Make sure headers for your running kernel are installed:

```bash
sudo apt install linux-headers-$(uname -r)
```

---

## Tested Environment

| Component | Version |
|-----------|---------|
| OS | Ubuntu 26.04 Beta |
| Kernel | `7.0.0-10-generic` |
| evdi | `1.14.11` |
| SMI Driver | `2.24.7.0` |

---

## License

This install script is released under the **MIT License** – see [`LICENSE`](LICENSE) for details.

The SMI USB Display driver itself is **proprietary software** owned by Silicon Motion Inc. This repository contains no SMI driver code.