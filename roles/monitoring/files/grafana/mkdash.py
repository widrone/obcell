"""Generates the Open5GS / host overview Grafana dashboard."""
import json, sys
import os
LAN = os.environ.get("OBCELL_LAN_IFACE", "eno1")
HOST = os.environ.get("OBCELL_NAME", "obcell")

DS = {"type": "prometheus", "uid": "prometheus"}
panels, y = [], 0
pid = 0

def nid():
    global pid; pid += 1; return pid

def row(title):
    global y
    panels.append({"type": "row", "title": title, "id": nid(), "gridPos": {"x": 0, "y": y, "w": 24, "h": 1}, "collapsed": False})
    y += 1

def stat(title, expr, x, w=4, h=4, desc="", unit="none", thresholds=None):
    panels.append({"type": "stat", "title": title, "id": nid(), "description": desc, "datasource": DS,
        "gridPos": {"x": x, "y": y, "w": w, "h": h},
        "targets": [{"refId": "A", "datasource": DS, "expr": expr, "instant": True}],
        "fieldConfig": {"defaults": {"unit": unit, "color": {"mode": "thresholds"},
            "thresholds": {"mode": "absolute", "steps": thresholds or [{"color": "blue", "value": None}]}}, "overrides": []},
        "options": {"reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False},
                    "colorMode": "background", "graphMode": "area", "textMode": "value", "justifyMode": "center"}})

def ts(title, targets, x, w=12, h=8, unit="none", desc="", stack=False):
    panels.append({"type": "timeseries", "title": title, "id": nid(), "description": desc, "datasource": DS,
        "gridPos": {"x": x, "y": y, "w": w, "h": h},
        "targets": [{"refId": chr(65 + i), "datasource": DS, "expr": e, "legendFormat": l} for i, (e, l) in enumerate(targets)],
        "fieldConfig": {"defaults": {"unit": unit, "custom": {"fillOpacity": 15, "lineWidth": 2, "showPoints": "never",
            "stacking": {"mode": "normal" if stack else "none"}}}, "overrides": []},
        "options": {"legend": {"displayMode": "list", "placement": "bottom"}, "tooltip": {"mode": "multi"}}})

def bars(title, expr, legend, x, w=12, h=9, unit="none", desc=""):
    panels.append({"type": "bargauge", "title": title, "id": nid(), "description": desc, "datasource": DS,
        "gridPos": {"x": x, "y": y, "w": w, "h": h},
        "targets": [{"refId": "A", "datasource": DS, "expr": expr, "legendFormat": legend, "instant": True}],
        "fieldConfig": {"defaults": {"unit": unit, "min": 0, "color": {"mode": "continuous-BlYlRd"},
            "thresholds": {"mode": "absolute", "steps": [{"color": "blue", "value": None}]}}, "overrides": []},
        "options": {"orientation": "horizontal", "displayMode": "gradient", "showUnfilled": True, "valueMode": "color",
                    "namePlacement": "left", "reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False}}})

UP = [{"color": "red", "value": None}, {"color": "green", "value": 1}]

row("Network status")
stat("5G cells", 'sum(gnb{nf="amf"})', 0, desc="gNBs with an active NG connection to the AMF", thresholds=UP)
stat("5G phones", 'sum(ran_ue{nf="amf"})', 4, desc="UEs with an NGAP context in the AMF")
stat("4G cells", 'sum(enb{nf="mme"})', 8, desc="eNBs with an active S1 connection to the MME", thresholds=UP)
stat("4G phones", 'sum(enb_ue{nf="mme"})', 12, desc="UEs with an S1AP context in the MME")
stat("Data sessions", 'sum(fivegs_upffunction_upf_sessionnbr{nf="upf"})', 16, desc="Active PDU sessions / bearers through the UPF (4G + 5G)")
stat("Core NFs up", 'sum(up{job="open5gs"}) or vector(0)', 20, desc="Open5GS network functions answering metrics scrapes (of 7)",
     thresholds=[{"color": "red", "value": None}, {"color": "orange", "value": 5}, {"color": "green", "value": 7}])
y += 4

row("Phones and sessions")
ts("Connected phones", [('sum(ran_ue{nf="amf"})', "5G phones (AMF)"), ('sum(enb_ue{nf="mme"})', "4G phones (MME)")], 0)
ts("Sessions", [('sum(amf_session{nf="amf"})', "5G AMF sessions"), ('sum(mme_session{nf="mme"})', "4G MME sessions"),
                ('sum(fivegs_upffunction_upf_sessionnbr{nf="upf"})', "UPF data sessions")], 12)
y += 8

row("5G registration and authentication (AMF)")
ts("Registration attempts / successes per minute", [
    ('sum(rate(fivegs_amffunction_rm_reginitreq[5m]))*60', "initial req"),
    ('sum(rate(fivegs_amffunction_rm_reginitsucc[5m]))*60', "initial ok"),
    ('sum(rate(fivegs_amffunction_rm_regmobreq[5m]))*60', "mobility req"),
    ('sum(rate(fivegs_amffunction_rm_regperiodreq[5m]))*60', "periodic req")], 0, unit="short")
ts("Authentication per minute", [
    ('sum(rate(fivegs_amffunction_amf_authreq[5m]))*60', "auth requests"),
    ('sum(rate(fivegs_amffunction_amf_authreject[5m]))*60', "auth rejects")], 12, unit="short",
   desc="Rejects usually mean a SIM whose keys don't match the subscriber database")
y += 8
stat("Registrations (total)", 'sum(fivegs_amffunction_rm_reginitsucc)', 0, w=6, desc="Successful initial registrations since AMF start")
stat("Auth rejects (total)", 'sum(fivegs_amffunction_amf_authreject)', 6, w=6,
     thresholds=[{"color": "green", "value": None}, {"color": "red", "value": 1}])
stat("Paging requests (total)", 'sum(fivegs_amffunction_mm_paging5greq)', 12, w=6)
stat("Subscribers known to HSS (4G)", 'sum(hss_imsi)', 18, w=6)
y += 4

row("User-plane traffic (UPF, all phones)")
ts("GTP packets per second", [
    ('sum(rate(fivegs_ep_n3_gtp_indatapktn3upf[1m]))', "uplink (from phones)"),
    ('sum(rate(fivegs_ep_n3_gtp_outdatapktn3upf[1m]))', "downlink (to phones)")], 0, unit="pps")
ts("Phone traffic on ogstun (bytes/s)", [
    ('rate(node_network_receive_bytes_total{device="ogstun"}[1m])', "uplink (phones -> internet)"),
    ('rate(node_network_transmit_bytes_total{device="ogstun"}[1m])', "downlink (internet -> phones)")], 12, unit="Bps",
   desc="Per-phone breakdown is in ntopng")
y += 8

row(f"Network traffic (ntopng: phones on ogstun, LAN on {LAN})")
stat("Phones with traffic", 'sum(ntopng_phone_hosts) or vector(0)', 0, desc="Phone (UE pool 10.45.0.0/16) addresses with traffic on ogstun, excluding the core's gateway 10.45.0.1")
stat(f"LAN hosts ({LAN})", f'sum(ntopng_interface_hosts{{ifname="{LAN}",scope="local"}})', 4, desc=f"Local LAN hosts seen on {LAN} (this machine's traffic plus broadcast/multicast)")
stat("Active flows", 'sum(ntopng_interface_flows)', 8)
stat("Alerted flows", 'sum(ntopng_interface_alerted_flows)', 12,
     thresholds=[{"color": "green", "value": None}, {"color": "orange", "value": 1}], desc="Flows ntopng flagged (see Alerts in ntopng)")
stat("Capture drops (5 min)", 'sum(increase(ntopng_interface_drops[5m])) or vector(0)', 16, desc="Packets ntopng failed to capture in the last 5 minutes (it shares cores 2-3 with the other containers)",
     thresholds=[{"color": "green", "value": None}, {"color": "red", "value": 1}])
stat("ntopng", 'max(ntopng_up) or vector(0)', 20, thresholds=UP, desc="1 = ntopng answering the exporter")
y += 4
ts("Throughput per interface", [('ntopng_interface_throughput_bps', "{{ifname}}")], 0, unit="bps")
ts("Traffic per interface (bytes/s)", [('sum by (ifname, direction) (rate(ntopng_interface_bytes_total[2m]))', "{{ifname}} {{direction}}")], 12, unit="Bps")
y += 8
bars("Top talkers now", 'topk(10, ntopng_host_throughput_bps)', "{{ifname}}  {{host}}", 0, unit="bps",
     desc="Current throughput of the busiest hosts on each interface (from ntopng)")
bars("Top applications, last hour", 'topk(10, sum by (ifname, app) (increase(ntopng_app_bytes_total[1h])))', "{{ifname}}  {{app}}", 12, unit="bytes",
     desc="Bytes per application protocol detected by nDPI")
y += 9

row(f"Host ({HOST})")
ts("CPU usage per core", [('100 - avg by (cpu) (rate(node_cpu_seconds_total{mode="idle"}[1m]))*100', "core {{cpu}}")], 0, unit="percent",
   desc="Cores 0-1 are reserved for the gNB; 2-3 run media/monitoring containers")
ts("Memory and LAN", [('node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes', "memory used"),
                      (f'rate(node_network_receive_bytes_total{{device="{LAN}"}}[1m])', f"{LAN} rx/s"),
                      (f'rate(node_network_transmit_bytes_total{{device="{LAN}"}}[1m])', f"{LAN} tx/s")], 12, unit="bytes")
y += 8

dash = {"title": "Open5GS core overview", "uid": "open5gs-overview", "tags": ["open5gs", "4G", "5G"],
        "timezone": "browser", "refresh": "5s", "time": {"from": "now-1h", "to": "now"}, "schemaVersion": 39,
        "editable": True, "panels": panels,
        "links": [{"title": "gNB radio dashboards (OCUDU)", "type": "dashboards", "tags": [], "asDropdown": True, "includeVars": False, "keepTime": True},
                  {"title": "ntopng (per-phone traffic)", "type": "link", "url": "/ntopng", "targetBlank": True}]}
json.dump(dash, open(sys.argv[1], "w"), indent=1)
print(len(panels), "panels")
