#!/usr/bin/env python3
"""Shared helpers for waybar custom modules. No secrets, no sudo."""

from __future__ import annotations

import ipaddress
import json
import os
import socket
import subprocess
import time
import urllib.error
import urllib.request
from pathlib import Path

CACHE = Path.home() / ".cache" / "waybar"
HW_CACHE = CACHE / "hw.json"
_GLOBALS: dict[str, str] | None = None
_HW: dict | None = None

# Nerd Fonts (ttf-nerd-fonts-symbols): md-expansion_card, md-memory, fa-globe
ICON_GPU = "\U000f08ae"
ICON_VRAM = "\U000f035b"
ICON_GLOBE = "\uf0ac"

SKIP_IFACE_PREFIXES = (
    "lo",
    "docker",
    "br-",
    "veth",
    "virbr",
    "tun",
    "Meta",
    "wg",
    "tailscale",
)


def _global_paths() -> list[Path]:
    paths: list[Path] = []
    env = os.environ.get("ARCH_INSTALL_GLOBALS") or os.environ.get("SETUP_LINUX_GLOBALS")
    if env:
        paths.append(Path(env))
    paths.append(Path.home() / ".config" / "arch-install" / "globals.sh")
    paths.append(Path.home() / ".config" / "setup_linux" / "globals.sh")
    # waybar/scripts/lib.py -> repo root
    paths.append(Path(__file__).resolve().parents[2] / "globals.sh")
    return paths


def load_globals() -> dict[str, str]:
    """Parse KEY=value from globals.sh. First existing path wins."""
    global _GLOBALS
    if _GLOBALS is not None:
        return _GLOBALS
    data: dict[str, str] = {}
    for path in _global_paths():
        if not path.is_file():
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except OSError:
            continue
        for raw in text.splitlines():
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith("export "):
                line = line[7:].strip()
            if "=" not in line or line.endswith("{") or "()" in line.split("=")[0]:
                continue
            key, _, val = line.partition("=")
            key = key.strip()
            if not key or not key.replace("_", "").isalnum():
                continue
            val = val.strip()
            if len(val) >= 2 and val[0] == val[-1] and val[0] in "\"'":
                val = val[1:-1]
            data[key] = val
        break
    _GLOBALS = data
    return data


def g(name: str, default: str = "") -> str:
    return load_globals().get(name, default) or default


def cache_dir() -> Path:
    CACHE.mkdir(parents=True, exist_ok=True)
    return CACHE


def emit(text: str, tooltip: str = "", cls=None, percentage: int | None = None) -> None:
    payload = {"text": text, "tooltip": tooltip}
    if cls is not None:
        payload["class"] = cls
    if percentage is not None:
        payload["percentage"] = percentage
    print(json.dumps(payload, ensure_ascii=False), flush=True)


def read_hw() -> dict:
    return hw_info()


def _dmi(name: str) -> str:
    return read_text(f"/sys/class/dmi/id/{name}") or ""


def board_fp() -> str:
    return "|".join(
        [
            _dmi("sys_vendor"),
            _dmi("product_name"),
            _dmi("board_name"),
            _dmi("board_serial"),
        ]
    )


def gpu_fp() -> str:
    dev = amdgpu_device()
    if not dev:
        return ""
    return "|".join(
        [
            read_text(dev / "vendor") or "",
            read_text(dev / "device") or "",
            read_text(dev / "subsystem_device") or "",
        ]
    )


def detect_vram_type() -> str:
    try:
        proc = run(["journalctl", "-k", "-b", "--no-pager"], timeout=4)
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return ""
    blob = proc.stdout
    for token in ("GDDR7", "GDDR6", "GDDR5", "GDDR4", "HBM3", "HBM2", "HBM"):
        if token in blob:
            return token
    return ""


def detect_ram_type() -> str:
    try:
        proc = run(["dmidecode", "-t", "memory"], timeout=4)
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return ""
    if proc.returncode != 0:
        return ""
    found: list[str] = []
    for line in proc.stdout.splitlines():
        s = line.strip()
        if s.startswith("Type:") and "Error Correction" not in s:
            t = s.split(":", 1)[1].strip()
            if t.startswith("DDR"):
                found.append(t)
    return found[0] if found else ""


def hw_info() -> dict:
    """RAM/VRAM types from cache, refreshed if board or GPU identity changed."""
    global _HW
    if _HW is not None:
        return _HW
    board = board_fp()
    gpu = gpu_fp()
    cached: dict = {}
    try:
        cached = json.loads(HW_CACHE.read_text())
    except (OSError, json.JSONDecodeError):
        cached = {}
    ram = cached.get("ram_type") or ""
    vram = cached.get("vram_type") or ""
    if cached.get("board_fp") != board:
        ram = detect_ram_type() or ""
    if cached.get("gpu_fp") != gpu or not vram:
        vram = detect_vram_type() or vram
    if cached.get("board_fp") == board and cached.get("ram_type") and not ram:
        ram = cached.get("ram_type") or ""
    out = {
        "board_fp": board,
        "gpu_fp": gpu,
        "ram_type": ram,
        "vram_type": vram,
    }
    if out != cached:
        try:
            cache_dir()
            HW_CACHE.write_text(json.dumps(out, indent=2) + "\n")
        except OSError:
            pass
    _HW = out
    return out


def run(cmd: list[str], timeout: float = 3.0) -> subprocess.CompletedProcess:
    return subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        timeout=timeout,
        check=False,
    )


def read_text(path: Path | str) -> str | None:
    try:
        return Path(path).read_text().strip()
    except OSError:
        return None


def amdgpu_device() -> Path | None:
    drm = Path("/sys/class/drm")
    if not drm.is_dir():
        return None
    for card in sorted(drm.glob("card*/device")):
        if (card / "gpu_busy_percent").is_file():
            return card
    return None


def global_v6_prefix64() -> ipaddress.IPv6Network | None:
    """Current ISP /64 from a global address on a physical NIC (prefix is dynamic)."""
    for name in physical_ifaces():
        try:
            proc = run(["ip", "-j", "-6", "addr", "show", "dev", name, "scope", "global"], timeout=2)
            data = json.loads(proc.stdout) if proc.returncode == 0 and proc.stdout.strip() else []
        except (json.JSONDecodeError, subprocess.TimeoutExpired):
            continue
        for link in data:
            for a in link.get("addr_info") or []:
                if a.get("family") != "inet6":
                    continue
                local = a.get("local")
                if not local:
                    continue
                try:
                    addr = ipaddress.IPv6Address(local)
                except ValueError:
                    continue
                if addr.is_global:
                    return ipaddress.IPv6Network(f"{addr}/64", strict=False)
    return None


def home_server_v6(iid: int = 6) -> str | None:
    net = global_v6_prefix64()
    if net is None:
        return None
    return str(net.network_address + iid)


def physical_ifaces() -> list[str]:
    base = Path("/sys/class/net")
    names = []
    for p in sorted(base.iterdir()):
        name = p.name
        if any(name == pre or name.startswith(pre) for pre in SKIP_IFACE_PREFIXES):
            continue
        names.append(name)
    return names


def ping_host(host: str, ipv6: bool = False, timeout: float = 1.5) -> tuple[bool, str | None]:
    cmd = ["ping", "-6" if ipv6 else "-4", "-c", "1", "-W", "1", host]
    try:
        proc = run(cmd, timeout=timeout)
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return False, None
    rtt = None
    for line in proc.stdout.splitlines():
        if "time=" in line:
            try:
                rtt = line.split("time=")[1].split()[0]
            except IndexError:
                pass
    return proc.returncode == 0, rtt


def doh(name: str, qtype: str, timeout: float = 4.0) -> list[str]:
    """DNS-over-HTTPS. Avoids mihomo fake-ip on UDP/53."""
    url = f"https://cloudflare-dns.com/dns-query?name={name}&type={qtype}"
    req = urllib.request.Request(url, headers={"accept": "application/dns-json"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            data = json.loads(resp.read().decode())
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, OSError, socket.timeout):
        return []
    answers = data.get("Answer") or []
    out = []
    for ans in answers:
        # 1=A, 28=AAAA
        if ans.get("type") in (1, 28) or qtype.upper() in ("A", "AAAA"):
            rec = ans.get("data")
            if rec:
                out.append(rec)
    return out


def curl(
    url: str,
    timeout: float = 3.0,
    resolve: str | None = None,
    ipv6: bool | None = None,
    proxy: str | None = None,
) -> str | None:
    cmd = ["curl", "-sS", "--max-time", str(int(timeout))]
    if ipv6 is True:
        cmd.append("-6")
    elif ipv6 is False:
        cmd.append("-4")
    if proxy:
        cmd.extend(["-x", proxy])
    if resolve:
        cmd.extend(["--resolve", resolve])
    cmd.append(url)
    try:
        proc = run(cmd, timeout=timeout + 1)
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return None
    if proc.returncode != 0:
        return None
    return proc.stdout.strip() or None


def iso_flag(cc: str) -> str:
    cc = (cc or "").strip().upper()
    if len(cc) != 2 or not cc.isalpha():
        return ""
    return "".join(chr(0x1F1E6 + ord(c) - 65) for c in cc)


def load_json(path: Path) -> dict | None:
    try:
        return json.loads(path.read_text())
    except (OSError, json.JSONDecodeError):
        return None


def save_json(path: Path, obj: dict) -> None:
    cache_dir()
    path.write_text(json.dumps(obj))
