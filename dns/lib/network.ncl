let
# library imports
common = import "./common.ncl",
in let
# ipv6 regex Taken from
# https://stackoverflow.com/questions/53497/regular-expression-that-matches-valid-ipv6-addresses
# with minor tweaks:
#   removed match for "fe80..." (link-local IPv6 addresses with zone index)
#   added ::FFFF:x.y.z.w ip4-to-ip6 map (uppercase FFFF. original supported ffff lowercase)
# This might not be perfect - it doesn't need to be - but it works for our test cases
ip6_regex = "^(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|::((ffff|FFFF)(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))$",
ip4_regex = "^((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])$",
# in_range : Number -> Number -> Number -> Bool = fun _min _max value =>
#   value >= _min && value <= _max,
in {

  patterns = {
    # true if the string can be converted to an int in the range 0 to max, inclusive
    _is_strnum_le : String -> Number -> Bool = fun str max =>
      std.string.is_match "^\\d+$" str
      && (std.string.to_number str) <= max,
    is_ip4_regex : String -> Bool = std.string.is_match ip4_regex,
    is_ip6_regex : String -> Bool = std.string.is_match ip6_regex,
    is_ip_regex : String -> Bool = fun addr => is_ip4_regex addr || is_ip6_regex addr,
    is_ip4_cidr : String -> Bool = is_ip_cidr is_ip4_regex 32,
    is_ip6_cidr : String -> Bool = is_ip_cidr is_ip6_regex 128,
    # handle ip4 or ip6 with regex function and optional /prefix bits
    is_ip_cidr : (String -> Bool) -> Number -> String -> Bool = fun fn_regex bits addr =>
      let split = std.string.split "/" addr in
      std.array.length split
      |> match {
        1 => fn_regex addr,
        2 => fn_regex (std.array.at 0 split) && (_is_strnum_le (std.array.at 1 split) bits),
        _ => false,
      },
  },

  # kinds of network service. Meant to be generic, even if there are multiple implementations
  ServiceKind = [| 'Database, 'Dns, 'Dhcp, 'Http, 'Syslog |],

  # implementation of network service - vendor or major software package
  VariantTag = [| 'Unbound, 'Mysql, 'Postgres, 'Other String |],

  Variant = {
    tag | VariantTag,
    # version number
    version | std.package.Semver | optional,
    # enabled feature flags that have an impact on configuration and deployment
    features | { _ : Dyn } | optional | default = {},
  },

  # Port : contract verifying valid port number
  Port = common.IntInRange 0 65535,

  # Ipv4 address
  Ip4Address =
    std.contract.from_validator (fun value =>
      if std.is_string value && patterns.is_ip4_regex (std.to_string value) then
        'Ok
      else
        errors.invalid_ip4
    ),

  # Ipv4 address with optional /prefix
  Ip4AddrCidr =
    std.contract.from_validator (fun value =>
      if std.is_string value && patterns.is_ip4_cidr value then
        'Ok
      else
        errors.invalid_ip4
    ),

  # Ipv6 address
  Ip6Address =
    std.contract.from_validator (fun value =>
      if std.is_string value
      && patterns.is_ip6_regex (std.to_string value) then
        'Ok
      else
        errors.invalid_ip6
    ),

  # Ipv6 address with optional /prefix
  Ip6AddrCidr =
    std.contract.from_validator (fun value =>
      if std.is_string value && patterns.is_ip6_cidr value then
        'Ok
      else
        errors.invalid_ip6
    ),

  # Ipv4 or Ipv6 address
  IpAddress =
    std.contract.from_validator (fun addr =>
      if std.is_string addr
      && (patterns.is_ip4_regex addr || patterns.is_ip6_regex addr) then
        'Ok
      else
        errors.invalid_ip
    ),

  # Ipv4 or Ipv6 address with optional /prefix
  IpAddrCidr =
    std.contract.from_validator (fun value =>
      if std.is_string value
      && (patterns.is_ip4_cidr value || patterns.is_ip6_cidr value) then
        'Ok
      else
        errors.invalid_ip
    ),

  ## Error messages
  ##
  errors = {
    invalid_ip = 'Error { message = "Invalid IP Address" },
    invalid_ip4 = 'Error { message = "Invalid IPv4 Address" },
    invalid_ip6 = 'Error { message = "Invalid IPv6 Address" },
  },

  ## Constants
  ##
  const = {

    # RFC1918: https://datatracker.ietf.org/doc/html/rfc1918.html
    # Private and link-local
    rfc1918_networks = [
      "10.0.0.0/8",
      "172.16.0.0/12",
      "192.168.0.0/16",
      "169.254.0.0/16", # ip4 link-local
      "fd00::/8", # RFC4139
      "fe80::/10", # ip6 link-local
    ],

    # cidr pattern for ip4-mapped ip6 addresses
    ip4_to_ip6_mapped = "::ffff:0:0/96",
  },

  # protocols for a NetService. These are all Layer 4
  Proto = [| 'Udp, 'Tcp, 'TcpUdp, 'Quic |],

  # Hostname (and/or ip address), port, and protocol
  HostPort = {
    hostname | doc "Hostname" | String | optional,
    address | doc "Ip address" | IpAddress | optional,
    port | doc "Port. May be omitted to use default port for service" | Port | optional,
    proto | Proto | optional,
  },

  # HostPort with specific defaults and protocol
  mk_HostPort : Port -> Proto -> HostPort = fun defport defproto =>
    (
      HostPort
      & {
        port | default = defport,
        proto | default = defproto,
      }
    ) | HostPort,

  # physical host
  NetHost =
    common.Entity
    & {
      host | doc "host name(s)" | Array String,
      address | doc "server address(es)" | Array IpAddress,
    },

  # Start and end ip range (inclusive)
  # Example: start=192.168.0.64-192.168.0.80 is equivalent to 192.168.0.64/28
  Ip4Range = {
    start | doc "start ip address" | Ip4Address,
    end | doc "end ip address" | Ip4Address,
  },

  # rules for allowing or denying access to service based on ip address or range
  # Note that access can also be affected by firewall, the interface-ip bindings,
  # and service listen ip bindings
  NetAccessRule = {
    ip | std.contract.any_of [Ip4AddrCidr, Ip4Range, Ip6AddrCidr],
    access | [| 'Deny, 'Allow, 'Refuse, 'Drop |],
    comment | doc "Optional notes about the rule" | String | optional,
  },

  # a generic network service. Remote or Local
  NetService =
    common.Entity
    & {
      variant | doc "Service variant" | Variant | optional,
      listen | doc "for local service, list of ips and ports to open for listening" | Array HostPort | optional,
      address | doc "addresses clients use to connect to this service." | Array HostPort | optional,
    },

  # Network service with kind, default port and protocol
  mk_NetService : ServiceKind -> Port -> Proto -> NetService = fun kind_ defport defproto =>
    (
      NetService
      & {
        kind = kind_,
        listen | doc "for local service, list of ips and ports to open for listening" | Array (mk_HostPort defport defproto) | optional,
        address | doc "addresses clients use to connect to this service." | Array (mk_HostPort defport defproto) | optional,
      }
    ) | NetService,

  TlsSettings = {
    requireTls | Bool | default = true,
    certBundle | common.FilePath | optional,
    privateKey | String | optional,
    ciphers | doc "list of ciphers to allow" | Array String | optional,
    minTlsVersion
      | doc "minimum TLS version"
      | [| 'Tls12, 'Tls13 |]
      | optional
      | default
      = 'Tls13,
    useSni
      | doc "enable sending SNI extensions on TLS connections"
      | Bool
      | default
      = true,
  },

  SyslogServer = mk_NetService 'Syslog 514 'Udp,
  HttpsServer = mk_NetService 'Http 443 'Tcp,
}
