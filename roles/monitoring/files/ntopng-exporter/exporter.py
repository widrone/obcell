"""Prometheus exporter for ntopng Community: reads ntopng's REST API on each scrape.

Exposes per interface: traffic counters, throughput, host and flow counts, the top hosts by
traffic and the top applications (nDPI) by bytes. Listens on 127.0.0.1:9101/metrics.
"""
import ipaddress
import json
import os
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

NTOPNG = os.environ.get("NTOPNG_URL", "http://127.0.0.1:3001").rstrip("/")
LISTEN_PORT = int(os.environ.get("LISTEN_PORT", "9101"))
TOP_HOSTS = int(os.environ.get("TOP_HOSTS", "15"))
TOP_APPS = int(os.environ.get("TOP_APPS", "15"))
# Phone (UE) address pool on ogstun, and the core's own gateway address in it (not a phone).
UE_POOL = ipaddress.ip_network(os.environ.get("UE_POOL", "10.45.0.0/16"))
UE_GATEWAY = ipaddress.ip_address(os.environ.get("UE_GATEWAY", "10.45.0.1"))


def api(path):
    with urllib.request.urlopen(f"{NTOPNG}/lua/rest/v2/get/{path}", timeout=5) as r:
        body = json.load(r)
    if body.get("rc", 0) != 0:
        raise RuntimeError(f"{path}: {body.get('rc_str')}")
    return body["rsp"]


def esc(v):
    return str(v).replace("\\", "\\\\").replace('"', '\\"').replace("\n", " ")


class Metrics:
    def __init__(self):
        self.lines, self.declared = [], set()

    def add(self, metric, mtype, help_text, value, **labels):
        if metric not in self.declared:
            self.lines += [f"# HELP {metric} {help_text}", f"# TYPE {metric} {mtype}"]
            self.declared.add(metric)
        lbl = ",".join(f'{k}="{esc(v)}"' for k, v in labels.items())
        self.lines.append(f"{metric}{{{lbl}}} {float(value or 0)}")

    def text(self):
        return "\n".join(self.lines) + "\n"


def collect():
    m = Metrics()
    try:
        interfaces = api("ntopng/interfaces.lua")
    except Exception as e:  # ntopng down or still starting
        m.add("ntopng_up", "gauge", "1 if the ntopng REST API answered", 0)
        print("scrape failed:", e, flush=True)
        return m.text()
    m.add("ntopng_up", "gauge", "1 if the ntopng REST API answered", 1)

    for itf in interfaces:
        try:
            collect_interface(m, itf["ifid"], itf["ifname"])
        except Exception as e:  # keep the other interface's metrics
            print(f"interface {itf.get('ifname')}: {e}", flush=True)
    return m.text()


def collect_interface(m, ifid, ifname):
        d = api(f"interface/data.lua?ifid={ifid}")
        m.add("ntopng_interface_bytes_total", "counter", "Bytes seen on the interface",
              d.get("bytes_upload"), ifname=ifname, direction="upload")
        m.add("ntopng_interface_bytes_total", "counter", "Bytes seen on the interface",
              d.get("bytes_download"), ifname=ifname, direction="download")
        m.add("ntopng_interface_throughput_bps", "gauge", "Current throughput (bits/s)", d.get("throughput_bps"), ifname=ifname)
        m.add("ntopng_interface_hosts", "gauge", "Active hosts", d.get("num_hosts"), ifname=ifname, scope="all")
        m.add("ntopng_interface_hosts", "gauge", "Active hosts", d.get("num_local_hosts"), ifname=ifname, scope="local")
        m.add("ntopng_interface_devices", "gauge", "Active L2 devices (MACs)", d.get("num_devices"), ifname=ifname)
        m.add("ntopng_interface_flows", "gauge", "Active flows", d.get("num_flows"), ifname=ifname)
        m.add("ntopng_interface_alerted_flows", "gauge", "Active flows with an alert",
              (d.get("alerted_flows_error") or 0) + (d.get("alerted_flows_warning") or 0), ifname=ifname)
        m.add("ntopng_interface_drops", "gauge", "Packets dropped by capture", d.get("drops"), ifname=ifname)

        hosts = api(f"host/active.lua?ifid={ifid}&perPage={TOP_HOSTS}&currentPage=1"
                    "&sortColumn=column_traffic&sortOrder=desc")["data"]
        for h in hosts:
            lbl = dict(ifname=ifname, ip=h.get("ip"), host=h.get("name") or h.get("ip"),
                       local="yes" if h.get("is_localhost") else "no")
            m.add("ntopng_host_bytes_total", "counter", "Bytes sent/received by a top-talker host",
                  h["bytes"].get("sent"), direction="sent", **lbl)
            m.add("ntopng_host_bytes_total", "counter", "Bytes sent/received by a top-talker host",
                  h["bytes"].get("recvd"), direction="rcvd", **lbl)
            m.add("ntopng_host_throughput_bps", "gauge", "Current throughput of a top-talker host (bits/s)",
                  h.get("thpt", {}).get("bps"), **lbl)
            m.add("ntopng_host_flows", "gauge", "Active flows of a top-talker host",
                  h.get("num_flows", {}).get("total"), **lbl)

        if ifname == "ogstun":
            phones = 0
            page = api(f"host/active.lua?ifid={ifid}&perPage=1000&currentPage=1&mode=local")["data"]
            for h in page:
                try:
                    ip = ipaddress.ip_address(h.get("ip", ""))
                except ValueError:
                    continue
                if ip in UE_POOL and ip != UE_GATEWAY:
                    phones += 1
            m.add("ntopng_phone_hosts", "gauge", "Phones (UE pool addresses) with traffic on ogstun", phones, ifname=ifname)

        apps = api(f"interface/l7/stats.lua?ifid={ifid}&ndpistats_mode=sinceStartup")
        for a in sorted(apps, key=lambda a: a.get("value", 0), reverse=True)[:TOP_APPS]:
            m.add("ntopng_app_bytes_total", "counter", "Bytes per application protocol (nDPI) since ntopng start",
                  a.get("value"), ifname=ifname, app=a.get("label"))


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
    ThreadingHTTPServer(("127.0.0.1", LISTEN_PORT), Handler).serve_forever()
