# Instructor Jump Host

The optional instructor jump host provides a separate management path to the
Dynamips AUX console ports without exposing Telnet to the workshop WAN.

Enable it during installation with:

```bash
sudo ./setup_routing_workshop_ubuntu24.sh --enable-instructor-jumphost
```

The addressing plan is:

| Function | Address/port |
| --- | --- |
| Ubuntu host management bridge | `192.168.30.254/24` |
| Instructor LXC jump host | `192.168.30.222/24` |
| Ubuntu host administration | WAN TCP `22` |
| Student Guacamole | WAN TCP `443` |
| Instructor SSH | WAN TCP `2222` to `192.168.30.222:22` |
| Dynamips AUX proxies | `192.168.30.254:3001-3014` |

The jump host reuses the workshop VM administrator's existing SSH public keys
from `~/.ssh/authorized_keys`. Password authentication and root SSH login are
disabled inside the jump host. The instructor account is forced into the
router-selection menu and SSH forwarding is disabled.

The menu maps Router r01 to AUX TCP/3001, Router r02 to TCP/3002, through
Router r14 on TCP/3014.

On Azure, the VM still uses its normal Azure-assigned NIC address. The internal
`192.168.30.0/24` network exists only behind the Ubuntu VM. Configure the Azure
Network Security Group separately to permit:

* TCP `22` from administrator source addresses.
* TCP `443` from workshop/student source addresses.
* TCP `2222` from instructor source addresses.

Do not expose TCP `3001-3014` in the Azure NSG.
