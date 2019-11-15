# How to extend a LVM partition

## LVM partitions

The Index VM appliance shipped by NetGovern is configured to use Logical Volume Manager as the device mapper.  This configuration allows to add virtual disk into a single pool and extend the file system without any downtime.

### Add a virtual disk to your VM

The new disk size should equal the extra disk space that is going to be added.  We have added a 50GB new disk for this guide.

### Re scan the scsi bus

The command `find /sys -type f -iname "scan" -print` should give you the list of the scsi hosts.

Example:

```bash
find /sys -type f -iname "scan" -print
/sys/devices/pci0000:00/0000:00:07.1/ata1/host1/scsi_host/host1/scan
/sys/devices/pci0000:00/0000:00:07.1/ata2/host2/scsi_host/host2/scan
/sys/devices/pci0000:00/0000:00:10.0/host0/scsi_host/host0/scan
/sys/module/scsi_mod/parameters/scan
```

To force a rescan, run the following as root:

```bash
echo "- - -" > /sys/devices/pci0000:00/0000:00:07.1/ata1/host1/scsi_host/host1/scan
echo "- - -" > /sys/devices/pci0000:00/0000:00:07.1/ata2/host2/scsi_host/host2/scan
echo "- - -" > /sys/devices/pci0000:00/0000:00:10.0/host0/scsi_host/host0/scan
```

The following one-liner re scans all of the hosts:

```bash
ARRAY1=$(find /sys -type f -iname "scan" -exec bash -c 'echo {} | grep host' \;);for i in $ARRAY1; do echo "- - -" > $i ; done
```

After the commands have run, the new disk should be listed.  Run the command `lsblk` as root:

```bash
lsblk
NAME          MAJ:MIN RM   SIZE RO TYPE MOUNTPOINT
fd0             2:0    1     4K  0 disk
sda             8:0    0   200G  0 disk
|-sda1          8:1    0  1000M  0 part /boot
`-sda2          8:2    0   199G  0 part
  |-vg1-lv001 253:0    0  48.8G  0 lvm  /
  |-vg1-lv003 253:1    0    34G  0 lvm  [SWAP]
  `-vg1-lv002 253:2    0 116.2G  0 lvm  /var
sdb             8:16   0    50G  0 disk
sr0            11:0    1  1024M  0 rom
```

The above example shows a 50GB disk, shown as **sdb**

### Identify the device name to be extended

Assuming no modifications have been made to the Index server disk system, the device mapped to the /var mount point should be named: /dev/mapper/vg1-lv002

Confirm it by running the commanf `df -h` as root:

```bash
df -h
Filesystem             Size  Used Avail Use% Mounted on
/dev/mapper/vg1-lv001   48G  2.4G   44G   6% /
devtmpfs               3.9G     0  3.9G   0% /dev
tmpfs                  3.9G     0  3.9G   0% /dev/shm
tmpfs                  3.9G   33M  3.8G   1% /run
tmpfs                  3.9G     0  3.9G   0% /sys/fs/cgroup
/dev/sda1              969M  197M  707M  22% /boot
/dev/mapper/vg1-lv002  113G  637M  106G   1% /var
tmpfs                  783M     0  783M   0% /run/user/1000
```

In the example above, the following line shows the name and disk space details:
**/dev/mapper/vg1-lv002  113G  637M  106G   1% /var**

In the appliance provided by NetGovern, the indexes are stored within /var/netmail.  If this was changed after, search for the line matching the mount point containing the solr indexes.

### Create the physical partition for the new disk

Using the fdisk utility, run `fdisk <newdisk device name>`:

```bash
fdisk /dev/sdb
Welcome to fdisk (util-linux 2.23.2).

Changes will remain in memory only, until you decide to write them.
Be careful before using the write command.

Device does not contain a recognized partition table
Building a new DOS disklabel with disk identifier 0x191a1e64.
```

Enter: "p" to create a new partition

```bash
Command (m for help): p

Disk /dev/sdb: 53.7 GB, 53687091200 bytes, 104857600 sectors
Units = sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes
Disk label type: dos
Disk identifier: 0x191a1e64

   Device Boot      Start         End      Blocks   Id  System
```

Enter: "n", p and hit [ENTER] to select the default values when asked

```bash
Command (m for help): n
Partition type:
   p   primary (0 primary, 0 extended, 4 free)
   e   extended
Select (default p): p
Partition number (1-4, default 1):
First sector (2048-104857599, default 2048):
Using default value 2048
Last sector, +sectors or +size{K,M,G} (2048-104857599, default 104857599):
Using default value 104857599
Partition 1 of type Linux and of size 50 GiB is set
```

Enter: "t" and then L to get the list of partition codes.  The partition type should be **8e** "Linux LVM"

```bash
Command (m for help): t
Selected partition 1
Hex code (type L to list all codes): L

 0  Empty           24  NEC DOS         81  Minix / old Lin bf  Solaris
 1  FAT12           27  Hidden NTFS Win 82  Linux swap / So c1  DRDOS/sec (FAT-
 2  XENIX root      39  Plan 9          83  Linux           c4  DRDOS/sec (FAT-
 3  XENIX usr       3c  PartitionMagic  84  OS/2 hidden C:  c6  DRDOS/sec (FAT-
 4  FAT16 <32M      40  Venix 80286     85  Linux extended  c7  Syrinx
 5  Extended        41  PPC PReP Boot   86  NTFS volume set da  Non-FS data
 6  FAT16           42  SFS             87  NTFS volume set db  CP/M / CTOS / .
 7  HPFS/NTFS/exFAT 4d  QNX4.x          88  Linux plaintext de  Dell Utility
 8  AIX             4e  QNX4.x 2nd part 8e  Linux LVM       df  BootIt
 9  AIX bootable    4f  QNX4.x 3rd part 93  Amoeba          e1  DOS access
 a  OS/2 Boot Manag 50  OnTrack DM      94  Amoeba BBT      e3  DOS R/O
 b  W95 FAT32       51  OnTrack DM6 Aux 9f  BSD/OS          e4  SpeedStor
 c  W95 FAT32 (LBA) 52  CP/M            a0  IBM Thinkpad hi eb  BeOS fs
 e  W95 FAT16 (LBA) 53  OnTrack DM6 Aux a5  FreeBSD         ee  GPT
 f  W95 Extd (LBA) 54  OnTrackDM6      a6  OpenBSD         ef  EFI (FAT-12/16/
10  OPUS            55  EZ-Drive        a7  NeXTSTEP        f0  Linux/PA-RISC b
11  Hidden FAT12    56  Golden Bow      a8  Darwin UFS      f1  SpeedStor
12  Compaq diagnost 5c  Priam Edisk     a9  NetBSD          f4  SpeedStor
14  Hidden FAT16 <3 61  SpeedStor       ab  Darwin boot     f2  DOS secondary
16  Hidden FAT16    63  GNU HURD or Sys af  HFS / HFS+      fb  VMware VMFS
17  Hidden HPFS/NTF 64  Novell Netware  b7  BSDI fs         fc  VMware VMKCORE
18  AST SmartSleep  65  Novell Netware  b8  BSDI swap       fd  Linux raid auto
1b  Hidden W95 FAT3 70  DiskSecure Mult bb  Boot Wizard hid fe  LANstep
1c  Hidden W95 FAT3 75  PC/IX           be  Solaris boot    ff  BBT
1e  Hidden W95 FAT1 80  Old Minix
Hex code (type L to list all codes): 8e
Changed type of partition 'Linux' to 'Linux LVM'
```

Enter: "w" to write the changes

```bash
Command (m for help): w
The partition table has been altered!

Calling ioctl() to re-read partition table.
Syncing disks.
```

Running the following command should output the newly created partition:

```bash
fdisk -l /dev/sdb

Disk /dev/sdb: 53.7 GB, 53687091200 bytes, 104857600 sectors
Units = sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes
Disk label type: dos
Disk identifier: 0x191a1e64

   Device Boot      Start         End      Blocks   Id  System
/dev/sdb1            2048   104857599    52427776   8e  Linux LVM
```

### LVM Configuration

Run the command `partprobe`.  It shouldn't output any results

```bash
partprobe
```

The command `pvdisplay` will show the LVM volumes:

```bash
pvdisplay
  --- Physical volume ---
  PV Name               /dev/sda2
  VG Name               vg1
  PV Size               199.02 GiB / not usable 3.00 MiB
  Allocatable           yes (but full)
  PE Size               4.00 MiB
  Total PE              50949
  Free PE               0
  Allocated PE          50949
  PV UUID               3tQJ5I-Qzk7-gkmF-mebm-0EsY-eOjR-Sk3NQb
```

The new device needs to be created as LVM volume.  Run the command `pvcreate` as root:

```bash
pvcreate /dev/sdb1
  Physical volume "/dev/sdb1" successfully created.
```

`pvdisplay` will show the new disk:

```bashpvdisplay
  --- Physical volume ---
  PV Name               /dev/sda2
  VG Name               vg1
  PV Size               199.02 GiB / not usable 3.00 MiB
  Allocatable           yes (but full)
  PE Size               4.00 MiB
  Total PE              50949
  Free PE               0
  Allocated PE          50949
  PV UUID               3tQJ5I-Qzk7-gkmF-mebm-0EsY-eOjR-Sk3NQb

  "/dev/sdb1" is a new physical volume of "<50.00 GiB"
  --- NEW Physical volume ---
  PV Name               /dev/sdb1
  VG Name
  PV Size               <50.00 GiB
  Allocatable           NO
  PE Size               0
  Total PE              0
  Free PE               0
  Allocated PE          0
  PV UUID               f3yfXa-0zpO-QBC8-I9OV-DvPm-l0ss-oe9wdS
```

It will also show the "VG Name": vg1 (default for NetGovern appliances).  This is needed fot he next step.
Using the command `vgextend <vg name> <new partition>` as root:

```bash
vgextend vg1 /dev/sdb1
  Volume group "vg1" successfully extended
```

Run `pvdisplay` again should show that the new Physical Volume belongs to the Volume Group vg1:

```bash
pvdisplay
  --- Physical volume ---
  PV Name               /dev/sda2
  VG Name               vg1
  PV Size               199.02 GiB / not usable 3.00 MiB
  Allocatable           yes (but full)
  PE Size               4.00 MiB
  Total PE              50949
  Free PE               0
  Allocated PE          50949
  PV UUID               3tQJ5I-Qzk7-gkmF-mebm-0EsY-eOjR-Sk3NQb

  --- Physical volume ---
  PV Name               /dev/sdb1
  VG Name               vg1
  PV Size               <50.00 GiB / not usable 3.00 MiB
  Allocatable           yes
  PE Size               4.00 MiB
  Total PE              12799
  Free PE               12799
  Allocated PE          0
  PV UUID               f3yfXa-0zpO-QBC8-I9OV-DvPm-l0ss-oe9wdS
```

### Extend the lvm partition

We need to extend the logical partition.  In this case `/dev/mapper/vg1-lv002` taken from the output of `df -h`.
The command syntax is: `lvextend -L <size to increase> <lvm partition>`

```bash
lvextend -L +50G /dev/mapper/vg1-lv002
  Insufficient free space: 12800 extents needed, but only 12799 available
```

If you get a message like the above, run it again, adding less than the physical disk size.

```bash
lvextend -L +49G /dev/mapper/vg1-lv002
  Size of logical volume vg1/lv002 changed from 116.19 GiB (29745 extents) to 165.19 GiB (42289 extents).
  Logical volume vg1/lv002 successfully resized.
```

Confirm the new size running the command `pvscan`:

```bash
pvscan
  PV /dev/sda2   VG vg1             lvm2 [<199.02 GiB / 0    free]
  PV /dev/sdb1   VG vg1             lvm2 [<50.00 GiB / 1020.00 MiB free]
  Total: 2 [<249.02 GiB] / in use: 2 [<249.02 GiB] / in no VG: 0 [0   ]
```

Now we need to resize the filesystem, using `resize2fs <lvm partition>`:

```bash
resize2fs /dev/mapper/vg1-lv002
resize2fs 1.42.9 (28-Dec-2013)
Filesystem at /dev/mapper/vg1-lv002 is mounted on /var; on-line resizing required
old_desc_blocks = 15, new_desc_blocks = 21
The filesystem on /dev/mapper/vg1-lv002 is now 43303936 blocks long.
```

`df -h` will show space usage updated

```bash
df -h
Filesystem             Size  Used Avail Use% Mounted on
/dev/mapper/vg1-lv001   48G  2.4G   44G   6% /
devtmpfs               3.9G     0  3.9G   0% /dev
tmpfs                  3.9G     0  3.9G   0% /dev/shm
tmpfs                  3.9G   33M  3.8G   1% /run
tmpfs                  3.9G     0  3.9G   0% /sys/fs/cgroup
/dev/sda1              969M  197M  707M  22% /boot
/dev/mapper/vg1-lv002  160G  644M  152G   1% /var
tmpfs                  783M     0  783M   0% /run/user/1000
```