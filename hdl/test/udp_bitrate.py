#!/usr/bin/env python3
"""UDP bitrate test for the PA200T UDP subsystem.

The FPGA is configured and read back over the J-Link pin TAP (OpenOCD), the
traffic itself runs over Ethernet:

  tx    FPGA -> host: the hardware generator sends sequence-numbered packets,
        the host counts them. Rate measured by the FPGA and by the host.
  rx    host -> FPGA: the host sends as fast as the kernel allows, the FPGA
        counts bytes and cycles.
  echo  host -> FPGA -> host: functional check with varying lengths.

Usage (from hdl/):  python3 test/udp_bitrate.py [--skip-setup] [--tests tx,rx,echo]
"""

import argparse
import os
import re
import socket
import struct
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
F_CLK = 125e6
# Ethernet overhead per UDP packet on the wire: preamble+SFD 8, MAC header 14,
# FCS 4, IFG 12, IPv4 header 20, UDP header 8.
WIRE_OVERHEAD = 8 + 14 + 4 + 12 + 20 + 8


def openocd(commands, setup_vars=None, script="pa200t_jlink.tcl", timeout=120):
    args = ["openocd"]
    for name, value in (setup_vars or {}).items():
        args += ["-c", f"set {name} {value}"]
    args += ["-f", os.path.join(HERE, script)]
    if commands:
        args += ["-c", f"{commands}; shutdown"]
    proc = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
    out = proc.stdout + proc.stderr
    if proc.returncode != 0:
        sys.exit(f"openocd failed ({proc.returncode}):\n{out}")
    return out


def openocd_async(commands):
    args = ["openocd", "-f", os.path.join(HERE, "pa200t_jlink.tcl"), "-c", f"{commands}; shutdown"]
    return subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)


def parse(prefix, text):
    return {m.group(1): int(m.group(2), 0) for m in re.finditer(rf"^{prefix} (\w+) (\S+)$", text, re.M)}


def traffic_counters():
    out = openocd("bluej_traffic_dump pa200t.tap 0x3; bluej_eth_status pa200t.tap 0x3")
    return parse("TRAFFIC", out), parse("ETH", out)


def iface_of(ip):
    out = subprocess.run(["ip", "-o", "-4", "addr"], capture_output=True, text=True).stdout
    for line in out.splitlines():
        fields = line.split()
        if fields[3].split("/")[0] == ip:
            return fields[1]
    return None


def nic_stats(iface):
    stats = {}
    for name in ("rx_packets", "rx_crc_errors", "rx_dropped", "rx_missed_errors"):
        try:
            with open(f"/sys/class/net/{iface}/statistics/{name}") as f:
                stats[name] = int(f.read())
        except (OSError, TypeError):
            pass
    return stats


def neigh_state(ip):
    out = subprocess.run(["ip", "neigh", "show", ip], capture_output=True, text=True).stdout.split()
    return out[-1] if out else "NONE"


def arp_flux_possible(host_ip, iface):
    """True if another interface shares host_ip's subnet and may answer the FPGA's ARP requests."""
    def sysctl(name, dev):
        try:
            with open(f"/proc/sys/net/ipv4/conf/{dev}/{name}") as f:
                return int(f.read())
        except OSError:
            return 0
    if max(sysctl("arp_ignore", "all"), sysctl("arp_ignore", iface)) >= 1:
        return False
    out = subprocess.run(["ip", "-o", "-4", "addr"], capture_output=True, text=True).stdout
    nets = {}
    for line in out.splitlines():
        f = line.split()
        addr, plen = f[3].split("/")
        a = struct.unpack(">I", socket.inet_aton(addr))[0]
        mask = (0xffffffff << (32 - int(plen))) & 0xffffffff
        nets.setdefault((a & mask, mask), set()).add(f[1])
    a = struct.unpack(">I", socket.inet_aton(host_ip))[0]
    return any(len(devs) > 1 and (a & mask) == net for (net, mask), devs in nets.items())


def steer_arp(sock, fpga, iface):
    """Make the FPGA's ARP entry for this host point at iface.

    With arp_ignore=0 every interface of this host answers the FPGA's ARP request
    and the last reply (usually Wi-Fi) wins. The FPGA's request also marks the
    host's neighbour entry stale, so the kernel soon sends a unicast probe from
    iface; the FPGA caches the sender of every ARP frame, which fixes the entry.
    """
    print(f"ARP: another interface shares the subnet; waiting for {iface}'s ARP probe "
          "(skip with: sudo sysctl -w net.ipv4.conf.all.arp_ignore=1)")
    openocd("bluej_traffic_echo pa200t.tap 1 0x3")
    sock.settimeout(0.2)
    try:
        sock.sendto(b"arp", fpga)       # the echo makes the FPGA resolve this host
        try:
            sock.recv(2048)
        except socket.timeout:
            pass
        probing = False
        deadline = time.monotonic() + 90
        while time.monotonic() < deadline:
            sock.sendto(b"arp", fpga)
            try:
                sock.recv(2048)
            except socket.timeout:
                pass
            state = neigh_state(fpga[0])
            if state in ("DELAY", "PROBE"):
                probing = True
            elif probing and state == "REACHABLE":
                break
            time.sleep(0.2)
        before = nic_stats(iface).get("rx_packets", 0)
        replies = 0
        for _ in range(100):
            sock.sendto(b"path", fpga)
            try:
                sock.recv(2048)
                replies += 1
            except socket.timeout:
                pass
        arrived = nic_stats(iface).get("rx_packets", 0) - before
    finally:
        openocd("bluej_traffic_echo pa200t.tap 0 0x3")
    ok = replies == 100 and arrived >= 100
    print(f"ARP: {replies}/100 replies, {arrived} packets arrived on {iface}: {'ok' if ok else 'still another path'}")
    return ok


def mbps(bytes_, seconds):
    return bytes_ * 8 / seconds / 1e6 if seconds > 0 else 0.0


def payload(seq, length):
    head = struct.pack(">I", seq & 0xffffffff)
    body = bytes((i & 0xff) for i in range(4, length))
    return (head + body)[:length]


def test_tx(args, sock, iface):
    """FPGA generator -> host socket."""
    length, count = args.length, args.count
    print(f"\n== TX: FPGA -> host, {count} x {length} B")
    sock.settimeout(0.5)
    while True:  # drain leftovers
        try:
            sock.recv(2048)
        except socket.timeout:
            break

    buf = bytearray(2048)
    view = memoryview(buf)
    body = bytes((i & 0xff) for i in range(4, length))
    received = 0
    rx_bytes = 0
    bad = 0
    max_seq = -1
    out_of_order = 0
    first = last = None

    nic0 = nic_stats(iface)
    proc = openocd_async(f"bluej_traffic_tx pa200t.tap {length} {count} {args.gap} 0x3")
    deadline = time.monotonic() + 30
    idle_since = None
    while time.monotonic() < deadline:
        try:
            n = sock.recv_into(buf)
        except socket.timeout:
            if proc.poll() is not None:
                if received or idle_since is None:
                    idle_since = idle_since or time.monotonic()
                if received >= count or (idle_since and time.monotonic() - idle_since > 2):
                    break
            continue
        now = time.perf_counter()
        if first is None:
            first = now
        last = now
        received += 1
        rx_bytes += n
        seq = struct.unpack_from(">I", buf)[0]
        if seq < max_seq:
            out_of_order += 1
        max_seq = max(max_seq, seq)
        if n != length or view[4:n] != body:
            bad += 1
        if received >= count:
            break
    proc.wait()
    nic1 = nic_stats(iface)

    c, eth = traffic_counters()
    hw_secs = c["TX_CYCLES"] / F_CLK
    hw_bytes = c["TX_PACKETS"] * length
    lost = count - received
    host_secs = (last - first) if received > 1 else 0
    print(f"FPGA sent {c['TX_PACKETS']} packets in {c['TX_CYCLES']} cycles: "
          f"{mbps(hw_bytes, hw_secs):.1f} Mb/s payload, "
          f"{mbps(c['TX_PACKETS'] * (length + WIRE_OVERHEAD), hw_secs):.1f} Mb/s on the wire")
    print(f"host received {received} packets ({lost} lost, {bad} bad, {out_of_order} out of order), "
          f"{mbps(rx_bytes, host_secs):.1f} Mb/s payload over {host_secs * 1e3:.1f} ms")
    if nic0:
        print(f"{iface}: " + ", ".join(f"{k} +{nic1[k] - nic0[k]}" for k in nic0))
        if nic1["rx_packets"] - nic0["rx_packets"] < received * 0.99:
            print(f"error: most packets did not arrive on {iface}; the FPGA resolved this host to another"
                  " interface (ARP flux). Set net.ipv4.conf.all.arp_ignore=1 or rerun with --steer-arp.")
            return False
    loss_pct = 100.0 * lost / count
    if lost:
        print(f"note: {loss_pct:.2f}% lost on the host side; at full line rate the receiving NIC/driver"
              " can drop packets (rx_packets above counts them arriving). Use --gap to lower the rate.")
    return c["TX_PACKETS"] == count and bad == 0 and out_of_order == 0 and loss_pct <= args.max_loss


def test_rx(args, sock, fpga):
    """Host socket -> FPGA counters."""
    length, count = args.length, args.count
    print(f"\n== RX: host -> FPGA, {count} x {length} B")
    sock.sendto(payload(0, 16), fpga)   # resolve ARP before the timed run
    time.sleep(0.3)
    openocd(f"bluej_traffic_rx_clear pa200t.tap {args.fpga_port} 0x3")

    packets = [payload(i, length) for i in range(min(count, 4096))]
    t0 = time.perf_counter()
    for i in range(count):
        p = packets[i % len(packets)]
        if i >= len(packets):
            p = struct.pack(">I", i) + p[4:]
        while True:
            try:
                sock.sendto(p, fpga)
                break
            except BlockingIOError:
                pass
            except OSError as e:
                if e.errno == 105:  # ENOBUFS: queue full, retry
                    continue
                raise
    t1 = time.perf_counter()
    time.sleep(0.3)

    c, eth = traffic_counters()
    secs = c["RX_CYCLES"] / F_CLK
    print(f"host sent {count} packets in {(t1 - t0) * 1e3:.1f} ms: {mbps(count * length, t1 - t0):.1f} Mb/s payload")
    print(f"FPGA counted {c['RX_PACKETS']} packets / {c['RX_BYTES']} B in {c['RX_CYCLES']} cycles: "
          f"{mbps(c['RX_BYTES'], secs):.1f} Mb/s payload; "
          f"{count - c['RX_PACKETS']} lost, {c['RX_SEQ_ERRORS']} sequence gaps, {c['RX_BAD_FRAMES']} bad, "
          f"{c['RX_IGNORED']} other ports")
    print("endpoint: " + ", ".join(f"{k}={v:#x}" for k, v in eth.items()))
    return c["RX_PACKETS"] == count and c["RX_BAD_FRAMES"] == 0


def test_echo(args, sock, fpga):
    print("\n== ECHO: host -> FPGA -> host")
    openocd("bluej_traffic_echo pa200t.tap 1 0x3")
    sock.settimeout(0.5)
    ok = 0
    lengths = [1, 2, 3, 4, 5, 17, 64, 255, 256, 511, 1000, 1471, 1472]
    try:
        for i, n in enumerate(lengths * 4):
            data = payload(i, n) if n >= 4 else bytes(range(n))
            sock.sendto(data, fpga)
            try:
                reply, src = sock.recvfrom(2048)
            except socket.timeout:
                print(f"  no reply for {n} B")
                continue
            if reply == data:
                ok += 1
            else:
                print(f"  mismatch for {n} B: got {len(reply)} B")
    finally:
        openocd("bluej_traffic_echo pa200t.tap 0 0x3")
    total = len(lengths) * 4
    print(f"{ok}/{total} echoed packets correct")
    return ok == total


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--fpga-ip", default="192.168.178.250")
    ap.add_argument("--host-ip", default=None, help="default: the address routing to --fpga-ip")
    ap.add_argument("--netmask", default="255.255.255.0")
    ap.add_argument("--gateway", default="192.168.178.1")
    ap.add_argument("--mac", default="02:50:41:32:30:30")
    ap.add_argument("--fpga-port", type=int, default=5000)
    ap.add_argument("--host-port", type=int, default=5001)
    ap.add_argument("--length", type=int, default=1472, help="UDP payload bytes")
    ap.add_argument("--count", type=int, default=100000)
    ap.add_argument("--gap", type=int, default=0, help="FPGA idle cycles after each generated packet")
    ap.add_argument("--tests", default="tx,rx,echo")
    ap.add_argument("--skip-setup", action="store_true", help="keep the PHY and endpoint configuration")
    ap.add_argument("--steer-arp", choices=("auto", "always", "never"), default="auto",
                    help="make the FPGA's ARP entry point at the wired NIC (auto: if another NIC shares the subnet)")
    ap.add_argument("--max-loss", type=float, default=1.0,
                    help="TX packets the host may miss, in percent (host NIC drops at full line rate)")
    args = ap.parse_args()

    host_ip = args.host_ip
    if host_ip is None:
        probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        probe.connect((args.fpga_ip, args.fpga_port))
        host_ip = probe.getsockname()[0]
        probe.close()

    if not args.skip_setup:
        print(f"setup: FPGA {args.fpga_ip} ({args.mac}), peer {host_ip}:{args.host_port}")
        out = openocd(None, {
            "udp_mac": args.mac.replace(":", ""),
            "udp_local_ip": args.fpga_ip,
            "udp_netmask": args.netmask,
            "udp_gateway": args.gateway,
            "udp_peer_ip": host_ip,
            "udp_src_port": args.fpga_port,
            "udp_dst_port": args.host_port,
        }, script="pa200t_udp_setup.tcl")
        for line in out.splitlines():
            if line.startswith(("PHY link", "eth ", "ETH ")):
                print(" ", line)
        if "UDP SETUP DONE" not in out:
            sys.exit(out)

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 48 << 20)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 4 << 20)
    sock.bind((host_ip, args.host_port))
    fpga = (args.fpga_ip, args.fpga_port)
    iface = iface_of(host_ip)

    if args.steer_arp == "always" or (args.steer_arp == "auto" and arp_flux_possible(host_ip, iface)):
        if not steer_arp(sock, fpga, iface):
            sys.exit("could not make the FPGA reach this host on " + str(iface))

    results = {}
    for test in args.tests.split(","):
        if test == "tx":
            results[test] = test_tx(args, sock, iface)
        elif test == "rx":
            results[test] = test_rx(args, sock, fpga)
        elif test == "echo":
            results[test] = test_echo(args, sock, fpga)
        else:
            sys.exit(f"unknown test {test}")

    print("\n" + ", ".join(f"{t}: {'PASS' if r else 'FAIL'}" for t, r in results.items()))
    sys.exit(0 if all(results.values()) else 1)


if __name__ == "__main__":
    main()
