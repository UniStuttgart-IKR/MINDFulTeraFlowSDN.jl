using MA1024

const TFS_BASE_URL = "http://127.0.0.1:80/tfs-api/devices"
devices=MA1024.get_devices(TFS_BASE_URL)


MA1024.print_devices(devices)