#!/bin/bash
mkdir -p /mnt/hugepages1G
mount -t hugetlbfs -o pagesize=1G none /mnt/hugepages1G
mkdir -p /mnt/huge
(mount | grep hugetlbfs) > /dev/null || mount -t hugetlbfs nodev /mnt/huge
for i in {0..7}
do
	if [[ -e "/sys/devices/system/node/node$i" ]]
	then
		echo 512 > /sys/devices/system/node/node$i/hugepages/hugepages-2048kB/nr_hugepages
	fi
done

