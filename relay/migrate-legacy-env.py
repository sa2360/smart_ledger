"""Run as root on the server. Move existing unit credentials to a private file.

Never prints values and never overwrites a pre-existing environment file.
This preserves operation during migration; it does not revoke exposed keys.
"""
import os
import shlex
import subprocess
from pathlib import Path

if os.geteuid() != 0:
    raise SystemExit("请使用 sudo python3 migrate-legacy-env.py")
target = Path("/etc/yiyuji/relay.env")
if target.exists():
    raise SystemExit("环境文件已存在，未覆盖。")
raw = subprocess.check_output(
    ["systemctl", "show", "yiyuji-relay", "--property=Environment", "--value"],
    text=True,
)
allowed = {"AGNES_KEY", "BAIDU_API_KEY", "BAIDU_SECRET_KEY", "AGNES_UPSTREAM"}
values = {}
for entry in shlex.split(raw):
    key, separator, value = entry.partition("=")
    if separator and key in allowed and value:
        values[key] = value
if not {"AGNES_KEY", "BAIDU_API_KEY", "BAIDU_SECRET_KEY"} <= values.keys():
    raise SystemExit("旧服务未找到全部配置；请在服务器手动创建 relay.env，未写入文件。")
target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
descriptor = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
with os.fdopen(descriptor, "w", encoding="utf-8") as output:
    for key, value in values.items():
        output.write(f"{key}={shlex.quote(value)}\n")
    output.write("TRUST_PROXY=true\n")
print("配置已保存到 root 私有环境文件。请在服务商控制台轮换旧密钥，并更新此文件。")
