output "talos_disk_image_url" {
  value       = data.talos_image_factory_urls.this.urls.disk_image
  description = "Talos disk image url"
}