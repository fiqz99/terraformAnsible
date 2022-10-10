variable "pubkey"{
  default = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDHAPlLxda+JBIWATOwD5bIDcGFAekxm+G/63AYXvbUG9JavvMaKqMeW75O/+m1KH613j5xpql36rSO8PBeXO+sFnZwYIQUDibAHJayrHwpNlKeieEKLDmZogAJEhWZSAEe5Hey/VlUcYpkzCKyhDYeWeFFDNCM7Aq0M2Gy3HYdov6QZaDV4WRrVcprTdkvsHw6GXzbL3vcMWyB2+r4Q4/cC4ffWFYRPfRrjaAsUgdIS5IOKGV6aQAMMDM5Pe5DuKWfSmDG4C+9HAmoo636u8oBA21NJZr+nry7EBPkueFSDJdBAiXRPVhkYaEJWw5uNZH/lTpD/2IDrFw0l3uZ3zN4ND/UZCcLQJ643iE3R5AGYEg9HYyOTm0zVu1AmA4Tr6NhRvwON4h0xFx0XN9BJZq3+iIcdz5MKzRHZYXFZwb8jgeH5oYNLn8GLmInJ19f8y/ucDds3du5J5urezlOTOrSIUYXthGklbITW0xDRLqRzBrUHO4uavgcixlrQDKOYWk= fiqz99@filip-vm"
}
variable "prefix"{
  default = "stfilip"
}
variable "resgrp"{
  default = "RES-GRP-CT360-TUTORING-GRP4"
}
variable "loc"{
  default = "West Europe"
}

resource "azurerm_virtual_network" "main" {
  name                = "${var.prefix}-network"
  resource_group_name = "${var.resgrp}"
  location            = "${var.loc}"
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "main"{
  name                 = "internal"
  resource_group_name  = "${var.resgrp}"
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.2.0/24"]
}

resource "azurerm_public_ip" "main" {
  name                    = "test"
  location                = "${var.loc}"
  resource_group_name     = "${var.resgrp}"
  allocation_method       = "Static"
}

resource "azurerm_network_interface" "main" {
  name                = "${var.prefix}-nic"
  location            = "${var.loc}"
  resource_group_name = "${var.resgrp}"

  ip_configuration {
    name                          = "testconfiguration1"
    subnet_id                     = azurerm_subnet.main.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id = azurerm_public_ip.main.id

  }
}


resource "azurerm_virtual_machine" "main" {
  name                  = "${var.prefix}-vm"
  location              = "${var.loc}"
  resource_group_name   = "${var.resgrp}"
  network_interface_ids = [azurerm_network_interface.main.id]
  vm_size               = "Standard_DS1_v2"
  
  os_profile {
    computer_name  = "${var.prefix}"
    admin_username = "azureuser"
    }

  os_profile_linux_config {
    disable_password_authentication = true
    ssh_keys {
      path = "/home/azureuser/.ssh/authorized_keys"
      key_data = "${var.pubkey}"
    }
  }

  storage_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts-gen2"
    version   = "20.04.202209200"
  }

  storage_os_disk {
    name              = "${var.prefix}-storage"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  
  tags = {
    environment = "staging"
  }
}

resource "azurerm_network_security_group" "main" {
  name                = "acceptanceTestSecurityGroup1"
  location            = "${var.loc}"
  resource_group_name = "${var.resgrp}"

  security_rule {
    name                       = "test"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

}

data "azurerm_public_ip" "main" {
  name                = azurerm_public_ip.main.name
  resource_group_name = "${var.resgrp}"
}

output "public_ip_address" {
  value = data.azurerm_public_ip.main.ip_address
}

resource "local_file" "inventory" {
    depends_on = [azurerm_virtual_machine.main]
    content  = data.azurerm_public_ip.main.ip_address
    filename = "inventory"
}

resource "time_sleep" "wait_30_seconds" {
  depends_on = [local_file.inventory]

  create_duration = "30s"
}


resource "null_resource" "nr"{
  depends_on = [time_sleep.wait_30_seconds]
  provisioner "local-exec" {
    command = "w ; ssh-keyscan -H $(cat inventory) >> ~/.ssh/known_hosts"  
  }
}

resource "null_resource" "nr1"{
  depends_on = [null_resource.nr]
  provisioner "local-exec" {
    command = "ansible-playbook -i ./inventory -u azureuser --private-key ~/.ssh/id_rsa install-jenkins.yml"
  }
}

