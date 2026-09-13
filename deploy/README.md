# Cisterns server deployment

The public server is a headless instance of the same Godot build as the client.
It listens on UDP port `6026` and hosts one authoritative two-player match.

Installed paths on the current VDS:

- executable: `/opt/cisterns/Cisterns.x86_64`;
- project pack: `/opt/cisterns/Cisterns.pck`;
- systemd unit: `/etc/systemd/system/cisterns.service`;
- runtime log: `/var/lib/cisterns/server.log`.
- log rotation: `/etc/logrotate.d/cisterns` (four compressed files, rotation at
  least weekly or after 1 MiB).

Useful administration commands:

```sh
systemctl status cisterns
journalctl -u cisterns
systemctl restart cisterns
```

The unit runs as a dynamic unprivileged user, restarts after a failure, is
limited to 50% of one CPU and 320 MiB of memory. The VDS also has a dedicated
256 MiB swap file at `/swapfile-cisterns`.

## Linux build

Until the full 4.7.2 export-template archive is installed, the portable Linux
build consists of the matching Godot executable and a project PCK with the same
base name. Build it with:

```sh
./deploy/build_linux.sh /path/to/Godot_v4.7.2-stable_linux.x86_64
```

Run `build/linux/Cisterns.x86_64`; it discovers `Cisterns.pck` beside itself.
Both files must be distributed together.

Headless connection smoke test flags are available for deployment checks:

```sh
./Cisterns.x86_64 --headless -- --connect-public --auto-ready
```

The solo path can be checked without UI with `--headless -- --solo`.
