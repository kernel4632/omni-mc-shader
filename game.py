"""独立游戏调试实例：复用已有游戏资源，在项目开发目录运行测试。

调用位置：这是开发工具的命令行入口，供人工执行 `configure`、`launch`、
`regression` 和 `sample`，不参与玩家启动器和正式游戏流程。

可复制示例：
    .venv/Scripts/python.exe game.py configure --minecraft-dir D:/Games/.minecraft \
        --version fabric-loader-version --java D:/Java/bin/java.exe
    .venv/Scripts/python.exe game.py launch
    .venv/Scripts/python.exe game.py regression --world TestWorld --pack-format 61
    .venv/Scripts/python.exe game.py sample --presentmon .dev/tools/PresentMon.exe \
        --pid 1234 --seconds 30 --context .dev/performance-context.json

设计原因与安全取舍：游戏本体的 `libraries` 和 `assets` 可以复用，减少下载和
磁盘占用；存档、设置、日志、采样和报告必须留在 `.dev`，避免碰到玩家数据。
启动使用开发身份并关闭多人游戏，但不读取玩家账号、登录凭据或访问令牌。
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
import paths  # 开发目录写入边界在专用模块里只检查一次。

ROOT = Path(__file__).resolve().parent  # 不依赖终端工作目录。
SETTINGS = ROOT / ".dev/game.local.json"  # 个人路径不提交。

# --- 检查开发目录路径 ---
def development_path(path: Path) -> Path:
    """确认开发输出留在 `.dev`，并拒绝符号链接与目录联接逃逸。

    开发工具只允许写入本项目的 `.dev`，因为这里的文件可以随时删除，不会
    污染玩家真实实例。边界检查集中在 `paths.development_path`，这里只固定本项目的根目录。
    """
    return paths.development_path(path, ROOT)  # 根目录固定为项目自身，调用处不再重复传递。


# --- 保存本机配置 ---
def configure(directory: Path, version: str, java: Path, isolated_java: bool = False) -> None:
    """检查已有游戏安装和 Java，并保存开发实例配置。

    配置只记录用户明确指定的资源路径，不读取玩家账号或令牌。`isolated_java`
    会把运行时复制到 `.dev/java`，便于辨认进程；代价是占用额外磁盘空间。
    """
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
        destination = development_path(ROOT / ".dev/java")  # 不修改系统安装，也不允许链接改写目标。
        if not destination.exists():  # 已准备的运行时不重复覆盖。
            shutil.copytree(runtime, destination)  # 只复制首次配置的运行时。
        java = development_path(destination / "bin/omni-java.exe")  # 独立名称用于进程与采样辨认。
        shutil.copyfile(destination / "bin/java.exe", java)  # 名称区分测试与玩家进程。
    development_path(SETTINGS)  # 写配置前确认 `.dev` 没有被链接带出项目。
    SETTINGS.parent.mkdir(parents=True, exist_ok=True)  # 本机配置仅写开发目录。
    SETTINGS.write_text(json.dumps({"minecraftDirectory": str(directory), "version": version,
                                    "java": str(java)}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("本机启动配置已保存到 .dev/game.local.json")


# --- 启动开发实例 ---
def launch(capture: bool) -> None:
    """启动独立开发实例，并把日志和捕获留在项目开发目录。

    游戏目录只使用 `.dev/minecraft`，资源目录可以复用已有安装以减少复制。
    启动使用开发测试身份，不读取玩家账号；进程记录、日志和捕获也不能写入玩家目录。
    """
    from minecraft_launcher_lib.command import get_minecraft_command  # 成熟依赖解析启动参数。
    from minecraft_launcher_lib.utils import generate_test_options  # 不读取玩家账号。

    development_path(SETTINGS)  # 配置文件本身也必须留在开发目录。
    if not SETTINGS.exists():
        raise ValueError("请先运行 game.py configure 配置已有游戏安装")
    data = json.loads(SETTINGS.read_text(encoding="utf-8"))  # 不读取任何账号或访问令牌。
    installed = json.loads((Path(data["minecraftDirectory"]) / "versions" / data["version"] /
                            (data["version"] + ".json")).read_text(encoding="utf-8-sig"))
    tools = json.loads((ROOT / "dev-tools.lock.json").read_text(encoding="utf-8"))  # 运行版本必须匹配调试环境。
    if installed.get("inheritsFrom", installed.get("id")) != tools["minecraft"]:
        raise ValueError("现有游戏版本与锁定调试模组不一致，请配置对应的 Fabric 游戏版本")
    game = development_path(ROOT / ".dev/minecraft")  # 存档与设置完全独立，不能被链接带出项目。
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
        capture_folder = development_path(ROOT / ".dev/captures")
        capture_folder.mkdir(parents=True, exist_ok=True)
        command = [str(matches[0]), "capture", "-d", str(game), "-c",
                   str(development_path(capture_folder / "Omni")), *command]
    log = development_path(ROOT / ".dev/game-launch.log")  # 捕获游戏实际输出。
    record = development_path(ROOT/".dev/game-process.json")  # 启动前确认采样身份记录可安全写入。
    with log.open("wb") as output:  # 游戏原始日志可追溯启动失败。
        process = subprocess.Popen(command, cwd=game, stdout=output, stderr=subprocess.STDOUT)
    record.write_text(json.dumps({"pid":process.pid,"java":str(Path(data["java"]).resolve()),"gameDirectory":str(game.resolve())})+"\n",encoding="utf-8")  # 后续仍核对实际进程，防止进程号复用。
    print(f"已启动专用开发实例，进程 {process.pid}；日志：.dev/game-launch.log")


# --- 准备版本描述 ---
def prepare_launcher(directory: Path, version: str) -> Path:
    """把已有版本描述复制到开发目录，并展开真实继承关系。

    启动器生成的 JSON 可能带 UTF-8 BOM（文件开头的兼容标记），这里统一
    读取后重写为项目自己的描述。只复制版本描述和游戏本体，不复制存档、设置、账号或令牌。
    """
    launcher = development_path(ROOT / ".dev/launcher")  # 描述规范化只在自有目录进行。
    versions_to_copy, copied_versions = [version], set()  # 显式跟踪继承链。
    while versions_to_copy:
        current = versions_to_copy.pop()  # 逐个读取父版本。
        if current in copied_versions or Path(current).name != current or "/" in current or "\\" in current:
            raise ValueError("游戏版本描述包含循环或越界引用")
        copied_versions.add(current)  # 相同版本再次出现即拒绝循环。
        source = directory / "versions" / current  # 只读取用户选择安装的继承链。
        data = json.loads((source / (current + ".json")).read_text(encoding="utf-8-sig"))
        if "inheritsFrom" in data and "jar" not in data:
            data["jar"] = data["inheritsFrom"] # 模组版本复用基础版本的游戏本体。
        destination = development_path(launcher / "versions" / current)  # 复制描述而非原实例设置。
        destination.mkdir(parents=True, exist_ok=True)  # 描述复制留在开发目录。
        description = development_path(destination / (current + ".json"))  # 版本描述也拒绝已有链接。
        description.write_text(json.dumps(data), encoding="utf-8")
        jar = source / (current + ".jar")  # 仅复制实际存在的版本本体。
        if jar.exists():
            target = development_path(destination / jar.name)  # 自有描述目录中的本体路径。
            if not target.exists() or target.stat().st_size != jar.stat().st_size:
                shutil.copyfile(jar, target)  # 游戏本体仍来自用户已有合法安装。
        if "inheritsFrom" in data:
            versions_to_copy.append(data["inheritsFrom"])  # 继续真实继承关系。
    return launcher


# --- 生成回归场景 ---
def regression(world: str, pack_format: int) -> Path:
    """在专用测试世界生成可执行场景，并写出未运行的回归报告。

    `world` 只允许指向 `.dev/minecraft/saves` 下已有的专用世界；命令只准备
    测试材料，不会误建目录或操作玩家存档。数据包、函数、报告和每个写入文件
    都在写入前检查路径链接，安全优先于替用户修复错误目录。
    """
    if not re_world(world) or type(pack_format) is not int or pack_format<1:
        raise ValueError("需要单个测试世界名与实际数据包格式编号")  # 玩家输入先检查，不建立任何目录。
    folder = development_path(ROOT / ".dev/minecraft/saves" / world)  # 世界目录不能通过链接指向玩家存档。
    if not (folder / "level.dat").is_file(): raise ValueError("请先在专用实例创建测试世界，不能指向真实玩家存档")  # 不创建伪造世界。
    pack = development_path(folder / "datapacks/Omni-regression")  # 数据包目录也必须留在自有实例。
    functions = development_path(pack / "data/omni/function")  # 函数目录链接不能逃逸。
    pack_file = development_path(pack / "pack.mcmeta")  # 数据包描述不能写入链接目标。
    setup_file = development_path(functions / "setup.mcfunction")  # 初始化函数必须属于本次测试包。
    for member in pack.rglob("*"):
        development_path(member)  # 任何现有成员链接在第一次写入前统一拒绝。
    destination = development_path(ROOT / ".dev/reports/regression.json")  # 报告路径也在所有写入之前检查。
    functions.mkdir(parents=True,exist_ok=True)  # 不碰其他数据包。
    pack_file.write_text(json.dumps({"pack":{"pack_format":pack_format,"description":"Omni 专用场景回归"}},ensure_ascii=False)+"\n",encoding="utf-8")
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
    setup_file.write_text("\n".join(setup)+"\n",encoding="utf-8")  # 只有玩家执行函数后才改变专用世界。
    scenes = {
        "day":["time set noon","weather clear","execute in minecraft:overworld run tp @s 12 83 12 135 20"],  # 日间同场景对照。
        "night":["time set midnight","weather clear","execute in minecraft:overworld run tp @s 12 83 12 135 20"],  # 月光与星空。
        "rain":["time set noon","weather rain","execute in minecraft:overworld run tp @s 12 83 12 135 20"],  # 晴雨转换与湿润。
        "underwater":["execute in minecraft:overworld run tp @s -5 77 -5 0 0"],  # 相机真正浸入深水池。
        "cave":["execute in minecraft:overworld run tp @s -10 81 8 180 0"],  # 无天空光的室内明暗。
        "nether":["execute in minecraft:the_nether run tp @s 0 100 0 0 0"],  # 下界环境与历史重置。
        "end":["execute in minecraft:the_end run tp @s 0 90 0 0 0"],  # 末地环境与历史重置。
    }
    for name,commands in scenes.items():
        scene_file = development_path(functions / (name+".mcfunction"))  # 每个场景文件都单独拒绝链接逃逸。
        scene_file.write_text("\n".join(commands)+"\n",encoding="utf-8")  # 不自动传送玩家。
    report = {"shaderVersion":build.version(),"world":world,"scenes":{n:{"status":"未运行","command":"/function omni:"+n} for n in scenes},"manualChecks":["手持物","方块破坏","透明粒子","重载","关闭再开启","传送","切维度","窗口缩放"],"scope":"只生成场景命令，未游戏验证"}
    destination.parent.mkdir(parents=True,exist_ok=True)  # 全部边界已经检查，再创建报告目录。
    destination.write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")  # 不把生成脚本当验证通过。
    return pack

# --- 检查世界名 ---
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

# --- 检查采样上下文 ---
def performance_context(context: dict) -> None:
    """检查性能采样的设备、场景和软件上下文。

    上下文只是解释帧时间的说明，不是账号信息，也不需要读取玩家配置。先
    要求七个字段完整且非空，再启动采样器，避免生成无法比较的报告。
    """
    required = {"device","driver","scene","resolution","preset","minecraft","iris"}  # 这些字段是比较两个样本的最小依据。
    if not isinstance(context,dict) or set(context)!=required or any(not isinstance(v,str) or not v.strip() for v in context.values()):
        raise ValueError("性能上下文必须填写设备、驱动、场景、分辨率、预设、游戏与加载器")

# --- 拆分进程命令行 ---
def command_arguments(command_line: str) -> list[str]:
    """按 Windows 启动参数规则拆分实际命令行，并拒绝歧义引号。

    结果只用于确认已启动进程的身份；严格拒绝异常引号，避免把另一个进程
    的命令行误认成 `Omni` 开发实例。
    """
    if not isinstance(command_line,str): raise ValueError("实际进程没有可读的命令行")
    result, token = [], []  # 保存已经拆出的参数和当前参数。
    quoted = False  # 跟踪当前是否处于带引号的参数。
    started = False  # 空引号也要被识别为一个参数。
    closed_quote = False  # 引号结束后不接受粘连字符。
    for character in command_line:
        if character=='"':
            if closed_quote: raise ValueError("实际进程命令包含歧义引号")
            quoted = not quoted; started = True  # 路径空格只在引号范围内保留。
        elif character.isspace() and not quoted:
            if started:
                result.append("".join(token)); token=[]; started=False; closed_quote=False  # 空白结束当前参数。
        else:
            if closed_quote: raise ValueError("实际进程命令包含粘连参数")
            token.append(character); started=True  # 普通字符直接保留，不改写路径。
        if not quoted and started and character=='"': closed_quote=True
    if quoted: raise ValueError("实际进程命令包含未闭合引号")
    if started: result.append("".join(token))
    return result

# --- 读取游戏目录参数 ---
def game_directory_argument(command_line: str) -> str:
    """从实际命令行取出唯一的 `--gameDir`，支持引号和无空格参数。"""
    arguments = command_arguments(command_line)  # 先完成完整命令行边界检查。
    values = []  # 同名参数超过一个就拒绝身份判断。
    for index, argument in enumerate(arguments):
        if argument=="--gameDir":
            if index+1>=len(arguments) or not arguments[index+1]: raise ValueError("实际进程命令缺少游戏目录")
            values.append(arguments[index+1])
        elif argument.startswith("--gameDir="):
            values.append(argument[len("--gameDir="):])
    if len(values)!=1 or not values[0]: raise ValueError("实际进程命令的游戏目录不唯一")
    return values[0]

# --- 统一路径身份 ---
def normalized_path(path: str | Path) -> Path:
    """统一绝对路径、真实路径和 Windows 大小写，便于比较目录身份。"""
    return Path(os.path.normcase(os.path.realpath(os.path.abspath(os.fspath(path)))))

def same_existing_directory(path: str | Path, expected: Path) -> bool:
    """比较两个已存在目录的真实身份，并确认目录仍在开发实例边界内。"""
    candidate = Path(path)
    if not candidate.is_absolute() or not candidate.is_dir() or not expected.is_dir(): return False
    candidate_real, expected_real = normalized_path(candidate), normalized_path(expected)  # 短名和长名归一到真实目录。
    development_real = normalized_path(ROOT/".dev")  # 身份比较仍限制在项目开发区。
    return candidate_real==expected_real and candidate_real.is_relative_to(development_real)

# --- 核对开发进程 ---
def development_process(pid: int) -> None:
    """核对工具记录、进程身份和实际游戏目录，拒绝进程号复用。

    采样只允许作用于本工具记录的 Java 进程。这里同时比对进程号、Java 可执行
    文件和 `--gameDir`，不读取玩家账号，因为进程身份只需要运行参数。
    """
    record = json.loads(development_path(ROOT/".dev/game-process.json").read_text(encoding="utf-8"))  # 只有工具自己启动的开发实例可采样。
    if not isinstance(record,dict) or record.get("pid")!=pid or not isinstance(record.get("java"),str) or not isinstance(record.get("gameDirectory"),str):
        raise ValueError("进程号不属于记录的 Omni 开发实例")
    expected_directory = development_path(ROOT/".dev/minecraft")  # 数据目录仍需实际边界检查。
    if not same_existing_directory(record["gameDirectory"],expected_directory):
        raise ValueError("记录的进程不使用本项目开发目录")
    command = f"Get-CimInstance Win32_Process -Filter 'ProcessId={pid}' | Select-Object ExecutablePath,CommandLine | ConvertTo-Json -Compress"  # pid已检查为正整数，没有字符串命令注入。
    result = subprocess.run(["powershell","-NoProfile","-Command",command],check=True,capture_output=True,text=True,encoding="utf-8",errors="replace")
    actual = json.loads(result.stdout or "null")  # 权限不足或进程不存在时拒绝，不猜测身份。
    if not isinstance(actual,dict) or not actual.get("ExecutablePath") or Path(actual["ExecutablePath"]).resolve()!=Path(record["java"]).resolve():
        raise ValueError("实际进程与开发运行时不匹配")
    actual_directory = game_directory_argument(actual.get("CommandLine"))
    if not same_existing_directory(actual_directory,expected_directory):
        raise ValueError("实际进程命令没有匹配的开发游戏目录")

# --- 汇总帧采样 ---
def frame_report(source: Path, pid: int, context: dict) -> dict:
    """汇总真实帧间隔采样，拒绝其他进程、多个交换链和无效数值。

    这里记录的是画面呈现间隔，包含等待时间，不把它冒充成单个光影效果的
    显卡耗时；上下文保留设备和场景，方便以后进行同条件比较。
    """
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

# --- 执行性能采样 ---
def sample(binary: Path, pid: int, seconds: int, context: Path) -> Path:
    """调用 PresentMon 捕获专用游戏进程，并固定写入开发目录。

    采样只读取用户提供的上下文文件和已核对的游戏进程，不读取玩家账号或
    登录数据。原始 CSV 不覆盖旧证据，报告由真实采样生成，避免手工数字看似性能结论。
    """
    data = json.loads(context.read_text(encoding="utf-8"))  # 性能上下文先于工具与进程边界，错误输入不产生外部动作。
    performance_context(data)  # 无效上下文必须在进程检查与采样之前失败。
    binary = binary.resolve()
    tools = development_path(ROOT/".dev/tools")
    if sys.platform!="win32" or not binary.is_file() or not normalized_path(binary).is_relative_to(normalized_path(tools)) or type(pid) is not int or pid<=0 or type(seconds) is not int or not 5<=seconds<=600:
        raise ValueError("采样需要开发目录内的 Windows PresentMon、游戏进程号与五至六百秒时长")
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

# --- 命令行入口 ---
def main() -> None:
    """解析四个公开命令，并把环境错误交给统一入口报告。

    参数先由 `argparse` 检查，具体命令才执行对应动作；不提供命令时不会启动
    游戏，也不会启动采样器。
    """
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
