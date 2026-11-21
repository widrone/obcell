"""Prometheus exporter for the Obcell's SDR hardware: which SDR dongles are plugged in (read from the host's
/sys/bus/usb, visible read-only in the container). Listens on 127.0.0.1:9102/metrics."""
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

USB = "/sys/bus/usb/devices"
PORT = int(os.environ.get("LISTEN_PORT", "9102"))
# (vendor, product) -> SDR kind
KNOWN = {
    ("0bda", "2832"): "rtlsdr", ("0bda", "2838"): "rtlsdr",
    ("0403", "601f"): "limesdr_mini",
    ("1d50", "6089"): "hackrf", ("1d50", "60a1"): "airspy",
    ("1d50", "6108"): "limesdr_usb",
    ("2500", "0020"): "usrp_b2xx", ("2500", "0021"): "usrp_b2xx", ("2500", "0022"): "usrp_b2xx",
}


def read(path):
    try:
        with open(path) as f:
            return f.read().strip()
    except OSError:
        return ""


def esc(v):
    return v.replace("\\", "\\\\").replace('"', '\\"')


def collect():
    lines = ["# HELP sdr_device_info SDR device present on USB (1 per device).", "# TYPE sdr_device_info gauge"]
    counts = {kind: 0 for kind in set(KNOWN.values())}
    for dev in sorted(os.listdir(USB)):
        d = os.path.join(USB, dev)
        kind = KNOWN.get((read(f"{d}/idVendor"), read(f"{d}/idProduct")))
        if not kind:
            continue
        counts[kind] += 1
        lines.append(f'sdr_device_info{{kind="{kind}",usb_port="{esc(dev)}",product="{esc(read(f"{d}/product"))}",'
                     f'serial="{esc(read(f"{d}/serial"))}",speed_mbps="{esc(read(f"{d}/speed"))}"}} 1')
    lines += ["# HELP sdr_devices Number of SDR devices of each kind present on USB.", "# TYPE sdr_devices gauge"]
    lines += [f'sdr_devices{{kind="{k}"}} {n}' for k, n in sorted(counts.items())]
    return "\n".join(lines) + "\n"


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/metrics":
            self.send_error(404)
            return
        body = collect().encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; version=0.0.4")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
