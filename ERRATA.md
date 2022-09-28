# FreeBSD

## Hosts which underwent an upgrade from 13.0 to 13.1

On hosts which have upgraded from 13.0 to 13.1, the virtualbox driver gives the following error:
```
VBoxHeadless: Error -1908 in suplibOsInit!
VBoxHeadless: Kernel driver not installed

VBoxHeadless: Tip! Make sure the kernel module is loaded. It may also help to reinstall VirtualBox.
```

To fix this, you need to recompile the `virtualbox-ose-kmod` driver. This is a slightly lengthy process as follows:
```
git clone https://github.com/freebsd/freebsd-src /usr/src
git clone https://git.freebsd.org/ports.git /usr/ports
cd /usr/ports/
git checkout 2022Q2
cd /usr/ports/emulators/virtualbox-ose-kmod
make clean deinstall reinstall
```

Accept the default options for all the dialogue screens. It will take a short while to compile everything. On success you'll see:
```
===> Staging rc.d startup script(s)
===>  Installing for virtualbox-ose-kmod-6.1.36
===>  Checking if virtualbox-ose-kmod is already installed
===>   Registering installation for virtualbox-ose-kmod-6.1.36
Installing virtualbox-ose-kmod-6.1.36...
The vboxdrv kernel module uses internal kernel APIs.

To avoid crashes due to kernel incompatibility, this module will only
load on FreeBSD 13.1 kernels.
```

Finally reboot, and confirm working with
```
vboxheadless --version
```
