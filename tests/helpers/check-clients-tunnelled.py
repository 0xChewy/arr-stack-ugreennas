#!/usr/bin/env python3
"""Every BitTorrent or Usenet client in the compose files must run inside
gluetun's network namespace.

⚠️  This script was generated with LLM assistance and human-reviewed.
    Read and understand it before running. Do not execute scripts you
    don't understand on your system. It only reads compose files and
    prints a verdict.

Usage: check-clients-tunnelled.py <directory containing docker-compose*.yml>

tests/vpn-zombies.bats checks the binding of services that DECLARE
`network_mode: service:gluetun`. This is the positive rule — the one that
matters: a download client added later without the binding leaks this
house's IP to the swarm and passes every other test. Two ways in, deliberately
overlapping: the named list is what must hold today; the image pattern catches
a client added under a name nobody thought to list.

Exit 0 and print the count when every client is bound; exit 1 and print
VIOLATION lines otherwise.
"""
import glob
import os
import re
import sys

BOUND = ("service:gluetun", "container:gluetun")
NAMED = {"qbittorrent", "sabnzbd"}
CLIENT_IMAGE = re.compile(r"(qbittorrent|sabnzbd|transmission|deluge|rtorrent|nzbget|aria2)", re.I)


def main(root):
    services = {}
    for path in sorted(glob.glob(os.path.join(root, "docker-compose*.yml"))):
        fname = os.path.basename(path)
        svc = image = mode = None
        with open(path) as fh:
            for line in fh:
                m = re.match(r"^  ([A-Za-z0-9_.-]+):\s*$", line)
                if m:
                    if svc:
                        services[svc] = (fname, image, mode)
                    svc, image, mode = m.group(1), None, None
                    continue
                if svc is None:
                    continue
                s = line.strip()
                if s.startswith("image:"):
                    image = s.split(":", 1)[1].strip().strip('"')
                elif s.startswith("network_mode:"):
                    mode = s.split(":", 1)[1].strip().strip('"')
        if svc:
            services[svc] = (fname, image, mode)

    candidates = set(NAMED)
    for svc, (_, image, _) in services.items():
        if image and CLIENT_IMAGE.search(image):
            candidates.add(svc)

    bad = []
    for svc in sorted(candidates):
        if svc not in services:
            bad.append(f"{svc} is in the must-be-tunnelled list but no compose file defines it")
            continue
        fname, image, mode = services[svc]
        if mode not in BOUND:
            bad.append(f"{fname}: {svc} ({image or 'no image'}) has network_mode {mode or 'unset'} -- must be one of {', '.join(BOUND)}")

    if bad:
        print("VIOLATION: a download client is outside the VPN namespace")
        print("\n".join("  " + b for b in bad))
        return 1
    print(f"checked {len(candidates)} client(s), all inside gluetun's namespace")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "."))
