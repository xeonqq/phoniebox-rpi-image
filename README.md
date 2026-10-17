# phoniebox-image

Custom Raspberry Pi 3 image (built with [rpi-image-gen](../rpi-image-gen))
that ships a fully pre-configured [Phoniebox](../RPi-Jukebox-RFID) which
installs itself on first boot.

## Layout

| Path | Purpose |
| --- | --- |
| `config/phoniebox-pi3.yaml` | Image build config (device `rpi3`, user credentials, packages, `network-manager` layer) |
| `layer/phoniebox.yaml` | Custom mmdebstrap layer with Phoniebox base packages |
| `hooks/customize90-phoniebox` | Build hook: clones the Phoniebox source into `/opt/Phoniebox` and enables the first-boot service |
| `rootfs-overlay/` | Files dropped into the image rootfs (first-boot service + scripts + preseed) |

## Login credentials

Set in `config/phoniebox-pi3.yaml` (`device.user1` / `device.user1pass`).
Default: user `phoniebox`, password `Phoniebox1!` — change before building!
The password must satisfy rpi-image-gen's policy (>=8 chars, lower+upper,
digit, special char from `@$!%*?&`).

## Pre-selecting the interactive installer options

The upstream `install-jukebox.sh` is interactive. Instead of piping
answers, `rootfs-overlay/usr/local/sbin/phoniebox-install-unattended`
sources the upstream installer routines directly and skips the three
interactive entry points (`welcome()`, `customize_options()`, `finish()`).
All option variables come from
`rootfs-overlay/etc/phoniebox-image/preseed.env` — edit that file to
change hotspot SSID/password, RFID reader, Samba, WebApp, kiosk mode, etc.

The RFID reader registration is inherently interactive (it needs the
reader type), so it is disabled by default (`ENABLE_RFID_READER=false`).
Register your reader later over SSH:

```
cd ~/RPi-Jukebox-RFID && installation/components/setup_rfid_reader.sh
```

## First-boot flow

1. NetworkManager becomes the active network manager.
2. If the boot partition contains `phoniebox-wifi.conf`
   (`SSID=`, `PSK=`, optional `COUNTRY=`), the device joins that WiFi.
3. Otherwise a temporary bootstrap hotspot is opened (default SSID
   `Phoniebox_Setup`, password `PlayItLoud!` — see preseed).
4. Once the device has internet, the Phoniebox installation runs
   unattended (20–60 min) and the box reboots.

To configure the home WiFi from the bootstrap hotspot:

```
ssh phoniebox@10.0.0.1          # password from config/phoniebox-pi3.yaml
sudo phoniebox-wifi-setup "MyHomeSSID" "MyHomePassword" DE
```

After the box reboots it behaves like a normal Phoniebox, including the
upstream Auto-Hotspot (`Phoniebox_Hotspot_phoniebox` / `PlayItLoud!`)
whenever it cannot reach a known WiFi (Web App: `http://phoniebox.local`).

## Building

```
cd ../rpi-image-gen
./rpi-image-gen build -S ../phoniebox-image -c ../phoniebox-image/config/phoniebox-pi3.yaml
```

## Logs on the device

* First boot: `/var/log/phoniebox-firstboot.log`
* Installer: `/home/phoniebox/INSTALL-*.log`