#platform=x86, AMD64, or Intel EM64T
#version=DEVEL
# Install OS instead of upgrade
install
# Firewall configuration
firewall --enabled --ssh --http
# Use network installation
url --url=$tree
# If any cobbler repo definitions were referenced in the kickstart profile, include them here.
$yum_repo_stanza
# Network information
network  --bootproto=dhcp --device=eth0
# Root password
rootpw --plaintext ovirt
# System authorization information
auth  --useshadow  --passalgo=md5
# Use graphical install
graphical
firstboot --disable
xconfig --startxonboot
# System keyboard
keyboard us
# System language
lang en_US.UTF-8
# SELinux configuration
selinux --permissive
services --enabled sshd,httpd
user --name=ovirtadm --groups=ovirtadm,wheel --password=ovirt
# Installation logging level
logging --level=debug

# System timezone
timezone  Etc/UTC
# System bootloader configuration
bootloader --location=mbr
# Partition clearing information
clearpart --all  
autopart --type=lvm

reboot

%packages --excludedocs
@admin-tools
@base-x
@editors
@fonts
@input-methods
@system-tools
@xfce-desktop
@xfce-desktop
chkconfig
firefox
fpaste
hostname
iptables
leafpad
net-tools
openssh-server
ovirt-engine
ovirt-engine-cli
spice-vdagent
spice-xpi
system-config-firewall-base
-cadaver
-elinks
-empathy
-evolution-NetworkManager
-evolution-help
-fetchmail
-freeipa-server
-icedtea-web
-mutt
-transmission-gtk
%end

%post

## EDIT HERE ##
cd /root
if ! test -d .ssh; then
  mkdir --mode=700 .ssh
fi
cat >> .ssh/authorized_keys << END_AUTHORIZED_KEYS
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDQmD6mdIkZp4aD54Q/1OQVLMf27xA8M2p6/xWEfCNmLh1zGa5+O97g/3RKjEY5hLEku30miLWVNXlHvOu83mrBOJ+fuYb3rmgl0anPZmvH6zZJ1BCDbFQyLegugoNjzFhPDb/32nyRfhNGQUeZpiaAz7TMsI1tsbqxnKo0Kdkhk2IJwISJ/ZtrDJ1PC3dOSnmKNbMmeoc7ZIccxdr0yz6KOUzc5PkRryZTVY+PS4ucCSXuJugR332DDsLazi0ewphcfHSXghMHRCLwQJQrPMR7xmakzB2VL2VabcEj6tIKAuLcCG/oy1iyeOSJne74QyVWtja/pjZGupwe/fQH0zPb mark@localhost.localdomain
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDORU5MbDinpwHfMbqIVQcMb/gQ3KNEtJWEkCQhjOIUpOb86Lh8x/aG7ppokUaWWgqsM7BUSwXfS4h0qXAilKjrCElJHxicjxiHVTFkaqCbDPvzwWwoMpKxBAIhxJdAW5M4Mm6xry70AFREIX1XgGm6mQ3nlfKNVLWLHyysCPLWTb9V8gVyV8T4t3vCH5EFnr5LSQOy9ihNo7wXa9x0PgLbXsOkOWQTOp1g3osrvQWCFI/82jM7+4OOyJGv0ZtUBe5lEJMgwJtslOJVs6q9cTF4RfQN964QFsyPinsvVfU/eaFNp5kH+QcxzEDdFtugOLPcQYpvmI2Tw0TJ15FK/E5L root@localhost.localdomain
END_AUTHORIZED_KEYS
chmod 600 .ssh/authorized_keys
if -x /usr/sbin/selinuxenabled && /usr/sbin/selinuxenabled; then
  chcon -R -h -t home_ssh_t .ssh
fi


mkdir -p /home/ovirtadm/engine
cat >/home/ovirtadm/engine/answer <<EOF
[general]
OVERRIDE_HTTPD_CONFIG=yes
HTTP_PORT=80
HTTPS_PORT=443
OVERRIDE_HTTPD_ROOT=yes
MAC_RANGE=00:1A:4A:23:01:00-00:1A:4A:23:01:FF
RANDOM_PASSWORDS=no
HOST_FQDN=ENGINE_FQDN
AUTH_PASS=ovirt
ORG_NAME=ovirt.org
DC_TYPE=NFS
DB_REMOTE_INSTALL=local
DB_HOST=
DB_PORT=5432
DB_ADMIN=postgres
DB_REMOTE_PASS=
DB_SECURE_CONNECTION=no
DB_LOCAL_PASS=ovirt
NFS_MP=
CONFIG_NFS=no
OVERRIDE_FIREWALL=iptables
SUPERUSER_PASS=ovirt
APPLICATION_MODE=virt
FIREWALL_MANAGER=iptables
EOF

%end
