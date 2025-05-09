# Convert abstract dns configuration (input) to nixos unbound configuration
# (for 'service.unbound')
let
# Import libraries
common = import "lib/common.ncl",
network = import "lib/network.ncl",
dns = import "lib/dns.ncl",
# the configuration to convert
input = import "./example-dns.ncl",
#
in let
  map_rec = common.map_rec,
  getdeep = common.getdeep,
  cfg = input.config.myserver,
  # cache the subset of config objects that are dns servers
  dns_servers = std.array.filter dns.is_dns_server (std.record.values input.config),

  # # convert 'Some_/'None (e.g., output of getdeep) into a record:
  # #   'Some value is mapped through the provided function, 'None maps to {}.
  # map_rec = fun mapper => match { 'Some v => (mapper v), 'None => {} },

  # convert NetAccessRule permission enum to acceptable verb for unbound
  map_perm = match {
    'Drop => "refuse",
    # all other variants are vallid verbs for unbound
    perm => perm |> std.to_string |> std.string.lowercase,
  },
in
let
# find dns server from config with the specific id
lookup_dns_server = fun id =>
  (common.find_first (fun server => (id == server.id)) dns_servers)
  |> match {
    # id must be id of a configured DnsServer, otherwise this contract will fail
    'Some server => server | (dns.DnsServer & { .. }),
    'None => std.fail_with "Configuration is missing a DNS server with id %{std.to_string id}",
  },
in
(
  # for config.service.unbound
  {
    # always enabled if the config is defined
    enable = true,
    enableRootTrustAnchor = cfg.dnssec.useRootTrustAnchor,
    group = cfg.sysConfig.group,
    user = cfg.sysConfig.user,
    localControlSocketPath
      | doc "path for remote control socket"
      | common.Nullable String
      | default
      = null,
    stateDir = cfg.sysConfig.workingDir,
    settings = {
      server =
        {
          access-control =
            cfg.netAccess
            |> std.array.map (fun rule =>
              "%{rule.ip} %{rule.access |> map_perm}"
            ),
          directory = cfg.sysConfig.workingDir,
          do-ip4 = cfg.listen |> std.array.any (fun l => network.patterns.is_ip4_regex l.address),
          do-ip6 = cfg.listen |> std.array.any (fun l => network.patterns.is_ip6_regex l.address),
          do-tcp = cfg.listen |> std.array.any (fun l => l.proto == 'Tcp || l.proto == 'TcpUdp),
          do-udp = cfg.listen |> std.array.any (fun l => l.proto == 'Udp || l.proto == 'TcpUdp),
          hide-identity = cfg.privacy.hideHostname,
          hide-version = cfg.privacy.hideVersion,
          interface =
            # all listen IP addresses plus all declared interfaces
            (
              cfg.listen
              |> std.array.map (fun hostport =>
                let port = std.record.get_or "port" 53 hostport in
                if port != 53 then
                  "%{hostport.address}@%{port}"
                else
                  hostport.address
              )
            )
            @ (std.record.get_or "interfaces" [] cfg),
          local-data =
            cfg.localOverrides
            |> std.array.filter_map (fun ovr =>
              ovr.type
              |> match {
                'A record => 'Some "'%{record.name} A %{record.address}'",
                'AAAA record => 'Some "'%{record.name} AAAA %{record.address}'",
                'TXT record => 'Some "'%{record.name} TXT \"%{record.value}\"'",
                _ => 'None
              }
            ),
          local-data-ptr =
            cfg.localOverrides
            |> std.array.filter_map (fun ovr =>
              ovr.type
              |> match {
                'A record if record.auto-reverse => 'Some "'%{record.address} %{record.name}'",
                'AAAA record if record.auto-reverse => 'Some "'%{record.address} %{record.name}'",
                # TODO: implement PTR records
                _ => 'None
              }
            ),
          # log queries if requested, regardless of verbosity level
          log-queries = cfg.logging.queries,
          logfile =
            # log to stderr if logfile is ""
            if (cfg.logging.toStderr || !std.is_string cfg.logging.logDir) then
              "\"\""
            else
              "%{cfg.logging.logDir}/unbound.log",

          minimal-responses = cfg.privacy.minimalResponse,
          qname-minimisation = cfg.privacy.qnameMinimisation,
          private-address = cfg.privateAddresses,
          private-domain = std.record.get_or "privateDomains" [] cfg,
          verbosity =
            if cfg.logging.cacheMiss then
              5
            else if (std.array.elem cfg.verbosity ['Debug, 'Trace]) then
              4
            else if cfg.logging.requests || cfg.logging.responses then
              3
            else if std.array.elem cfg.verbosity ['Error, 'Warning] then
              0
            else
              # anything else
              # Confirm we didn't omit another verbosity enum variant.
              let _ = cfg.verbosity == 'Info | std.test.Assert in
              1,
        }
        & (getdeep [cfg.privacy, "hostname"] |> map_rec (fun h => { identity = h }))
        & (getdeep [cfg.privacy, "version"] |> map_rec (fun v => { version = v }))
        & (
          getdeep [cfg, "cache"]
          |> map_rec (fun cache =>
            {
              prefetch = cache.prefetch,
              cache-max-ttl = cache.maxTtl,
              cache-min-ttl = if std.array.elem "minTtl" (std.record.fields cache) then cache.minTtl else 0,
            }
          )
        ),
      forward-zone =
        cfg.forwardZones
        |> std.array.map (fun zone =>
          (
            # dereference serverId to lookup server definition
            let server = lookup_dns_server zone.serverId in
            {
              # no domain field is treated as wildcard.
              name = if (std.record.get_or "domain" "*" zone) == "*" then "." else zone.domain,
              forward-addr =
                server.address
                |> std.array.filter_map (fun hp =>
                  (getdeep [hp, "address"])
                  |> std.enum.map (fun addr =>
                    if std.record.has_field "port" hp then "%{addr}@%{hp.port}" else "%{addr}"
                  )
                ),
              forward-host =
                server.address
                |> std.array.filter_map (fun hp =>
                  (getdeep [hp, "hostname"])
                  |> std.enum.map (fun host =>
                    if std.record.has_field "port" hp then "%{host}@%{hp.port}" else "%{host}"
                  )
                ),
            }
          )
        ),
    },
    # whether to verify generated configuration using unbound-checkconf.
    # unbound-checkconf is somewhat useful as an extra validation,
    # but with limitations:
    # - error messages aren't very informative: they contain line numbers only,
    #   not error descriptions, and line numbers can be off-by-one, and you have
    #   to find the generated file in the nix store, so we much prefer
    #   to catch errors earlier
    # - it can't be used if remote-control is enabled
    #   (ref: https://github.com/NixOS/nixpkgs/issues/293001)
    checkconf | priority 10 =
      !(common.getdeep_or false [cfg, "extra", "settings", "remote-control", "control-enable"]),
  }
  & (std.record.get_or "extra" {} cfg)
)
