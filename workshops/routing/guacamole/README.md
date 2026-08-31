# Guacamole configuration

The installer generates the live Guacamole configuration under:

`/opt/routing-workshop/guacamole`

This repository deliberately does not contain a `user-mapping.xml` with a
real workshop password hash or generated TLS private key.

The tested network design is:

- `guacd` uses host networking.
- Dynamips console ports remain bound to `127.0.0.1:2001-2014`.
- Guacamole reaches host-based `guacd` through `host.docker.internal:4822`.
- `extra_hosts: host.docker.internal:host-gateway` is configured on the
  **guacamole** service.
- `user-mapping.xml` router entries use `127.0.0.1` because those connections
  are made by `guacd`, which shares the host network.
- `user-mapping.xml` is mode `0644` so the non-root Guacamole container can
  read the bind-mounted file.

The live Compose file is created automatically by
`setup_routing_workshop_ubuntu24.sh`.
