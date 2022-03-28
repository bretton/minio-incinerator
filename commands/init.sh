#!/usr/bin/env bash

if [ -z "$BASH_VERSION" ]; then
  >&2 echo "This needs to run in bash"
  exit 1
fi

usage()
{
  echo "Usage: mininc init [-hv] [-d flavourdir] [-n network] [-r freebsd_version] incinerator_name

    flavourdir defaults to 'flavours'
    network defaults to '10.100.1'
    freebd_version defaults to '13.0'
"
}

if [ -f config.ini ]; then
    # shellcheck disable=SC1091
    source config.ini
else
    echo "config.ini is missing? Please fix"
    exit 1; exit 1
fi

if [ -z "${ACCESSIP}" ]; then
    echo "ACCESSIP is unset. Please configure web access IP in config.ini"
    exit 1; exit 1
fi

if [ -z "${DISKSIZE}" ]; then
    echo "DISKSIZE is unset. Please configure disk sizes in config.ini"
    exit 1; exit 1
fi

availablespace=$(df "${PWD}" | awk '/[0-9]%/{print $(NF-2)}')
totaldisksize=$(echo "16 * ${DISKSIZE}" |bc -l)

if [ "${totaldisksize}" -ge "${availablespace}" ]; then
    echo "Insufficient disk space for virtual disks of size ${DISKSIZE}. Please reduce the disk size in config.ini or free up some disk space"
    exit 1; exit 1
fi

FREEBSD_VERSION=13.0
FLAVOURS_DIR="flavours"
# Do not change this if using Virtualbox DHCP on primary interface
GATEWAY="10.0.2.2"

# ToDo: get IP, ping a range to find free IP, set ACCESSIP to free IP.
# getmyip()
# {
#     /usr/bin/env perl -MSocket -le 'socket(S, PF_INET, SOCK_DGRAM, getprotobyname(\"udp\")); connect(S, sockaddr_in(1, inet_aton(\"1.1.1.1\"))); print inet_ntoa((sockaddr_in(getsockname(S)))[1]);'
# }

# enable experimental disk support
export VAGRANT_EXPERIMENTAL="disks"

OPTIND=1
while getopts "hvd:n:r:" _o ; do
  case "$_o" in
  d)
    FLAVOURS_DIR="${OPTARG}"
    ;;
  h)
    usage
    exit 0
    ;;
  v)
    # shellcheck disable=SC2034
    VERBOSE="YES"
    ;;
  n)
    NETWORK="${OPTARG}"
    ;;
  r)
    FREEBSD_VERSION="${OPTARG}"
    ;;
  *)
    usage
    exit 1
    ;;
  esac
done

shift "$((OPTIND-1))"

if [ $# -ne 1 ]; then
  usage
  exit 1
fi

NETWORK="$(echo "${NETWORK:=10.100.1}" | awk -F\. '{ print $1"."$2"."$3 }')"
INCINERATOR_NAME="$1"

set -eE
trap 'echo error: $STEP failed' ERR
# shellcheck disable=SC1091
source "${INCLUDE_DIR}/common.sh"
common_init_vars

set -eE
trap 'echo error: $STEP failed' ERR

if [ -z "${INCINERATOR_NAME}" ] || [ -z "${FREEBSD_VERSION}" ]; then
  usage
  exit 1
fi

if [[ ! "${INCINERATOR_NAME}" =~ $INCINERATOR_NAME_REGEX ]]; then
  >&2 echo "invalid incinerator name $INCINERATOR_NAME"
  exit 1
fi

if [[ ! "${FREEBSD_VERSION}" =~ $FREEBSD_VERSION_REGEX ]]; then
  >&2 echo "unsupported freebsd version $FREEBSD_VERSION"
  exit 1
fi

if [[ ! "${NETWORK}" =~ $NETWORK_REGEX ]]; then
  >&2 echo "invalid network $NETWORK (expecting A.B.C, e.g. 10.100.1)"
  exit 1
fi

step "Init incinerator"
mkdir "$INCINERATOR_NAME"
git init "$INCINERATOR_NAME" >/dev/null
cd "$INCINERATOR_NAME"
if [ "$(git branch --show-current)" = "master" ]; then
  git branch -m master main
fi

if [ "${FLAVOURS_DIR}" = "flavours" ]; then
  mkdir flavours
  echo "Place your flavours in this directory" >flavours/README.md
fi

step "Generate SSH key to upload"
ssh-keygen -b 2048 -t rsa -f miniokey -q -N ""

# temp fix
step "Make _build directory as a temporary fix to error which crops up"
mkdir _build/

# temp fix 2 for SSH timeouts on minio3 or minio4
export SSH_AUTH_SOCK=""

# add remote IP to file for ansible read
echo "${ACCESSIP}" > access.ip

# Create ansible site.yml to process once hosts are up
cat >site.yml<<"EOF"
---

- hosts: all
  tasks:
  - name: Build facts from stored UUID values
    set_fact:
      minio_access_ip: "{{ lookup('file', 'access.ip') }}"
      minio1_hostname: minio1
      minio2_hostname: minio2
      minio3_hostname: minio3
      minio4_hostname: minio4
      minio_nat_gateway: 10.100.1.1
      minio1_ip_address: 10.100.1.10
      minio2_ip_address: 10.100.1.20
      minio3_ip_address: 10.100.1.30
      minio4_ip_address: 10.100.1.40
      minio1_disk1: https://10.100.1.10:9000/mnt/minio/disk1
      minio1_disk2: https://10.100.1.10:9000/mnt/minio/disk2
      minio1_disk3: https://10.100.1.10:9000/mnt/minio/disk3
      minio1_disk4: https://10.100.1.10:9000/mnt/minio/disk4
      minio2_disk1: https://10.100.1.20:9000/mnt/minio/disk1
      minio2_disk2: https://10.100.1.20:9000/mnt/minio/disk2
      minio2_disk3: https://10.100.1.20:9000/mnt/minio/disk3
      minio2_disk4: https://10.100.1.20:9000/mnt/minio/disk4
      minio3_disk1: https://10.100.1.30:9000/mnt/minio/disk1
      minio3_disk2: https://10.100.1.30:9000/mnt/minio/disk2
      minio3_disk3: https://10.100.1.30:9000/mnt/minio/disk3
      minio3_disk4: https://10.100.1.30:9000/mnt/minio/disk4
      minio4_disk1: https://10.100.1.40:9000/mnt/minio/disk1
      minio4_disk2: https://10.100.1.40:9000/mnt/minio/disk2
      minio4_disk3: https://10.100.1.40:9000/mnt/minio/disk3
      minio4_disk4: https://10.100.1.40:9000/mnt/minio/disk4
      minio_erasure_coding_collection: https://minio{1...4}:9000/mnt/minio/disk{1...4}
      minio_nameserver: 8.8.8.8
      minio_ssh_key: "~/.ssh/miniokey"
      minio1_ssh_port: 10122
      minio2_ssh_port: 10222
      minio3_ssh_port: 10322
      minio4_ssh_port: 10422
      minio_access_key: demoadmin
      minio_access_password: NP4c2KzyESKCIEsDk2I2Dmb2HAFsGSxec30Uxiqz
      local_minio_disk1: /mnt/minio/disk1
      local_minio_disk2: /mnt/minio/disk2
      local_minio_disk3: /mnt/minio/disk3
      local_minio_disk4: /mnt/minio/disk4
      local_openssl_dir: /usr/local/etc/ssl
      local_openssl_ca_dir: /usr/local/etc/ssl/CAs
      local_openssl_conf: openssl.conf
      local_openssl_root_key: rootca.key
      local_openssl_root_cert: rootca.crt
      local_openssl_private_key: private.key
      local_openssl_public_cert: public.crt
      local_openssl_root_key_size: 8192
      local_openssl_root_key_expiry: 3650
      local_openssl_client_key_size: 4096
      local_openssl_client_key_expiry: 3650
      local_openssl_nginx_cert: bundle.pem

  - name: Wait for port 22 to become open, wait for 2 seconds
    wait_for:
      port: 22
      delay: 2

  - name: Enable root ssh logins and set keep alives
    become: yes
    become_user: root
    shell:
      cmd: |
        sed -i '' \
          -e 's|^#PermitRootLogin no|PermitRootLogin yes|g' \
          -e 's|^#Compression delayed|Compression no|g' \
          -e 's|^#ClientAliveInterval 0|ClientAliveInterval 20|g' \
          -e 's|^#ClientAliveCountMax 3|ClientAliveCountMax 5|g' \
          /etc/ssh/sshd_config

  - name: Restart sshd
    become: yes
    become_user: root
    ansible.builtin.service:
      name: sshd
      state: restarted

  - name: Wait for port 22 to become open, wait for 5 seconds
    wait_for:
      port: 22
      delay: 5

  - name: Add minio hosts to /etc/hosts
    become: yes
    become_user: root
    shell:
      cmd: |
        cat <<EOH >> /etc/hosts
        {{ minio1_ip_address }} {{ minio1_hostname }}
        {{ minio2_ip_address }} {{ minio2_hostname }}
        {{ minio3_ip_address }} {{ minio3_hostname }}
        {{ minio4_ip_address }} {{ minio4_hostname }}
        EOH

  - name: Add dns to resolv.conf
    become: yes
    become_user: root
    shell:
      cmd: |
        echo nameserver {{ minio_nameserver }} >> /etc/resolv.conf

  - name: Create pkg config directory
    become: yes
    become_user: root
    file: path=/usr/local/etc/pkg/repos state=directory mode=0755

  - name: Create pkg config
    become: yes
    become_user: root
    copy:
      dest: /usr/local/etc/pkg/repos/FreeBSD.conf
      content: |
        FreeBSD: { url: "pkg+http://pkg.FreeBSD.org/${ABI}/latest" }

  - name: Upgrade package pkg
    become: yes
    become_user: root
    shell:
      cmd: "pkg upgrade -qy pkg"

  - name: Upgrade packages
    become: yes
    become_user: root
    shell:
      cmd: "pkg upgrade -qy"

  - name: Install common packages
    become: yes
    become_user: root
    ansible.builtin.package:
      name:
        - bash
        - curl
        - nano
        - vim-tiny
        - sudo
        - python38
        - rsync
        - tmux
        - jq
        - ripgrep
        - dmidecode
        - openntpd
        - pftop
        - openssl
        - nginx
        - minio
        - minio-client
        - py38-minio
        - nmap
      state: present

  - name: Enable openntpd
    become: yes
    become_user: root
    ansible.builtin.service:
      name: openntpd
      enabled: yes

  - name: Start openntpd
    become: yes
    become_user: root
    ansible.builtin.service:
      name: openntpd
      state: started

  - name: Disable coredumps
    become: yes
    become_user: root
    sysctl:
      name: kern.coredump
      value: '0'

  - name: Create .ssh directory
    ansible.builtin.file:
      path: /home/vagrant/.ssh
      state: directory
      mode: '0700'
      owner: vagrant
      group: vagrant

  - name: Create root .ssh directory
    ansible.builtin.file:
      path: /root/.ssh
      state: directory
      mode: '0700'
      owner: root
      group: wheel

  - name: copy over ssh private key
    ansible.builtin.copy:
      src: miniokey
      dest: /home/vagrant/.ssh/miniokey
      owner: vagrant
      group: vagrant
      mode: '0600'

  - name: copy over ssh private key to root
    ansible.builtin.copy:
      src: miniokey
      dest: /root/.ssh/miniokey
      owner: root
      group: wheel
      mode: '0600'

  - name: copy over ssh public key
    ansible.builtin.copy:
      src: miniokey.pub
      dest: /home/vagrant/.ssh/miniokey.pub
      owner: vagrant
      group: vagrant
      mode: '0600'

  - name: copy over ssh public key to root
    ansible.builtin.copy:
      src: miniokey.pub
      dest: /root/.ssh/miniokey.pub
      owner: root
      group: wheel
      mode: '0600'

  - name: Append ssh pubkey to authorized_keys
    become: yes
    become_user: vagrant
    shell:
      chdir: /home/vagrant/
      cmd: |
        cat /home/vagrant/.ssh/miniokey.pub >> /home/vagrant/.ssh/authorized_keys

  - name: Append ssh pubkey to authorized_keys for root
    become: yes
    become_user: root
    shell:
      chdir: /root/
      cmd: |
        cat /root/.ssh/miniokey.pub >> /root/.ssh/authorized_keys

  - name: Create directory /usr/local/etc/ssl
    ansible.builtin.file:
      path: "{{ local_openssl_dir }}"
      state: directory
      mode: '0755'
      owner: root
      group: wheel

  - name: Create directory /usr/local/etc/ssl/CAs
    ansible.builtin.file:
      path: "{{ local_openssl_ca_dir }}"
      state: directory
      mode: '0755'
      owner: root
      group: wheel

  - name: Configure minio disk permissions disk 1
    ansible.builtin.file:
      path: "{{ local_minio_disk1 }}"
      state: directory
      mode: '0755'
      owner: minio
      group: minio

  - name: Configure minio disk permissions disk 2
    ansible.builtin.file:
      path: "{{ local_minio_disk2 }}"
      state: directory
      mode: '0755'
      owner: minio
      group: minio

  - name: Configure minio disk permissions disk 3
    ansible.builtin.file:
      path: "{{ local_minio_disk3 }}"
      state: directory
      mode: '0755'
      owner: minio
      group: minio

  - name: Configure minio disk permissions disk 4
    ansible.builtin.file:
      path: "{{ local_minio_disk4 }}"
      state: directory
      mode: '0755'
      owner: minio
      group: minio

- hosts: minio1
  gather_facts: yes
  tasks:
  - name: Wait for port 22 to become open, wait for 2 seconds
    wait_for:
      port: 22
      delay: 2

  - name: Create ssh client config
    become: yes
    become_user: vagrant
    copy:
      dest: /home/vagrant/.ssh/config
      content: |
        Host {{ minio1_hostname }}
          # HostName {{ minio1_ip_address }}
          HostName {{ minio_nat_gateway }}
          StrictHostKeyChecking no
          User vagrant
          IdentityFile ~/.ssh/miniokey
          # Port 22
          Port {{ minio1_ssh_port }}
          Compression no
          ServerAliveInterval 20

        Host {{ minio2_hostname }}
          # HostName {{ minio2_ip_address }}
          HostName {{ minio_nat_gateway }}
          StrictHostKeyChecking no
          User vagrant
          IdentityFile ~/.ssh/miniokey
          # Port 22
          Port {{ minio2_ssh_port }}
          Compression no
          ServerAliveInterval 20

        Host {{ minio3_hostname }}
          # HostName {{ minio3_ip_address }}
          HostName {{ minio_nat_gateway }}
          StrictHostKeyChecking no
          User vagrant
          IdentityFile ~/.ssh/miniokey
          # Port 22
          Port {{ minio3_ssh_port }}
          Compression no
          ServerAliveInterval 20

        Host {{ minio4_hostname }}
          # HostName {{ minio4_ip_address }}
          HostName {{ minio_nat_gateway }}
          StrictHostKeyChecking no
          User vagrant
          IdentityFile ~/.ssh/miniokey
          # Port 22
          Port {{ minio4_ssh_port }}
          Compression no
          ServerAliveInterval 20

  - name: Create ssh client config for root user
    become: yes
    become_user: root
    copy:
      dest: /root/.ssh/config
      content: |
        Host {{ minio1_hostname }}
          # HostName {{ minio1_ip_address }}
          HostName {{ minio_nat_gateway }}
          StrictHostKeyChecking no
          User vagrant
          IdentityFile ~/.ssh/miniokey
          Port {{ minio1_ssh_port }}
          ServerAliveInterval 20

        Host {{ minio2_hostname }}
          # HostName {{ minio2_ip_address }}
          HostName {{ minio_nat_gateway }}
          StrictHostKeyChecking no
          User vagrant
          IdentityFile ~/.ssh/miniokey
          Port {{ minio2_ssh_port }}
          ServerAliveInterval 20

        Host {{ minio3_hostname }}
          # HostName {{ minio3_ip_address }}
          HostName {{ minio_nat_gateway }}
          StrictHostKeyChecking no
          User vagrant
          IdentityFile ~/.ssh/miniokey
          Port {{ minio3_ssh_port }}
          ServerAliveInterval 20

        Host {{ minio4_hostname }}
          # HostName {{ minio4_ip_address }}
          HostName {{ minio_nat_gateway }}
          StrictHostKeyChecking no
          User vagrant
          IdentityFile ~/.ssh/miniokey
          Port {{ minio4_ssh_port }}
          ServerAliveInterval 20

  - name: Setup openssl CA and generate root key
    become: yes
    become_user: root
    shell:
      chdir: "{{ local_openssl_ca_dir }}"
      cmd: |
        openssl genrsa \
          -out {{ local_openssl_root_key }} {{ local_openssl_root_key_size }}

  - name: Setup openssl CA and generate root certificate
    become: yes
    become_user: root
    shell:
      chdir: "{{ local_openssl_ca_dir }}"
      cmd: |
        openssl req \
          -sha256 \
          -new \
          -x509 \
          -days {{ local_openssl_root_key_expiry }} \
          -key {{ local_openssl_root_key }} \
          -out {{ local_openssl_root_cert }} \
          -subj /C=US/ST=None/L=City/O=Organisation/CN={{ minio1_hostname }}

  - name: Wait for port 22 to become open, wait for 2 seconds
    wait_for:
      port: 22
      delay: 2

  - name: Wait for ssh to become available minio2
    become: yes
    become_user: root
    wait_for:
      host: "{{ minio_nat_gateway }}"
      port: "{{ minio1_ssh_port }}"
      delay: 10
      timeout: 90
      state: started

  - name: Run ssh-keyscan on minio2 (mitigating an error that crops up otherwise)
    become: yes
    become_user: root
    shell:
      cmd: |
        ssh-keyscan -T 20 -p 10222 {{ minio_nat_gateway }}

  - name: Wait for port 22 to become open, wait for 2 seconds
    wait_for:
      port: 22
      delay: 2

  - name: Wait for ssh to become available minio2
    become: yes
    become_user: root
    wait_for:
      host: "{{ minio_nat_gateway }}"
      port: "{{ minio2_ssh_port }}"
      delay: 10
      timeout: 90
      state: started

  - name: Copy CA key to minio2
    become: yes
    become_user: root
    shell:
      chdir: "{{ local_openssl_ca_dir }}"
      cmd: |
        rsync -avz {{ local_openssl_root_key }} root@{{ minio2_hostname }}:{{ local_openssl_ca_dir }}/

  - name: Wait for port 22 to become open, wait for 2 seconds
    wait_for:
      port: 22
      delay: 2

  - name: Wait for ssh to become available minio2
    become: yes
    become_user: root
    wait_for:
      host: "{{ minio_nat_gateway}}"
      port: "{{ minio2_ssh_port }}"
      delay: 10
      timeout: 90
      state: started

  - name: Copy CA cert to minio2
    become: yes
    become_user: root
    shell:
      chdir: "{{ local_openssl_ca_dir }}"
      cmd: |
        rsync -avz {{ local_openssl_root_cert }} root@{{ minio2_hostname }}:{{ local_openssl_ca_dir }}/

  - name: Wait for port 22 to become open, wait for 2 seconds
    wait_for:
      port: 22
      delay: 2

  - name: Wait for ssh to become available minio3
    become: yes
    become_user: root
    wait_for:
      host: "{{ minio_nat_gateway }}"
      port: "{{ minio3_ssh_port }}"
      delay: 10
      timeout: 90
      state: started

  - name: Run ssh-keyscan on minio2 (mitigating an error that crops up otherwise)
    become: yes
    become_user: root
    shell:
      cmd: |
        ssh-keyscan -T 20 -p 10322 {{ minio_nat_gateway }}

  - name: Wait for port 22 to become open, wait for 2 seconds
    wait_for:
      port: 22
      delay: 2

  - name: Wait for ssh to become available minio3
    become: yes
    become_user: root
    wait_for:
      host: "{{ minio_nat_gateway }}"
      port: "{{ minio3_ssh_port }}"
      delay: 10
      timeout: 90
      state: started

  - name: Copy CA key to minio3
    become: yes
    become_user: root
    shell:
      chdir: "{{ local_openssl_ca_dir }}"
      cmd: |
        rsync -avz {{ local_openssl_root_key }} root@{{ minio3_hostname }}:{{ local_openssl_ca_dir }}/

  - name: Wait for port 22 to become open, wait for 2 seconds
    wait_for:
      port: 22
      delay: 2

  - name: Wait for ssh to become available minio3
    become: yes
    become_user: root
    wait_for:
      host: "{{ minio_nat_gateway }}"
      port: "{{ minio3_ssh_port }}"
      delay: 10
      timeout: 90
      state: started

  - name: Copy CA cert to minio3
    become: yes
    become_user: root
    shell:
      chdir: "{{ local_openssl_ca_dir }}"
      cmd: |
        rsync -avz {{ local_openssl_root_cert }} root@{{ minio3_hostname }}:{{ local_openssl_ca_dir }}/

  - name: Wait for port 22 to become open, wait for 2 seconds
    wait_for:
      port: 22
      delay: 2

  - name: Wait for ssh to become available minio3
    become: yes
    become_user: root
    wait_for:
      host: "{{ minio_nat_gateway }}"
      port: "{{ minio4_ssh_port }}"
      delay: 10
      timeout: 90
      state: started

  - name: Run ssh-keyscan on minio2 (mitigating an error that crops up otherwise)
    become: yes
    become_user: root
    shell:
      cmd: |
        ssh-keyscan -T 20 -p 10422 {{ minio_nat_gateway }}

  - name: Wait for port 22 to become open, wait for 2 seconds
    wait_for:
      port: 22
      delay: 2

  - name: Wait for ssh to become available minio4
    become: yes
    become_user: root
    wait_for:
      host: "{{ minio_nat_gateway }}"
      port: "{{ minio4_ssh_port }}"
      delay: 10
      timeout: 90
      state: started

  - name: Copy CA key to minio4
    become: yes
    become_user: root
    shell:
      chdir: "{{ local_openssl_ca_dir }}"
      cmd: |
        rsync -avz {{ local_openssl_root_key }} root@{{ minio4_hostname }}:{{ local_openssl_ca_dir }}/

  - name: Wait for port 22 to become open, wait for 2 seconds
    wait_for:
      port: 22
      delay: 2

  - name: Wait for ssh to become available minio4
    become: yes
    become_user: root
    wait_for:
      host: "{{ minio_nat_gateway }}"
      port: "{{ minio4_ssh_port }}"
      delay: 10
      timeout: 90
      state: started

  - name: Copy CA cert to minio4
    become: yes
    become_user: root
    shell:
      chdir: "{{ local_openssl_ca_dir }}"
      cmd: |
        rsync -avz {{ local_openssl_root_cert }} root@{{ minio4_hostname }}:{{ local_openssl_ca_dir }}/

  - name: Wait for port 22 to become open, wait for 2 seconds
    wait_for:
      port: 22
      delay: 2

  - name: Create /usr/local/etc/ssl/openssl.conf on minio1
    become: yes
    become_user: root
    copy:
      dest: "{{ local_openssl_dir }}/{{ local_openssl_conf }}"
      content: |
        basicConstraints = CA:FALSE
        nsCertType = server
        nsComment = "OpenSSL Generated Server Certificate"
        subjectKeyIdentifier = hash
        authorityKeyIdentifier = keyid,issuer:always
        keyUsage = critical, digitalSignature, keyEncipherment
        extendedKeyUsage = serverAuth
        subjectAltName = @alt_names
        [alt_names]
        IP.1 = {{ minio1_ip_address }}
        IP.2 = {{ minio_access_ip }}
        DNS.1 = {{ minio1_hostname }}

  - name: Generate certificates on minio1 round 1
    become: yes
    become_user: root
    shell:
      chdir: "{{ local_openssl_dir }}"
      cmd: |
        openssl genrsa \
          -out {{ local_openssl_private_key }} {{ local_openssl_client_key_size }}

  - name: Set minio ownership private key minio1
    ansible.builtin.file:
      path: "{{ local_openssl_dir }}/{{ local_openssl_private_key }}"
      mode: '0644'
      owner: minio
      group: minio

  - name: Generate certificates on minio1 round 2
    become: yes
    become_user: root
    shell:
      chdir: "{{ local_openssl_dir }}"
      cmd: |
        openssl req -new \
          -key {{ local_openssl_private_key }} \
          -out {{ local_openssl_public_cert }} \
          -subj /C=US/ST=None/L=City/O=Organisation/CN={{ minio1_hostname }}

  - name: Generate certificates on minio1 round 3
    become: yes
    become_user: root
    shell:
      chdir: "{{ local_openssl_dir }}"
      cmd: |
        openssl x509 -req \
          -in {{ local_openssl_public_cert }} \
          -CA CAs/{{ local_openssl_root_cert }} \
          -CAkey CAs/{{ local_openssl_root_key }} \
          -CAcreateserial \
          -out {{ local_openssl_public_cert }} \
          -days {{ local_openssl_client_key_expiry }} \
          -sha256 \
          -extfile {{ local_openssl_conf }}

  - name: Set minio ownership public key minio1
    ansible.builtin.file:
      path: "{{ local_openssl_dir }}/{{ local_openssl_public_cert }}"
      mode: '0644'
      owner: minio
      group: minio

  - name: Create certificate bundle for nginx on minio1
    become: yes
    become_user: root
    shell:
      chdir: "{{ local_openssl_dir }}"
      cmd: |
        cat {{ local_openssl_public_cert }} CAs/{{ local_openssl_root_cert }} >> {{ local_openssl_nginx_cert }}

  - name: Update nginx.conf with proxy
    become: yes
    become_user: root
    copy:
      dest: /usr/local/etc/nginx/nginx.conf
      content: |
        worker_processes  1;
        error_log /var/log/nginx/error.log;
        events {
          worker_connections 1024;
        }
        http {
          include mime.types;
          default_type application/octet-stream;
          sendfile on;
          keepalive_timeout 65;
          gzip off;
          server {                              
            listen 80;
            return 301 https://$host$request_uri;
          } 
          server {
            listen 443 ssl;
            ssl_certificate {{ local_openssl_dir }}/{{ local_openssl_nginx_cert }};
            ssl_certificate_key {{ local_openssl_dir }}/{{ local_openssl_private_key }};
            server_name {{ minio1_hostname }};
            ignore_invalid_headers off;
            client_max_body_size 0;
            proxy_buffering off;
            location / {
              proxy_set_header X-Real-IP $remote_addr;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              proxy_set_header X-Forwarded-Proto $scheme;
              proxy_set_header Host $http_host;
              proxy_connect_timeout 300;
              proxy_http_version 1.1;
              proxy_set_header Connection "";
              chunked_transfer_encoding off;
              proxy_buffering off;
              proxy_ssl_verify off;
              proxy_pass https://{{ minio_nat_gateway }}:10901;
            }
          }
        }

  - name: Enable nginx
    become: yes
    become_user: root
    ansible.builtin.service:
      name: nginx
      enabled: yes

  - name: Start nginx
    become: yes
    become_user: root
    ansible.builtin.service:
      name: nginx
      state: started

  # - name: Enable minio sysrc entries on minio1
  #   become: yes
  #   become_user: root
  #   shell:
  #     cmd: |
  #       service minio enable
  #       sysrc minio_certs="{{ local_openssl_dir }}"
  #       sysrc minio_env="MINIO_ACCESS_KEY={{ minio_access_key }} MINIO_SECRET_KEY={{ minio_access_password }}"
  #       sysrc minio_disks="{{ minio1_disk1 }} {{ minio1_disk2 }} {{ minio1_disk3 }} {{ minio1_disk4 }} {{ minio2_disk1 }} {{ minio2_disk2 }} {{ minio2_disk3 }} {{ minio2_disk4 }} {{ minio3_disk1 }} {{ minio3_disk2 }} {{ minio3_disk3 }} {{ minio3_disk4 }} {{ minio4_disk1 }} {{ minio4_disk2 }} {{ minio4_disk3 }} {{ minio4_disk4 }}"

  - name: Enable minio sysrc entries on minio1
    become: yes
    become_user: root
    shell:
      cmd: |
        service minio enable
        sysrc minio_certs="{{ local_openssl_dir }}"
        sysrc minio_env="MINIO_ACCESS_KEY={{ minio_access_key }} MINIO_SECRET_KEY={{ minio_access_password }}"
        sysrc minio_disks="{{ minio_erasure_coding_collection }}"

- hosts: minio2
  gather_facts: yes
  tasks:
  - name: Wait for port 22 to become open, wait for 2 seconds
    wait_for:
      port: 22
      delay: 2

  - name: Create /usr/local/etc/ssl/openssl.conf on minio2
    become: yes
    become_user: root
    copy:
      dest: "{{ local_openssl_dir }}/{{ local_openssl_conf }}"
      content: |
        basicConstraints = CA:FALSE
        nsCertType = server
        nsComment = "OpenSSL Generated Server Certificate"
        subjectKeyIdentifier = hash
        authorityKeyIdentifier = keyid,issuer:always
        keyUsage = critical, digitalSignature, keyEncipherment
        extendedKeyUsage = serverAuth
        subjectAltName = @alt_names
        [alt_names]
        IP.1 = {{ minio2_ip_address }}
        IP.2 = {{ minio_access_ip }}
        DNS.1 = {{ minio2_hostname }}

  - name: Generate certificates on minio2 round 1
    become: yes
    become_user: root
    shell:
      chdir: "{{ local_openssl_dir }}"
      cmd: |
        openssl genrsa \
          -out {{ local_openssl_private_key }} {{ local_openssl_client_key_size }}

  - name: Set minio ownership private key minio2
    ansible.builtin.file:
      path: "{{ local_openssl_dir }}/{{ local_openssl_private_key }}"
      mode: '0644'
      owner: minio
      group: minio

  - name: Generate certificates on minio2 round 2
    become: yes
    become_user: root
    shell:
      chdir: "{{ local_openssl_dir }}"
      cmd: |
        openssl req -new \
          -key {{ local_openssl_private_key }} \
          -out {{ local_openssl_public_cert }} \
          -subj /C=US/ST=None/L=City/O=Organisation/CN={{ minio2_hostname }}

  - name: Generate certificates on minio2 round 3
    become: yes
    become_user: root
    shell:
      chdir: "{{ local_openssl_dir }}"
      cmd: |
        openssl x509 -req \
          -in {{ local_openssl_public_cert }} \
          -CA CAs/{{ local_openssl_root_cert }} \
          -CAkey CAs/{{ local_openssl_root_key }} \
          -CAcreateserial \
          -out {{ local_openssl_public_cert }} \
          -days {{ local_openssl_client_key_expiry }} \
          -sha256 \
          -extfile {{ local_openssl_conf }}

  - name: Set minio ownership public key minio2
    ansible.builtin.file:
      path: "{{ local_openssl_dir }}/{{ local_openssl_public_cert }}"
      mode: '0644'
      owner: minio
      group: minio

  - name: Create certificate bundle for nginx on minio2
    become: yes
    become_user: root
    shell:
      chdir: "{{ local_openssl_dir }}"
      cmd: |
        cat {{ local_openssl_public_cert }} CAs/{{ local_openssl_root_cert }} >> {{ local_openssl_nginx_cert }}

  # - name: Enable minio sysrc entries on minio2
  #   become: yes
  #   become_user: root
  #   shell:
  #     cmd: |
  #       service minio enable
  #       sysrc minio_certs="{{ local_openssl_dir }}"
  #       sysrc minio_env="MINIO_ACCESS_KEY={{ minio_access_key }} MINIO_SECRET_KEY={{ minio_access_password }}"
  #       sysrc minio_disks="{{ minio1_disk1 }} {{ minio1_disk2 }} {{ minio1_disk3 }} {{ minio1_disk4 }} {{ minio2_disk1 }} {{ minio2_disk2 }} {{ minio2_disk3 }} {{ minio2_disk4 }} {{ minio3_disk1 }} {{ minio3_disk2 }} {{ minio3_disk3 }} {{ minio3_disk4 }} {{ minio4_disk1 }} {{ minio4_disk2 }} {{ minio4_disk3 }} {{ minio4_disk4 }}"

  - name: Enable minio sysrc entries on minio2
    become: yes
    become_user: root
    shell:
      cmd: |
        service minio enable
        sysrc minio_certs="{{ local_openssl_dir }}"
        sysrc minio_env="MINIO_ACCESS_KEY={{ minio_access_key }} MINIO_SECRET_KEY={{ minio_access_password }}"
        sysrc minio_disks="{{ minio_erasure_coding_collection }}"

- hosts: minio3
  gather_facts: yes
  tasks:
  - name: Wait for port 22 to become open, wait for 2 seconds
    wait_for:
      port: 22
      delay: 2

  - name: Create /usr/local/etc/ssl/openssl.conf on minio3
    become: yes
    become_user: root
    copy:
      dest: "{{ local_openssl_dir }}/{{ local_openssl_conf }}"
      content: |
        basicConstraints = CA:FALSE
        nsCertType = server
        nsComment = "OpenSSL Generated Server Certificate"
        subjectKeyIdentifier = hash
        authorityKeyIdentifier = keyid,issuer:always
        keyUsage = critical, digitalSignature, keyEncipherment
        extendedKeyUsage = serverAuth
        subjectAltName = @alt_names
        [alt_names]
        IP.1 = {{ minio3_ip_address }}
        IP.2 = {{ minio_access_ip }}
        DNS.1 = {{ minio3_hostname }}

  - name: Generate certificates on minio3 round 1
    become: yes
    become_user: root
    shell:
      chdir: "{{ local_openssl_dir }}"
      cmd: |
        openssl genrsa \
          -out {{ local_openssl_private_key }} {{ local_openssl_client_key_size }}

  - name: Set minio ownership private key minio3
    ansible.builtin.file:
      path: "{{ local_openssl_dir }}/{{ local_openssl_private_key }}"
      mode: '0644'
      owner: minio
      group: minio

  - name: Generate certificates on minio3 round 2
    become: yes
    become_user: root
    shell:
      chdir: "{{ local_openssl_dir }}"
      cmd: |
        openssl req -new \
          -key {{ local_openssl_private_key }} \
          -out {{ local_openssl_public_cert }} \
          -subj /C=US/ST=None/L=City/O=Organisation/CN={{ minio3_hostname }}

  - name: Generate certificates on minio3 round 3
    become: yes
    become_user: root
    shell:
      chdir: "{{ local_openssl_dir }}"
      cmd: |
        openssl x509 -req \
          -in {{ local_openssl_public_cert }} \
          -CA CAs/{{ local_openssl_root_cert }} \
          -CAkey CAs/{{ local_openssl_root_key }} \
          -CAcreateserial \
          -out {{ local_openssl_public_cert }} \
          -days {{ local_openssl_client_key_expiry }} \
          -sha256 \
          -extfile {{ local_openssl_conf }}

  - name: Set minio ownership public key minio3
    ansible.builtin.file:
      path: "{{ local_openssl_dir }}/{{ local_openssl_public_cert }}"
      mode: '0644'
      owner: minio
      group: minio

  - name: Create certificate bundle for nginx on minio3
    become: yes
    become_user: root
    shell:
      chdir: "{{ local_openssl_dir }}"
      cmd: |
        cat {{ local_openssl_public_cert }} CAs/{{ local_openssl_root_cert }} >> {{ local_openssl_nginx_cert }}

  # - name: Enable minio sysrc entries on minio3
  #   become: yes
  #   become_user: root
  #   shell:
  #     cmd: |
  #       service minio enable
  #       sysrc minio_certs="{{ local_openssl_dir }}"
  #       sysrc minio_env="MINIO_ACCESS_KEY={{ minio_access_key }} MINIO_SECRET_KEY={{ minio_access_password }}"
  #       sysrc minio_disks="{{ minio1_disk1 }} {{ minio1_disk2 }} {{ minio1_disk3 }} {{ minio1_disk4 }} {{ minio2_disk1 }} {{ minio2_disk2 }} {{ minio2_disk3 }} {{ minio2_disk4 }} {{ minio3_disk1 }} {{ minio3_disk2 }} {{ minio3_disk3 }} {{ minio3_disk4 }} {{ minio4_disk1 }} {{ minio4_disk2 }} {{ minio4_disk3 }} {{ minio4_disk4 }}"

  - name: Enable minio sysrc entries on minio3
    become: yes
    become_user: root
    shell:
      cmd: |
        service minio enable
        sysrc minio_certs="{{ local_openssl_dir }}"
        sysrc minio_env="MINIO_ACCESS_KEY={{ minio_access_key }} MINIO_SECRET_KEY={{ minio_access_password }}"
        sysrc minio_disks="{{ minio_erasure_coding_collection }}"

- hosts: minio4
  gather_facts: yes
  tasks:
  - name: Wait for port 22 to become open, wait for 2 seconds
    wait_for:
      port: 22
      delay: 2

  - name: Create /usr/local/etc/ssl/openssl.conf on minio4
    become: yes
    become_user: root
    copy:
      dest: "{{ local_openssl_dir }}/{{ local_openssl_conf }}"
      content: |
        basicConstraints = CA:FALSE
        nsCertType = server
        nsComment = "OpenSSL Generated Server Certificate"
        subjectKeyIdentifier = hash
        authorityKeyIdentifier = keyid,issuer:always
        keyUsage = critical, digitalSignature, keyEncipherment
        extendedKeyUsage = serverAuth
        subjectAltName = @alt_names
        [alt_names]
        IP.1 = {{ minio4_ip_address }}
        IP.2 = {{ minio_access_ip }}
        DNS.1 = {{ minio4_hostname }}

  - name: Generate certificates on minio4 round 1
    become: yes
    become_user: root
    shell:
      chdir: "{{ local_openssl_dir }}"
      cmd: |
        openssl genrsa \
          -out {{ local_openssl_private_key }} {{ local_openssl_client_key_size }}

  - name: Set minio ownership private key minio4
    ansible.builtin.file:
      path: "{{ local_openssl_dir }}/{{ local_openssl_private_key }}"
      mode: '0644'
      owner: minio
      group: minio

  - name: Generate certificates on minio4 round 2
    become: yes
    become_user: root
    shell:
      chdir: "{{ local_openssl_dir }}"
      cmd: |
        openssl req -new \
          -key {{ local_openssl_private_key }} \
          -out {{ local_openssl_public_cert }} \
          -subj /C=US/ST=None/L=City/O=Organisation/CN={{ minio4_hostname }}

  - name: Generate certificates on minio4 round 3
    become: yes
    become_user: root
    shell:
      chdir: "{{ local_openssl_dir }}"
      cmd: |
        openssl x509 -req \
          -in {{ local_openssl_public_cert }} \
          -CA CAs/{{ local_openssl_root_cert }} \
          -CAkey CAs/{{ local_openssl_root_key }} \
          -CAcreateserial \
          -out {{ local_openssl_public_cert }} \
          -days {{ local_openssl_client_key_expiry }} \
          -sha256 \
          -extfile {{ local_openssl_conf }}

  - name: Set minio ownership public key minio4
    ansible.builtin.file:
      path: "{{ local_openssl_dir }}/{{ local_openssl_public_cert }}"
      mode: '0644'
      owner: minio
      group: minio

  - name: Create certificate bundle for nginx on minio4
    become: yes
    become_user: root
    shell:
      chdir: "{{ local_openssl_dir }}"
      cmd: |
        cat {{ local_openssl_public_cert }} CAs/{{ local_openssl_root_cert }} >> {{ local_openssl_nginx_cert }}

  # - name: Enable minio sysrc entries on minio4
  #   become: yes
  #   become_user: root
  #   shell:
  #     cmd: |
  #       service minio enable
  #       sysrc minio_certs="{{ local_openssl_dir }}"
  #       sysrc minio_env="MINIO_ACCESS_KEY={{ minio_access_key }} MINIO_SECRET_KEY={{ minio_access_password }}"
  #       sysrc minio_disks="{{ minio1_disk1 }} {{ minio1_disk2 }} {{ minio1_disk3 }} {{ minio1_disk4 }} {{ minio2_disk1 }} {{ minio2_disk2 }} {{ minio2_disk3 }} {{ minio2_disk4 }} {{ minio3_disk1 }} {{ minio3_disk2 }} {{ minio3_disk3 }} {{ minio3_disk4 }} {{ minio4_disk1 }} {{ minio4_disk2 }} {{ minio4_disk3 }} {{ minio4_disk4 }}"

  - name: Enable minio sysrc entries on minio4
    become: yes
    become_user: root
    shell:
      cmd: |
        service minio enable
        sysrc minio_certs="{{ local_openssl_dir }}"
        sysrc minio_env="MINIO_ACCESS_KEY={{ minio_access_key }} MINIO_SECRET_KEY={{ minio_access_password }}"
        sysrc minio_disks="{{ minio_erasure_coding_collection }}"

- hosts: all
  gather_facts: yes
  tasks:
  - name: Start minio
    become: yes
    become_user: root
    ansible.builtin.service:
      name: minio
      state: started

# - hosts: minio2
#   gather_facts: yes
#   tasks:
#   - name: Start minio
#     become: yes
#     become_user: root
#     ansible.builtin.service:
#       name: minio
#       state: started
EOF

step "Create Vagrantfile"
cat >Vagrantfile<<EOV
# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|
  config.vm.define "minio1", primary: true do |node|
    node.vm.hostname = 'minio1'
    node.vm.boot_timeout = 600
    node.vm.box = "FreeBSD-${FREEBSD_VERSION}-RELEASE-amd64"
    node.vm.synced_folder '.', '/vagrant', disabled: true
    node.ssh.forward_agent = false
    node.vm.communicator = "ssh"
    node.ssh.connect_timeout = 60
    node.ssh.keep_alive = true
    node.vm.provider "virtualbox" do |vb|
      vb.memory = "4096"
      vb.cpus = "4"
      vb.customize ["modifyvm", :id, "--ioapic", "on"]
      vb.customize ["modifyvm", :id, "--vrde", "off"]
      vb.customize ["modifyvm", :id, "--audio", "none"]
      vb.customize ["createhd", "--filename", "minio1-disk1.vdi", "--size", "${DISKSIZE}"]
      vb.customize ["storageattach", :id, "--storagectl", "SATA Controller", "--port", 1, "--device", 0, "--type", "hdd", "--medium", "minio1-disk1.vdi"]
      vb.customize ["createhd", "--filename", "minio1-disk2.vdi", "--size", "${DISKSIZE}"]
      vb.customize ["storageattach", :id, "--storagectl", "SATA Controller", "--port", 2, "--device", 0, "--type", "hdd", "--medium", "minio1-disk2.vdi"]
      vb.customize ["createhd", "--filename", "minio1-disk3.vdi", "--size", "${DISKSIZE}"]
      vb.customize ["storageattach", :id, "--storagectl", "SATA Controller", "--port", 3, "--device", 0, "--type", "hdd", "--medium", "minio1-disk3.vdi"]
      vb.customize ["createhd", "--filename", "minio1-disk4.vdi", "--size", "${DISKSIZE}"]
      vb.customize ["storageattach", :id, "--storagectl", "SATA Controller", "--port", 4, "--device", 0, "--type", "hdd", "--medium", "minio1-disk4.vdi"]
      vb.customize ["modifyvm", :id, "--nictype1", "virtio"]
      vb.customize ["modifyvm", :id, "--nictype2", "virtio"]
      vb.customize ["modifyvm", :id, "--nictype3", "virtio"]
      vb.customize ["modifyvm", :id, "--nicpromisc1", "allow-all"]
      vb.customize ["modifyvm", :id, "--nicpromisc2", "allow-all"]
      vb.customize ["modifyvm", :id, "--nicpromisc3", "allow-all"]
      vb.customize ["setextradata", :id,
        "VBoxInternal/Devices/ahci/0/LUN#[0]/Config/IgnoreFlush", "0"]
      vb.default_nic_type = "virtio"
    node.vm.network :forwarded_port, guest: 22, host_ip: "${NETWORK}.1",
      host: 10122, id: "minio1-ssh"
    node.vm.network :forwarded_port, guest: 9000, host_ip: "${NETWORK}.1",
      host: 10901, id: "minio1-minio"
    end
    node.vm.network :private_network, ip: "${NETWORK}.10", auto_config: false
    node.vm.network :public_network, ip: "${ACCESSIP}", auto_config: false
    node.vm.provision "shell", run: "always", inline: <<-SHELL
      sysrc ipv6_network_interfaces="none"
      sysrc ifconfig_vtnet0_name="untrusted"
      sysrc defaultrouter="${GATEWAY}"
      sysrc gateway_enable="YES"
      sysrc ifconfig_vtnet1="inet ${NETWORK}.10 netmask 255.255.255.0"
      sysrc ifconfig_vtnet2="inet ${ACCESSIP} netmask 255.255.255.0"
      sysctl -w net.inet.tcp.msl=3000
      echo "net.inet.tcp.msl=3000" >> /etc/sysctl.conf
      echo 'interface "vtnet0" { supersede domain-name-servers 8.8.8.8; }' >> /etc/dhclient.conf
      service netif restart && service routing restart
      ping -c 1 google.com
      mkdir -p /mnt/minio
      gpart create -s GPT ada1
      gpart add -t freebsd-zfs -l minio-disk1 ada1
      zpool create -o feature@livelist=disabled -o feature@zstd_compress=disabled -o feature@log_spacemap=disabled -m /mnt/minio/disk1 minio-disk1 ada1p1
      gpart create -s GPT ada2
      gpart add -t freebsd-zfs -l minio-disk2 ada2
      zpool create -o feature@livelist=disabled -o feature@zstd_compress=disabled -o feature@log_spacemap=disabled -m /mnt/minio/disk2 minio-disk2 ada2p1
      gpart create -s GPT ada3
      gpart add -t freebsd-zfs -l minio-disk3 ada3
      zpool create -o feature@livelist=disabled -o feature@zstd_compress=disabled -o feature@log_spacemap=disabled -m /mnt/minio/disk3 minio-disk3 ada3p1
      gpart create -s GPT ada4
      gpart add -t freebsd-zfs -l minio-disk4 ada4
      zpool create -o feature@livelist=disabled -o feature@zstd_compress=disabled -o feature@log_spacemap=disabled -m /mnt/minio/disk4 minio-disk4 ada4p1
    SHELL
  end
  config.vm.define "minio2", primary: false do |node|
    node.vm.hostname = 'minio2'
    node.vm.boot_timeout = 600
    node.vm.box = "FreeBSD-${FREEBSD_VERSION}-RELEASE-amd64"
    node.vm.synced_folder '.', '/vagrant', disabled: true
    node.ssh.forward_agent = false
    node.vm.communicator = "ssh"
    node.ssh.connect_timeout = 60
    node.ssh.keep_alive = true
    node.vm.provider "virtualbox" do |vb|
      vb.memory = "4096"
      vb.cpus = "4"
      vb.customize ["modifyvm", :id, "--ioapic", "on"]
      vb.customize ["modifyvm", :id, "--vrde", "off"]
      vb.customize ["modifyvm", :id, "--audio", "none"]
      vb.customize ["createhd", "--filename", "minio2-disk1.vdi", "--size", "${DISKSIZE}"]
      vb.customize ["storageattach", :id, "--storagectl", "SATA Controller", "--port", 1, "--device", 0, "--type", "hdd", "--medium", "minio2-disk1.vdi"]
      vb.customize ["createhd", "--filename", "minio2-disk2.vdi", "--size", "${DISKSIZE}"]
      vb.customize ["storageattach", :id, "--storagectl", "SATA Controller", "--port", 2, "--device", 0, "--type", "hdd", "--medium", "minio2-disk2.vdi"]
      vb.customize ["createhd", "--filename", "minio2-disk3.vdi", "--size", "${DISKSIZE}"]
      vb.customize ["storageattach", :id, "--storagectl", "SATA Controller", "--port", 3, "--device", 0, "--type", "hdd", "--medium", "minio2-disk3.vdi"]
      vb.customize ["createhd", "--filename", "minio2-disk4.vdi", "--size", "${DISKSIZE}"]
      vb.customize ["storageattach", :id, "--storagectl", "SATA Controller", "--port", 4, "--device", 0, "--type", "hdd", "--medium", "minio2-disk4.vdi"]
      vb.customize ["modifyvm", :id, "--nictype1", "virtio"]
      vb.customize ["modifyvm", :id, "--nictype2", "virtio"]
      vb.customize ["modifyvm", :id, "--nicpromisc1", "allow-all"]
      vb.customize ["modifyvm", :id, "--nicpromisc2", "allow-all"]
      vb.customize ["setextradata", :id,
        "VBoxInternal/Devices/ahci/0/LUN#[0]/Config/IgnoreFlush", "0"]
      vb.default_nic_type = "virtio"
    node.vm.network :forwarded_port, guest: 22, host_ip: "${NETWORK}.1",
      host: 10222, id: "minio2-ssh"
    node.vm.network :forwarded_port, guest: 9000, host_ip: "${NETWORK}.1",
      host: 10902, id: "minio2-minio"
    end
    node.vm.network :private_network, ip: "${NETWORK}.20", auto_config: false
    node.vm.provision "shell", run: "always", inline: <<-SHELL
      sysrc ipv6_network_interfaces="none"
      sysrc ifconfig_vtnet0_name="untrusted"
      sysrc defaultrouter="${GATEWAY}"
      sysrc gateway_enable="YES"
      sysrc ifconfig_vtnet1="inet ${NETWORK}.20 netmask 255.255.255.0"
      sysctl -w net.inet.tcp.msl=3000
      echo "net.inet.tcp.msl=3000" >> /etc/sysctl.conf
      echo 'interface "vtnet0" { supersede domain-name-servers 8.8.8.8; }' >> /etc/dhclient.conf
      service netif restart && service routing restart
      ping -c 1 google.com
      mkdir -p /mnt/minio
      gpart create -s GPT ada1
      gpart add -t freebsd-zfs -l minio-disk1 ada1
      zpool create -o feature@livelist=disabled -o feature@zstd_compress=disabled -o feature@log_spacemap=disabled -m /mnt/minio/disk1 minio-disk1 ada1p1
      gpart create -s GPT ada2
      gpart add -t freebsd-zfs -l minio-disk2 ada2
      zpool create -o feature@livelist=disabled -o feature@zstd_compress=disabled -o feature@log_spacemap=disabled -m /mnt/minio/disk2 minio-disk2 ada2p1
      gpart create -s GPT ada3
      gpart add -t freebsd-zfs -l minio-disk3 ada3
      zpool create -o feature@livelist=disabled -o feature@zstd_compress=disabled -o feature@log_spacemap=disabled -m /mnt/minio/disk3 minio-disk3 ada3p1
      gpart create -s GPT ada4
      gpart add -t freebsd-zfs -l minio-disk4 ada4
      zpool create -o feature@livelist=disabled -o feature@zstd_compress=disabled -o feature@log_spacemap=disabled -m /mnt/minio/disk4 minio-disk4 ada4p1
    SHELL
  end
  config.vm.define "minio3", primary: false do |node|
    node.vm.hostname = 'minio3'
    node.vm.boot_timeout = 600
    node.vm.box = "FreeBSD-${FREEBSD_VERSION}-RELEASE-amd64"
    node.vm.synced_folder '.', '/vagrant', disabled: true
    node.ssh.forward_agent = false
    node.vm.communicator = "ssh"
    node.ssh.connect_timeout = 60
    node.ssh.keep_alive = true
    node.vm.provider "virtualbox" do |vb|
      vb.memory = "4096"
      vb.cpus = "4"
      vb.customize ["modifyvm", :id, "--ioapic", "on"]
      vb.customize ["modifyvm", :id, "--vrde", "off"]
      vb.customize ["modifyvm", :id, "--audio", "none"]
      vb.customize ["createhd", "--filename", "minio3-disk1.vdi", "--size", "${DISKSIZE}"]
      vb.customize ["storageattach", :id, "--storagectl", "SATA Controller", "--port", 1, "--device", 0, "--type", "hdd", "--medium", "minio3-disk1.vdi"]
      vb.customize ["createhd", "--filename", "minio3-disk2.vdi", "--size", "${DISKSIZE}"]
      vb.customize ["storageattach", :id, "--storagectl", "SATA Controller", "--port", 2, "--device", 0, "--type", "hdd", "--medium", "minio3-disk2.vdi"]
      vb.customize ["createhd", "--filename", "minio3-disk3.vdi", "--size", "${DISKSIZE}"]
      vb.customize ["storageattach", :id, "--storagectl", "SATA Controller", "--port", 3, "--device", 0, "--type", "hdd", "--medium", "minio3-disk3.vdi"]
      vb.customize ["createhd", "--filename", "minio3-disk4.vdi", "--size", "${DISKSIZE}"]
      vb.customize ["storageattach", :id, "--storagectl", "SATA Controller", "--port", 4, "--device", 0, "--type", "hdd", "--medium", "minio3-disk4.vdi"]
      vb.customize ["modifyvm", :id, "--nictype1", "virtio"]
      vb.customize ["modifyvm", :id, "--nictype2", "virtio"]
      vb.customize ["modifyvm", :id, "--nicpromisc1", "allow-all"]
      vb.customize ["modifyvm", :id, "--nicpromisc2", "allow-all"]
      vb.customize ["setextradata", :id,
        "VBoxInternal/Devices/ahci/0/LUN#[0]/Config/IgnoreFlush", "0"]
      vb.default_nic_type = "virtio"
    node.vm.network :forwarded_port, guest: 22, host_ip: "${NETWORK}.1",
      host: 10322, id: "minio3-ssh"
    node.vm.network :forwarded_port, guest: 9000, host_ip: "${NETWORK}.1",
      host: 10903, id: "minio3-minio"
    end
    node.vm.network :private_network, ip: "${NETWORK}.30", auto_config: false
    node.vm.provision "shell", run: "always", inline: <<-SHELL
      sysrc ipv6_network_interfaces="none"
      sysrc ifconfig_vtnet0_name="untrusted"
      sysrc defaultrouter="${GATEWAY}"
      sysrc gateway_enable="YES"
      sysrc ifconfig_vtnet1="inet ${NETWORK}.30 netmask 255.255.255.0"
      sysctl -w net.inet.tcp.msl=3000
      echo "net.inet.tcp.msl=3000" >> /etc/sysctl.conf
      echo 'interface "vtnet0" { supersede domain-name-servers 8.8.8.8; }' >> /etc/dhclient.conf
      service netif restart && service routing restart
      ping -c 1 google.com
      mkdir -p /mnt/minio
      gpart create -s GPT ada1
      gpart add -t freebsd-zfs -l minio-disk1 ada1
      zpool create -o feature@livelist=disabled -o feature@zstd_compress=disabled -o feature@log_spacemap=disabled -m /mnt/minio/disk1 minio-disk1 ada1p1
      gpart create -s GPT ada2
      gpart add -t freebsd-zfs -l minio-disk2 ada2
      zpool create -o feature@livelist=disabled -o feature@zstd_compress=disabled -o feature@log_spacemap=disabled -m /mnt/minio/disk2 minio-disk2 ada2p1
      gpart create -s GPT ada3
      gpart add -t freebsd-zfs -l minio-disk3 ada3
      zpool create -o feature@livelist=disabled -o feature@zstd_compress=disabled -o feature@log_spacemap=disabled -m /mnt/minio/disk3 minio-disk3 ada3p1
      gpart create -s GPT ada4
      gpart add -t freebsd-zfs -l minio-disk4 ada4
      zpool create -o feature@livelist=disabled -o feature@zstd_compress=disabled -o feature@log_spacemap=disabled -m /mnt/minio/disk4 minio-disk4 ada4p1
    SHELL
  end
  config.vm.define "minio4", primary: false do |node|
    node.vm.hostname = 'minio4'
    node.vm.boot_timeout = 600
    node.vm.box = "FreeBSD-${FREEBSD_VERSION}-RELEASE-amd64"
    node.vm.synced_folder '.', '/vagrant', disabled: true
    node.ssh.forward_agent = false
    node.vm.communicator = "ssh"
    node.ssh.connect_timeout = 60
    node.ssh.keep_alive = true
    node.vm.provider "virtualbox" do |vb|
      vb.memory = "4096"
      vb.cpus = "4"
      vb.customize ["modifyvm", :id, "--ioapic", "on"]
      vb.customize ["modifyvm", :id, "--vrde", "off"]
      vb.customize ["modifyvm", :id, "--audio", "none"]
      vb.customize ["createhd", "--filename", "minio4-disk1.vdi", "--size", "${DISKSIZE}"]
      vb.customize ["storageattach", :id, "--storagectl", "SATA Controller", "--port", 1, "--device", 0, "--type", "hdd", "--medium", "minio4-disk1.vdi"]
      vb.customize ["createhd", "--filename", "minio4-disk2.vdi", "--size", "${DISKSIZE}"]
      vb.customize ["storageattach", :id, "--storagectl", "SATA Controller", "--port", 2, "--device", 0, "--type", "hdd", "--medium", "minio4-disk2.vdi"]
      vb.customize ["createhd", "--filename", "minio4-disk3.vdi", "--size", "${DISKSIZE}"]
      vb.customize ["storageattach", :id, "--storagectl", "SATA Controller", "--port", 3, "--device", 0, "--type", "hdd", "--medium", "minio4-disk3.vdi"]
      vb.customize ["createhd", "--filename", "minio4-disk4.vdi", "--size", "${DISKSIZE}"]
      vb.customize ["storageattach", :id, "--storagectl", "SATA Controller", "--port", 4, "--device", 0, "--type", "hdd", "--medium", "minio4-disk4.vdi"]
      vb.customize ["modifyvm", :id, "--nictype1", "virtio"]
      vb.customize ["modifyvm", :id, "--nictype2", "virtio"]
      vb.customize ["modifyvm", :id, "--nicpromisc1", "allow-all"]
      vb.customize ["modifyvm", :id, "--nicpromisc2", "allow-all"]
      vb.customize ["setextradata", :id,
        "VBoxInternal/Devices/ahci/0/LUN#[0]/Config/IgnoreFlush", "0"]
      vb.default_nic_type = "virtio"
    node.vm.network :forwarded_port, guest: 22, host_ip: "${NETWORK}.1",
      host: 10422, id: "minio4-ssh"
    node.vm.network :forwarded_port, guest: 9000, host_ip: "${NETWORK}.1",
      host: 10904, id: "minio4-minio"
    end
    node.vm.network :private_network, ip: "${NETWORK}.40", auto_config: false
    node.vm.provision "shell", run: "always", inline: <<-SHELL
      sysrc ipv6_network_interfaces="none"
      sysrc ifconfig_vtnet0_name="untrusted"
      sysrc defaultrouter="${GATEWAY}"
      sysrc gateway_enable="YES"
      sysrc ifconfig_vtnet1="inet ${NETWORK}.40 netmask 255.255.255.0"
      sysctl -w net.inet.tcp.msl=3000
      echo "net.inet.tcp.msl=3000" >> /etc/sysctl.conf
      echo 'interface "vtnet0" { supersede domain-name-servers 8.8.8.8; }' >> /etc/dhclient.conf
      service netif restart && service routing restart
      ping -c 1 google.com
      mkdir -p /mnt/minio
      gpart create -s GPT ada1
      gpart add -t freebsd-zfs -l minio-disk1 ada1
      zpool create -o feature@livelist=disabled -o feature@zstd_compress=disabled -o feature@log_spacemap=disabled -m /mnt/minio/disk1 minio-disk1 ada1p1
      gpart create -s GPT ada2
      gpart add -t freebsd-zfs -l minio-disk2 ada2
      zpool create -o feature@livelist=disabled -o feature@zstd_compress=disabled -o feature@log_spacemap=disabled -m /mnt/minio/disk2 minio-disk2 ada2p1
      gpart create -s GPT ada3
      gpart add -t freebsd-zfs -l minio-disk3 ada3
      zpool create -o feature@livelist=disabled -o feature@zstd_compress=disabled -o feature@log_spacemap=disabled -m /mnt/minio/disk3 minio-disk3 ada3p1
      gpart create -s GPT ada4
      gpart add -t freebsd-zfs -l minio-disk4 ada4
      zpool create -o feature@livelist=disabled -o feature@zstd_compress=disabled -o feature@log_spacemap=disabled -m /mnt/minio/disk4 minio-disk4 ada4p1
    SHELL
    node.vm.provision 'ansible' do |ansible|
      ansible.compatibility_mode = '2.0'
      ansible.limit = 'all'
      ansible.playbook = 'site.yml'
      ansible.become = true
      ansible.verbose = ''
      ansible.config_file = 'ansible.cfg'
      ansible.raw_ssh_args = "-o ControlMaster=no -o IdentitiesOnly=yes -o ConnectionAttempts=20 -o ConnectTimeout=60 -o ServerAliveInterval=20"
      ansible.raw_arguments = [	"--timeout=1000" ]
      ansible.groups = {
        "all" => [ "minio1", "minio2", "minio3", "minio4" ],
        "all:vars" => {
          "ansible_python_interpreter" => "/usr/local/bin/python"
        },
      }
    end
  end
end
EOV

step "Create potman.ini"
cat >potman.ini<<EOP
[incinerator]
name="${INCINERATOR_NAME}"
vm_manager="vagrant"
freebsd_version="${FREEBSD_VERSION}"
network="${NETWORK}"
gateway="${GATEWAY}"
flavours_dir="${FLAVOURS_DIR}"
EOP

step "Creating ansible.cfg"
cat >ansible.cfg<<EOCFG
[defaults]
host_key_checking = False
timeout = 30
log_path = ansible.log
[ssh_connection]
retries=10
EOCFG


step "Create gitignore file"
cat >.gitignore<<EOG
*~
.vagrant
_build
ansible.tgz
ansible.log
ansible.cfg
pubkey.asc
secret.asc
id_rsa
id_rsa.pub
miniokey
miniokey.pub
EOG

step "Success"

echo "Created incinerator ${INCINERATOR_NAME}"
