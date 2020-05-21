provider "ibm" {
  region     = "us-south"
  generation = 2
}

resource "ibm_is_vpc" "vpc" {
  name           = "vpc"
  classic_access = false
}

resource "ibm_is_subnet" "subnet" {
  name                     = "subnet"
  vpc                      = ibm_is_vpc.vpc.id
  zone                     = "us-south-1"
  total_ipv4_address_count = "256"
}

resource "ibm_is_security_group" "sg" {
  count = 10
  name  = "sg-${count.index}"
  vpc   = ibm_is_vpc.vpc.id
}

resource "ibm_is_security_group_rule" "sgr" {
  count      = 10
  group      = ibm_is_security_group.sg[ count.index ].id
  direction  = "inbound"
  remote     = "0.0.0.0/0"

  tcp {
    port_min = 1000 + count.index
    port_max = 1000 + count.index
  }
}

data "ibm_is_image" "ubuntu_1804" {
  name = "ibm-ubuntu-18-04-64"
}

resource "ibm_is_instance" "server" {
  name           = "server"
  image          = data.ibm_is_image.ubuntu_1804.id
  profile        = "bx2-2x8"
  vpc            = ibm_is_vpc.vpc.id
  zone           = "us-south-1"
  keys           = []

  primary_network_interface {
    name            = "eth0"
    subnet          = ibm_is_subnet.subnet.id
    security_groups = [
      ibm_is_security_group.sg[0].id,
      ibm_is_security_group.sg[1].id,
      ibm_is_security_group.sg[2].id,
      ibm_is_security_group.sg[3].id,
      ibm_is_security_group.sg[4].id,
      ibm_is_security_group.sg[5].id,
      ibm_is_security_group.sg[6].id,
      ibm_is_security_group.sg[7].id,
      ibm_is_security_group.sg[8].id,
      ibm_is_security_group.sg[9].id ]
  }
}
