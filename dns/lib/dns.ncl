# TODO: zone, dnsserver, forwardZoneRef
let
# library imports
network = import "./network.ncl",
common = import "./common.ncl",
in let
  DnsEntry
    | doc "Pair of hostname and ip address, for example, for dns override"
    = {
      type
        | [|
          'A {
            name
              | doc "hostname, '@' for root, '*' for wildcard"
              | String,
            address
              | doc "ipv4 address"
              | network.Ip4Address,
            auto-reverse
              | doc "true to auto-add reverse recoord"
              | Bool
              | default
              = true,
          },
          'AAAA {
            name
              | doc "hostname, '@' for root, '*' for wildcard"
              | String,
            address
              | doc "ipv6 address"
              | network.Ip46ddress,
            auto-reverse
              | doc "true to auto-add reverse recoord"
              | Bool
              | default
              = true,
          },
          'CNAME {
            name
              | doc "hostname, '@' for root"
              | String,
            target
              | doc "e.g., www.example.com"
              | String
          },
          'DNSKEY {
            name | String,
            ttl
              | doc "value in minutes, or 'auto'"
              | String
              | default
              = "auto",
            flags | doc "0-65535" | std.number.Nat,
            proto | String | default = "DNSSEC",
            algorithm | doc "0-255" | std.number.Nat,
            key | doc "public key in base64" | String,
          },
          'MX {
            name | doc "hostname, '@' for root" | String,
            mailServer | doc "e.g., mx.example.com" | String,
            ttl | doc "time in minutes, or 'auto'" | String | default = "auto",
            priority | doc "0-65535" | std.number.Nat,
          },
          'NS {
            name | doc "hostname, '@' for root" | String,
            nameServer | doc "e.g., ns1.example.com" | String,
            ttl | doc "time in minutes, or 'auto'" | String | default = "auto",
          },
          'PTR {
            name | doc "hostname to be returned for reverse lookups, '@' for root" | String,
            domain | doc "e.g., www.example.com" | String,
            ttl | doc "time in minutes, or 'auto'" | String | default = "auto",
          },
          'SRV {
            name | String,
            priority | doc "0-65535" | std.number.Nat,
            weight | doc "0-65535" | std.number.Nat,
            ttl
              | doc "value in minutes, or 'auto'"
              | String
              | default
              = "auto",
            port | doc "0-65535" | std.number.Nat,
            target | doc "e.g., www.example.com" | String,
          },
          'TXT {
            name | String,
            ttl
              | doc "value in minutes, or 'auto'"
              | String
              | default
              = "auto",
            content | doc "record content" | String,
          }
        |],
      comment | doc "optional comment" | String | optional,
    },
  DnsCacheSchema = {
    prefetch | doc "prefetch when cache entry is nearing expiration" | Bool | optional | default = false,
    minTtl | doc "min ttl in seconds. omit to disable" | std.number.PosNat | optional,
    maxTtl
      | doc "max ttl in seconds. When cache entry has reached ttl age, it is expired. Default=86400 (1 day)"
      | std.number.PosNat
      | optional
      | default
      = 86400,
  },
  DnsLoggingSchema = {
    queries | doc "log all queries" | Bool | optional | default = false,
    requests | doc "log all requests" | Bool | optional | default = false,
    responses | doc "log all responses" | Bool | optional | default = false,
    cacheMiss | doc "log cache misses" | Bool | optional | default = false,
    toStderr
      | doc "log to stderr. True for nix systemd, to be captured by journald"
      | Bool
      | optional
      | default
      = true,
    logDir | doc "directory for file-based logging" | common.FilePath | optional,
  },
  Dnssec = {
    useQuic | Bool | optional | default = false,
    useDoH | Bool | optional | default = false,
    useDoT | Bool | optional | default = false,
    trustAnchorFile | String | optional,
    useRootTrustAnchor
      | doc "use and update root trust anchor for DNSSEC validation"
      | Bool
      | optional
      | default
      = true,
    tls | network.TlsSettings | optional,
  },
  DnsPrivacy | doc "advanced privacy controls" = {
    qnameMinimisation
      | doc "send minimum amount of information to upstream servers to enhance privacy"
      | Bool
      | default
      = true,
    denyAny | doc "deny queries of type ANY with an empty response" | Bool | optional | default = true,
    minimalResponse
      | doc m%"do not insert authority/additional sections into response messages
      when those sections are not required. This reduces response size significantly,
      and may avoid TCP fallback for some responses which may cause a slight speedup."%
      | Bool
      | optional
      | default
      = true,
    hideHostname | doc "refuse queries to id.server and hostname.bind" | Bool | optional | default = true,
    hostname | doc "identity to report. if unset, hostname of server is returned" | String | optional,
    hideVersion | doc "refuse queries to version.server and version.bind" | Bool | default = true,
    version | doc "version to report. if unset, package version is returned" | String | optional,
  },
in
let Zone
  | doc m%"dns-managed network space, often with its own acccess rules
         or server settings"%
  = {
    domain | doc "fully qualified domain name" | String,
    entries | doc "hosts in the local zone, used to create 'A' records." | Array DnsEntry,
    # additional zone settings
    zoneSettings | common.ExtraSettings | optional,
  },
in
{
  DnsServer
    | doc "generic dns server, remote or local"
    =
      (
        {
          withDefaults = {
            kind = 'Dns,
            port = 53,
            proto = 'Udp,
          }
        } | network.mkNetService
      ).outputs
      & {
        # TODO: DNSSEC settings, cert files, etc.
      },

  # returns true if the server is a dns server
  is_dns_server = fun server => server.kind == 'Dns,

  ForwardZoneRef = {
    domain
      | doc "domain, including wildcards, to forward to upstream server. Omit for all-domain wildcard"
      | String
      | optional,
    serverId | doc "server id for upstream dns server" | common.Id,
  },

  ManagedDnsServer
    | doc "managed dns server - one that we install and run"
    =
      DnsServer
      & {
        verbosity | doc "Logging verbosity" | common.Verbosity | default = 'Info,
        logging
          | doc "Logging settings"
          | DnsLoggingSchema
          | optional
          | default
          = DnsLoggingSchema,
        interfaces
          | doc m%"interfaces to connect to network, in addition to any ip addresses in `listen`.
          For interface names listed here, all IP addresses on that interface are used."%
          | Array String
          | optional,
        cache
          | doc "Cache settings"
          | common.Nullable DnsCacheSchema
          | optional
          | default
          = DnsCacheSchema,
        zoneDataFile | doc "file(s) to load zone data" | Array common.FilePath | optional,
        localZones
          | doc "local zones - we act as server for the zone"
          | Array Zone
          | optional,
        forwardZones
          | doc "forward zones, selected by 'domain' field to send o recursive server"
          | Array ForwardZoneRef
          | optional,
        netAccess | doc "access control by ip" | Array network.NetAccessRule | optional,
        localOverrides
          | doc "static addresses to return for intercepted queries"
          | Array DnsEntry
          | optional,
        dnssec | doc "DNSSEC settings" | Dnssec | default = Dnssec,
        privacy
          | doc "Advanced privacy settings"
          | DnsPrivacy
          | optional
          | default
          = DnsPrivacy,
        privateAddresses
          | doc m%"private subnets on your private network, will not be allowed
              to be returned for public internet names"%
          | Array network.IpAddrCidr
          | optional
          | default
          = network.const.rfc1918_networks,
        privateDomains
          | doc m%"allow this domain, and all its subdomains,
              to contain private addresses. Supercedes privateAddresses"%
          | Array String
          | optional,
        sysConfig
          | doc "system (os) settings"
          | common.SystemService
          | optional
          | default
          = common.SystemService,
      },

  UnboundDefaults
    | ManagedDnsServer
    | doc m%"
        unbound-specific defaults, using abstract schema (ManagedDnsServer).
        To override settings that aren't defined in the abstract schema, use 'extra'
      "%
    = {
      sysConfig =
        {
          user = "unbound",
          group = "unbound",
          workingDir | default = "/var/lib/unbound",
        } | common.SystemService,
      verbosity = 'Info,
      extra = {
        # example how to demonstrate setting additional values
        settings.answer-cookie = "no",
        checkconf = true,
      },
    },
}
