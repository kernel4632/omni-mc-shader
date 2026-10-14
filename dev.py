"""开发环境：在项目内安装检查器、便携图形工具和独立游戏调试资源。

示例：python dev.py setup --graphics；python dev.py doctor；python dev.py watch。
下载缓存和本机设置放 .dev/，源代码只保存可重复的工具版本与校验值。
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import tarfile
import time
import urllib.request
import venv
import zipfile
from pathlib import Path
from urllib.parse import urlparse

import build

ROOT = Path(__file__).resolve().parent
DEV = ROOT / ".dev"


def lockfile() -> dict:
    """检查下载配置的边界格式，避免不完整配置安装到错误位置。"""
    data = json.loads((ROOT / "dev-tools.lock.json").read_text(encoding="utf-8"))
    if data.get("schemaVersion") != 1 or not re.fullmatch(r"[\d.]+", data["minecraft"]):
        raise ValueError("开发工具锁定文件格式或 Minecraft 版本无效")
    for name, tool in data["tools"].items():
        if not re.fullmatch(r"[a-z]+", name):
            raise ValueError(f"开发工具名称无效：{name}")
        for system in ("windows", "linux"):
            if system in tool:
                artifact = tool[system]
                validate_url(artifact["url"])
                digest = artifact["sha256"]
                if not isinstance(digest, str) or not re.fullmatch(r"[0-9a-f]{64}", digest):
                    raise ValueError(f"{name} 的 SHA256 无效")
    for mod in data["mods"]:
        validate_url(mod["url"])
        if Path(mod["file"]).name != mod["file"] or not mod["file"].endswith(".jar"):
            raise ValueError("模组下载文件名必须是单个 JAR 文件")
        for algorithm, length in (("sha1", 40), ("sha512", 128)):
            if not re.fullmatch(rf"[0-9a-f]{{{length}}}", mod[algorithm]):
                raise ValueError(f"{mod['name']} 的 {algorithm} 无效")
    return data


def validate_url(url: str) -> None:
    """只接受 HTTPS 下载地址，防止配置引用本机或非网络资源。"""
    parsed = urlparse(url)
    if parsed.scheme != "https" or not parsed.netloc or parsed.username or parsed.password:
        raise ValueError(f"下载地址必须是没有凭据的 HTTPS 地址：{url}")


def download(url: str, destination: Path, digest: str | None, algorithm: str = "sha256") -> Path:
    """下载到缓存并检查校验值，中断时清理临时文件，保留原文件。"""
    validate_url(url)
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists() and digest and hashlib.new(algorithm, destination.read_bytes()).hexdigest() == digest:
        return destination
    temporary = destination.with_name(destination.name + ".part")
    print(f"下载 {destination.name}", flush=True)
    request = urllib.request.Request(url, headers={"User-Agent": "Omni-development/1"})
    try:
        with urllib.request.urlopen(request, timeout=45) as response, temporary.open("wb") as output:
            shutil.copyfileobj(response, output)
        actual = hashlib.new(algorithm, temporary.read_bytes()).hexdigest()
        if digest and actual != digest:
            raise ValueError(f"下载校验失败：{destination.name}，期望 {digest}，实际 {actual}")
        temporary.replace(destination)
    finally:
        temporary.unlink(missing_ok=True)
    return destination


def extract(archive: Path, destination: Path) -> None:
    """检查压缩包成员路径与链接后解压，只允许写入指定目录。"""
    destination.mkdir(parents=True, exist_ok=True)
    if archive.name.endswith(".zip"):
        with zipfile.ZipFile(archive) as package:
            for member in package.infolist():
                target = (destination / member.filename).resolve()
                if not target.is_relative_to(destination.resolve()) or "\\" in member.filename:
                    raise ValueError(f"压缩包路径越界：{member.filename}")
                if (member.external_attr >> 16) & 0o170000 == 0o120000:
                    raise ValueError(f"压缩包不能包含符号链接：{member.filename}")
            package.extractall(destination)
    else:
        with tarfile.open(archive) as package:
            for member in package.getmembers():
                if not (member.isfile() or member.isdir() or member.issym() or member.islnk()):
                    raise ValueError(f"压缩包不能包含特殊文件：{member.name}")
            # Python 的 data 过滤器允许包内链接，拒绝指向解压目录外的链接。
            package.extractall(destination, filter="data")


def install_tool(name: str, item: dict, system: str) -> None:
    """安装一个锁定版本工具，版本和下载校验标记一致时复用安装。"""
    artifact = item[system]
    destination = DEV / "tools" / name
    marker = destination / ".installed.json"
    expected = {"version": item["version"], "sha256": artifact["sha256"]}
    if marker.exists() and json.loads(marker.read_text(encoding="utf-8")) == expected:
        print(f"已就绪 {name} {item['version']}", flush=True)
        return
    filename = Path(urlparse(artifact["url"]).path).name
    package = download(artifact["url"], DEV / "downloads" / filename, artifact["sha256"])
    # 更新时先解压到临时位置，完整验证后才替换旧安装。
    staging = DEV / "tools" / (name + ".installing")
    if staging.exists():
        shutil.rmtree(staging)
    try:
        extract(package, staging)
        if name == "renderdoc":
            binary = next(staging.rglob("qrenderdoc.exe"))
            print("RenderDoc 下载 SHA256：" + hashlib.sha256(package.read_bytes()).hexdigest(), flush=True)
            command = "$s=Get-AuthenticodeSignature -LiteralPath $env:OMNI_SIGNED_BINARY; if ($s.Status -ne 'Valid' -or $s.SignerCertificate.Subject -notmatch 'CN=Baldur (Scott )?Karlsson,') { exit 1 }"
            result = subprocess.run(["powershell", "-NoProfile", "-Command", command],
                                    env=os.environ | {"OMNI_SIGNED_BINARY": str(binary)})
            if result.returncode:
                raise ValueError("RenderDoc 发布者签名未通过验证")
            print("RenderDoc 官方签名通过；下载 SHA256：" + hashlib.sha256(package.read_bytes()).hexdigest())
        if destination.exists():
            shutil.rmtree(destination)
        staging.replace(destination)
        marker.write_text(json.dumps(expected) + "\n", encoding="utf-8")
    finally:
        if staging.exists():
            shutil.rmtree(staging)
    print(f"已安装 {name} {item['version']}", flush=True)


def graphics(data: dict) -> None:
    """准备独立游戏资源与整合包；游戏本体和登录交给启动器处理。"""
    game = DEV / "minecraft"
    files = []
    for mod in data["mods"]:
        destination = game / "mods" / mod["file"]
        download(mod["url"], destination, mod["sha512"], "sha512")
        files.append({"path": "mods/" + mod["file"],
                      "hashes": {"sha1": mod["sha1"], "sha512": mod["sha512"]},
                      "downloads": [mod["url"]], "fileSize": destination.stat().st_size,
                      "env": {"client": "required", "server": "unsupported"}})
    index = {"formatVersion": 1, "game": "minecraft", "versionId": "omni-debug-1",
             "name": "Omni 光影开发", "summary": "项目专用 Iris 图形调试实例",
             "files": files, "dependencies": {"minecraft": data["minecraft"],
                                                "fabric-loader": data["fabric"]}}
    config = game / "config/iris.properties"
    config.parent.mkdir(parents=True, exist_ok=True)
    if not config.exists():
        config.write_text("enableShaders=true\nshaderPack=Omni-dev.zip\nenableDebugOptions=true\n", encoding="ascii")
    build.generate()
    build.sync()
    contents = {"modrinth.index.json": (json.dumps(index, ensure_ascii=False, indent=2) + "\n").encode(),
                "overrides/config/iris.properties": config.read_bytes(),
                "overrides/shaderpacks/Omni-dev.zip": (game / "shaderpacks/Omni-dev.zip").read_bytes()}
    build.archive(DEV / "Omni-debug.mrpack", contents)
    print("已准备 .dev/minecraft 和 .dev/Omni-debug.mrpack", flush=True)


def python_environment() -> None:
    """在项目虚拟环境中安装锁定图形测试依赖，不修改系统 Python。"""
    folder = ROOT / ".venv"
    interpreter = folder / ("Scripts/python.exe" if sys.platform == "win32" else "bin/python")
    if not interpreter.exists():
        venv.create(folder, with_pip=True)
    subprocess.run([str(interpreter), "-m", "pip", "install", "--require-hashes",
                    "-r", str(ROOT / "requirements-dev.lock")], check=True)


def setup(with_graphics: bool) -> None:
    """安装日常检查工具，按需增加便携 RenderDoc、测试依赖和游戏模组。"""
    system = {"win32": "windows", "linux": "linux"}.get(sys.platform)
    if system is None or platform.machine().lower() not in ("amd64", "x86_64"):
        raise ValueError("自动安装目前支持 Windows / Linux x64")
    if with_graphics and system != "windows":
        raise ValueError("便携图形环境目前支持 Windows x64；Linux 可单独安装 RenderDoc")
    data = lockfile()
    for name in ("glslang", "actionlint"):
        install_tool(name, data["tools"][name], system)
    build.generate()
    if with_graphics:
        install_tool("renderdoc", data["tools"]["renderdoc"], system)
        python_environment()
        graphics(data)


def doctor() -> None:
    """实际运行工具版本命令，确认安装的程序可以启动。"""
    for name in ("glslang", "actionlint"):
        subprocess.run([str(build.tool(name)), "--version" if name == "glslang" else "-version"], check=True)
    binaries = sorted((DEV / "tools/renderdoc").rglob("renderdoccmd.exe"))
    if binaries:
        subprocess.run([str(binaries[0]), "version"], check=True)
    game = DEV / "minecraft"
    data = lockfile()
    if game.exists():
        for mod in data["mods"]:
            path = game / "mods" / mod["file"]
            if not path.exists() or hashlib.sha512(path.read_bytes()).hexdigest() != mod["sha512"]:
                raise ValueError(f"调试模组缺失或校验失败：{mod['name']}")
        print(f"调试模组校验通过；Minecraft {data['minecraft']} 实际加载需在启动器中验证")


def watch() -> None:
    """源文件变化后重新检查并同步；编译失败时保留游戏中的上一份有效包。"""
    print("正在观察 shaders/、presets/ 和 VERSION。Ctrl+C 停止。", flush=True)
    previous = None
    try:
        while True:
            paths = [ROOT / "VERSION", *shader_files(), *(ROOT / "presets").glob("*.properties")]
            current = tuple((str(path), path.stat().st_mtime_ns) for path in sorted(paths))
            if current != previous:
                previous = current
                # 每次构建是独立命令；错误由构建入口报告，观察过程可以继续。
                subprocess.run([sys.executable, str(ROOT / "build.py"), "sync"], cwd=ROOT)
            time.sleep(0.5)
    except KeyboardInterrupt:
        print("已停止观察")


def shader_files() -> list[Path]:
    """只观察维护的源码，排除生成菜单与翻译，防止无限重建。"""
    return [path for path in (ROOT / "shaders").rglob("*") if path.is_file() and
            (path.suffix in {".glsl", ".vsh", ".fsh", ".gsh", ".csh"}
             or path.name == "pipeline.properties")]


def main() -> None:
    """解析安装命令，所有错误在命令入口统一输出。"""
    parser = argparse.ArgumentParser(description="Omni 项目内开发环境")
    parser.add_argument("command", choices=("setup", "doctor", "watch", "renderdoc"))
    parser.add_argument("--graphics", action="store_true", help="增加本机图形调试工具和独立游戏资源")
    args = parser.parse_args()
    if args.command == "setup":
        setup(args.graphics)
    elif args.command == "doctor":
        doctor()
    elif args.command == "watch":
        watch()
    else:
        matches = sorted((DEV / "tools/renderdoc").rglob("qrenderdoc.exe"))
        if not matches:
            raise ValueError("请先执行 python dev.py setup --graphics")
        subprocess.Popen([str(matches[0])], cwd=matches[0].parent)
        print("已打开项目内 RenderDoc")


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
    try:
        main()
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        print(f"错误：{error}", file=sys.stderr)
        sys.exit(1)
