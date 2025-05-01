# Snapshotter Infrastructure

The instances performing the snapshots are running on dedicated Hetzner servers (Protocol Support account).

### List of servers

kurtosis-sync-test:
- `kt-sync-test` (65.21.238.80/2a01:4f9:6a:4daa::/64  - #EX44 #2672971) ( 2x 512 GB NVMe SSD + 1 TB NVMe SSD)


## Other notes

### OS Installation on Hetzner and Raid 0

```
installimage -a -f yes -r yes -l 0 -i images/Debian-bookworm-latest-amd64-base.tar.gz -n debian -p /boot/efi:esp:256M,/boot:ext3:1024M,/:ext4:all
```
