#!/usr/bin/env python3
"""Every BitTorrent or Usenet client must run inside gluetun's network namespace.

⚠️  This script was generated with LLM assistance and human-reviewed.
    Read and understand it before running. Do not execute scripts you
    don't understand on your system. It reads JSON and prints a verdict.

Usage: check-clients-tunnelled.py RESOLVED.json [RESOLVED.json ...]

Each argument is the output of `docker compose -f <file> config --format json`
for one compose file — resolved, so YAML anchors, merge keys and variables are
already applied. An earlier version read the YAML with a line parser and was
fooled by all three, and by a volume that happened to share a service's name.

tests/vpn-zombies.bats checks the binding of services that DECLARE
`network_mode: service:gluetun`. This is the positive rule: a download client
added later without the binding leaks this house's IP to the swarm and passes
every other test. Two ways in, deliberately overlapping: NAMED is what must
hold today; CLIENT_IMAGE catches a client added under a name nobody listed.
NOT_A_CLIENT keeps sidecars that are merely named after a client — an
exporter, a backup job — out of the tunnel, where they would be wrong.

Exit 0 and print the count when every client is bound; exit 1 with VIOLATION
lines otherwise. A NAMED client that no file defines is a violation too.
"""
import json
import os
import re
import sys

BOUND = ("service:gluetun", "container:gluetun")
NAMED = {"qbittorrent", "sabnzbd"}
CLIENT_IMAGE = re.compile(
    r"(qbittorrent|sabnzbd|transmission|deluge|rtorrent|rutorrent|nzbget|aria2|pyload|jdownloader|slskd|porla)", re.I
)
NOT_A_CLIENT = re.compile(r"(exporter|backup|metrics|prometheus)", re.I)


def main(paths):
    if not paths:
        print("VIOLATION: no resolved compose files given")
        return 1
    services = {}
    for path in paths:
        with open(path) as fh:
            doc = json.load(fh)
        label = os.path.basename(path)
        for svc, cfg in (doc.get("services") or {}).items():
            if svc in services:
                print(f"VIOLATION: service {svc} is defined in both {services[svc][0]} and {label}")
                return 1
            services[svc] = (label, cfg.get("image"), cfg.get("network_mode"))

    candidates = set(NAMED)
    for svc, (_, image, _) in services.items():
        if image and CLIENT_IMAGE.search(image) and not NOT_A_CLIENT.search(f"{svc} {image}"):
            candidates.add(svc)

    bad = []
    for svc in sorted(candidates):
        if svc not in services:
            bad.append(f"{svc} is in the must-be-tunnelled list but no compose file defines it")
            continue
        label, image, mode = services[svc]
        if mode not in BOUND:
            bad.append(f"{label}: {svc} ({image or 'no image'}) has network_mode {mode or 'unset'} -- must be one of {', '.join(BOUND)}")

    if bad:
        print("VIOLATION: a download client is outside the VPN namespace")
        print("\n".join("  " + b for b in bad))
        return 1
    print(f"checked {len(candidates)} client(s), all inside gluetun's namespace")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
