# Introduction
`minio-incinerator` (aka `mininc`) borrows heavily from `potman`, `clusterfurnace` and `cephsmelter` to build a virtualbox minio cluster .

Do not run in production! This is a testing environment to show minio running on FreeBSD.

# Outline
This will bring up 4 minio servers, configured for erasure coding, with a web interface:
* minio1 (2CPU, 4GB, 4 attached disks, nginx reverse proxy host)
* minio2 (2CPU, 4GB, 4 attached disks)
* minio3 (2CPU, 4GB, 4 attached disks)
* minio4 (2CPU, 4GB, 4 attached disks)

# Requirements
The host computer running `minio-incinerator` needs at least 12 CPU threads, 24GB memory, plus 200GB disk space, preferably high speed SSD.

# Overview

## Quickstart
To create your own incinerator, init the VMs:

    git clone https://github.com/bretton/minio-incinerator.git
    cd minio-incinerator

      (edit) config.ini and set ACCESSIP to a free IP on LAN, and set DISKSIZE

    export PATH=$(pwd)/bin:$PATH
    mininc init -d "$(pwd)/flavours" mycluster
    cd mycluster
    mininc packbox
    mininc startvms
    ...
    mininc status
    ...

## Stopping

    mininc stopvms

## Destroying

    mininc destroyvms

## Dependencies

`minio-incinerator` requires
- ansible
- bash
- git
- packer
- vagrant
- virtualbox

# Installation and Operation

## FreeBSD

(todo: add steps from https://docs.freebsd.org/en/books/handbook/virtualization/#virtualization-host-virtualbox )

Install packages, start services and configure permissions and networks
```
pkg install bash git packer py38-ansible py38-packaging vagrant virtualbox-ose
service vboxnet enable
service vboxnet start
    
(sudo) pw groupmod vboxusers -m <username>

mkdir -p /etc/vbox
vi /etc/vbox/networks.conf
```

(add, with asterisk; this is extremely broad)
```
* 0.0.0.0/0
```

Add to /etc/rc.conf because the host needs to be a router for private networks in Virtualbox to get internet access
```
gateway_enable="YES"
```

Restart networking (may pause ssh session for a bit)
```
sudo service netif restart && sudo service routing restart
```

edit .profile, add the following, adjusting for username
```
PATH=/home/<username>/minio-incinerator/bin:$PATH; export PATH
```

Download and configure minio-incinerator:
```
git clone https://github.com/bretton/minio-incinerator
cd minio-incinerator

  (edit) config.ini and set ACCESSIP to a free IP on LAN, and set DISKSIZE

export PATH=$(pwd)/bin:$PATH
mininc init -v -d "$(pwd)/flavours" mycluster
cd mycluster
mininc packbox
mininc startvms

  vagrant ssh minio1   
  vagrant ssh minio2
  vagrant ssh minio3
  vagrant ssh minio4
```

## Ubuntu 20.04 with Virtualbox
Install necessary packages
```
sudo apt-get install curl wget -y
sudo apt-get install ruby-full -y   # Ubuntu 20.04 is Ruby 2.7

sudo add-apt-repository ppa:git-core/ppa -y
sudo apt-get update
sudo apt-get install git -y

sudo apt-get install ansible virtualbox -y

curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
sudo apt-get update && sudo apt-get install packer vagrant
```

Download and configure minio-incinerator:
```
git clone https://github.com/bretton/minio-incinerator.git
cd minio-incinerator

  (edit) config.ini and set ACCESSIP to a free IP on LAN, and set DISKSIZE

export PATH=$(pwd)/bin:$PATH
mininc init -v -d "$(pwd)/flavours" mycluster
cd mycluster
mininc packbox
mininc startvms

  vagrant ssh minio1   
  vagrant ssh minio2
  vagrant ssh minio3
  vagrant ssh minio4
```

# Usage

    Usage: mininc command [options]

    Commands:
        destroyvms  -- Destroy VMs
        export      -- Export Vagrant .box files
        help        -- Show usage
        init        -- Initialize new minio-incinerator
        packbox     -- Create vm box image
        startvms    -- Start (and provision) VMs
        status      -- Show status
        stopvms     -- Stop VMs

## Minio Dashboard

The Minio web interface is available on via nginx reverse proxy at https://ACCESSIP for the IP address set in ACCESSIP variable of `config.ini`.

Accept the self-signed certificate TWICE. First is for nginx, second minio. Remember, this is not a production-ready environment. 

Login with user "admin" and password "demopassword" to access the dashboard.

You can now create a bucket and explore settings.

## config.ini

### Access IP

A virtual interface is created with a free IP address from the LAN. You must provide this free IP address in `config.ini` in the `ACCESSIP` section.

### Disk Sizes

Virtual disks are saved in the `minio-incinerator` directory for the duration of running the program. 

Set the size of the virtual disks in `config.ini` in the `DISKSIZE` section. 

Input disk size in thousands of MB, where 10000 (MB) is the same as 10GB. 

To set a 20GB disk, use 20000.

Do not add the metric M, or MB or GB! It won't work.

Sixteen (16) virtual drives will be created of this size, so ensure you have sufficient disk space!

A basic check is done to see if the input figures can be catered to, on init.

