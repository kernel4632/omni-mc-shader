"""定位并调用 Slang 编译器，把探针编译成 SPIR-V。

调用位置：`omni-gfx/build.py spirv` 与 `omni-gfx/build.py all`。
设计原因与取舍：
    编译器是开发工具，下载到 `.dev/tools`，不进仓库；构建只用项目内路径，
    不依赖系统搜索顺序，换机器时行为一致。缺少编译器时给出明确获取方式，
    不自动联网，避免普通检查意外下载几十兆文件。
"""
from __future__ import annotations

import json  # 读取发布信息，选择与平台匹配的压缩包。
import os  # 允许用环境变量临时指定编译器。
import platform  # 判断下载哪个平台的压缩包。
import shutil  # 解压后移动目录。
import subprocess  # 调用编译器和版本命令。
import sys  # 按平台选择可执行文件名。
import tarfile  # 读取 Linux 压缩包。
import tempfile  # 下载与解压先放临时目录。
import urllib.request  # 只在显式要求时下载编译器。
import zipfile  # 读取 Windows 与 macOS 压缩包。
from pathlib import Path  # 固定工具目录与输出路径。

LIB = Path(__file__).resolve().parent.parent  # omni-gfx 根目录。
DEV_TOOLS = LIB.parent / ".dev" / "omni-gfx" / "tools"  # 本机工具目录，已被忽略规则排除。
SLANG_DIR = DEV_TOOLS / "slang"  # 编译器解压位置。
PROBES = LIB / "tests" / "probes"  # 每模块一个编译探针。
SPIRV_OUT = LIB / "generated" / "spirv"  # 生成产物目录，二进制不进仓库。


def find() -> Path:
    """返回项目内的 `slangc` 可执行文件路径，找不到时报出获取方式。

    先看 `SLANGC` 环境变量，再递归搜索 `.dev` 工具目录；只接受文件，
    避免把同名目录当成编译器。错误信息给出本项目实际支持的下载命令。
    """
    override = os.environ.get("SLANGC")  # 允许开发者用环境变量指定已装好的编译器。
    if override:
        path = Path(override)
        if path.is_file():
            return path
        raise ValueError(f"SLANGC 指向的文件不存在：{path}")
    name = "slangc.exe" if sys.platform == "win32" else "slangc"  # 平台决定可执行文件名。
    matches = sorted(SLANG_DIR.rglob(name)) if SLANG_DIR.is_dir() else []  # 解压层级可能不同。
    if not matches:
        raise ValueError("缺少 Slang 编译器：运行构建脚本的 spirv 命令并加下载选项，或设置 SLANGC")
    return matches[0]  # 排序后固定选择第一个，保证多次构建一致。


def version() -> str:
    """返回编译器版本的第一行，写进 SPIR-V 清单。

    版本是复现产物的一部分：不同版本的优化与指令选择可能不同，
    记录后可以判断旧产物是否需要重新生成。
    """
    result = subprocess.run([str(find()), "-version"], capture_output=True, text=True, encoding="utf-8", errors="replace")  # 版本命令不修改文件。
    if result.returncode != 0:  # 编译器自身报错时不能继续。
        raise RuntimeError(result.stderr.strip() or result.stdout.strip())
    return (result.stdout or result.stderr).strip().splitlines()[0]  # 第一行通常就是版本号。


def download() -> Path:
    """下载最近发布的 Slang 压缩包并解压到项目工具目录，返回编译器路径。

    只从 GitHub 官方发布地址下载，压缩包按平台选择；下载和解压都在临时目录完成，
    成功后才替换正式目录，避免中断留下半套工具。调用方必须显式触发。
    """
    if platform.system() == "Windows":
        pattern, suffix = "windows-x86_64.zip", "zip"  # Windows 使用普通发布包，不用调试信息包。
    elif platform.system() == "Linux":
        pattern, suffix = "linux-x86_64.tar.gz", "tar"  # Linux 使用压缩包。
    else:
        raise ValueError("当前平台没有自动下载规则，请手动安装 Slang 并设置 SLANGC")
    request = urllib.request.Request("https://api.github.com/repos/shader-slang/slang/releases/latest", headers={"User-Agent": "omni-gfx"})  # 官方发布接口。
    release = json.load(urllib.request.urlopen(request, timeout=60))  # 发布信息是外部输入，失败直接报错。
    asset = next((item for item in release.get("assets", []) if pattern in item.get("name", "") and "debug" not in item.get("name", "")), None)  # 选普通发布包。
    if not asset:
        raise ValueError("发布页找不到匹配的 Slang 压缩包：" + pattern)
    DEV_TOOLS.mkdir(parents=True, exist_ok=True)  # 首次下载时创建目录。
    with tempfile.TemporaryDirectory(prefix="slang-", dir=DEV_TOOLS) as temporary:  # 解压先放临时目录。
        archive = Path(temporary) / asset["name"]  # 下载文件名来自发布页，只用于本地。
        urllib.request.urlretrieve(asset["browser_download_url"], archive)  # 下载完整压缩包。
        unpacked = Path(temporary) / "unpacked"  # 解压目标。
        unpacked.mkdir()
        if suffix == "zip":
            with zipfile.ZipFile(archive) as bundle:
                bundle.extractall(unpacked)
        else:
            with tarfile.open(archive) as bundle:
                bundle.extractall(unpacked)
        if SLANG_DIR.exists():
            shutil.rmtree(SLANG_DIR)  # 替换旧版本，避免多份编译器混用。
        shutil.move(str(unpacked), str(SLANG_DIR))  # 完整解压后才进入正式位置。
    return find()  # 返回新编译器路径。


def compile_probe(module: str, output: Path) -> None:
    """把一个模块探针编译成 SPIR-V，失败时带回编译器原始输出。

    `module` 是数学、颜色或采样模块；探针文件与输出文件同名。
    编译命令固定目标与阶段，不读取调用方环境中的默认配置。
    """
    probe = PROBES / f"{module}.slang"  # 每模块一个探针。
    output.parent.mkdir(parents=True, exist_ok=True)  # 首次生成时创建目录。
    command = [
        str(find()), str(probe),
        "-entry", "probeMain", "-stage", "fragment",
        "-target", "spirv", "-emit-spirv-directly",
        "-o", str(output),
    ]  # 直接生成 SPIR-V，不依赖外部转换工具。
    result = subprocess.run(command, capture_output=True, text=True, encoding="utf-8", errors="replace")  # 保留输出用于报错。
    if result.returncode != 0:
        detail = (result.stderr or result.stdout).strip().splitlines()[:6]  # 只显示前几行，便于定位。
        raise RuntimeError(f"Slang 编译失败：{module}\n" + "\n".join(detail))
