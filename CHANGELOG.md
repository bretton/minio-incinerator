0.6

* Live on github
* README updates

---

0.5

* Cluster with 4 nodes, 4 drives each
* Boots with erasure coding config
* Updated README

---

0.4

* Generated certificate & key needs minio:minio ownership explicitly set
* Fixed nginx proxy, certificates need multiple IPs set
* Current version is 4 node cluster with 2 disks each, optimal would be 4 disks each

---

0.3

* Fixed bunch of bugs in previous version

---

0.2

* Use rsync instead of scp to copy SSL files between servers, else host verification errors
* Added lots of checks for ssh due to timeouts
* first working version with 2 pools, 2 servers each, 2 disks per server

---

0.1

* First bash at minio-incinerator, drawing inspiration from potman, clusterfurnace, cephsmelter and making adjustments
* Brings up 4 virtual machines, SSH connection issues syncing certificates around
