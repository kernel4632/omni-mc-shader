"""独立游戏调试：复用已有安装的游戏库，在 .dev/minecraft 中运行测试实例。

示例：.venv/Scripts/python.exe game.py configure --minecraft-dir D:/Games/.minecraft
      --version fabric-loader-version --java D:/Java/bin/java.exe
随后执行 .venv/Scripts/python.exe game.py launch。使用开发测试身份，禁用多人游戏。
正常游玩和账号登录交给启动器；本工具不读取现有账号或访问令牌。
"""

from __future__ import annotations

import argparse  # 解析独立实例与回归命令。
import csv  # 读取真实帧间隔采样。
import json  # 本机设置与测试报告。
import math  # 拒绝无穷与无效测量值。
import os  # 规范化Windows短路径和长路径表示。
import re  # Windows世界名与进程参数在边界检查。
import shutil  # 复用游戏资源，不复制玩家数据。
import statistics  # 真实样本汇总。
import subprocess  # 启动受控实例与采样器。
import sys  # 唯一入口报告错误。
from pathlib import Path, PureWindowsPath  # 不把Windows驱动相对路径当作世界名。

import build  # 游戏启动前使用同一构建检查。

ROOT = Path(__file__).resolve().parent  # 不依赖终端工作目录。
SETTINGS = ROOT / ".dev/game.local.json"  # 个人路径不提交。

def development_path(path: Path) -> Path:
    """确认自有输出留在开发目录，并拒绝路径中任何链接或目录联接。"""
    root_absolute = Path(os.path.abspath(os.fspath(ROOT)))  # 词法比较统一短名和长名。
    base = root_absolute/".dev"
    absolute = Path(os.path.abspath(os.fspath(path)))
    if not absolute.is_relative_to(base):
        raise ValueError("输出必须留在本项目 .dev 内")  # 目录链接不能把输出转到玩家目录。
    current = root_absolute
    for part in absolute.relative_to(root_absolute).parts:
        current /= part
        if current.is_symlink() or current.is_junction():
            raise ValueError(f"开发输出路径不能包含链接或目录联接：{current}")  # 文件链接与Windows目录联接同样拒绝。
    existing = absolute
    missing = []
    while not existing.exists():
        missing.append(existing.name)
        existing = existing.parent
    canonical_existing = Path(os.path.realpath(os.fspath(existing)))
    canonical_absolute = canonical_existing.joinpath(*reversed(missing))
    if not canonical_absolute.is_relative_to(Path(os.path.realpath(os.fspath(base)))):
        raise ValueError("输出的真实路径越过本项目 .dev")  # 已存在的链接目标也不能逃逸。
    return absolute


def configure(directory: Path, version: str, java: Path, isolated_java: bool = False) -> None:
    """检查已有安装与 Java，将个人路径只保存在忽略的本机配置。"""
    directory, java = directory.resolve(), java.resolve()  # 配置边界固定资源位置。
    if not version or Path(version).name != version or "/" in version or "\\" in version:
        raise ValueError("游戏版本必须是 versions/ 中的单个目录名")
    source = directory / "versions" / version / (version + ".json")  # 使用用户选择的已有安装描述。
    if not source.is_file() or not java.is_file():
        raise ValueError("找不到指定游戏版本 JSON 或 Java 可执行程序")
    subprocess.run([str(java), "-version"], check=True)  # 实际确认运行时能启动。
    if isolated_java:  # 复制运行时必须由配置参数明确选择。
        runtime = java.parent.parent  # 独立进程需要完整运行时。
        if not (runtime / "release").is_file() or not (runtime / "lib").is_dir():
            raise ValueError("独立复制需要完整 Java runtime 的 bin/java.exe")
        destination = ROOT / ".dev/java"  # 不修改系统安装。
        if not destination.exists():  # 已准备的运行时不重复覆盖。
            shutil.copytree(runtime, destination)  # 只复制首次配置的运行时。
        java = destination / "bin/omni-java.exe"  # 独立名称用于进程与采样辨认。
        shutil.copyfile(destination / "bin/java.exe", java)  # 名称区分测试与玩家进程。
    SETTINGS.parent.mkdir(parents=True, exist_ok=True)  # 本机配置仅写开发目录。
    SETTINGS.write_text(json.dumps({"minecraftDirectory": str(directory), "version": version,
                                   "java": str(java)}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("本机启动配置已保存到 .dev/game.local.json")


def launch(capture: bool) -> None:
    """在独立游戏目录启动开发实例，将日志和捕获都留在项目内。"""
    from minecraft_launcher_lib.command import get_minecraft_command  # 成熟依赖解析启动参数。
    from minecraft_launcher_lib.utils import generate_test_options  # 不读取玩家账号。

    if not SETTINGS.exists():
        raise ValueError("请先运行 game.py configure 配置已有游戏安装")
    data = json.loads(SETTINGS.read_text(encoding="utf-8"))  # 不读取任何账号或访问令牌。
    installed = json.loads((Path(data["minecraftDirectory"]) / "versions" / data["version"] /
                            (data["version"] + ".json")).read_text(encoding="utf-8-sig"))
    tools = json.loads((ROOT / "dev-tools.lock.json").read_text(encoding="utf-8"))  # 运行版本必须匹配调试环境。
    if installed.get("inheritsFrom", installed.get("id")) != tools["minecraft"]:
        raise ValueError("现有游戏版本与锁定调试模组不一致，请配置对应的 Fabric 游戏版本")
    game = ROOT / ".dev/minecraft"  # 存档与设置完全独立。
    game.mkdir(parents=True, exist_ok=True)  # 游戏启动目录与玩家实例隔离。
    build.generate()  # 启动前生成所有真实入口。
    build.check()  # 无效代码不能同步到开发实例。
    build.sync()  # 只更新工具管理的包。
    launch_options = generate_test_options()  # 使用依赖提供的开发身份。
    launch_options.update({"username": "OmniDeveloper", "executablePath": data["java"],
                           "gameDirectory": str(game), "nativesDirectory": str(game / "natives"),
                           "disableMultiplayer": True, "disableChat": True,
                           "customResolution": True, "resolutionWidth": "960", "resolutionHeight": "540",
                           "jvmArguments": ["-Xmx2G", "-Ddebugger=skip"]})
    launcher = prepare_launcher(Path(data["minecraftDirectory"]), data["version"])  # 原安装描述保持不变。
    command = get_minecraft_command(data["version"], launcher, launch_options)  # 真实继承版本由成熟依赖处理。
    for index, argument in enumerate(command):  # 本体资源复用已有安装，不搬移玩家文件。
        for folder in ("libraries", "assets"):
            argument = argument.replace(str(launcher / folder), str(Path(data["minecraftDirectory"]) / folder))
        command[index] = argument  # 启动仍使用独立游戏目录。
    # 独立游戏目录仍可复用本体资源；不复制玩家的存档、设置或账号。
    if capture:  # 捕获开销只有显式选择才引入。
        matches = sorted((ROOT / ".dev/tools/renderdoc").rglob("renderdoccmd.exe"))  # 调用项目内锁定工具。
        if not matches:
            raise ValueError("请先运行 python dev.py setup --graphics")
        (ROOT / ".dev/captures").mkdir(parents=True, exist_ok=True)
        command = [str(matches[0]), "capture", "-d", str(game), "-c",
                   str(ROOT / ".dev/captures/Omni"), *command]
    log = ROOT / ".dev/game-launch.log"  # 捕获游戏实际输出。
    with log.open("wb") as output:  # 游戏原始日志可追溯启动失败。
        process = subprocess.Popen(command, cwd=game, stdout=output, stderr=subprocess.STDOUT)
    record = development_path(ROOT/".dev/game-process.json")  # 采样器只能接受工具自己启动的进程。
    record.write_text(json.dumps({"pid":process.pid,"java":str(Path(data["java"]).resolve()),"gameDirectory":str(game.resolve())})+"\n",encoding="utf-8")  # 后续仍核对实际进程，防止进程号复用。
    print(f"已启动专用开发实例，进程 {process.pid}；日志：.dev/game-launch.log")


def prepare_launcher(directory: Path, version: str) -> Path:
    """将已有版本描述规范化到项目内，兼容启动器生成的 UTF-8 BOM。"""
    launcher = ROOT / ".dev/launcher"  # 描述规范化只在自有目录进行。
    pending, copied = [version], set()  # 显式跟踪继承链。
    while pending:
        current = pending.pop()  # 逐个读取父版本。
        if current in copied or Path(current).name != current or "/" in current or "\\" in current:
            raise ValueError("游戏版本描述包含循环或越界引用")
        copied.add(current)  # 相同版本再次出现即拒绝循环。
        source = directory / "versions" / current  # 只读取用户选择安装的继承链。
        data = json.loads((source / (current + ".json")).read_text(encoding="utf-8-sig"))
        if "inheritsFrom" in data and "jar" not in data:
            data["jar"] = data["inheritsFrom"] # 模组版本复用基础版本的游戏本体。
        destination = launcher / "versions" / current  # 复制描述而非原实例设置。
        destination.mkdir(parents=True, exist_ok=True)  # 描述复制留在开发目录。
        (destination / (current + ".json")).write_text(json.dumps(data), encoding="utf-8")
        jar = source / (current + ".jar")  # 仅复制实际存在的版本本体。
        if jar.exists():
            target = destination / jar.name  # 自有描述目录中的本体路径。
            if not target.exists() or target.stat().st_size != jar.stat().st_size:
                shutil.copyfile(jar, target)  # 游戏本体仍来自用户已有合法安装。
        if "inheritsFrom" in data:
            pending.append(data["inheritsFrom"])  # 继续真实继承关系。
    return launcher


def regression(world: str, pack_format: int) -> Path:
    """在专用测试存档中生成可执行回归场景，不启动或操作游戏。"""
    if not re_world(world) or type(pack_format) is not int or pack_format<1:
        raise ValueError("需要单个测试世界名与实际数据包格式编号")  # 玩家输入先检查，不建立任何目录。
    folder = development_path(ROOT / ".dev/minecraft/saves" / world)  # 世界目录不能通过链接指向玩家存档。
    if not (folder / "level.dat").is_file(): raise ValueError("请先在专用实例创建测试世界，不能指向真实玩家存档")  # 不创建伪造世界。
    pack = development_path(folder / "datapacks/Omni-regression")  # 数据包目录也必须留在自有实例。
    functions = development_path(pack / "data/omni/function")  # 函数目录链接不能逃逸。
    for member in pack.rglob("*"):
        development_path(member)  # 任何现有成员链接在第一次写入前统一拒绝。
    destination = development_path(ROOT / ".dev/reports/regression.json")  # 报告路径也在所有写入之前检查。
    functions.mkdir(parents=True,exist_ok=True)  # 不碰其他数据包。
    (pack / "pack.mcmeta").write_text(json.dumps({"pack":{"pack_format":pack_format,"description":"Omni 专用场景回归"}},ensure_ascii=False)+"\n",encoding="utf-8")
    setup = [
        "execute in minecraft:overworld run forceload add -16 -16 16 16",  # 确保专用区域在命令执行时已加载。
        "execute in minecraft:overworld run fill -16 79 -16 16 79 16 minecraft:stone",  # 专用测试平台。
        "execute in minecraft:overworld run fill -16 80 -16 16 92 16 minecraft:air",  # 清除平台上方遮挡。
        "execute in minecraft:overworld run fill -10 80 -10 0 80 0 minecraft:water",  # 浅水透明与反射。
        "execute in minecraft:overworld run fill -10 75 -10 0 78 0 minecraft:stone",  # 深水池底。
        "execute in minecraft:overworld run fill -9 76 -9 -1 79 -1 minecraft:water",  # 水下实际深度区域。
        "execute in minecraft:overworld run fill 2 80 -8 2 85 0 minecraft:glass",  # 透明玻璃对照。
        "execute in minecraft:overworld run setblock 5 80 -4 minecraft:glowstone",  # 局部原版光源。
        "execute in minecraft:overworld run fill 9 80 -6 9 84 -6 minecraft:oak_log",  # 树干与叶片遮挡对照。
        "execute in minecraft:overworld run fill 7 84 -8 11 86 -4 minecraft:oak_leaves",  # 风摆、裁切与阴影。
        "execute in minecraft:overworld run kill @e[type=minecraft:armor_stand,tag=omni_test]",  # 重复准备只移除工具自己的实体。
        'execute in minecraft:overworld run summon minecraft:armor_stand 4 80 0 {Tags:["omni_test"]}',  # 独立实体路径不累积重复对象。
        "execute in minecraft:overworld run fill -14 80 4 -6 85 12 minecraft:stone",  # 洞穴外围。
        "execute in minecraft:overworld run fill -13 81 5 -7 83 11 minecraft:air",  # 无天空光的洞穴内部。
        "execute in minecraft:overworld run fill -10 81 4 -10 82 5 minecraft:air",  # 洞穴开口。
        "execute in minecraft:overworld run fill 4 80 5 8 84 9 minecraft:oak_planks",  # 小型建筑外墙。
        "execute in minecraft:overworld run fill 5 81 6 7 83 8 minecraft:air",  # 建筑内部。
        "gamerule minecraft:advance_time false",  # 当前版本规则注册表的时间冻结名称。
        "gamerule minecraft:advance_weather false",  # 当前版本规则注册表的天气冻结名称。
        "gamemode creative @s",  # 防止固定测试位置导致坠落或窒息。
    ]
    (functions / "setup.mcfunction").write_text("\n".join(setup)+"\n",encoding="utf-8")  # 只有玩家执行函数后才改变专用世界。
    scenes = {
        "day":["time set noon","weather clear","execute in minecraft:overworld run tp @s 12 83 12 135 20"],  # 日间同场景对照。
        "night":["time set midnight","weather clear","execute in minecraft:overworld run tp @s 12 83 12 135 20"],  # 月光与星空。
        "rain":["time set noon","weather rain","execute in minecraft:overworld run tp @s 12 83 12 135 20"],  # 晴雨转换与湿润。
        "underwater":["execute in minecraft:overworld run tp @s -5 77 -5 0 0"],  # 相机真正浸入深水池。
        "cave":["execute in minecraft:overworld run tp @s -10 81 8 180 0"],  # 无天空光的室内明暗。
        "nether":["execute in minecraft:the_nether run tp @s 0 100 0 0 0"],  # 下界环境与历史重置。
        "end":["execute in minecraft:the_end run tp @s 0 90 0 0 0"],  # 末地环境与历史重置。
    }
    for name,commands in scenes.items(): (functions / (name+".mcfunction")).write_text("\n".join(commands)+"\n",encoding="utf-8")  # 不自动传送玩家。
    report = {"shaderVersion":build.version(),"world":world,"scenes":{n:{"status":"未运行","command":"/function omni:"+n} for n in scenes},"manualChecks":["手持物","方块破坏","透明粒子","重载","关闭再开启","传送","切维度","窗口缩放"],"scope":"只生成场景命令，未游戏验证"}
    destination.parent.mkdir(parents=True,exist_ok=True)  # 全部边界已经检查，再创建报告目录。
    destination.write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")  # 不把生成脚本当验证通过。
    return pack

def re_world(value: str) -> bool:
    """检查世界名，拒绝路径、符号链接逃逸和特殊目录。"""
    if not isinstance(value,str) or value!=value.strip() or not value or value in (".",".."):
        return False  # 空白、特殊目录与隐式改名不接受。
    if PureWindowsPath(value).drive or re.search(r'[<>:"/\\|?*\x00-\x1f]',value) or value.endswith(("."," ")):
        return False  # 驱动相对路径、替代数据流与Windows非法名称都拒绝。
    if re.fullmatch(r"(?:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\..*)?",value,re.I):
        return False  # 设备名称不是世界目录。
    try:
        development_path(ROOT/".dev/minecraft/saves"/value)
    except ValueError:
        return False  # 链接逃逸保留为无效用户输入。
    return True

def performance_context(context: dict) -> None:
    """在捕获之前检查设备与固定场景信息，不产生外部采样副作用。"""
    required = {"device","driver","scene","resolution","preset","minecraft","iris"}  # 这些字段是比较两个样本的最小依据。
    if not isinstance(context,dict) or set(context)!=required or any(not isinstance(v,str) or not v.strip() for v in context.values()):
        raise ValueError("性能上下文必须填写设备、驱动、场景、分辨率、预设、游戏与加载器")

def development_process(pid: int) -> None:
    """核对工具启动记录与当前实际进程，拒绝任意进程号与号复用。"""
    record = json.loads(development_path(ROOT/".dev/game-process.json").read_text(encoding="utf-8"))  # 只有工具自己启动的开发实例可采样。
    if not isinstance(record,dict) or record.get("pid")!=pid or not isinstance(record.get("java"),str) or not isinstance(record.get("gameDirectory"),str):
        raise ValueError("进程号不属于记录的 Omni 开发实例")
    expected_directory = development_path(ROOT/".dev/minecraft").resolve()  # 数据目录仍需实际边界检查。
    if Path(record["gameDirectory"]).resolve()!=expected_directory:
        raise ValueError("记录的进程不使用本项目开发目录")
    command = f"Get-CimInstance Win32_Process -Filter 'ProcessId={pid}' | Select-Object ExecutablePath,CommandLine | ConvertTo-Json -Compress"  # pid已检查为正整数，没有字符串命令注入。
    result = subprocess.run(["powershell","-NoProfile","-Command",command],check=True,capture_output=True,text=True,encoding="utf-8",errors="replace")
    actual = json.loads(result.stdout or "null")  # 权限不足或进程不存在时拒绝，不猜测身份。
    if not isinstance(actual,dict) or not actual.get("ExecutablePath") or Path(actual["ExecutablePath"]).resolve()!=Path(record["java"]).resolve():
        raise ValueError("实际进程与开发运行时不匹配")
    arguments = actual.get("CommandLine","").replace("\\","/").lower()  # 比较标准化后的受控启动参数。
    target = str(expected_directory).replace("\\","/").lower()
    if not re.search(r'--gameDir\s+"?'+re.escape(target)+r'(?:"|\s|$)',arguments,re.I):
        raise ValueError("实际进程命令没有匹配的开发游戏目录")

def frame_report(source: Path, pid: int, context: dict) -> dict:
    """汇总真实采样，拒绝混进其他进程、交换链与无效数值。"""
    performance_context(context)  # 文件汇总的外部入口同样要求完整测量信息。
    frames, chains = [],set()  # 同一交换链才能比较帧间隔。
    with source.open(encoding="utf-8-sig",newline="") as stream:
        reader = csv.DictReader(stream)
        if not {"ProcessID","SwapChainAddress","MsBetweenPresents"}.issubset(reader.fieldnames or []): raise ValueError("需要 PresentMon 一版指标的帧间隔采样")  # 指标不冒充纯着色器耗时。
        for row in reader:
            if int(row["ProcessID"])!=pid: continue  # 只汇总指定游戏进程。
            chains.add(row["SwapChainAddress"])
            value = float(row["MsBetweenPresents"])
            if not math.isfinite(value) or value<=0: raise ValueError("采样包含非正或无效帧间隔")  # 不静默丢弃慢帧。
            frames.append(value)
    if len(chains)!=1 or len(frames)<20: raise ValueError("至少需要二十帧且只有一个交换链")  # 不能用几帧声称稳定性能。
    ordered = sorted(frames)  # 按完整样本分布计算慢帧百分位。
    result = {"shaderVersion":build.version(),"context":context,"processId":pid,"samples":len(frames),"meanFrameMs":statistics.fmean(frames),"p99FrameMs":ordered[math.ceil(len(ordered)*0.99)-1],"averageFps":1000.0/statistics.fmean(frames),"scope":"呈现帧间隔，包含处理器等待，不等同于单效果显卡耗时"}
    return result  # 原始样本由调用者保留。

def sample(binary: Path, pid: int, seconds: int, context: Path) -> Path:
    """调用官方采样器捕获专用游戏进程，固定写入开发目录。"""
    binary = binary.resolve()
    if sys.platform!="win32" or not binary.is_file() or not binary.is_relative_to(development_path(ROOT/".dev/tools")) or type(pid) is not int or pid<=0 or type(seconds) is not int or not 5<=seconds<=600:
        raise ValueError("采样需要开发目录内的 Windows PresentMon、游戏进程号与五至六百秒时长")
    data = json.loads(context.read_text(encoding="utf-8"))  # 输入场景信息先保留原始记录。
    performance_context(data)  # 无效上下文必须在进程检查与采样之前失败。
    folder = development_path(ROOT / ".dev/reports/performance")
    output = development_path(folder / "frames.csv")  # 真实原始采样文件不能是链接。
    destination = development_path(folder / "summary.json")
    if output.exists(): raise ValueError("已有原始采样，请先归档再采新样本")  # 不覆盖历史证据。
    development_process(pid)  # 任意玩家Java进程或复用pid不能被当作隔离实例。
    folder.mkdir(parents=True,exist_ok=True)  # 所有输入与进程身份检查完成才开始写入。
    command = [str(binary),"--process_id",str(pid),"--timed",str(seconds),"--terminate_after_timed","--output_file",str(output),"--v1_metrics","--no_console_stats","--session_name","OmniPerformance"]  # 官方已核对命令接口。
    subprocess.run(command,check=True)  # 不自动提权，不终止其他采样会话。
    report = frame_report(output,pid,data)
    destination.write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")  # 只有真实样本能生成结论。
    return destination

def main() -> None:
    """解析配置与启动参数，统一报告环境错误。"""
    parser = argparse.ArgumentParser(description="Omni 独立 Minecraft 调试")
    commands = parser.add_subparsers(dest="command", required=True)  # 不给命令时不会启动游戏。
    config = commands.add_parser("configure")  # 本机安装只保存受控路径。
    config.add_argument("--minecraft-dir", type=Path, required=True)
    config.add_argument("--version", required=True)
    config.add_argument("--java", type=Path, required=True)
    config.add_argument("--isolated-java", action="store_true", help="将现有 Java 复制到项目内，方便区分测试进程")
    run = commands.add_parser("launch")  # 游戏启动必须明确触发。
    run.add_argument("--capture", action="store_true", help="用项目内 RenderDoc 启动以捕获画面")
    regression_command = commands.add_parser("regression")  # 只准备专用世界的可重复场景。
    regression_command.add_argument("--world",required=True)  # 世界名只接受单个受控目录。
    regression_command.add_argument("--pack-format",type=int,required=True)
    performance = commands.add_parser("sample")  # 真实捕获与游戏启动分别授权。
    performance.add_argument("--presentmon",type=Path,required=True)  # 采样器必须位于开发工具目录。
    performance.add_argument("--pid",type=int,required=True)
    performance.add_argument("--seconds",type=int,default=30)
    performance.add_argument("--context",type=Path,required=True)  # 场景上下文先于任何外部捕获。
    args = parser.parse_args()  # 参数检查先于任何外部动作。
    if args.command == "configure":
        configure(args.minecraft_dir, args.version, args.java, args.isolated_java)
    elif args.command=="launch":
        launch(args.capture)
    elif args.command=="regression":
        print(regression(args.world,args.pack_format))  # 只生成函数，不运行游戏。
    else:
        print(sample(args.presentmon,args.pid,args.seconds,args.context))  # 捕获只由显式命令触发。


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
    try:
        main()
    except (ValueError, OSError, subprocess.SubprocessError, ImportError) as error:
        print(f"游戏启动失败：{error}", file=sys.stderr)
        sys.exit(1)
