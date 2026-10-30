resource "talos_image_factory_schematic" "this" {
  schematic = file(var.talos_schematic_file)
}

data "talos_image_factory_urls" "this" {
  talos_version     = var.talos_version
  schematic_id      = talos_image_factory_schematic.this.id
  platform          = "metal"
  disk_image_format = "qcow2"
}
