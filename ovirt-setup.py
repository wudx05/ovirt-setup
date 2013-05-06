#!/bin/env python
import argparse
import errno
import subprocess
import os
import libvirt
import sys
import tempfile
import time
from virtinst.util import randomMAC
from xml.dom import minidom

COBBLER_SERVER = "127.0.0.1"
IMAGES_DIR = "/var/lib/libvirt/images/"
VM_IMG = IMAGES_DIR + "%s.qcow2"
IMG_SIZE = "20G"
ENGINE_BASE = "engineBase"
VDSM_BASE = "vdsmBase"

NETWORK_NAME = 'ovirt-test'
DOMAIN_NAME = 'test.ovirt.org'
SUBNET = '192.168.247'

NODES_PER_DEPLOYMENT = 2


def run_cmd(cmd, sudo=False):
    if sudo:
        cmd = ['/usr/bin/sudo'] + cmd
    print subprocess.list2cmdline(cmd)
    p = subprocess.Popen(cmd)
    out, err = p.communicate()
    if p.returncode:
        raise Exception(err)


def run_guest_cmd(guest_ip, guest_cmd):
    ssh_cmd = ["ssh", "-o", "StrictHostKeyChecking=no",
               "-o", "ConnectTimeout=30", "-o", "ConnectionAttempts=3",
               "root@%s" % guest_ip]
    cmd = ssh_cmd + guest_cmd
    run_cmd(cmd)


def enable_nested(domxml):
    """
    <cpu mode='custom' match='exact'>
      <model fallback='allow'>Conroe</model>
      <feature policy='require' name='vmx'/>
    </cpu>
    """
    domain = domxml.getElementsByTagName("domain")[0]
    cpu = domxml.createElement("cpu")
    cpu.setAttribute("mode", 'custom')
    cpu.setAttribute("match", 'exact')
    model = domxml.createElement("model")
    model.setAttribute("fallback", 'allow')
    model.appendChild(domxml.createTextNode('Conroe'))
    cpu.appendChild(model)
    feature_vmx = domxml.createElement("feature")
    feature_vmx.setAttribute("name", 'vmx')
    feature_vmx.setAttribute("policy", "require")
    cpu.appendChild(feature_vmx)
    domain.appendChild(cpu)
    return domxml


def remove_kernel_boot(domxml):
    osxml = domxml.getElementsByTagName("os")[0]
    try:
        kernel = osxml.getElementsByTagName("kernel")[0]
        osxml.removeChild(kernel)
        initrd = osxml.getElementsByTagName("initrd")[0]
        osxml.removeChild(initrd)
        cmdline = osxml.getElementsByTagName("cmdline")[0]
        osxml.removeChild(cmdline)
    except:
        pass
    return domxml


def fix_reboot_action(domxml):
    on_reboot = domxml.getElementsByTagName("on_reboot")[0]
    on_reboot.firstChild.data = 'restart'
    on_crash = domxml.getElementsByTagName("on_crash")[0]
    on_crash.firstChild.data = 'restart'


def create_qcow2_image(image, backing_file=None):
    if backing_file:
        option = "backing_file=%s" % backing_file
    else:
        option = "preallocation=metadata"
    if 'storage' in image:
        image_size = '100G'
    else:
        image_size = IMG_SIZE
    cmd = ["qemu-img", "create", "-f", "qcow2", "-o", option, image,
           image_size]
    run_cmd(cmd, sudo=True)


def create_base_vm(vm_name, vm_type, profile_name):
    koan_cmd = ["koan", "--server", COBBLER_SERVER, "--virt",
                "--profile=%s" % profile_name, "--virt-type=kvm",
                "--qemu-disk-type=virtio", "--virt-name=%s" % vm_name]
    run_cmd(koan_cmd, sudo=True)

    conn = libvirt.open("qemu:///system")
    v = conn.lookupByName(vm_name)
    domxml = minidom.parseString(v.XMLDesc(0))

    if vm_type == 'vdsm':
        domxml = enable_nested(domxml)

    remove_kernel_boot(domxml)
    fix_reboot_action(domxml)
    conn.defineXML(domxml.toxml())


def create_network():
    # Reserve ip addresses above x.x.x.100 for static configuration
    networkXML = "<network><name>%s</name><forward mode='nat'/> \
                  <bridge name='virbr-ovirt' stp='on' delay='0' /> \
                  <domain name='%s'/> \
                  <ip address='%s.1' netmask='255.255.255.0'> \
                  <dhcp><range start='%s.2' end='%s.100'/> \
                  </dhcp></ip></network>" % (NETWORK_NAME, DOMAIN_NAME, SUBNET,
                                             SUBNET, SUBNET)
    conn = libvirt.open("qemu:///system")
    net = conn.networkDefineXML(networkXML)
    net.create()
    net.setAutostart(1)


def update_network_map(vm_name, mac):
    conn = libvirt.open("qemu:///system")
    net = conn.networkLookupByName(NETWORK_NAME)
    doc = minidom.parseString(net.XMLDesc(0))

    #fixme: find a better approach to relocate ip address
    try:
        last_num = max([int(host.getAttribute('ip').split('.')[-1])
                       for host in doc.getElementsByTagName('host')]) + 1
    except ValueError:
        last_num = 2
    guest_ip = SUBNET + '.' + str(last_num)

    leases = open('/var/lib/libvirt/dnsmasq/%s.leases' % NETWORK_NAME).read()
    while  guest_ip in leases:
        last_num += 1
        guest_ip = SUBNET + '.' + str(last_num)

    xml = "<host mac='%s' name='%s' ip='%s' />" % (mac, vm_name, guest_ip)

    net.update(libvirt.VIR_NETWORK_UPDATE_COMMAND_ADD_FIRST,
               libvirt.VIR_NETWORK_SECTION_IP_DHCP_HOST, -1, xml,
               libvirt.VIR_NETWORK_UPDATE_AFFECT_CONFIG |
               libvirt.VIR_NETWORK_UPDATE_AFFECT_LIVE)

    return guest_ip


def delete_network_map(vm_name):
    conn = libvirt.open("qemu:///system")
    net = conn.networkLookupByName(NETWORK_NAME)
    doc = minidom.parseString(net.XMLDesc(0))
    for host in doc.getElementsByTagName('host'):
        if host.getAttribute('name') == vm_name:
            xml = host.toxml()
            break
    else:
        return
    net.update(libvirt.VIR_NETWORK_UPDATE_COMMAND_DELETE,
               libvirt.VIR_NETWORK_SECTION_IP_DHCP_HOST, -1, xml,
               libvirt.VIR_NETWORK_UPDATE_AFFECT_CONFIG |
               libvirt.VIR_NETWORK_UPDATE_AFFECT_LIVE)


def update_guest_mac(mnt_point, mac):
    cfg = mnt_point + '/etc/sysconfig/network-scripts/ifcfg-eth0'
    with open(cfg) as f:
        lines = [line for line in f if not line.startswith('HWADDR=')]
    lines.append('\n' + "HWADDR=%s" % mac)
    with open(cfg, 'w') as f:
        f.writelines(lines)


def update_guest(vm_name, mac):
    tmp_dir = tempfile.mkdtemp()
    cmd = ["guestmount", "-d", vm_name, "-m", "/dev/fedora/root", tmp_dir]
    run_cmd(cmd, sudo=True)
    update_guest_mac(tmp_dir, mac)
    cmd = ["umount", tmp_dir]
    run_cmd(cmd, sudo=True)
    os.rmdir(tmp_dir)


def setup_engine(vm_name, guest_ip):
    answer_file = '/home/ovirtadm/engine/answer'
    run_guest_cmd(guest_ip, ['sed', '-i', "'s/ENGINE_FQDN/%s/'" %
                             (vm_name + '.' + DOMAIN_NAME),
                             answer_file])
    run_guest_cmd(guest_ip, ['engine-setup', '--answer-file', answer_file])


def start_vm(vm_name, libvirt_conn=None):
    if not libvirt_conn:
        libvirt_conn = libvirt.open("qemu:///system")
    d = libvirt_conn.lookupByName(vm_name)
    d.create()


def clone_vm(base_name, vm_name):
    image = VM_IMG % vm_name
    mac = randomMAC()
    cmd = ["virt-clone", "--connect", "qemu:///system", "-o",
           base_name, "-n", vm_name, "-f", image,
           "--preserve-data", "--mac", mac]
    run_cmd(cmd, sudo=True)

    libvirt_conn = libvirt.open("qemu:///system")
    base_image = get_vm_disks(base_name, libvirt_conn)['vda']
    create_qcow2_image(image, base_image)
    guest_ip = update_network_map(vm_name, mac)
    update_guest(vm_name, mac)
    time.sleep(10)
    start_vm(vm_name, libvirt_conn)
    if 'engine' in base_name:
        time.sleep(20)
        setup_engine(vm_name, guest_ip)


def get_vm_disks(vm_name, libvirt_conn=None):
    if not libvirt_conn:
        libvirt_conn = libvirt.open("qemu:///system")
    disks = {}
    dom = libvirt_conn.lookupByName(vm_name)
    dom_xml = minidom.parseString(dom.XMLDesc(0))
    disks_xml = (dom_xml.getElementsByTagName('devices')[0]
                 .getElementsByTagName('disk'))

    for d in disks_xml:
        name = d.getElementsByTagName('target')[0].getAttribute('dev')
        path = d.getElementsByTagName('source')[0].getAttribute('file')
        disks[name] = path

    return disks


def delete_vm(vm_name):
    conn = libvirt.open("qemu:///system")
    try:
        for name, path in get_vm_disks(vm_name, conn).iteritems():
            print name, path
            os.unlink(path)
    except IOError as e:
        if e.errno == errno.ENOENT:
            pass
        else:
            raise
    except:
        pass

    try:
        delete_network_map(vm_name)
    except:
        pass

    try:
        v = conn.lookupByName(vm_name)
        v.undefine()
        v.destroy()
    except:
        pass


def createBase():
    create_network()
    create_base_vm('engine')
    create_base_vm('vdsm')


def cleanupBase():
    conn = libvirt.open("qemu:///system")
    baseInfos = {}
    for k in baseInfos.iterkeys():
        try:
            v = conn.lookupByName(baseInfos[k].name)
            v.undefine()
        except:
            pass

    try:
        net = conn.networkLookupByName(NETWORK_NAME)
        net.undefine()
        net.destroy()
    except:
        pass


def cloneDeployment(deploymentName):
    for i in range(NODES_PER_DEPLOYMENT):
        vm_name = deploymentName + '-vdsm' + str(i)
        clone_vm(vm_name, 'vdsm')
    vm_name = deploymentName + '-engine' + str(i)
    clone_vm(vm_name, 'engine')


def cleanupDeployment(deploymentName):
    for i in range(NODES_PER_DEPLOYMENT):
        delete_vm(deploymentName + '-vdsm' + str(i))
    delete_vm(deploymentName + '-engine')

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="cmd")
    parset_setup = subparsers.add_parser('setup')

    parser_create = subparsers.add_parser('create-base')
    parser_create.add_argument('--type')
    parser_create.add_argument('--profile')
    parser_create.add_argument('--name')

    parser_clone = subparsers.add_parser('clone-vm')
    parser_clone.add_argument('--base')
    parser_clone.add_argument('--name')

    parser_delete = subparsers.add_parser('delete-vm')
    parser_delete.add_argument('--name')

    args = parser.parse_args()
    print args.cmd,  # args.type, args.profile

    if args.cmd == 'setup':
        create_network()
    elif args.cmd == 'create-base':
        create_base_vm(args.name, args.type, args.profile)
    elif args.cmd == 'clone-vm':
        clone_vm(args.base, args.name)
    elif args.cmd == 'delete-vm':
        delete_vm(args.name)

    elif sys.argv[1] == 'cleanupBase':
        cleanupBase()
    elif sys.argv[1] == 'cloneDeployment':
        cloneDeployment(sys.argv[2])
    elif sys.argv[1] == 'delete_vm':
        delete_vm(sys.argv[2])
