## wifikey - a tool to manage distinct PSK keys per client

### How it works

In WPA2-PSK mode, `hostapd` is able to manage different keys for different
devices (identified by their MAC address).  This is done with a PSK file,
which contains MAC/key pairs.  See the hostapd docs for more information.
The `wifikey` tool creates and maintains these PSK files (which are ignored
by LuCI).

For each SSID, there is a `.psk` file and also a `.mac` file where
`wifikey` collects the MAC addresses of connected clients.  When creating a
new key, the known clients are saved with the previously used key in the
`.psk` file.  Other clients then won't be able to use that key.

The files are named after the SSID.  The SSIDs are URL-encoded for safe use
as file names.

WPS also generates individual keys and writes them into the PSK files.  This
is done by `hostapd`.

### Installation requirements

The following packages are required for installing on OpenWrt 23.05:

- Hostapd
    - hostapd or wpad (any variant works)
    - hostapd-utils
- Perl
    - perl
    - perlbase-fcntl
    - perlbase-mime
    - perlbase-open
- uhttpd
    - Other http servers will work but need to be secured appropriately.
- qrencode

### Installing

Create directory `/usr/local/lib/wifikey` and copy everything here into that
directory.

Copy `wifikey` into `/www/cgi-bin`.

Create directory `/etc/wifi`.

Run `wifikey-setup` and follow the instructions given there.

Install a cron job to run `/usr/local/lib/wifikey/wkmacs` every 10 minutes.

Put this line into `/etc/httpd.conf` (create that file if necessary):

	/cgi-bin/wifikey:wifikey:$p$root

Put the following line into `/etc/sysupgrade.conf`:

    /etc/wifi/*

### Configuration

For an interface to be managed with `wifikey`, it must be set up with
WPA2-PSK security.  Devices configured otherwise (e.g.  WPA2-EAP) are
ignored by the tools.  Network device configuration should be complete
before running `wifikey-setup`.  Be very careful with changes afterwards and
verify that everything still fits together.

Make sure the permissions on the `/etc/wifi` directory and its files are
correct.  Both the directory and files must be readable and writable by the
user `hostapd` runs under and the user the CGI script runs under, and
preferrably nobody else. `wifikey-setup` tries to get that right.

##### Security

Anyone who can access the web page created by this tool is able to connect new
devices to your wireless network and deny access to already connected devices.
Care must be taken to make sure this page is protected appropriately.
With the instructions above, you will need to provide the LuCI root password.
It is advisable to use HTTPS only.

### Using

Call [your.router/cgi-bin/wifikey](http://your.router/cgi-bin/wifikey) with
the browser.  Select the right network (SSID) at the top.  The SSID and key
will be shown readably and as QR code.

A new key is generated with the *New key* button.  Select size and format
first.  You can also select to delete the current key, in that case no new
devices will be able to connect until you generate a new key.

The *Stations* button invokes the stations editor, see below.

To connect a device with WPS, first push the appropriate button on the
device, then the *WPS* button in the wifikey dialog.  The latter will blink
to indicate progress and can also be re-pressed to cancel.  Re-keying is not
possible during WPS operation to avoid interference of both mechanisms.

Use the small reload icon at the bottom right if anything gets stuck.

A backup generated from LuCI will contain all the known devices and keys.
It is advisable to regularly generate a backup.

Note that a client, once connected, may not change its MAC address. Some
systems (like GrapheneOS) use a random MAC for every new connection, for
privacy reasons. This feature has to be disabled on the client. Using
per-network random MACs is okay, though.

#### Stations editor

The stations editor shows the list of known associated stations, their
timestamps (when they were first seen) and comments. Note that this list
is updated only when generating a new key.

Each line has the buttons *REV* to revoke a station, *RCL* to restore the
current key to the one used by the selected station, and *UPD* to update
the comment and VLAN ID. *REV* is red when a station is revoked, and may
then be pushed to re-enable the station with its previous key.

A comment is arbitrary but may not contain spaces or special characters,
and is limited to 15 characters. A revoked station gets disconnected and
may not reconnect with its old key (unless re-enabled), but may use the
currently used key.

### Legal

This tool is made available under the license specified in the LICENSE file.
