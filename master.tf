resource "azurerm_availability_set" "osmasteras" {
  name                = "${var.openshift_azure_resource_prefix}-as-master-${var.openshift_azure_resource_suffix}"
  location            = "${azurerm_resource_group.osrg.location}"
  resource_group_name = "${azurerm_resource_group.osrg.name}"
  managed             = true
}

resource "azurerm_network_interface" "osmasternic" {
  name                      = "${var.openshift_azure_resource_prefix}-nic-master-${var.openshift_azure_resource_suffix}-${format("%01d", count.index)}"
  count                     = "${var.openshift_azure_master_vm_count}"
  location                  = "${azurerm_resource_group.osrg.location}"
  resource_group_name       = "${azurerm_resource_group.osrg.name}"
  network_security_group_id = "${azurerm_network_security_group.osmasternsg.id}"

  ip_configuration {
    name                                    = "configuration-${count.index}"
    subnet_id                               = "${azurerm_subnet.osmastersubnet.id}"
    private_ip_address_allocation           = "dynamic"
    load_balancer_backend_address_pools_ids = ["${azurerm_lb_backend_address_pool.osmasterlbbepool.id}"]
    load_balancer_inbound_nat_rules_ids     = ["${element(azurerm_lb_nat_rule.osmasterlbnatrule22.*.id, count.index)}"]
  }
}

resource "azurerm_lb_backend_address_pool" "osmasterlbbepool" {
  resource_group_name = "${azurerm_resource_group.osrg.name}"
  loadbalancer_id     = "${azurerm_lb.osmasterlb.id}"
  name                = "BackEndAddressPool"
}

resource "azurerm_lb_nat_rule" "osmasterlbnatrule22" {
  resource_group_name            = "${azurerm_resource_group.osrg.name}"
  loadbalancer_id                = "${azurerm_lb.osmasterlb.id}"
  name                           = "SSH-${format("%01d", count.index)}"
  count                          = "${var.openshift_azure_master_vm_count}"
  protocol                       = "Tcp"
  frontend_port                  = "${22 + count.index}"
  backend_port                   = 22
  frontend_ip_configuration_name = "PublicIPAddress"
}

resource "azurerm_lb_rule" "osmasterlbrule8443" {
  resource_group_name            = "${azurerm_resource_group.osrg.name}"
  loadbalancer_id                = "${azurerm_lb.osmasterlb.id}"
  name                           = "OpenShiftAdminConsole"
  protocol                       = "Tcp"
  frontend_port                  = 8443
  backend_port                   = 8443
  frontend_ip_configuration_name = "PublicIPAddress"
  probe_id                       = "${azurerm_lb_probe.osmasterlbprobe8443.id}"
  idle_timeout_in_minutes        = 30
  backend_address_pool_id        = "${azurerm_lb_backend_address_pool.osmasterlbbepool.id}"
}

resource "azurerm_lb_probe" "osmasterlbprobe8443" {
  resource_group_name = "${azurerm_resource_group.osrg.name}"
  loadbalancer_id     = "${azurerm_lb.osmasterlb.id}"
  name                = "8443Probe"
  port                = 8443
  number_of_probes    = 2
}

resource "azurerm_public_ip" "osmasterip" {
  name                         = "${var.openshift_azure_resource_prefix}-vip-master-${var.openshift_azure_resource_suffix}"
  location                     = "${azurerm_resource_group.osrg.location}"
  resource_group_name          = "${azurerm_resource_group.osrg.name}"
  public_ip_address_allocation = "static"
  domain_name_label            = "${var.openshift_azure_resource_prefix}-${var.openshift_master_dns_name}-${var.openshift_azure_resource_suffix}"
}

resource "azurerm_lb" "osmasterlb" {
  name                = "${var.openshift_azure_resource_prefix}-nlb-master-${var.openshift_azure_resource_suffix}"
  location            = "${azurerm_resource_group.osrg.location}"
  resource_group_name = "${azurerm_resource_group.osrg.name}"

  frontend_ip_configuration {
    name                 = "PublicIPAddress"
    public_ip_address_id = "${azurerm_public_ip.osmasterip.id}"
  }
}

resource "azurerm_virtual_machine" "osmastervm" {
  name                  = "${var.openshift_azure_resource_prefix}-vm-master-${var.openshift_azure_resource_suffix}-${format("%01d", count.index)}"
  count                 = "${var.openshift_azure_master_vm_count}"
  location              = "${azurerm_resource_group.osrg.location}"
  resource_group_name   = "${azurerm_resource_group.osrg.name}"
  network_interface_ids = ["${element(azurerm_network_interface.osmasternic.*.id, count.index)}"]
  availability_set_id   = "${azurerm_availability_set.osmasteras.id}"
  vm_size               = "${var.openshift_azure_master_vm_size}"

  storage_image_reference {
    publisher = "${var.openshift_azure_vm_os["publisher"]}"
    offer     = "${var.openshift_azure_vm_os["offer"]}"
    sku       = "${var.openshift_azure_vm_os["sku"]}"
    version   = "${var.openshift_azure_vm_os["version"]}"
  }

  storage_os_disk {
    name              = "${var.openshift_azure_resource_prefix}-disk-os-master-${var.openshift_azure_resource_suffix}-${format("%01d", count.index)}"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  storage_data_disk {
    name              = "${var.openshift_azure_resource_prefix}-disk-data-master-${var.openshift_azure_resource_suffix}-${format("%01d", count.index)}"
    managed_disk_type = "Standard_LRS"
    create_option     = "Empty"
    lun               = 0
    disk_size_gb      = "${var.openshift_azure_data_disk_size}"
  }

  os_profile {
    computer_name  = "${var.openshift_azure_resource_prefix}-vm-master-${var.openshift_azure_resource_suffix}-${format("%01d", count.index)}"
    admin_username = "${var.openshift_azure_vm_username}"
    admin_password = "${uuid()}"
  }

  os_profile_linux_config {
    disable_password_authentication = true

    ssh_keys {
      path     = "/home/${var.openshift_azure_vm_username}/.ssh/authorized_keys"
      key_data = "${file(var.openshift_azure_public_key)}"
    }
  }
}

resource "azurerm_virtual_machine_extension" "osmastervmextension" {
  name                 = "osmastervmextension"
  count                = "${var.openshift_azure_master_vm_count}"
  location             = "${azurerm_resource_group.osrg.location}"
  resource_group_name  = "${azurerm_resource_group.osrg.name}"
  depends_on           = ["azurerm_virtual_machine.osmastervm"]
  virtual_machine_name = "${element(azurerm_virtual_machine.osmastervm.*.name, count.index)}"
  publisher            = "Microsoft.Azure.Extensions"
  type                 = "CustomScript"
  type_handler_version = "2.0"

  settings = <<SETTINGS
    {
        "fileUris": [
            "${var.openshift_azure_master_prep_script}", "${var.openshift_azure_deploy_openshift_script}"
        ],
        "commandToExecute": "bash masterPrep.sh ${azurerm_storage_account.osstoragepv.name} ${var.openshift_azure_vm_username} && bash deployOpenShift.sh ${var.openshift_azure_vm_username} ${var.openshift_initial_password} ${base64encode(file(var.openshift_azure_private_key))} '${var.openshift_azure_resource_prefix}-vm-master-${var.openshift_azure_resource_suffix}' ${azurerm_public_ip.osmasterip.fqdn} ${azurerm_public_ip.osmasterip.ip_address} '${var.openshift_azure_resource_prefix}-vm-infra-${var.openshift_azure_resource_suffix}' '${var.openshift_azure_resource_prefix}-vm-node-${var.openshift_azure_resource_suffix}' ${var.openshift_azure_node_vm_count} ${var.openshift_azure_infra_vm_count} ${var.openshift_azure_master_vm_count} ${azurerm_public_ip.osinfraip.ip_address}.${var.openshift_azure_default_subdomain} ${azurerm_storage_account.osstorageregistry.name} ${azurerm_storage_account.osstorageregistry.primary_access_key} ${var.azure_tenant_id} ${var.azure_subscription_id} ${var.azure_client_id} ${var.azure_client_secret} ${azurerm_resource_group.osrg.name} '${azurerm_resource_group.osrg.location}' ${azurerm_storage_account.osstoragepv.name} ${azurerm_storage_account.osstoragepv.primary_access_key} ${var.openshift_ansible_url} ${var.openshift_ansible_branch}"
    }
SETTINGS
}

output "OpenShift Web Console" {
  value = "https://${azurerm_public_ip.osmasterip.fqdn}:8443/console"
}
