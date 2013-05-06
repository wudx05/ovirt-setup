#platform=x86, AMD64, or Intel EM64T
#version=DEVEL
# Install OS instead of upgrade
install
# Firewall configuration
firewall --enabled --ssh
# Use network installation
url --url=$tree
# If any cobbler repo definitions were referenced in the kickstart profile, include them here.
$yum_repo_stanza
# Network information
network --onboot yes --device eth0 --bootproto dhcp --noipv6
# Root password
rootpw --plaintext ovirt
# System authorization information
auth  --useshadow  --passalgo=md5
# Use graphical install
graphical
firstboot --disable
xconfig --startxonboot
poweroff
# System keyboard
keyboard us
# System language
lang en_US.UTF-8
# SELinux configuration
selinux --enforcing
# Installation logging level
logging --level=info

# System timezone
timezone  Etc/UTC
# System bootloader configuration
bootloader --location=mbr
# Partition clearing information
clearpart --all  
autopart --type=lvm
services --enabled=network --disabled=NetworkManager

%packages --excludedocs 
vdsm
vdsm-cli
vdsm-gluster
-NetworkManager
%end

%post

## EDIT HERE ##
cd /root
if ! test -d .ssh; then
  mkdir --mode=700 .ssh
fi
cat >> .ssh/authorized_keys << END_AUTHORIZED_KEYS
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDQmD6mdIkZp4aD54Q/1OQVLMf27xA8M2p6/xWEfCNmLh1zGa5+O97g/3RKjEY5hLEku30miLWVNXlHvOu83mrBOJ+fuYb3rmgl0anPZmvH6zZJ1BCDbFQyLegugoNjzFhPDb/32nyRfhNGQUeZpiaAz7TMsI1tsbqxnKo0Kdkhk2IJwISJ/ZtrDJ1PC3dOSnmKNbMmeoc7ZIccxdr0yz6KOUzc5PkRryZTVY+PS4ucCSXuJugR332DDsLazi0ewphcfHSXghMHRCLwQJQrPMR7xmakzB2VL2VabcEj6tIKAuLcCG/oy1iyeOSJne74QyVWtja/pjZGupwe/fQH0zPb mark@localhost.localdomain
END_AUTHORIZED_KEYS
chmod 600 .ssh/authorized_keys
if -x /usr/sbin/selinuxenabled && /usr/sbin/selinuxenabled; then
  chcon -R -h -t home_ssh_t .ssh
fi

%end

