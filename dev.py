"""项目内开发环境：安装检查器、图形工具和独立游戏调试资源。

调用位置：开发者在项目根目录直接运行本文件；构建工具只被观察和图形准备流程调用。
可复制命令：`python dev.py setup --graphics`、`python dev.py doctor`、`python dev.py watch`。
设计原因：下载、工具、虚拟环境和调试实例全部放进 `.dev/` 或 `.venv/`，不触碰玩家目录。
安全取舍：只接受无凭据的 `HTTPS`，按锁定文件校验下载字节，先检查压缩包路径和链接再写入。
"""

from __future__ import annotations

import argparse  # 开发命令只执行明确选择的操作。
import hashlib  # 下载与安装必须核对锁定字节。
import json  # 工具版本与本机标记。
import os  # 签名检查使用专用环境变量。
import platform  # 检查便携二进制架构。
import re  # 校验下载记录格式。
import shutil  # 复制下载流与独立资源。
import subprocess  # 真正运行已安装工具。
import sys  # 根据实际系统选择发行包。
import tarfile  # 安全解压开发工具。
import time  # 观察源文件变化。
import urllib.request  # 通过加密网络获取锁定资源。
import venv  # Python 图形环境与系统隔离。
import zipfile  # 开发整合包与工具归档。
from pathlib import Path  # 所有数据相对项目定位。
from urllib.parse import urlparse  # 下载边界拒绝本机协议。

import build  # 观察模式复用同一构建流程。

ROOT = Path(__file__).resolve().parent  # 换终端目录不改变项目。
DEV = ROOT / ".dev"  # 下载、工具和个人设置不进入发行包。


def read_lock() -> dict:
    """读取并检查开发工具锁定文件。

    版本从锁定记录读取；这个边界检查下载地址、哈希和调试模组文件名。
    安装流程只使用检查后的数据，因此不会自行猜测版本或来源。
    """
    data = json.loads((ROOT / "dev-tools.lock.json").read_text(encoding="utf-8"))  # 外部安装记录边界检查一次。
    if data.get("schemaVersion") != 1 or not re.fullmatch(r"[\d.]+", data["minecraft"]):
        raise ValueError("开发工具锁定文件格式或 Minecraft 版本无效")
    for name, tool in data["tools"].items():  # 各工具独立固定版本。
        if not re.fullmatch(r"[a-z]+", name):
            raise ValueError(f"开发工具名称无效：{name}")
        for system in ("windows", "linux"):  # 不推断其他平台兼容。
            if system in tool:
                artifact = tool[system]  # 一个平台对应一份官方包。
                validate_url(artifact["url"])  # 下载协议先验证。
                digest = artifact["sha256"]  # 不以文件名判断内容正确。
                if not isinstance(digest, str) or not re.fullmatch(r"[0-9a-f]{64}", digest):
                    raise ValueError(f"{name} 的 SHA256 无效")
    for mod in data["mods"]:  # 调试环境不能混入未锁定模组。
        validate_url(mod["url"])  # 模组来源同样只允许加密网络。
        if Path(mod["file"]).name != mod["file"] or not mod["file"].endswith(".jar"):
            raise ValueError("模组下载文件名必须是单个 JAR 文件")
        for algorithm, length in (("sha1", 40), ("sha512", 128)):  # 同时满足整合包与下载校验。
            if not re.fullmatch(rf"[0-9a-f]{{{length}}}", mod[algorithm]):
                raise ValueError(f"{mod['name']} 的 {algorithm} 无效")
    return data  # 安装流程信任检查后的内部记录。


def validate_url(url: str) -> None:
    """只接受没有内嵌凭据的 `HTTPS` 下载地址，拒绝本机文件协议。"""
    parsed = urlparse(url)  # 拒绝配置把凭据拼进网址。
    if parsed.scheme != "https" or not parsed.netloc or parsed.username or parsed.password:
        raise ValueError(f"下载地址必须是没有凭据的 HTTPS 地址：{url}")


def download_file(url: str, destination: Path, digest: str | None, algorithm: str = "sha256") -> Path:
    """下载文件并验证完整内容。

    下载前检查地址，完成后按指定算法计算完整文件的哈希，与锁定值比较。
    调用方未提供锁定值时仍计算哈希，但不据此声称下载内容已通过校验。
    先写 `.part` 临时文件，校验通过后才替换缓存；失败时清理临时文件，
    这样中断下载不会覆盖已经可用的文件。
    """
    validate_url(url)  # 公开下载入口检查一次。
    destination.parent.mkdir(parents=True, exist_ok=True)  # 缓存只建立在调用方指定位置。
    if destination.exists() and digest and hashlib.new(algorithm, destination.read_bytes()).hexdigest() == digest:
        return destination  # 已有字节匹配校验时无需重下。
    temporary = destination.with_name(destination.name + ".part")  # 中断下载不能覆盖有效文件。
    print(f"下载 {destination.name}", flush=True)
    request = urllib.request.Request(url, headers={"User-Agent": "Omni-development/1"})  # 服务端可识别开发下载。
    try:
        with urllib.request.urlopen(request, timeout=45) as response, temporary.open("wb") as output:
            shutil.copyfileobj(response, output)  # 完整写入临时下载。
        actual = hashlib.new(algorithm, temporary.read_bytes()).hexdigest()  # 校验实际内容。
        if digest and actual != digest:
            raise ValueError(f"下载校验失败：{destination.name}，期望 {digest}，实际 {actual}")
        temporary.replace(destination)  # 通过后原子替换缓存。
    finally:
        temporary.unlink(missing_ok=True)  # 失败不遗留半包。
    return destination  # 下游只读取完整资源。


def extract(archive: Path, destination: Path) -> None:
    """检查压缩包边界后解压到指定目录。

    `ZIP` 成员拒绝反斜杠、逃出目标目录的路径和符号链接；`tar` 成员只允许普通文件、
    目录和链接，并交给 Python 的 `data` 过滤器限制路径与链接不能逃出解压目录。
    这是为了防止锁定下载包借助路径或链接把文件写到工具目录以外。
    """
    destination.mkdir(parents=True, exist_ok=True)  # 只解压到工具管理的位置。
    if archive.name.endswith(".zip"):  # 按发行包格式使用对应安全解压策略。
        with zipfile.ZipFile(archive) as package:
            for member in package.infolist():  # 解压前检查每个成员。
                target = (destination / member.filename).resolve()  # 防止上级路径逃逸。
                if not target.is_relative_to(destination.resolve()) or "\\" in member.filename:
                    raise ValueError(f"压缩包路径越界：{member.filename}")
                if (member.external_attr >> 16) & 0o170000 == 0o120000:
                    raise ValueError(f"压缩包不能包含符号链接：{member.filename}")
            package.extractall(destination)  # 全部检查通过才写入成员。
    else:
        with tarfile.open(archive) as package:
            for member in package.getmembers():  # 拒绝设备文件等危险成员。
                if not (member.isfile() or member.isdir() or member.issym() or member.islnk()):
                    raise ValueError(f"压缩包不能包含特殊文件：{member.name}")
            # Python 的 `data` 过滤器允许包内链接，拒绝指向解压目录外的链接。
            package.extractall(destination, filter="data")  # 标准安全过滤器限制路径与链接。


def install_tool(name: str, tool: dict, system: str) -> None:
    """安装一个锁定版本的开发工具。

    `.installed.json` 同时记录工具版本和压缩包 `SHA256`，两者都相同才复用安装。
    更新时先在临时目录解压和检查，完成后再替换旧目录；工具始终留在项目内，
    不修改系统工具，也不写入玩家的 Minecraft 目录。
    """
    artifact = tool[system]  # 安装真正的平台资源。
    destination = DEV / "tools" / name  # 不修改系统工具。
    marker = destination / ".installed.json"  # 记录安装的版本与包内容。
    expected = {"version": tool["version"], "sha256": artifact["sha256"]}  # 复用必须两个条件都相同。
    if marker.exists() and json.loads(marker.read_text(encoding="utf-8")) == expected:
        print(f"已就绪 {name} {tool['version']}", flush=True)  # 明确报告复用的锁定版本。
        return  # 日常安装不重复替换完整工具。
    filename = Path(urlparse(artifact["url"]).path).name  # 文件名只用作缓存位置。
    package = download_file(artifact["url"], DEV / "downloads" / filename, artifact["sha256"])  # 内容由哈希判断。
    # 更新时先解压到临时位置，完整验证后才替换旧安装。
    installing = DEV / "tools" / (name + ".installing")  # 新安装完成前保留旧版。
    if installing.exists():
        shutil.rmtree(installing)  # 清理上次中断的自有安装目录。
    try:
        extract(package, installing)  # 安全解压真实发行包。
        if name == "renderdoc":
            binary = next(installing.rglob("qrenderdoc.exe"))  # 验证实际可执行文件发布者。
            print("RenderDoc 下载 SHA256：" + hashlib.sha256(package.read_bytes()).hexdigest(), flush=True)
            # 固定官方签名者，并通过环境变量传入路径，避免把本机路径拼进脚本。
            command = "$s=Get-AuthenticodeSignature -LiteralPath $env:OMNI_SIGNED_BINARY; if ($s.Status -ne 'Valid' -or $s.SignerCertificate.Subject -notmatch 'CN=Baldur (Scott )?Karlsson,') { exit 1 }"
            result = subprocess.run(["powershell", "-NoProfile", "-Command", command],
                                    env=os.environ | {"OMNI_SIGNED_BINARY": str(binary)})
            if result.returncode:
                raise ValueError("RenderDoc 发布者签名未通过验证")
            print("RenderDoc 官方签名通过；下载 SHA256：" + hashlib.sha256(package.read_bytes()).hexdigest())
        if destination.exists():
            shutil.rmtree(destination)  # 完整新安装已准备好才替换旧工具。
        installing.replace(destination)  # 切换到已检查的安装。
        marker.write_text(json.dumps(expected) + "\n", encoding="utf-8")  # 最后才标记成功。
    finally:
        if installing.exists():
            shutil.rmtree(installing)  # 失败后清理未完成安装。
    print(f"已安装 {name} {tool['version']}", flush=True)  # 只在目录切换成功后报告安装。


def prepare_graphics(data: dict) -> None:
    """准备独立游戏调试资源与整合包。

    模组下载、配置和光影包只写入项目的 `.dev/minecraft/`，玩家的启动器、
    存档、登录信息和真实游戏目录由启动器自己管理；这样调试环境可删除，
    也不会把开发配置带入玩家正在使用的实例。
    """
    game = DEV / "minecraft"  # 开发模组与玩家实例隔离。
    files = []  # 整合包只声明锁定的下载。
    for mod in data["mods"]:
        destination = game / "mods" / mod["file"]  # 工具仅管理这些指定模组。
        download_file(mod["url"], destination, mod["sha512"], "sha512")  # 不把安装记录当加载成功。
        files.append({"path": "mods/" + mod["file"],  # 整合包只使用实例内的相对路径。
                      "hashes": {"sha1": mod["sha1"], "sha512": mod["sha512"]},  # 保留整合包要求的两种校验值。
                      "downloads": [mod["url"]], "fileSize": destination.stat().st_size,  # 大小取自已校验的实际下载。
                      "env": {"client": "required", "server": "unsupported"}})  # 这些资源只用于客户端调试。
    index = {"formatVersion": 1, "game": "minecraft", "versionId": "omni-debug-1",  # 保持启动器识别的整合包协议。
             "name": "Omni 光影开发", "summary": "项目专用 Iris 图形调试实例",  # 名称说明用途，避免与玩家实例混淆。
             "files": files, "dependencies": {"minecraft": data["minecraft"],  # 游戏版本从同一锁定记录读取。
                                                 "fabric-loader": data["fabric"]}}  # 加载器版本同样不自行更新。
    config = game / "config/iris.properties"  # 独立实例加载开发包。
    config.parent.mkdir(parents=True, exist_ok=True)  # 不改玩家配置。
    if not config.exists():  # 首次写入默认值，保留开发者随后调整的配置。
        config.write_text("enableShaders=true\nshaderPack=Omni-dev.zip\nenableDebugOptions=true\n", encoding="ascii")
    build.generate()  # 整合包必须包含实际新入口。
    build.sync()  # 同步受控开发资源。
    contents = {"modrinth.index.json": (json.dumps(index, ensure_ascii=False, indent=2) + "\n").encode(),  # 中文整合包说明使用统一编码。
                "overrides/config/iris.properties": config.read_bytes(),  # 携带独立实例当前配置。
                "overrides/shaderpacks/Omni-dev.zip": (game / "shaderpacks/Omni-dev.zip").read_bytes()}  # 携带刚同步的开发光影。
    build.archive(DEV / "Omni-debug.mrpack", contents)  # 固定产物顺序方便重复构建。
    print("已准备 .dev/minecraft 和 .dev/Omni-debug.mrpack", flush=True)


def prepare_python_environment() -> None:
    """建立项目虚拟环境，按 `requirements-dev.lock` 的版本和哈希安装依赖。

    `--require-hashes` 拒绝未锁定的安装内容；依赖只进入 `.venv/`，不修改系统 Python。
    """
    folder = ROOT / ".venv"  # 开发依赖不装入系统解释器。
    interpreter = folder / ("Scripts/python.exe" if sys.platform == "win32" else "bin/python")  # 只使用项目的解释器。
    if not interpreter.exists():
        venv.create(folder, with_pip=True)  # 首次建立专用环境。
    subprocess.run([str(interpreter), "-m", "pip", "install", "--require-hashes",  # 安装器同时检查版本与文件内容。
                    "-r", str(ROOT / "requirements-dev.lock")], check=True)


def setup(with_graphics: bool) -> None:
    """安装锁定的检查工具，显式选择图形环境时再准备额外依赖。

    平台与架构在命令边界检查；全部下载留在项目内，避免影响玩家目录和系统工具。
    """
    system = {"win32": "windows", "linux": "linux"}.get(sys.platform)  # 只选择已提供的官方平台包。
    if system is None or platform.machine().lower() not in ("amd64", "x86_64"):
        raise ValueError("自动安装目前支持 Windows / Linux x64")
    if with_graphics and system != "windows":
        raise ValueError("便携图形环境目前支持 Windows x64；Linux 可单独安装 RenderDoc")
    data = read_lock()  # 安装前统一检查下载输入。
    for name in ("glslang", "actionlint"):
        install_tool(name, data["tools"][name], system)  # 每个锁定工具独立安装。
    build.generate()  # 初次环境也生成全部程序与菜单。
    if with_graphics:  # 没有明确选择图形环境时不下载游戏资源。
        install_tool("renderdoc", data["tools"]["renderdoc"], system)
        prepare_python_environment()  # 图形依赖只按显式选择安装。
        prepare_graphics(data)  # 准备整合包，不启动游戏。


def doctor() -> None:
    """运行工具版本命令，并检查独立实例的模组是否匹配锁定哈希。

    版本命令只证明工具能启动，下载校验只证明文件内容匹配；两者都不代表游戏加载成功。
    """
    for name in ("glslang", "actionlint"):  # 实际执行版本命令，不只看安装目录。
        subprocess.run([str(build.tool(name)), "--version" if name == "glslang" else "-version"], check=True)
    binaries = sorted((DEV / "tools/renderdoc").rglob("renderdoccmd.exe"))  # 是否存在只决定检查对象。
    if binaries:  # 只检查用户已安装的图形捕获工具。
        subprocess.run([str(binaries[0]), "version"], check=True)
    game = DEV / "minecraft"  # 只检查开发实例。
    data = read_lock()  # 校验按真实锁定字节进行。
    if game.exists():  # 独立实例不存在时不推断游戏状态。
        for mod in data["mods"]:
            path = game / "mods" / mod["file"]  # 文件名不是兼容证据。
            if not path.exists() or hashlib.sha512(path.read_bytes()).hexdigest() != mod["sha512"]:
                raise ValueError(f"调试模组缺失或校验失败：{mod['name']}")
        print(f"调试模组校验通过；Minecraft {data['minecraft']} 实际加载需在启动器中验证")


def watch() -> None:
    """观察源文件并调用构建同步，失败后等待下一次修改。

    同步只面向项目开发实例；生成文件不参与观察，避免生成操作再次触发自身。
    构建入口负责报告编译错误和保留上一份有效包，本函数只管理观察周期。
    """
    print("正在观察 shaders/、presets/ 和 VERSION。Ctrl+C 停止。", flush=True)
    previous = None  # 首次观察也进行构建。
    try:
        while True:
            paths = [ROOT / "VERSION", ROOT / "dependencies.json", *shader_files(), *(ROOT / "presets").glob("*.properties")]  # 显式流程与依赖变化同样触发。
            current = tuple((str(path), path.stat().st_mtime_ns) for path in sorted(paths))  # 文件名与修改时间共同决定是否重新同步。
            if current != previous:  # 维护的源码变化才触发同步。
                previous = current  # 失败后等待下一次修改，不无限重试。
                # 每次构建是独立命令；错误由构建入口报告，观察过程可以继续。
                subprocess.run([sys.executable, str(ROOT / "build.py"), "sync"], cwd=ROOT)
            time.sleep(0.5)  # 低频观察不占满处理器。
    except KeyboardInterrupt:  # 用户停止观察不算构建失败。
        print("已停止观察")


def shader_files() -> list[Path]:
    """只观察维护的源码，排除生成菜单与翻译，防止无限重建。"""
    return [path for path in (ROOT / "shaders").rglob("*") if path.is_file() and
            (path.suffix in {".glsl", ".vsh", ".fsh", ".gsh", ".csh", ".tcs", ".tes"}
              or path.name in {"pipeline.properties", "programs.json"})]  # 新细分阶段与显式流程表不能漏掉。


def main() -> None:
    """解析安装命令，所有错误在命令入口统一输出。"""
    parser = argparse.ArgumentParser(description="Omni 项目内开发环境")  # 命令入口统一报告边界错误。
    parser.add_argument("command", choices=("setup", "doctor", "watch", "renderdoc"))  # 固定公开命令，避免隐式执行其他动作。
    parser.add_argument("--graphics", action="store_true", help="增加本机图形调试工具和独立游戏资源")  # 额外下载必须显式选择。
    args = parser.parse_args()  # 无参数不进行安装或启动。
    if args.command == "setup":  # 安装与检查显式分开。
        setup(args.graphics)  # 只有明确安装命令修改开发环境。
    elif args.command == "doctor":
        doctor()  # 实际运行版本命令检查工具。
    elif args.command == "watch":
        watch()  # 长期观察由用户明确启动。
    else:
        matches = sorted((DEV / "tools/renderdoc").rglob("qrenderdoc.exe"))  # 运行安装的捕获界面。
        if not matches:
            raise ValueError("请先执行 python dev.py setup --graphics")
        subprocess.Popen([str(matches[0])], cwd=matches[0].parent)
        print("已打开项目内 RenderDoc")


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")  # 终端统一编码，中文状态不依赖系统区域设置。
    sys.stderr.reconfigure(encoding="utf-8")  # 错误使用同一编码，便于保存诊断日志。
    try:
        main()
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        print(f"错误：{error}", file=sys.stderr)
        sys.exit(1)
