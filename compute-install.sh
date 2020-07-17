IP=${1}


# Prerrequisites
PART1=true

# nova-compute
PART2=true

# old part (non-existing)
PART3=true

# neutron
PART4=true

if [ "$PART1" == "true" ]; then
if [ "$IP" == "" ]; then
	echo "must enter an IP ending (eg. 247 para 192.168.10.247)"
	exit 1
fi

cat > /etc/netplan/config.yaml <<EOT
network:
    ethernets:
        eno2:
            addresses:
                    - 192.168.10.$IP/24
            gateway4: 192.168.10.220
            nameservers:
                    addresses: [ 8.8.8.8 ]
        eno1: {}
    version: 2
EOT

netplan generate
netplan apply
apt update
apt purge -y ifupdown

cat >> /etc/default/grub << EOT
GRUB_CMDLINE_LINUX_DEFAULT="ipv6.disable=1"
GRUB_CMDLINE_LINUX="ipv6.disable=1"
EOT
update-grub

apt install -y chrony
sed -i 's/^pool/#pool/g' /etc/chrony/chrony.conf
echo "server controller iburst" >> /etc/chrony/chrony.conf
service chrony restart
fi

if [ "$PART2" == "true" ]; then
apt install software-properties-common
add-apt-repository cloud-archive:rocky
apt update && apt -y dist-upgrade
apt install -y python-openstackclient nova-compute nova-compute-kvm

cp /etc/nova/nova.conf /etc/nova/nova.conf.orig

cat > /etc/nova/nova.conf << EOT
[DEFAULT]
enabled_apis = osapi_compute,metadata
# BUG: log_dir = /var/log/nova
lock_path = /var/lock/nova
state_path = /var/lib/nova
transport_url = rabbit://openstack:RABBIT_PASS@controller
my_ip = 192.168.10.$IP
use_neutron = true
firewall_driver = nova.virt.firewall.NoopFirewallDriver
vnc_keymap=es
[api]
auth_strategy = keystone
[api_database]
connection = sqlite:////var/lib/nova/nova_api.sqlite
[cells]
enable = False
[cinder]
os_region_name = RegionOne
[database]
connection = sqlite:////var/lib/nova/nova.sqlite
[glance]
glance_api_version=2
api_servers = http://controller:9292
[keystone_authtoken]
auth_url = http://controller:5000/v3
memcached_servers = controller:11211
auth_type = password
project_domain_name = default
user_domain_name = default
project_name = service
username = nova
password = NOVA_PASS
[neutron]
url = http://controller:9696
auth_url = http://controller:5000
auth_type = password
project_domain_name = default
user_domain_name = default
region_name = RegionOne
project_name = service
username = neutron
password = NEUTRON_PASS
[oslo_concurrency]
lock_path = /var/lib/nova/tmp
[placement]
region_name = RegionOne
project_domain_name = Default
project_name = service
auth_type = password
user_domain_name = Default
auth_url = http://controller:5000/v3
username = placement
password = PLACEMENT_PASS
[vnc]
enabled = true
server_listen = 0.0.0.0
server_proxyclient_address = \$my_ip
novncproxy_base_url = http://controller:6080/vnc_lite.html
EOT
fi

if [ "$PART4" == "true" ]; then
apt install -y neutron-linuxbridge-agent

cp /etc/neutron/neutron.conf /etc/neutron/neutron.conf.orig

cat > /etc/neutron/neutron.conf <<EOT
[DEFAULT]
lock_path = /var/lock/neutron
core_plugin = ml2
transport_url = rabbit://openstack:RABBIT_PASS@controller
auth_strategy = keystone
[agent]
root_helper = "sudo /usr/bin/neutron-rootwrap /etc/neutron/rootwrap.conf"
[keystone_authtoken]
www_authenticate_uri = http://controller:5000
auth_url = http://controller:5000
memcached_servers = controller:11211
auth_type = password
project_domain_name = default
user_domain_name = default
project_name = service
username = neutron
password = NEUTRON_PASS
EOT

cp /etc/neutron/plugins/ml2/linuxbridge_agent.ini /etc/neutron/plugins/ml2/linuxbridge_agent.ini.orig

cat > /etc/neutron/plugins/ml2/linuxbridge_agent.ini <<EOT
[linux_bridge]
physical_interface_mappings = provider:eno1
[securitygroup]
firewall_driver = neutron.agent.linux.iptables_firewall.IptablesFirewallDriver
enable_security_group = true
[vxlan]
enable_vxlan = true
local_ip = 192.168.10.$IP
l2_population = true
EOT
fi

echo "ready... press enter to reboot!!!"
read
reboot
