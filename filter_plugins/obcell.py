"""Small filters used by the Obcell templates."""


def obcell_cpu_range(cpus):
    """[0, 1] -> '0-1', [0, 2, 3] -> '0,2-3' (systemd AllowedCPUs / human-readable CPU lists)."""
    cpus = sorted(int(c) for c in cpus)
    out, start, prev = [], None, None
    for c in cpus:
        if start is None:
            start = prev = c
        elif c == prev + 1:
            prev = c
        else:
            out.append(f"{start}-{prev}" if prev != start else str(start))
            start = prev = c
    if start is not None:
        out.append(f"{start}-{prev}" if prev != start else str(start))
    return ",".join(out)


def obcell_cpu_list(spec):
    """'0-3,6' -> [0, 1, 2, 3, 6] (kernel cpulist format, e.g. Cpus_allowed_list)."""
    out = []
    for part in str(spec).strip().split(","):
        if not part:
            continue
        lo, _, hi = part.partition("-")
        out.extend(range(int(lo), int(hi or lo) + 1))
    return out


def obcell_urls(hosts, port=None, scheme="https"):
    """['a.local', '10.0.0.2'] | obcell_urls(8443) -> ['https://a.local:8443', 'https://10.0.0.2:8443']."""
    suffix = f":{port}" if port else ""
    return [f"{scheme}://{h}{suffix}" for h in hosts]


def obcell_ports(hosts, port):
    """['a.local'] | obcell_ports(5443) -> ['a.local:5443']."""
    return [f"{h}:{port}" for h in hosts]


class FilterModule:
    def filters(self):
        return {"obcell_cpu_range": obcell_cpu_range, "obcell_cpu_list": obcell_cpu_list, "obcell_urls": obcell_urls, "obcell_ports": obcell_ports}
