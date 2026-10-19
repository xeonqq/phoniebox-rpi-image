# phoniebox-image

Custom Raspberry Pi 3 image (built with [rpi-image-gen](../rpi-image-gen))
that ships a fully pre-configured [Phoniebox](../RPi-Jukebox-RFID) which
installs itself on first boot.

## Layout

| Path | Purpose |
| --- | --- |
| `config/phoniebox-pi3.yaml` | Image build config (device `rpi3`, user credentials, packages incl. `network-manager` pkg) |
| `layer/phoniebox.yaml` | Custom mmdebstrap layer with Phoniebox base packages + network stack setup (NetworkManager only) |
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

The RFID reader registration is non-interactive (it defaults to
`rc522_spi` / MFRC522 via SPI with standard wiring: CE0, IRQ=GPIO24,
RST=GPIO25). To change the default reader type, set
`RFID_READER_NAME=<module>` in `preseed.env` (e.g. for a different
hardware module), or register it later interactively over SSH:

```
cd ~/RPi-Jukebox-RFID && installation/components/setup_rfid_reader.sh
```

## Network stack

NetworkManager is the **only** network manager of the image. The base
image (`trixie-minbase`) ships `systemd-networkd` + `iwd` and the
`dnsmasq` package enables its own daemon — all three break the hotspot:

* `systemd-networkd` configures `wlan0` itself (`02-wlan0.network`) and
  needs `iwd` for WiFi.
* `iwd` takes the WiFi device over via netifd and blocks
  wpa_supplicant / NetworkManager.
* the standalone `dnsmasq` binds `0.0.0.0:53` and clashes with the
  dnsmasq instance NetworkManager starts for the hotspot
  (`ipv4.method shared` → `--listen-address=10.0.0.1`).

`layer/phoniebox.yaml` therefore enables `NetworkManager.service` and
disables `systemd-networkd`, `systemd-networkd.socket`, `iwd` and
`dnsmasq` at build time, removes `02-wlan0.network` and pins the WiFi
backend to `wpa_supplicant`
(`/etc/NetworkManager/conf.d/99-phoniebox-wifi.conf`).

The `network-manager` *layer* of rpi-image-gen cannot be used for this:
it provides the `network-activator` capability which is already provided
by `systemd-net-min` (required by `trixie-minbase`) → provider conflict
at build time. The package is installed instead and configured in the
custom layer.

## First-boot flow

1. NetworkManager becomes the active (and only) network manager.
2. If the box is wired and gets internet within 30 s, the installation
   starts right away.
3. If the boot partition contains `phoniebox-wifi.conf`
   (`SSID=`, `PSK=`, optional `COUNTRY=`), the device joins that WiFi
   (up to 120 s).
4. Otherwise a temporary bootstrap hotspot is opened **immediately**
   (default SSID `Phoniebox_Setup`, password `PlayItLoud!` — see
   preseed) and stays up until the box has internet.
5. Once the device has internet, the Phoniebox installation runs
   unattended (20–60 min) and the box reboots.

To configure the home WiFi from the bootstrap hotspot, either use the
setup portal (`http://10.0.0.1/` — the phone/computer has to be
connected to the `Phoniebox_Setup` hotspot) or SSH in:

```
ssh phoniebox@10.0.0.1          # password from config/phoniebox-pi3.yaml
sudo phoniebox-wifi-setup "MyHomeSSID" "MyHomePassword" DE
```

Note: while the WiFi device is an access point it cannot scan for other
networks, so the list of nearby networks in the portal is often empty —
type the SSID manually. Activating the home WiFi closes the hotspot.

After the box reboots it behaves like a normal Phoniebox, including the
upstream Auto-Hotspot (`Phoniebox_Hotspot_phoniebox` / `PlayItLoud!`)
whenever it cannot reach a known WiFi (Web App: `http://phoniebox.local`).

## Building

```
cd ../rpi-image-gen
./rpi-image-gen build -S ../phoniebox-image -c ../phoniebox-image/config/phoniebox-pi3.yaml
```

### Disk space

`rpi-image-gen` keeps the chroot and the deploy directory of every build in
`<rpi-image-gen>/work`. A build needs roughly 9 GB (chroot ~1.6 GB, image
~6 GB, deploy ~1.2 GB), so on a small SD card the second build already
runs out of space and dies with

```
E: Sub-process env returned an error code (1)
... /tmp/apt-dpkg-install-XXXX/41-docker.io_..._arm64.deb
```

Free the space of the previous builds before building again (needs root,
the directories belong to the build user):

```
sudo ../phoniebox-image/scripts/clean-build-space.sh ../rpi-image-gen
```

## Logs on the device

* First boot: `/var/log/phoniebox-firstboot.log`
* Installer: `/home/phoniebox/INSTALL-*.log`

The first-boot log contains the output of every `nmcli` call — if the
`Phoniebox_Setup` hotspot does not show up, this is the place to look
(typical causes: `wlan0` is not managed by NetworkManager, the WiFi
device does not support AP mode, or the driver is still busy with a
previous network manager).
