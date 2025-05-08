let network = import "../lib/network.ncl"
in
let NotC = fun c => std.contract.not c,
in
{
  hp_laserjet =
    {
      id = "101",
      kind = 'Printer,
      comment = "front desk",
      host = ["hp-printer", "hp451"],
      address = ["100.100.100.19"],
    } | network.NetHost,

  valid-ip4 = [
    # An address is also AddrCidr
    "1.1.1.1" | network.Ip4Address | network.Ip4AddrCidr,
    "10.10.10.100" | network.Ip4Address | network.Ip4AddrCidr,
    "255.255.255.255" | network.Ip4Address | network.Ip4AddrCidr,
    "127.0.0.1" | network.Ip4Address | network.Ip4AddrCidr,
  ],
  invalid-ip4 = [
    "" | NotC network.Ip4Address,
    "10.10.10.256" | NotC network.Ip4Address,
    "0" | NotC network.Ip4Address,
    "a.a.a.a" | NotC network.Ip4Address,
    "1.1.1.1.1" | NotC network.Ip4Address,
    "fe80::" | NotC network.Ip4Address,
  ],
  valid-ip4-cidr = [
    # valud examples
    "1.1.1.1/32" | network.Ip4AddrCidr,
    "10.0.0.1/8" | network.Ip4AddrCidr,
    "0.0.0.0/0" | network.Ip4AddrCidr,
  ],
  invalid-ip4-cidr = [
    # valud examples
    "1.1.1.1/33" | NotC network.Ip4AddrCidr,
    "10.0.0.1111/8" | NotC network.Ip4AddrCidr,
    "0.0.0.0/-1" | NotC network.Ip4AddrCidr,
    "127.0.0.0.0/8" | NotC network.Ip4AddrCidr,
  ],
  valid-ip6 = [
    "fe80::/64" | network.Ip6AddrCidr,
    "FE80::/64" | network.Ip6AddrCidr,
    "::" | network.Ip6Address | network.Ip6AddrCidr,
    "::1" | network.Ip6Address | network.Ip6AddrCidr,
    "fe80::21d8:f50:c295:c4be" | network.Ip6Address,
    "2001:cdba:0000:0000:0000:0000:3257:9652" | network.Ip6Address | network.Ip6AddrCidr,
    "2001:cdba:0:0:0:0:3257:9652" | network.Ip6Address | network.Ip6AddrCidr,
    "2001:cdba::3257:9652" | network.Ip6Address | network.Ip6AddrCidr,
    "2001:cdba::1222" | network.Ip6Address | network.Ip6AddrCidr,
    "21DA:D3:0:2F3B:2AA:FF:FE28:9C5A" | network.Ip6Address | network.Ip6AddrCidr,
    "2001:cdba::1:2:3:3257:9652" | network.Ip6Address | network.Ip6AddrCidr,
    "::1" | network.Ip6Address | network.Ip6AddrCidr,
    "1::8" | network.Ip6Address | network.Ip6AddrCidr,
    "1:2::8" | network.Ip6Address | network.Ip6AddrCidr,
  ],

  # test the ip4-v6 mapping syntax
  valid-ip4-to-ip6 = [
    "::ffff:192.168.0.1" | network.Ip6Address,
    "::ffff:100.100.100.100" | network.Ip6Address,
    "::FFFF:100.100.100.100" | network.Ip6Address,
  ],
}
