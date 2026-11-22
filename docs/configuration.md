# Configuration reference

## Where settings live

| File | What goes in it |
|---|---|
| `inventory/hosts.yml` | the Obcells, and how Ansible reaches each one (`ansible_connection: local` on the box itself, or `ansible_host` + `ansible_user` over SSH) |
| `inventory/<host>.yml` | a box added by `install.sh`. Ansible reads every file in `inventory/`, so this works the same as an entry in `hosts.yml` |
| `inventory/host_vars/<host>/main.yml` | everything that is specific to one box |
| `group_vars/all/main.yml` | defaults for every Obcell, plus values derived from host_vars |
| `group_vars/all/sdr.yml` | one profile per supported radio |
| `group_vars/all/web.yml` | names and URLs the web front door answers on (derived) |
| `group_vars/all/secrets.yml` | where each secret comes from (lookups into `secrets/<host>/`) |

Everything web-facing is derived from host_vars, so none of it is edited by hand: Caddy
sites, Authelia domains, CORS/CSRF/allowed-origin lists, Homepage links and allowed hosts,
probes, the gNB YAML, the systemd units, the CPU fences and the dashboards.

## Host settings (`host_vars/<host>/main.yml`)

| Variable | Meaning | Default |
|---|---|---|
| `obcell_user`, `obcell_name` | owner of `~/openlive` etc.; the box name (`<name>.local` via mDNS) | `ansible_user`, the inventory name |
| `obcell_lan_iface` | LAN interface (mDNS, ntopng, dashboards); IP and CIDR come from facts | the default-route interface |
| `obcell_timezone`, `obcell_set_hostname` | time zone; whether to set the OS hostname to `obcell_name` | — / `false` |
| `sdr_type` | `limesdr_mini`, `limesdr_usb`, `usrp_b2xx`, `usrp_x3xx`, `zmq` (no RF) | `zmq` |
| `sdr_serial` | pin the gNB to one device | "" |
| `cell` | `band`, `dl_arfcn`, `bandwidth_mhz`, `scs_khz`, `pci`, `srate`, `tx_gain`/`rx_gain` (null = SDR default) | n40, 2350 MHz, 20 MHz |
| `gnb_start_at_boot` | enable the gNB unit at boot (it transmits!) | `false`; keep it that way |
| `open5gs_mcc/mnc/tac`, `ue_pool_v4` | PLMN, tracking area, phone address pool | 999/70, TAC 1, 10.45.0.0/16 |
| `obcell_cpus` | CPUs the gNB/container split is made from | detected each run from PID 1's affinity (honours cgroup limits, offline CPUs, isolcpus) |
| `cpu_pinning`, `gnb_cpus`, `container_cpus` | the gNB gets its own CPUs; containers are fenced off them | on with ≥4 usable CPUs: lower half / upper half |
| `ocudu_build_jobs` | parallel compile jobs | one per CPU, at most one per 2 GiB RAM |
| `tailscale_enabled`, `obcell_tailnet_name`, `tailscale_authkey` | tailnet access + Let's Encrypt certs via tailscaled | off |
| `srsue_enabled` | build srsUE + the ZMQ test configs (virtual phone) | off |
| `rtlsdr_enabled` | RTL-SDR for OpenWebRX (driver blacklist, receiver profiles) | on |
| `usb2_roothub_no_autosuspend` | xHCI quirk (the reference NUC) | off |
| `openlive_enabled`, `intercom_enabled`, `monitoring_enabled` | skip whole stacks | on |
| `owntracks_enabled` | OwnTracks Recorder (where the crew's phones are), with a phone setup page | on |
| `owntracks_funnel` | also put the post URL, and only that, on the public internet through Tailscale Funnel | off |
| `owntracks_app_server` | the address in the setup QR code | the Funnel address, else the tailnet name, else the LAN IP |
| `docker_daemon_config`, `docker_extra_packages` | `/etc/docker/daemon.json` content (e.g. `storage-driver: fuse-overlayfs` inside LXD) | none written |
| `obcell_readme_*`, `obcell_cpu_note`, `obcell_hardware_desc` | wording for the runbook on the box | generic text |

**Radios.** Each profile in `group_vars/all/sdr.yml` sets the driver packages, the device
string, the gains, whether OCUDU needs the SoapySDR clock patch, and the USB id used for
"SDR plugged in" alerts. Adding a new radio means adding one entry there.

**GPU.** Open Live's compositor (Strom) gets `/dev/dri` and the video/render groups only if
the box has a GPU.

## Secrets (`secrets/<host>/`, git-ignored)

- Generated on the first run: passwords, API keys, the Authelia password hash (argon2id) and
  the Strom admin hash (bcrypt). Later runs reuse the same files, so nothing rotates.
- **SIMs:** `secrets/<host>/subscribers.yml` holds an `open5gs_subscribers:` list (imsi, k,
  opc, optional imei). They are inserted only if missing; after that the WebUI owns them.
- **OwnTracks post token:** `owntracks_pub_token`, the secret end of the URL the apps post to.
- **RTMPS feeds:** `secrets/<host>/rtmps_feeds.conf` holds the stream keys; without it,
  placeholders are written.
- **Moving an Obcell:** copy the folder to the new control machine yourself (never through git).
- **Encryption at rest (optional):** `ansible-vault encrypt secrets/<host>/*`.

## Data (not configuration)

`obcell backup` on the box writes `~/obcell-backups/obcell-config-<time>.tar.gz`. `restore.yml` puts
back the Open5GS subscribers (mongorestore), the Open Live productions (CouchDB) and Caddy's
root CA, and the OwnTracks location history (it replaces what the new box recorded). The Intercom production *Crew* (lines Talkback + Radio) and the OpenWebRX receiver
profiles are seeded on a fresh install.

## Pinned versions

- **Container images:** by digest in the compose templates.
- **Sources:** OCUDU `077b0808ab`, Open Live and Studio `v0.8.0` (+ local patches),
  intercom-manager `5faf97e`, intercom-frontend `1009edc`, srsRAN_4G `release_23_11`.
- **Packages:**
  - Open5GS 2.8.0 from `ppa:open5gs/latest`.
  - Node 20 (NodeSource), used to build the Open5GS WebUI.
  - MongoDB, per Ubuntu release: 6.0 on 22.04, 8.0 on 24.04 and later (the 24.04 build on
    26.04, see [ubuntu-releases.md](ubuntu-releases.md)).
  - LimeSuite 23.11: from `ppa:myriadrf/drivers` on 22.04, from the Ubuntu archive on 24.04+.

To upgrade something, change the pin and run the playbook. Patches are re-applied, and
changed sources trigger a rebuild.

## Tags

| Tag | Runs |
|---|---|
| `base docker tailscale open5gs sdr ocudu srsue Obcell openlive intercom owntracks monitoring control` | that role |
| `core`, `ran`, `web` | groups of roles |
| `frontdoor` | only the Caddy sites, Homepage links, runbook table and WebUI listen address |
| `homepage` | only the Homepage link-rewrite script |

Read-only fact tasks that templates need are tagged `always`, so any tag-limited run works.

## Templates with two delimiter styles

- Most templates use normal Jinja `{{ }}`.
- Files that contain `{{ }}` themselves use `[= =]`, `[% %]` and `[# #]`: the `obcell` CLI,
  `control.py`, `radio_bridge.py` and the Prometheus alert rules (Docker `--format`,
  Prometheus `{{ $value }}`, Python f-strings).

## OwnTracks (where the crew is)

The [OwnTracks](https://owntracks.org) app on each phone reports its position to the
[Recorder](https://github.com/owntracks/recorder) in `~/owntracks`. The map, the table and
the API are at `https://<name>:2443/` behind the operator login (Homepage tile *OwnTracks*).

**HTTP, not MQTT.** The app's HTTP mode posts each position over HTTPS. That goes through
Caddy like every other service, and through Tailscale Funnel when it has to be public, with
no MQTT broker to run. The trade-off: the app can't receive commands from the server, and it
only hears about the other phones when it posts itself.

**Adding a phone: one scan, no account.**
- **The setup page** is `https://<name>:2443/join/`, or `http://<LAN IP>/join/` on the LAN and
  the cell (plain HTTP, so there's no certificate warning). It needs no login; the Homepage
  tile *Add a phone to OwnTracks* links to it, so put it on a screen.
- **What the QR code holds:** an `owntracks:///config?inline=` link with only HTTP mode and the
  post URL, so one code fits every phone. People then set their own username, device ID and
  tracker ID in the app; until they do, the phone shows up as `owntracks/phone`.
- **Fallbacks:** on the phone itself, the page's *Set up OwnTracks* button does the same as the
  scan. For Android cameras that only open web links, a second code opens the page on the phone.
- **In a terminal:** `obcell owntracks` prints the same code.

**No logins, but a secret URL.** The post URL ends in a random token
(`secrets/<host>/owntracks_pub_token`). Caddy passes `/pub/<token>` to the Recorder and sends
everything else on that port to the operator login. The app sends its username and device ID
itself, so anyone with the URL can post under any name. To change the token, delete the file,
run the playbook, and scan the new code on every phone.

**Where the setup is visible:** the page holds the URL, and anyone on the LAN, the tailnet or
the cell can open it. It's never on Funnel.

**Which URL the code holds** (`owntracks_app_server`):

| Setting | URL in the app | Works for phones |
|---|---|---|
| `owntracks_funnel: true` | `https://<tailnet name>:10000/pub/<token>` | anywhere with internet, Let's Encrypt certificate |
| a tailnet, no Funnel | `https://<tailnet name>:2443/pub/<token>` | with the Tailscale app |
| neither | `https://<LAN IP>:2443/pub/<token>` | on the LAN or the cell, trusting Caddy's CA |

The Funnel URL also works from the LAN and the cell, through the box's internet uplink, so a
phone that moves around keeps one URL. Without an uplink, the app queues positions and sends
them later.

**Turning Funnel on:**
1. In the Tailscale admin console, under *Access controls*, allow Funnel for the Obcell's node:
   `"nodeAttrs": [{"target": ["<the node or its tag>"], "attr": ["funnel"]}]`. HTTPS
   certificates must be on for the tailnet; they already are when the tailnet names work.
2. Set `owntracks_funnel: true` in the host vars and run `site.yml --tags owntracks,frontdoor,cli`.
   If the policy doesn't allow Funnel yet, the role stops and points to step 1.
3. Phones set up before this hold the old URL: scan the new code.
4. Test from a phone that is off Wi-Fi and the tailnet: `https://<tailnet name>:10000/` gives
   404, and only the post URL gets through.

Funnel uses port 10000 because it only offers 443, 8443 and 10000, and Caddy already serves 443
and 8443 on the tailnet name.
