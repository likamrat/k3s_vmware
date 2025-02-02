data "vsphere_datacenter" "dc" {
  name = "${var.vsphere_datacenter}"
}

data "vsphere_datastore_cluster" "datastore_cluster" {
  count = var.vsphere_datastore_cluster != "" ? 1 : 0
  name = var.vsphere_datastore_cluster
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_datastore" "datastore" {
  count = var.vsphere_datastore != "" && var.vsphere_datastore_cluster == "" ? 1 : 0
  name = var.vsphere_datastore
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_resource_pool" "pool" {
  name = var.vsphere_resource_pool
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_network" "network" {
  count = var.network_cards != null ? length(var.network_cards) : 0
  name = var.network_cards[count.index]
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_virtual_machine" "template" {
  name = "${var.vsphere_vm_template_name}"
  datacenter_id = "${data.vsphere_datacenter.dc.id}"
}

locals {
  interface_count     = length(var.ipv4_submask) #Used for Subnet handeling
  template_disk_count = length(data.vsphere_virtual_machine.template.disks)
}

// Provisioning k3s Worker nodes from the VM template
resource "vsphere_virtual_machine" "worker" {
  count = var.vsphere_virtual_machine_k3s_worker_count
  name = "${var.vsphere_virtual_machine_k3s_worker_name}-${format("%02d", count.index+1)}"
  resource_pool_id = data.vsphere_resource_pool.pool.id
  folder = var.vsphere_folder
  datastore_cluster_id = var.vsphere_datastore_cluster != "" ? data.vsphere_datastore_cluster.datastore_cluster[0].id : null
  datastore_id = var.vsphere_datastore != "" ? data.vsphere_datastore.datastore[0].id : null
  num_cpus = var.cpu_count
  num_cores_per_socket = var.num_cores_per_socket
  cpu_hot_add_enabled = var.cpu_hot_add_enabled
  cpu_hot_remove_enabled = var.cpu_hot_remove_enabled
  memory = var.memory_size
  memory_hot_add_enabled = var.memory_hot_add_enabled
  guest_id = data.vsphere_virtual_machine.template.guest_id
  scsi_type = data.vsphere_virtual_machine.template.scsi_type

  dynamic "network_interface" {
    for_each = var.network_cards
    content {
      network_id = data.vsphere_network.network[network_interface.key].id
      adapter_type = data.vsphere_virtual_machine.template.network_interface_types[0]
    }
  }

  // Disks defined in the original template
  dynamic "disk" {
    for_each = data.vsphere_virtual_machine.template.disks
    iterator = template_disks
    content {
      label            = "disk${template_disks.key}"
      size             = data.vsphere_virtual_machine.template.disks[template_disks.key].size
      unit_number      = template_disks.key
      thin_provisioned = data.vsphere_virtual_machine.template.disks[template_disks.key].thin_provisioned
      eagerly_scrub    = data.vsphere_virtual_machine.template.disks[template_disks.key].eagerly_scrub
    }
  }

  clone {
    template_uuid = data.vsphere_virtual_machine.template.id
    customize {
      linux_options {
        host_name = "${var.vsphere_virtual_machine_k3s_worker_name}-${format("%02d", count.index+1)}"
        domain = var.domain
      }

      dynamic "network_interface" {
        for_each = var.network_cards
        content {
          ipv4_address = cidrhost(var.virtual_machine_network_address, var.virtual_machine_k3s_worker_ip_address_start + count.index)
          ipv4_netmask = "%{if local.interface_count == 1}${var.ipv4_submask[0]}%{else}${var.ipv4_submask[network_interface.key]}%{endif}"
        }
      }

      dns_server_list = var.vm_dns
      ipv4_gateway = var.vm_gateway
    }
  }
}

// Provisioning k3s Master nodes from the VM template
resource "vsphere_virtual_machine" "master" {
  count = var.vsphere_virtual_machine_k3s_master_count
  name = "${var.vsphere_virtual_machine_k3s_master_name}-${format("%02d", count.index+1)}"
  resource_pool_id = data.vsphere_resource_pool.pool.id
  folder = var.vsphere_folder
  datastore_cluster_id = var.vsphere_datastore_cluster != "" ? data.vsphere_datastore_cluster.datastore_cluster[0].id : null
  datastore_id = var.vsphere_datastore != "" ? data.vsphere_datastore.datastore[0].id : null
  num_cpus = var.cpu_count
  num_cores_per_socket = var.num_cores_per_socket
  cpu_hot_add_enabled = var.cpu_hot_add_enabled
  cpu_hot_remove_enabled = var.cpu_hot_remove_enabled
  memory = var.memory_size
  memory_hot_add_enabled = var.memory_hot_add_enabled
  guest_id = data.vsphere_virtual_machine.template.guest_id
  scsi_type = data.vsphere_virtual_machine.template.scsi_type

  dynamic "network_interface" {
    for_each = var.network_cards
    content {
      network_id = data.vsphere_network.network[network_interface.key].id
      adapter_type = data.vsphere_virtual_machine.template.network_interface_types[0]
    }
  }

  // Disks defined in the original template
  dynamic "disk" {
    for_each = data.vsphere_virtual_machine.template.disks
    iterator = template_disks
    content {
      label            = "disk${template_disks.key}"
      size             = data.vsphere_virtual_machine.template.disks[template_disks.key].size
      unit_number      = template_disks.key
      thin_provisioned = data.vsphere_virtual_machine.template.disks[template_disks.key].thin_provisioned
      eagerly_scrub    = data.vsphere_virtual_machine.template.disks[template_disks.key].eagerly_scrub
    }
  }

  clone {
    template_uuid = data.vsphere_virtual_machine.template.id
    customize {
      linux_options {
        host_name = "${var.vsphere_virtual_machine_k3s_master_name}-${format("%02d", count.index+1)}"
        domain = var.domain
      }

      dynamic "network_interface" {
        for_each = var.network_cards
        content {
          ipv4_address = cidrhost(var.virtual_machine_network_address, var.virtual_machine_k3s_master_ip_address_start + count.index)
          ipv4_netmask = "%{if local.interface_count == 1}${var.ipv4_submask[0]}%{else}${var.ipv4_submask[network_interface.key]}%{endif}"
        }
      }

      dns_server_list = var.vm_dns
      ipv4_gateway = var.vm_gateway
    }
  }
}
