# Experiments with nickel: DNS server configuration

### Goals: Use Nickel to

- configure system services using an abstract schema, to provide flexibility over variations in implementations. (\# initially, the schema defines a forwarding dns server and upstream dns servers)
- validate the configuration, using static and dynamic type checking and nickel contracts, and in-editor LSP, with customizable error messages
- convert the abstract configuration into a server- and nixos- specific configuration that can be exported as json and imported by a `.nix` config. (\* initially, unbound)

Caveat: This is a WIP and the DNS configuration is incomplete, although there's enough to make it work for a simple subnet forwarding dns server.

### Files:

- Schemas:

  - [`lib/dns.ncl`](lib/dns.ncl) configuration schema for a generic dns server
  - [`lib/network.ncl`](lib/network.ncl) network-related configuration and contracts
  - [`lib/common.ncl`](lib/common.ncl) common contracts and utility functions

- Example configuration

  - [`example-dns.ncl`](./example-dns.ncl) config for a `ManagedDNSServer`

- Conversion
  - [`convert-unbound.ncl`](./convert-unbound.ncl) converts a `ManagedDNSServer` to nixos-ready json configuration for unbound.
- [`justfile`](./justfile) cli commands. Type `just` (with no args) for help. `just gen-unbound` runs the conversion

### Workflow:

1. Hand-generate server configuration (`example-dns.ncl`), which is validated against the schema `dns.ManagedDNSServer`.

2. Convert the abstract configuration to a server- (Unbound) and os- (nixos) specific configuration using `convert-unbound.ncl`. On the command line, this is done with `just gen-unbound`. If there are no errors, the result is a json file that provides the complete configuration for nixos `server.unbound`.

3. Import into nixos by adding this module:

```
  { ... }:
let
  config = builtins.fromJSON (builtins.readFile ./unbound-conf.json);
in
{
  services.unbound = config;
}
```
