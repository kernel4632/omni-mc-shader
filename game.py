"""独立游戏调试：复用已有安装的游戏库，在 .dev/minecraft 中运行测试实例。

示例：.venv/Scripts/python.exe game.py configure --minecraft-dir D:/Games/.minecraft
      --version fabric-loader-version --java D:/Java/bin/java.exe
随后执行 .venv/Scripts/python.exe game.py launch。使用开发测试身份，禁用多人游戏。
正常游玩和账号登录交给启动器；本工具不读取现有账号或访问令牌。
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

import build

ROOT = Path(__file__).resolve().parent
SETTINGS = ROOT / ".dev/game.local.json"


def configure(directory: Path, version: str, java: Path, isolated_java: bool = False) -> None:
    """检查已有安装与 Java，将个人路径只保存在忽略的本机配置。"""
    directory, java = directory.resolve(), java.resolve()
    if not version or Path(version).name != version or "/" in version or "\\" in version:
        raise ValueError("游戏版本必须是 versions/ 中的单个目录名")
    source = directory / "versions" / version / (version + ".json")
    if not source.is_file() or not java.is_file():
        raise ValueError("找不到指定游戏版本 JSON 或 Java 可执行程序")
    subprocess.run([str(java), "-version"], check=True)
    if isolated_java:
        runtime = java.parent.parent
        if not (runtime / "release").is_file() or not (runtime / "lib").is_dir():
            raise ValueError("独立复制需要完整 Java runtime 的 bin/java.exe")
        destination = ROOT / ".dev/java"
        if not destination.exists():
            shutil.copytree(runtime, destination)
        java = destination / "bin/omni-java.exe"
        shutil.copyfile(destination / "bin/java.exe", java)
    SETTINGS.parent.mkdir(parents=True, exist_ok=True)
    SETTINGS.write_text(json.dumps({"minecraftDirectory": str(directory), "version": version,
                                   "java": str(java)}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("本机启动配置已保存到 .dev/game.local.json")


def launch(capture: bool) -> None:
    """在独立游戏目录启动开发实例，将日志和捕获都留在项目内。"""
    from minecraft_launcher_lib.command import get_minecraft_command
    from minecraft_launcher_lib.utils import generate_test_options

    if not SETTINGS.exists():
        raise ValueError("请先运行 game.py configure 配置已有游戏安装")
    data = json.loads(SETTINGS.read_text(encoding="utf-8"))
    installed = json.loads((Path(data["minecraftDirectory"]) / "versions" / data["version"] /
                            (data["version"] + ".json")).read_text(encoding="utf-8-sig"))
    tools = json.loads((ROOT / "dev-tools.lock.json").read_text(encoding="utf-8"))
    if installed.get("inheritsFrom", installed.get("id")) != tools["minecraft"]:
        raise ValueError("现有游戏版本与锁定调试模组不一致，请配置对应的 Fabric 游戏版本")
    game = ROOT / ".dev/minecraft"
    game.mkdir(parents=True, exist_ok=True)
    build.generate()
    build.check()
    build.sync()
    launch_options = generate_test_options()
    launch_options.update({"username": "OmniDeveloper", "executablePath": data["java"],
                           "gameDirectory": str(game), "nativesDirectory": str(game / "natives"),
                           "disableMultiplayer": True, "disableChat": True,
                           "customResolution": True, "resolutionWidth": "960", "resolutionHeight": "540",
                           "jvmArguments": ["-Xmx2G", "-Ddebugger=skip"]})
    launcher = prepare_launcher(Path(data["minecraftDirectory"]), data["version"])
    command = get_minecraft_command(data["version"], launcher, launch_options)
    for index, argument in enumerate(command):
        for folder in ("libraries", "assets"):
            argument = argument.replace(str(launcher / folder), str(Path(data["minecraftDirectory"]) / folder))
        command[index] = argument
    # 独立游戏目录仍可复用本体资源；不复制玩家的存档、设置或账号。
    if capture:
        matches = sorted((ROOT / ".dev/tools/renderdoc").rglob("renderdoccmd.exe"))
        if not matches:
            raise ValueError("请先运行 python dev.py setup --graphics")
        (ROOT / ".dev/captures").mkdir(parents=True, exist_ok=True)
        command = [str(matches[0]), "capture", "-d", str(game), "-c",
                   str(ROOT / ".dev/captures/Omni"), *command]
    log = ROOT / ".dev/game-launch.log"
    with log.open("wb") as output:
        process = subprocess.Popen(command, cwd=game, stdout=output, stderr=subprocess.STDOUT)
    print(f"已启动专用开发实例，进程 {process.pid}；日志：.dev/game-launch.log")


def prepare_launcher(directory: Path, version: str) -> Path:
    """将已有版本描述规范化到项目内，兼容启动器生成的 UTF-8 BOM。"""
    launcher = ROOT / ".dev/launcher"
    pending, copied = [version], set()
    while pending:
        current = pending.pop()
        if current in copied or Path(current).name != current or "/" in current or "\\" in current:
            raise ValueError("游戏版本描述包含循环或越界引用")
        copied.add(current)
        source = directory / "versions" / current
        data = json.loads((source / (current + ".json")).read_text(encoding="utf-8-sig"))
        if "inheritsFrom" in data and "jar" not in data:
            data["jar"] = data["inheritsFrom"] # 模组版本复用基础版本的游戏本体。
        destination = launcher / "versions" / current
        destination.mkdir(parents=True, exist_ok=True)
        (destination / (current + ".json")).write_text(json.dumps(data), encoding="utf-8")
        jar = source / (current + ".jar")
        if jar.exists():
            target = destination / jar.name
            if not target.exists() or target.stat().st_size != jar.stat().st_size:
                shutil.copyfile(jar, target)
        if "inheritsFrom" in data:
            pending.append(data["inheritsFrom"])
    return launcher


def main() -> None:
    """解析配置与启动参数，统一报告环境错误。"""
    parser = argparse.ArgumentParser(description="Omni 独立 Minecraft 调试")
    commands = parser.add_subparsers(dest="command", required=True)
    config = commands.add_parser("configure")
    config.add_argument("--minecraft-dir", type=Path, required=True)
    config.add_argument("--version", required=True)
    config.add_argument("--java", type=Path, required=True)
    config.add_argument("--isolated-java", action="store_true", help="将现有 Java 复制到项目内，方便区分测试进程")
    run = commands.add_parser("launch")
    run.add_argument("--capture", action="store_true", help="用项目内 RenderDoc 启动以捕获画面")
    args = parser.parse_args()
    if args.command == "configure":
        configure(args.minecraft_dir, args.version, args.java, args.isolated_java)
    else:
        launch(args.capture)


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
    try:
        main()
    except (ValueError, OSError, subprocess.SubprocessError, ImportError) as error:
        print(f"游戏启动失败：{error}", file=sys.stderr)
        sys.exit(1)
