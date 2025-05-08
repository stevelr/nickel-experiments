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
in let cfg = input.config.myserver,
in

let
# find subset of config schema that are dns servers
dns_servers | Array dns.DnsServer = (
  std.array.filter
    (fun server => server.kind == 'Dns)
    (std.record.values input.config)
),
if_not_null = fun val expr => if val != null then expr else {},
in
let
  dns_server_by_id
    : (String -> (Array dns.DnsServer) -> dns.DnsServer)
    = (fun id server_list =>
      (
        (common.find-first (fun server => (id == server.id)) server_list)
        |> match {
          # id must be id of a configured DnsServer, otherwise this contract will fail
          'Some server => (server | dns.DnsServer),
          'None => std.fail_with "Configuration is missing a DNS server with id %{std.to_string id}",
        }
      ) | dns.DnsServer
    ),
  remote-control-enabled = common.getdeep_or false [cfg, "extra", "settings", "remote-control", "control-enable"],
  # true if the list of addresses includes localhost
  has-localhost : (_ -> Bool) = (std.array.any (fun ip => (ip == "127.0.0.1") || (ip == "::1"))),
in
(
  # for config.service.unbound
  {
    # always enabled if the config is defined
    enable = true,
    # verify generated configuration
    # Unfortunately, this can't be used if remote-control is enabled!
    # https://github.com/NixOS/nixpkgs/issues/293001
    checkconf | priority 10 = !remote-control-enabled,
    enableRootTrustAnchor = cfg.dnssec.useRootTrustAnchor,
    group = cfg.sysConfig.group,
    user = cfg.sysConfig.user,
    localControlSocketPath | doc "path for remote control socket" | common.Nullable String | default = null,
    stateDir = cfg.sysConfig.workingDir,
    settings = {
      server =
        {
          access-control =
            cfg.netAccess
            |> std.array.map (fun rule =>
              let verb =
                rule.access
                |> match {
                  'Drop => "refuse",
                  # all other variants are vallid verbs for unbound
                  _ => std.string.lowercase (std.to_string rule.access),
                }
              in
              "%{rule.ip} %{verb}"
            ),
          do-ip4 = cfg.listen |> std.array.any (fun l => network.patterns.is_ip4_regex l.address),
          do-ip6 = cfg.listen |> std.array.any (fun l => network.patterns.is_ip6_regex l.address),
          do-tcp = cfg.listen |> std.array.any (fun l => l.proto == 'Tcp || l.proto == 'TcpUdp),
          do-udp = cfg.listen |> std.array.any (fun l => l.proto == 'Udp || l.proto == 'TcpUdp),
          hide-identity = cfg.privacy.hideHostname,
          hide-version = cfg.privacy.hideVersion,
          interface =
            # all listen IP addresses plus all declared interfaces
            (
              std.array.map
                (fun hostport =>
                  (
                    let port = std.record.get_or "port" 53 hostport in
                    if port != 53 then
                      "%{hostport.address}@%{port}"
                    else
                      hostport.address
                  )
                )
                cfg.listen
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

          #version = if cfg.privacy.version != null then cfg.privacy.version else "",
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
        & (if_not_null cfg.privacy.hostname { identity = cfg.privacy.hostname })
        & (if_not_null cfg.privacy.version { version = cfg.privacy.version })
        & (
          common.getdeep [cfg, "cache"]
          |> match {
            'Some cache =>
              {
                prefetch = cache.prefetch,
                cache-max-ttl = cache.maxTtl,
                cache-min-ttl = if std.array.elem "minTtl" (std.record.fields cache) then cache.minTtl else 0,
              },
            'None => {},
          }
        )
        & (
          common.getdeep [cfg.sysConfig, "workingDir"]
          |> match {
            'Some workingDir if workingDir != "" => { directory = workingDir },
            _ => {},
          }
        ),
      forward-zone =
        cfg.forwardZones
        |> std.array.map (fun zone =>
          (
            # dereference serverId to lookup server definition
            let server = dns_server_by_id zone.serverId dns_servers,
            in
            {
              name = if zone.domain == "*" then "." else zone.domain,
              forward-addr =
                server.address
                |> std.array.filter_map (fun hp =>
                  common.getdeep [hp, "address"]
                  |> match {
                    'None => 'None,
                    'Some addr => 'Some (if std.record.has_field "port" hp then "%{addr}@%{hp.port}" else "%{addr}")
                  }
                ),
              forward-host =
                server.address
                |> std.array.filter_map (fun hp =>
                  if (std.record.has_field "hostname" hp) then
                    'Some (if std.record.has_field "port" hp then "%{hp.hostname}@%{hp.port}" else "%{hp.hostname}")
                  else
                    'None
                ),
            }
          )
        ),
    }
  }
  & (std.record.get_or "extra" {} cfg)
)
