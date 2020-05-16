resource "ibm_resource_group" "resource_group" {
  count = var.resource_group_name == null ? 1 : 0
  name  = "${var.cluster_name}.${var.domain_name}"
}

data "ibm_resource_group" "resource_group" {
  name = var.resource_group_name == null ? ibm_resource_group.resource_group[ 0 ].name : var.resource_group_name
}

data "ibm_is_image" "ubuntu_1804" {
  name = "ibm-ubuntu-18-04-64"
}

####
# Keys
#

resource "ibm_is_ssh_key" "infra_key" {
  name           = "${var.cluster_name}-cluster-key"
  public_key     = file( "${var.infra_key}.pub" )
  resource_group = data.ibm_resource_group.resource_group.id
}

resource "ibm_is_ssh_key" "bastion_key" {
  name           = "${ibm_is_vpc.vpc.name}-bastion-key"
  public_key     = file( "${var.bastion_key}.pub" )
  resource_group = data.ibm_resource_group.resource_group.id
}

####
# VPC, Subnet and Public Gateway
#

resource "ibm_is_vpc" "vpc" {
  resource_group = data.ibm_resource_group.resource_group.id
  name           = var.cluster_name
  classic_access = false
}

resource "ibm_is_public_gateway" "public_gateway" {
  resource_group = ibm_is_vpc.vpc.resource_group

  name     = "public-gateway"
  vpc      = ibm_is_vpc.vpc.id
  zone     = var.zone_name
}

resource "ibm_is_subnet" "vpc_subnet" {
  name                     = "vpc-subnet"
  vpc                      = ibm_is_vpc.vpc.id
  zone                     = var.zone_name
  public_gateway           = ibm_is_public_gateway.public_gateway.id
  total_ipv4_address_count = "256"
}

####
# Security Groups
# Inbound: members of the VPC
# Inbound: members of the 10.0.0./8 network (IaaS)
# Outbound: No restrictions
#

resource "ibm_is_security_group" "vpc_default" {
  resource_group = ibm_is_vpc.vpc.resource_group
  name = "${ibm_is_vpc.vpc.name}-default"
  vpc  = ibm_is_vpc.vpc.id
}

resource "ibm_is_security_group_rule" "vpc_default_sgri_self" {
  group      = ibm_is_security_group.vpc_default.id
  direction  = "inbound"
  remote     = ibm_is_security_group.vpc_default.id
}

resource "ibm_is_security_group_rule" "vpc_default_sgri_iaas" {
  group      = ibm_is_security_group.vpc_default.id
  direction  = "inbound"
  remote     = "10.0.0.0/8"
}

resource "ibm_is_security_group_rule" "vpc_default_sgro_any" {
  group      = ibm_is_security_group.vpc_default.id
  direction  = "outbound"
  remote     = "0.0.0.0/0"
}

####
# Provision the Bastion
#

resource "ibm_is_subnet" "bastion_subnet" {
  name                     = "bastion-subnet"
  vpc                      = ibm_is_vpc.vpc.id
  zone                     = var.zone_name
  public_gateway           = ibm_is_public_gateway.public_gateway.id
  total_ipv4_address_count = "256"
}

####
# Bastion security groups
# Inbound: Ping from anywhere
# Inbound: SSH from specified CIDR
# Outbound: No restrictions
#

resource "ibm_is_security_group" "bastion_default" {
  resource_group = ibm_is_vpc.vpc.resource_group
  name = "bastion-default"
  vpc  = ibm_is_vpc.vpc.id
}

resource "ibm_is_security_group_rule" "vpc_default_sgri_bastion" {
  group      = ibm_is_security_group.vpc_default.id
  direction  = "inbound"
  remote     = ibm_is_security_group.bastion_default.id
}

resource "ibm_is_security_group_rule" "bastion_default_sgri_ping" {
  group      = ibm_is_security_group.bastion_default.id
  direction  = "inbound"
  remote     = "0.0.0.0/0"

  icmp {
    code = 0
    type = 8
  }
}

resource "ibm_is_security_group_rule" "bastion_default_sgri_ssh" {
  group      = ibm_is_security_group.bastion_default.id
  direction  = "inbound"
  remote     = "0.0.0.0/0" # TODO tighten

  tcp {
    port_min = 22
    port_max = 22
  }
}

resource "ibm_is_security_group_rule" "bastion_default_sgro_outbound" {
  group      = ibm_is_security_group.bastion_default.id
  direction  = "outbound"
  remote     = "0.0.0.0/0"
}

resource "ibm_is_instance" "bastion_server" {
  name           = "bastion"
  image          = data.ibm_is_image.ubuntu_1804.id
  profile        = "bx2-2x8"
  vpc            = ibm_is_vpc.vpc.id
  zone           = ibm_is_subnet.bastion_subnet.zone
  keys           = [ ibm_is_ssh_key.bastion_key.id ]
  resource_group = data.ibm_resource_group.resource_group.id

  primary_network_interface {
    name            = "eth0"
    subnet          = ibm_is_subnet.bastion_subnet.id
    security_groups = [ ibm_is_security_group.bastion_default.id ]
  }
}

resource "ibm_is_floating_ip" "bastion_server" {
  name           = "${ibm_is_instance.bastion_server.name}-fip"
  target         = ibm_is_instance.bastion_server.primary_network_interface[ 0 ].id
  resource_group = data.ibm_resource_group.resource_group.id

  connection {
    type        = "ssh"
    user        = "root"
    private_key = file( var.bastion_key )
    host        = ibm_is_floating_ip.bastion_server.address
  }

  provisioner "remote-exec" {
    scripts = [
      "${local.scripts_dir}/upgrade_os.sh",
      "${local.scripts_dir}/config_resolve.sh",
      "${local.scripts_dir}/do_reboot.sh" ]
  }

  # wait for the bastion to come online
  provisioner "local-exec" {
    command = "sleep 15"
  }
}

####
# Provision the installer
#

resource "ibm_is_instance" "installer" {
  name           = "installer"
  image          = data.ibm_is_image.ubuntu_1804.id
  profile        = "bx2-2x8"
  vpc            = ibm_is_vpc.vpc.id
  zone           = ibm_is_subnet.vpc_subnet.zone
  keys           = [ ibm_is_ssh_key.infra_key.id ]
  resource_group = data.ibm_resource_group.resource_group.id

  primary_network_interface {
    name            = "eth0"
    subnet          = ibm_is_subnet.vpc_subnet.id
    security_groups = [ ibm_is_security_group.vpc_default.id ]
  }

  connection {
    type                = "ssh"
    bastion_user        = "root"
    bastion_private_key = file( var.bastion_key )
    bastion_host        = ibm_is_floating_ip.bastion_server.address
    host                = self.primary_network_interface[ 0 ].primary_ipv4_address
    user                = "root"
    private_key         = file( var.infra_key )
  }

  provisioner "remote-exec" {
    scripts = [
      "${local.scripts_dir}/upgrade_os.sh",
      "${local.scripts_dir}/config_resolve.sh",
      "${local.scripts_dir}/install_sinatra.sh",
      "${local.scripts_dir}/install_ocp_client.sh",
      "${local.scripts_dir}/do_reboot.sh" ]
  }

  provisioner "file" {
    source      = var.pull_secret
    destination = "/opt/openshift/etc/pull_secret.txt"
  }

  # provisioner "file" {
  #   source      = "${path.module}/main.auto.tfvars"
  #   destination = "/opt/openshift/etc/main.auto.tfvars"
  # }
  #
  # provisioner "local-exec" {
  #   command = <<-EOT
  #     cat ${local.scripts_dir}/config_openshift_installation.sh \
  #       | ssh -o StrictHostKeyChecking=no \
  #             -o ProxyCommand="ssh -W %h:%p -o StrictHostKeyChecking=no -i ${var.bastion_key} root@${ibm_is_floating_ip.bastion_server.address}" -i ${var.infra_key} root@${ibm_is_instance.installer.primary_network_interface[ 0 ].primary_ipv4_address} \
  #             bash -s - ${var.cluster_name} ${var.domain_name}
  #   EOT
  # }
  #
  # provisioner "file" {
  #   source = "${local.helpers_dir}/bootstrap_helper.rb"
  #   destination = "/opt/openshift/bin/bootstrap_helper.rb"
  # }
}

####
# Provision the Load Balancer
#

resource "ibm_is_instance" "load_balancer" {
  name           = "load-balancer"
  image          = data.ibm_is_image.ubuntu_1804.id
  profile        = "bx2-2x8"
  vpc            = ibm_is_vpc.vpc.id
  zone           = ibm_is_subnet.vpc_subnet.zone
  keys           = [ ibm_is_ssh_key.infra_key.id ]
  resource_group = data.ibm_resource_group.resource_group.id

  primary_network_interface {
    name            = "eth0"
    subnet          = ibm_is_subnet.vpc_subnet.id
    security_groups = [ ibm_is_security_group.vpc_default.id ]
  }

  connection {
    type                = "ssh"
    bastion_user        = "root"
    bastion_private_key = file( var.bastion_key )
    bastion_host        = ibm_is_floating_ip.bastion_server.address
    host                = self.primary_network_interface[ 0 ].primary_ipv4_address
    user                = "root"
    private_key         = file( var.infra_key )
  }

  provisioner "remote-exec" {
    scripts = [
      "${local.scripts_dir}/upgrade_os.sh",
      "${local.scripts_dir}/install_haproxy.sh",
      "${local.scripts_dir}/config_resolve.sh" ]
  }

  provisioner "file" {
    destination = "/etc/haproxy/haproxy.cfg"

    content = <<-EOT
      global
        log 127.0.0.1 local2
        chroot /var/lib/haproxy
        pidfile /var/run/haproxy.pid
        maxconn 4000
        user haproxy
        group haproxy
        daemon
        stats socket /var/lib/haproxy/stats
        ssl-default-bind-ciphers PROFILE=SYSTEM
        ssl-default-server-ciphers PROFILE=SYSTEM

      defaults
        mode http
        log global
        option httplog
        option dontlognull
        option http-server-close
        option redispatch
        retries 3
        timeout http-request 10s
        timeout queue 1m
        timeout connect 10s
        timeout client 1m
        timeout server 1m
        timeout http-keep-alive 10s
        timeout check 10s
        maxconn 3000

      frontend openshift_api_server
        mode tcp
        option tcplog
        bind *:6443
        default_backend openshift_api_server

      backend openshift_api_server
        mode tcp
        balance source
        server bootstrap bootstrap.${var.cluster_name}.${var.domain_name}:6443
        server master-1 master-1.${var.cluster_name}.${var.domain_name}:6443
        server master-2 master-2.${var.cluster_name}.${var.domain_name}:6443
        server master-3 master-3.${var.cluster_name}.${var.domain_name}:6443

      frontend machine_config_server
        mode tcp
        option tcplog
        bind *:22623
        default_backend machine_config_server

      backend machine_config_server
        mode tcp
        balance source
        server bootstrap bootstrap.${var.cluster_name}.${var.domain_name}:22623
        server master-1 master-1.${var.cluster_name}.${var.domain_name}:22623
        server master-2 master-2.${var.cluster_name}.${var.domain_name}:22623
        server master-3 master-3.${var.cluster_name}.${var.domain_name}:22623

      frontend ingress_http
        mode tcp
        option tcplog
        bind *:80
        default_backend ingress_http

      backend ingress_http
        mode tcp
        server worker-1 worker-1.${var.cluster_name}.${var.domain_name}:80
        server worker-2 worker-2.${var.cluster_name}.${var.domain_name}:80

      frontend ingress_https
        mode tcp
        option tcplog
        bind *:443
        default_backend ingress_https

      backend ingress_https
        mode tcp
        server worker-1 worker-1.${var.cluster_name}.${var.domain_name}:443
        server worker-2 worker-2.${var.cluster_name}.${var.domain_name}:443
    EOT
  }
}
