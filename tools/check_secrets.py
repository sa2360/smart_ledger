"""Scan current tracked/unignored text files; never print matched credentials."""
import re
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[1]
paths = subprocess.check_output(
    ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"], cwd=root
).decode("utf-8").split("\0")
patterns = [
    re.compile(r"\bsk-[A-Za-z0-9_-]{24,}"),
    re.compile(r"(?:AGNES_KEY|BAIDU_API_KEY|BAIDU_SECRET_KEY)\s*[=:]\s*['\"]?[A-Za-z0-9_-]{16,}"),
    re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
]
failed = False
for name in sorted(set(paths) - {""}):
    path = root / name
    if not path.is_file():
        continue
    try:
        content = path.read_text(encoding="utf-8")
    except UnicodeError:
        continue
    for number, line in enumerate(content.splitlines(), 1):
        if any(pattern.search(line) for pattern in patterns):
            print(f"Potential secret: {name}:{number} (value redacted)")
            failed = True
if failed:
    raise SystemExit(1)
print("Current source secret scan passed (Git history and ignored artifacts excluded).")
