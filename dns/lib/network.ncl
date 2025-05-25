let
# library imports
common = import "./common.ncl",
in let
  ip6_regex
    | doc m%"
      ipv6 regex Taken from
      https://stackoverflow.com/questions/53497/regular-expression-that-matches-valid-ipv6-addresses
      with minor tweaks:
        removed match for "fe80..." (link-local IPv6 addresses with zone index)
        added ::FFFF:x.y.z.w ip4-to-ip6 map (uppercase FFFF. original supported ffff lowercase)
      This might not be perfect - it doesn't need to be - but it works for our test cases
      "%
    = "^(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|::((ffff|FFFF)(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))$",
  ip4_regex
    | doc m%"regex matching ipv4 address"%
    = "^((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])$",
  # in_range : Number -> Number -> Number -> Bool = fun _min _max value =>
  #   value >= _min && value <= _max,
in
{
  patterns
    | doc "regex patterns for networking"
    = {
      _is_strnum_le
        : String -> Number -> Bool
        | doc m%"verifies that str holds a number and that the number is <= max"%
        = fun str max =>
          std.string.is_match "^\\d+$" str
          && (std.string.to_number str) <= max,
      is_ip4_regex
        : String -> Bool
        | doc m%"
            verifies the param is a valid ipv4 address (matches ipv4 regex)

            ## Examples

            ```nickel
              is_ip4_regex "10.100.0.1"
              # => true
            ```
            "%
        = std.string.is_match ip4_regex,
      is_ip6_regex
        : String -> Bool
        | doc m%"
            verifies the param is a valid ipv6 address (matches ipv6 regex)

            ## Examples

            ```nickel
              is_ip6_regex "fe80::1111:2222:3333:4444"
              # => true
            ```
            "%
        = std.string.is_match ip6_regex,
      is_ip_regex
        : String -> Bool
        | doc m%"
            verifiees the param is a valid ipv4 or ipv6 address
            ## Examples

            ```nickel
              std.array.all is_ip_regex [ "192.168.0.1", "fe80::", "::1" ]
              # => true
            ```
            "%
        = fun addr => is_ip4_regex addr || is_ip6_regex addr,

      is_ip4_cidr
        : String -> Bool
        | doc m%"
            verifies the param is a valid ipv4 CIDR: an ipv4 address,
            optionally followed by /prefix, as in "127.0.0.1/8" or "192.168.0.1/32

            ## Examples

            ```nickel
              is_ip4_cidr "192.168.0.4/24"
              # => true
            ```
            "%
        = _is_ip_cidr is_ip4_regex 32,
      is_ip6_cidr
        : String -> Bool
        | doc m%"
            verifies the param is a valid ipv6 CIDR: an ipv6 address,
            optionally followed by /prefix
            ## Examples

            ```nickel
              is_ip6_cidr "fe80::/64"
              # => true
            ```
            "%
        = _is_ip_cidr is_ip6_regex 128,
      _is_ip_cidr
        : (String -> Bool) -> Number -> String -> Bool
        = fun fn_regex bits addr =>
          let split = std.string.split "/" addr in
          std.array.length split
          |> match {
            1 => fn_regex addr,
            2 => fn_regex (std.array.at 0 split) && (_is_strnum_le (std.array.at 1 split) bits),
            _ => false,
          },

      is_ip_localhost
        | doc "true if the value is a localhost ip address"
        = fun addr => std.array.elem addr ["127.0.0.1", "::1"],
    },

  ServiceKind
    | doc m%"Category of network service. Intended to be high-level,
        such as 'Database, 'Dns, etc, and not implementation specific.
        This is used by the UI to help the user organize and identify
        categories of services. Use `Variant` describing implementations.
        Because there are so may potential variations that are impossible
        to enumerate, records containing a `ServiceKind` accept string or enum tag,
        and convert the values to an enum tag."%
    = [| 'Database, 'Dns, 'Dhcp, 'Http, 'Syslog |],

  # implementation of network service - vendor or major software package
  VariantTag
    | doc m%"Implementation type, such as the software package.
        For a `ServiceKind` 'Dns, a VariantTag might be 'Mysql, 'Postgres, etc.
        Because there are so may potential variations that are impossible
        to enumerate, records containing a `VariantTag` accept string or enum tag,
        and convert the values to an enum tag."%
    = [|
      # Dns servers
      'Unbound,
      # Databases
      'Mysql,
      'Postgres,
    |],

  Variant
    | doc m%"Description of implementation. The `Variant` information is used
        by configuration generators to create implementation
        and version-specific settings"%
    = {
      tag
        | doc "Identification of package type and provider. Required"
        | VariantTag,
      version
        | doc m%"package version, in semver syntax. Optional. Not required if the
            configuration is not version-specific"%
        | std.package.Semver
        | optional,
      features
        | doc "enabled feature flags that have an impact on configuration and deployment"
        : { _ : Dyn }
        | optional
        | default
        = {},
    },

  Port
    | doc m%"contract verifying valid port number (0-65535)

        ## Examples
        ```nickel
          8080 | Port
          # => 8080
        ```
    "%
    = common.IntInRange 0 65535,

  Ip4Address
    | doc m%"
       contract that matches an ipv4 address

       ## Examples
       ```nickel
         "127.0.0.1" | Ip4Address
         # => "127.0.0.1"
       ```
      "%
    =
      std.contract.from_validator (fun value =>
        if std.is_string value && patterns.is_ip4_regex (std.to_string value) then
          'Ok
        else
          errors.invalid_ip4
      ),

  # Ipv4 address with optional /prefix
  Ip4AddrCidr
    | doc m%"
      contract that matches an ipv4 address or CIDR.

      ## Examples
      ```nickel
        "127.0.0.1" | Ip4AddrCidr
        # => "127.0.0.1"
      ```

      ```nickel
        "10.200.1.1/24" | Ip4AddrCidr
        # => "10.200.1.1/24"
      ```
    "%
    =
      std.contract.from_validator (fun value =>
        if std.is_string value && patterns.is_ip4_cidr value then
          'Ok
        else
          errors.invalid_ip4
      ),

  # Ipv6 address
  Ip6Address
    | doc m%"
      contract that matches an ipv6 address.

      ## Examples
      ```nickel
        "::1" | Ip6Address
        # => "::1"
      ```
     "%
    =
      std.contract.from_validator (fun value =>
        if std.is_string value
        && patterns.is_ip6_regex (std.to_string value) then
          'Ok
        else
          errors.invalid_ip6
      ),

  Ip6AddrCidr
    | doc m%"
      contract that matches an ipv6 address or CIDR.

      ## Examples
      ```nickel
        "fe80::/64" | Ip6Address
        # => "fe80::/64"
      ```
     "%
    =
      std.contract.from_validator (fun value =>
        if std.is_string value && patterns.is_ip6_cidr value then
          'Ok
        else
          errors.invalid_ip6
      ),

  IpAddress
    | doc m%"
      contract that matches an ipv4 or ipv6 address

      ## Examples
      ```nickel
        [ "127.0.0.1", "::1" ] | Array IpAddress
        # => "[ "127.0.0.1", "::1" ]"
      ```
     "%
    =
      std.contract.from_validator (fun addr =>
        if std.is_string addr
        && (patterns.is_ip4_regex addr || patterns.is_ip6_regex addr) then
          'Ok
        else
          errors.invalid_ip
      ),

  IpAddrCidr
    | doc m%"
        contract that matches IPv4 address with optional CIDR prefix,
        or IPv6 address with optional CIDR prefix
      "%
    =
      std.contract.from_validator (fun value =>
        if std.is_string value
        && (patterns.is_ip4_cidr value || patterns.is_ip6_cidr value) then
          'Ok
        else
          errors.invalid_ip
      ),

  ## Error messages
  ##
  errors
    | doc m%"common error messages returned from contracts in this library"%
    = {
      invalid_ip = 'Error { message = "Invalid IP Address" },
      invalid_ip4 = 'Error { message = "Invalid IPv4 Address" },
      invalid_ip6 = 'Error { message = "Invalid IPv6 Address" },
    },

  ## Constants
  ##
  const
    | doc m%"constants useful for network configuration"%
    = {

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

  Proto
    | doc "layer 4 protocols for a NetService"
    = [| 'Udp, 'Tcp, 'TcpUdp, 'Quic |],

  HostPort
    | doc m%"
      Hostname (and/or ip address), port, and protocol

      ##Examples
      ```nickel
        { hostname = "app", address = "10.100.0.40", port = "443", proto = "Tcp" }
        | HostPort
      ```
      "%
    = {
      hostname | doc "Hostname" | String | optional,
      address | doc "Ip address" | IpAddress | optional,
      port | doc "Port. May be omitted to use default port for service" | Port | optional,
      proto | Proto | optional,
    },

  # # HostPort with specific defaults and protocol
  # mk_HostPort : Port -> Proto -> HostPort = fun defport defproto =>
  #   (
  #     HostPort
  #     & {
  #       port | default = defport,
  #       proto | default = defproto,
  #     }
  #   ) | HostPort,

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
      listen
        | doc "for local service, list of ips and ports to open for listening"
        | Array HostPort
        | optional,
      address
        | doc "addresses clients use to connect to this service."
        | Array HostPort
        | optional,
    },

  mkNetService = {
    withDefaults | not_exported = {
      kind | ServiceKind,
      port | Port,
      proto | Proto,
    },
    outputs | NetService =
      common.Entity
      & NetService
      & {
        kind | default = withDefaults.kind,
        listen
          | doc "for local service, list of ips and ports to open for listening"
          | Array (
            HostPort
            & {
              port | default = withDefaults.port,
              proto | default = withDefaults.proto,
            }
          )
          | optional,
        address
          | doc "addresses clients use to connect to this service."
          | Array (
            HostPort
            & {
              port | default = withDefaults.port,
              proto | default = withDefaults.proto,
            }
          )
          | optional,
      },
  },

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

  SyslogServer | NetService =
    (
      {
        withDefaults = {
          kind = 'Syslog,
          port = 514,
          proto = 'Udp,
        }
      } | mkNetService
    ).outputs,

  HttpsServer | NetService =
    (
      {
        withDefaults = {
          kind = 'Http,
          port = 443,
          proto = 'Tcp,
        }
      } | mkNetService
    ).outputs,
}
