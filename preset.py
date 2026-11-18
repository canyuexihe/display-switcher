#!/usr/bin/env python3
"""显示器布局预设管理：save / apply / list / migrate"""
import json
import os
import re
import subprocess
import sys

BASE = os.path.expanduser("~/.display-switcher")
LAYOUTS = os.path.join(BASE, "layouts")
STATE = os.path.join(BASE, "state.json")
DP = os.path.join(BASE, "bin", "displayplacer")


def notify(title, msg):
    subprocess.run(
        ["osascript", "-e",
         f'display notification "{msg}" with title "显示器布局: {title}"'],
        capture_output=True)


def dp_list():
    return subprocess.run([DP, "list"], capture_output=True, text=True).stdout


def parse_screens(output):
    screens = {}
    for block in re.split(r"(?m)^Persistent screen id: ", output)[1:]:
        lines = block.split("\n")
        pid = lines[0].strip()
        info = {"id": pid, "serial": "", "name": ""}
        for ln in lines:
            if ln.startswith("Serial screen id:"):
                info["serial"] = ln.split(":", 1)[1].strip()
            elif ln.startswith("Type:"):
                info["name"] = ln.split(":", 1)[1].strip()
        screens[pid] = info
    cfg_lines = [l for l in output.split("\n") if l.startswith("displayplacer ")]
    if cfg_lines:
        for cfg in re.findall(r'"([^"]*)"', cfg_lines[-1]):
            m = re.match(r"id:(\S+)", cfg)
            if m and m.group(1) in screens:
                screens[m.group(1)]["config"] = cfg
    return screens


def load_state():
    try:
        with open(STATE) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {"lastUsed": {}}


def record_used(preset):
    key = "|".join(sorted(s["id"] for s in preset["screens"]))
    state = load_state()
    state.setdefault("lastUsed", {})[key] = preset["name"]
    with open(STATE, "w") as f:
        json.dump(state, f, ensure_ascii=False, indent=1)


def preset_path(name):
    return os.path.join(LAYOUTS, name + ".json")


def load_preset(name):
    with open(preset_path(name)) as f:
        p = json.load(f)
    p["name"] = name
    return p


def save(name):
    screens = parse_screens(dp_list())
    entries = [s for s in screens.values() if "config" in s]
    if not entries:
        print("未能读取当前显示器配置")
        sys.exit(1)
    preset = {"name": name, "screens": entries}
    os.makedirs(LAYOUTS, exist_ok=True)
    with open(preset_path(name), "w") as f:
        json.dump(preset, f, ensure_ascii=False, indent=1)
    record_used(preset)
    print(f"已保存预设: {name}（{len(entries)} 台显示器）")


def apply(name):
    try:
        preset = load_preset(name)
    except OSError:
        print(f"预设不存在: {name}")
        sys.exit(1)
    online = parse_screens(dp_list())
    missing = [s for s in preset["screens"] if s["id"] not in online]
    if missing:
        names = "、".join(s["name"] or s["id"][:8] for s in missing)
        notify(name, f"切换失败：{names} 未连接")
        print(f"以下显示器未连接: {names}")
        sys.exit(1)
    configs = [s["config"] for s in preset["screens"]]
    r = subprocess.run([DP] + configs, capture_output=True, text=True)
    if r.returncode != 0:
        notify(name, "切换失败（分辨率模式可能不支持）")
        print(r.stdout + r.stderr)
        sys.exit(1)
    record_used(preset)
    notify(name, "已切换")


def list_presets():
    if not os.path.isdir(LAYOUTS):
        return
    for fn in sorted(os.listdir(LAYOUTS)):
        if fn.endswith(".json"):
            print(fn[:-5])


def migrate():
    online = parse_screens(dp_list())
    backup = os.path.join(LAYOUTS, "backup-args")
    os.makedirs(backup, exist_ok=True)
    for fn in sorted(os.listdir(LAYOUTS)):
        if not fn.endswith(".args"):
            continue
        name = fn[:-5]
        with open(os.path.join(LAYOUTS, fn)) as f:
            configs = [l.strip() for l in f if l.strip()]
        entries = []
        for cfg in configs:
            pid = re.match(r"id:(\S+)", cfg).group(1)
            info = online.get(pid, {})
            entries.append({
                "id": pid,
                "serial": info.get("serial", ""),
                "name": info.get("name", ""),
                "config": cfg,
            })
        with open(preset_path(name), "w") as f:
            json.dump({"name": name, "screens": entries}, f,
                      ensure_ascii=False, indent=1)
        os.rename(os.path.join(LAYOUTS, fn), os.path.join(backup, fn))
        print(f"已迁移: {name}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("用法: layout.sh {save|apply|list|migrate} <名称>")
        sys.exit(1)
    cmd = sys.argv[1]
    if cmd in ("save", "apply"):
        if len(sys.argv) < 3:
            print(f"用法: layout.sh {cmd} <名称>")
            sys.exit(1)
        save(sys.argv[2]) if cmd == "save" else apply(sys.argv[2])
    elif cmd == "list":
        list_presets()
    elif cmd == "migrate":
        migrate()
    else:
        print(f"未知命令: {cmd}")
        sys.exit(1)