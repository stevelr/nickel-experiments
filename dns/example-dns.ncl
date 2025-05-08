# DNS server Configuration
#
let
  dns = import "lib/dns.ncl",
  common = import "lib/common.ncl",
in
let const = {
  # service ids
  UPSTREAM_DNS_QUAD_NINE_ID | common.Id = "a836db1f-2fd3-4a0e-8754-4c16239306e7",
  UPSTREAM_DNS_EXAMPLE_ID | common.Id = "0c5cfb09-3565-401b-adb0-f962e9a2c199",
  MY_DNS_SERVER_ID | common.Id = "3d42ca50-106d-4e56-aab3-14aabda7d670",
}
in
{
  config = {
    # upstream default dns
    dns_quad_nine : dns.DnsServer =
      {
        id = const.UPSTREAM_DNS_QUAD_NINE_ID,
        address = [
          { address = "9.9.9.11" },
          { address = "149.112.112.11" },
          { address = "2620:fe::11" },
          { address = "2620:fe::fe:11" },
        ],
        comment = "quad9.net ECS enabled, Malware blocking, DNSSEC validation",
      } | dns.DnsServer,

    # upstream for example.com
    dns_example_dot_com : dns.DnsServer =
      {
        id = const.UPSTREAM_DNS_EXAMPLE_ID,
        address = [{ address = "8.8.8.8", proto = 'Udp }],
      } | dns.DnsServer,

    myserver : dns.ManagedDnsServer =
      dns.UnboundDefaults
      & {
        id = const.MY_DNS_SERVER_ID,
        verbosity = 'Info,
        forwardZones = [
          { domain = "example.com", serverId = dns_example_dot_com.id },
          { domain = "*", serverId = dns_quad_nine.id }
        ],
        listen = [
          { address = "127.0.0.1" },
          { address = "192.168.70.1" },
          { address = "192.168.71.1" },
          { address = "192.168.72.1" },
        ],
        interfaces = [
          "enp0s1",
          "docker0",
        ],
        # access control rules
        netAccess = [
          { ip = "127.0.0.1", access = 'Allow, comment = "allow localhost" },
          { ip = "10.144.0.0/24", access = 'Allow, comment = "allow br0" },
          { ip = "192.168.64.0/18", access = 'Allow, comment = "allow all subnets" },
        ],
        localOverrides = [
          # intercept lookups and return fake IP
          {
            type = 'A { name = "router.example.com", address = "10.200.0.1" },
          },
          {
            type = 'A { name = "foo.example.com", address = "10.200.0.2", },
            comment = "override foo to handle locally"
          },
        ],
        cache.prefetch = true,
        logging.queries = true,
        # 'extra' is not part of the typed abstract shema. It can be used to
        # override any settings in the generated (nixos, unbound) configuration.
        extra = {
          settings = {
            remote-control = { control-enable = true },

            # example of how to do mkForce
            # server.username = {
            #   _type = "override",
            #   priority = 50, # mkForce uses priority 50
            #   content = "unbound2",
            # }
          }
        },
      } | dns.ManagedDnsServer,
  }
}
