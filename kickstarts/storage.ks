#platform=x86, AMD64, or Intel EM64T
#version=DEVEL
# Install OS instead of upgrade
install
# Firewall configuration
# firewall --enabled --ssh --port=3260,2049,111:udp
firewall --disabled
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
services --enabled=network,sshd,nfs-server,targetcli
# Installation logging level
logging --level=debug

# System timezone
timezone  Etc/UTC
# System bootloader configuration
bootloader --location=mbr
# Partition clearing information
clearpart --all  
#Disk partitioning information
part /boot --fstype ext4 --size=150
part pv.01 --size=10240
part pv.02 --size=42000
part pv.03 --size=42000 --grow

volgroup fedora pv.01
logvol swap --fstype swap --name=swap --vgname=fedora --size=1024
logvol / --fstype ext4 --name=root --vgname=fedora --size=100 --grow


volgroup vg_nfs pv.03
logvol /ovirt-iso --fstype ext4 --vgname=vg_nfs --name=lv01 --size=20480
logvol /ovirt-data --fstype ext4  --vgname=vg_nfs --name=lv02 --size=20480  --grow

reboot

%packages --excludedocs
targetcli
nfs-utils
%end

%post
chown 36:36 /ovirt-data
chown 36:36 /ovirt-iso
echo "/ovirt-data  *(rw)" > /etc/exports
echo "/ovirt-iso *(rw)" >> /etc/exports


vgcreate vg_iscsi /dev/vda2
lvcreate -Z n -L 20G --name lv01 vg_iscsi
lvcreate -Z n -L 20G --name lv02 vg_iscsi

cat > /etc/target/saveconfig.json <<EOF
{
  "fabric_modules": [], 
  "storage_objects": [
    {
      "attributes": {
        "block_size": 512, 
        "emulate_dpo": 0, 
        "emulate_fua_read": 0, 
        "emulate_fua_write": 1, 
        "emulate_rest_reord": 0, 
        "emulate_tas": 1, 
        "emulate_tpu": 0, 
        "emulate_tpws": 0, 
        "emulate_ua_intlck_ctrl": 0, 
        "emulate_write_cache": 1, 
        "enforce_pr_isids": 1, 
        "fabric_max_sectors": 8192, 
        "is_nonrot": 0, 
        "max_unmap_block_desc_count": 0, 
        "max_unmap_lba_count": 0, 
        "optimal_sectors": 8192, 
        "queue_depth": 128, 
        "unmap_granularity": 0, 
        "unmap_granularity_alignment": 0
      }, 
      "dev": "/dev/vg_iscsi/lv02", 
      "name": "block02", 
      "plugin": "block", 
      "readonly": false, 
      "write_back": true, 
      "wwn": "51d9932e-eeab-4494-8f8b-3a11c36fbd84"
    }, 
    {
      "attributes": {
        "block_size": 512, 
        "emulate_dpo": 0, 
        "emulate_fua_read": 0, 
        "emulate_fua_write": 1, 
        "emulate_rest_reord": 0, 
        "emulate_tas": 1, 
        "emulate_tpu": 0, 
        "emulate_tpws": 0, 
        "emulate_ua_intlck_ctrl": 0, 
        "emulate_write_cache": 1, 
        "enforce_pr_isids": 1, 
        "fabric_max_sectors": 8192, 
        "is_nonrot": 0, 
        "max_unmap_block_desc_count": 0, 
        "max_unmap_lba_count": 0, 
        "optimal_sectors": 8192, 
        "queue_depth": 128, 
        "unmap_granularity": 0, 
        "unmap_granularity_alignment": 0
      }, 
      "dev": "/dev/vg_iscsi/lv01", 
      "name": "block01", 
      "plugin": "block", 
      "readonly": false, 
      "write_back": true, 
      "wwn": "862cc2cc-999e-4a8a-bda0-db79615744db"
    }
  ], 
  "targets": [
    {
      "fabric": "iscsi", 
      "tpgs": [
        {
          "attributes": {
            "authentication": 0, 
            "cache_dynamic_acls": 1, 
            "default_cmdsn_depth": 16, 
            "demo_mode_write_protect": 0, 
            "generate_node_acls": 1, 
            "login_timeout": 15, 
            "netif_timeout": 2, 
            "prod_mode_write_protect": 0
          }, 
          "enable": true, 
          "luns": [
            {
              "index": 1, 
              "storage_object": "/backstores/block/block02"
            }, 
            {
              "index": 0, 
              "storage_object": "/backstores/block/block01"
            }
          ], 
          "node_acls": [], 
          "parameters": {
            "AuthMethod": "CHAP,None", 
            "DataDigest": "CRC32C,None", 
            "DataPDUInOrder": "Yes", 
            "DataSequenceInOrder": "Yes", 
            "DefaultTime2Retain": "20", 
            "DefaultTime2Wait": "2", 
            "ErrorRecoveryLevel": "0", 
            "FirstBurstLength": "65536", 
            "HeaderDigest": "CRC32C,None", 
            "IFMarkInt": "2048~65535", 
            "IFMarker": "No", 
            "ImmediateData": "Yes", 
            "InitialR2T": "Yes", 
            "MaxBurstLength": "262144", 
            "MaxConnections": "1", 
            "MaxOutstandingR2T": "1", 
            "MaxRecvDataSegmentLength": "8192", 
            "OFMarkInt": "2048~65535", 
            "OFMarker": "No", 
            "TargetAlias": "LIO Target"
          }, 
          "portals": [
            {
              "ip_address": "0.0.0.0", 
              "port": 3260
            }
          ], 
          "tag": 1
        }
      ], 
      "wwn": "iqn.2013-04.org.ovirt.test.storage:t01"
    }
  ]
}
EOF

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

%end
