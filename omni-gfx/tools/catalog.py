"""omni-gfx 模块与消费者的唯一清单。

调用位置：`generate.py` 与 `profile.py` 都从这里取模块顺序；测试用它核对探针、
生成物和真实画面消费者是否一致。模块顺序固定，生成文件与清单因此可复现。

调用示例：`for name in catalog.MODULES: generate.module_text(name)`。

设计原因与取舍：
    模块表以前在生成器和 profile 生成器各写一份，模块改名时容易只改一边。
    现在只保留这一份，并明确列出“仅探针”的模块：它们的文件头必须写清状态，
    不能把编译通过当成已经接入画面。
"""
from __future__ import annotations

import re
from pathlib import Path

LIB = Path(__file__).resolve().parent.parent
ROOT = LIB.parent

# 参与生成、探针与画面编译的模块：顺序固定，生成文件与清单因此可复现。
# 这里只放已经接到真实入口的模块；没有选项或入口的参考后端列在 REFERENCE，
# 它们仍参与严格函数对照，但不生成 GLSL、不编译探针、不进入光影包。
MODULES = (
    "common/math", "common/color", "common/sampling", "common/sampling/anisotropic", "common/noise", "common/camera",
    "surface", "water", "upscale", "parallax", "planet", "accretion", "lpv", "gbuffer", "heldlight",
    "atmosphere/atmosphere", "atmosphere/model", "atmosphere/sky",
    "cloud/cloud", "cloud/volume", "cloud/planar",
    "fog/fog", "fog/volume", "shadow/shadow", "shadow/map",
    "voxel/voxel", "voxel/trace",
    "gi/gi", "gi/blocklight", "gi/indirect", "gi/ambientocclusion",
    "reflection/reflection",
    "post/post", "post/exposure", "post/scene", "lens/lens",
    "antialias/antialias", "antialias/taa", "antialias/fxaa",
    "weather/weather", "weather/rain", "weather/lightning",
    "world/end", "world/portal",
)

# 只保留源码、供严格对照与后续接入的参考后端：没有当前选项选择它们，因此不生成。
# 值写清为什么还不生成；新增一个选项或真实调用后再把它移进 MODULES。
REFERENCE = {
    "cloud/layers": "Eclipse 五层云后端尚未有对应选项，当前画面使用 cloud/volume 的 NUBIS 云。",
    "reflection/wsr": "Eclipse WSR 反射只被参考高光后端调用，当前画面使用 reflection 的屏幕空间追踪。",
    "reflection/photonics": "Eclipse Photonics 体素反射尚未有对应选项，当前体素回退由 voxel 反射承担。",
    "reflection/specular": "Eclipse 高光后端尚未有对应选项，当前画面使用 reflection 的菲涅耳合并。",
}

# 生成文件头里的中文模块名，顺序与模块表一致。
DISPLAY = {
    "common/math": "数学",
    "common/color": "颜色",
    "common/sampling": "采样",
    "common/sampling/anisotropic": "各向异性过滤",
    "common/noise": "噪声",
    "common/camera": "相机变换",
    "surface": "表面",
    "water": "水面",
    "upscale": "放大",
    "parallax": "视差",
    "planet": "行星",
    "accretion": "吸积盘",
    "lpv": "光传播体积",
    "gbuffer": "延迟缓冲",
    "heldlight": "手持光",
    "atmosphere/atmosphere": "大气",
    "atmosphere/model": "大气查表",
    "atmosphere/sky": "天空",
    "cloud/cloud": "云",
    "cloud/volume": "体积云",
    "cloud/layers": "层状体积云",
    "cloud/planar": "平面云",
    "fog/fog": "雾",
    "fog/volume": "体积雾",
    "shadow/shadow": "阴影",
    "shadow/map": "阴影贴图",
    "voxel/voxel": "体素",
    "voxel/trace": "体素求交",
    "gi/gi": "全局光",
    "gi/blocklight": "方块光与 LPV 合成",
    "gi/indirect": "间接光",
    "gi/ambientocclusion": "环境光遮蔽",
    "reflection/reflection": "反射",
    "reflection/wsr": "WSR 反射（参考）",
    "reflection/photonics": "Photonics 反射（参考）",
    "reflection/specular": "高光（参考）",
    "post/post": "后期",
    "post/exposure": "曝光与泛光",
    "post/scene": "画面效果",
    "lens/lens": "镜头",
    "antialias/antialias": "抗锯齿",
    "antialias/taa": "时间取样",
    "antialias/fxaa": "FXAA",
    "weather/weather": "天气",
    "weather/rain": "雨纹",
    "weather/lightning": "闪电",
    "world/end": "末地",
    "world/portal": "末地传送门",
}

# 没有顶层画面入口、但由表内效果模块直接或间接引入并编译的子算法。
# 值必须是清单内的模块名：检查会沿着生成库的调用图确认它真的被那个模块的函数调用，
# 不接受“只靠探针或 profile 存活”的模块，也不接受写不出链路的假消费者。
PROBE_ONLY = {
    "gi/ambientocclusion": "gi/gi",
    "shadow/map": "fog/volume",
    "voxel/trace": "shadow/map",
    "weather/lightning": "cloud/volume",
}

INCLUDE_SLANG = re.compile(r'^\s*#include\s+"([\w./-]+)\.slang"', re.MULTILINE)
DEFINE = re.compile(r"^(?:static\s+)?(?:const\s+)?[A-Za-z_]\w*(?:<[^>]+>)?\s+([A-Za-z_]\w*)\s*\(", re.MULTILINE)
CALL = re.compile(r"\b([A-Za-z_]\w*)\s*\(")
SRC = LIB / "src"


def _read(path: Path) -> str:
    """读取源码文本；编码错误直接报出，不静默替换成乱码。"""
    return path.read_text(encoding="utf-8")


def _module_files(name: str, stack: tuple[str, ...] = ()) -> list[Path]:
    """返回一个模块的主文件与全部子文件，供依赖分析使用。

    主文件必须存在；子文件按引用递归收集，循环由 `stack` 截断。
    """
    path = SRC / f"{name}.slang"  # 主文件一定存在；子文件由递归检查确认。
    if not path.resolve().is_relative_to(SRC.resolve()):
        raise ValueError(f"模块名跳出源码目录：{name}")
    if not path.is_file():
        raise FileNotFoundError(f"模块 {name} 缺少源文件：{path.relative_to(ROOT).as_posix()}")
    files = [path]
    for reference in INCLUDE_SLANG.findall(_read(path)):
        target = _resolve_module(name, reference)  # 先按当前文件目录规范化。
        if target in MODULES or target in stack:
            continue  # 模块引用由主图处理，循环交给生成器报错。
        part = SRC / f"{target}.slang"
        if part.is_file():
            if not part.resolve().is_relative_to(SRC.resolve()):
                raise ValueError(f"子文件跳出源码目录：{part}")
            files.extend(_module_files_path(target, part, (*stack, name)))
    return files


def _module_files_path(target: str, path: Path, stack: tuple[str, ...]) -> list[Path]:
    """递归收集子文件；子文件之间只允许同目录引用，路径按子文件自己的位置解析。"""
    files = [path]
    for reference in INCLUDE_SLANG.findall(_read(path)):
        child = _resolve_module(target, reference)
        if child in MODULES or child in stack:
            continue  # 子文件不承担模块级引用，遇到时由图去处理。
        child_path = SRC / f"{child}.slang"
        if child_path.is_file():
            files.extend(_module_files_path(child, child_path, (*stack, target)))
    return files


def _resolve_module(name: str, reference: str) -> str:
    """把 Slang 的相对引用按所在目录规范化成 `src` 下的模块名。"""
    import posixpath  # 只在这里用到，保持模块导入轻量。
    return posixpath.normpath(posixpath.join(posixpath.dirname(name), reference))


def dependencies() -> dict[str, set[str]]:
    """返回每个模块直接引用的其它模块，子文件里的引用也计入。"""
    graph = {name: set() for name in MODULES}
    for name in MODULES:
        for path in _module_files(name):
            local = path.relative_to(SRC).with_suffix("").as_posix()
            for reference in INCLUDE_SLANG.findall(_read(path)):
                target = _resolve_module(local, reference)
                if target in MODULES and target != name:
                    graph[name].add(target)
    return graph


def _module_functions() -> dict[str, set[str]]:
    """返回每个模块导出的顶层函数名，子文件里的函数也归主模块。

    `DEFINE` 只匹配行首的函数定义；`if (`、`for (` 等控制语句没有返回类型，
    不会进入集合。这样后面的调用图只认真实入口，不把宏或分支当函数。
    """
    functions = {}
    for name in MODULES:
        names = set()
        for path in _module_files(name):
            names.update(DEFINE.findall(_read(path)))
        functions[name] = names
    return functions


def _module_calls(functions: dict[str, set[str]] | None = None) -> dict[str, set[str]]:
    """返回每个模块函数体里调用到的其它模块函数。"""
    functions = _module_functions() if functions is None else functions
    all_names = set().union(*functions.values())
    calls = {}
    for name in MODULES:
        used = set()
        for path in _module_files(name):
            used.update(word for word in CALL.findall(_read(path)) if word in all_names)
        calls[name] = used - functions[name]  # 自己调用自己不算模块间依赖。
    return calls


def _host_calls(functions: dict[str, set[str]] | None = None) -> dict[str, set[str]]:
    """扫描真实画面文件里的函数调用，返回 函数 → 调用文件集合。

    只排除生成目录；测试世界也是真实消费者。这里看的是 `ogx...(` 调用，
    而不是 `#include`，因为只把模块引进来、从不调用仍属于死代码。
    """
    functions = _module_functions() if functions is None else functions
    all_names = set().union(*functions.values())
    used = {name: set() for name in all_names}
    for base in (ROOT / "shaders", LIB / "examples"):
        if not base.is_dir():
            continue
        for path in base.rglob("*"):
            if path.suffix not in {".glsl", ".frag", ".vert", ".slang", ".vsh", ".fsh"}:
                continue
            if path.as_posix().startswith((ROOT / "shaders" / "omni-gfx").as_posix()):
                continue
            text = _read(path)
            for word in CALL.findall(text):
                if word in used:
                    used[word].add(path.relative_to(ROOT).as_posix())
    return {word: files for word, files in used.items() if files}


def _consumers_from(functions: dict[str, set[str]], host: dict[str, set[str]]) -> dict[str, set[str]]:
    """由函数表与宿主调用表推导 模块 → 直接调用文件集合。"""
    return {name: set().union(*(host.get(word, set()) for word in functions[name])) if functions[name] else set()
            for name in MODULES}


def _reachable_from(functions: dict[str, set[str]], calls: dict[str, set[str]],
                    host: dict[str, set[str]]) -> set[str]:
    """由函数表、模块调用图与宿主调用表推导可达函数名。"""
    reached = set(host)
    changed = True
    while changed:
        changed = False
        for name in MODULES:
            if not (functions[name] & reached):
                continue
            for called in calls[name]:
                if called not in reached:
                    reached.add(called)
                    changed = True
    return reached


def consumers() -> dict[str, set[str]]:
    """返回 模块 → 直接调用该模块函数的真实文件集合。"""
    functions = _module_functions()
    return _consumers_from(functions, _host_calls(functions))


def _reachable_functions() -> set[str]:
    """返回从真实画面调用可达的模块函数名。"""
    functions = _module_functions()
    return _reachable_from(functions, _module_calls(functions), _host_calls(functions))


def reachable() -> set[str]:
    """从真实画面文件里的函数调用出发，沿模块调用图求可达模块集合。

    一个模块只有至少一个导出函数被真实文件调用，或调用它的函数本身可达，
    才算进入真实编译；单纯被 `#include` 不再算消费。
    """
    functions = _module_functions()
    owner = {word: name for name, names in functions.items() for word in names}
    return {owner[word] for word in _reachable_functions() if word in owner}


def check_consumers() -> None:
    """核对模块表与真实调用：每个生成模块都要有可达的函数。

    只检查调用图，不再把 `#include` 当消费。`PROBE_ONLY` 中的模块允许没有
    直接画面调用，但必须能从登记的消费者函数走到；参考后端 `REFERENCE`
    不生成，因此不在这里要求调用，但也不能被任何真实文件调用。
    """
    if len(MODULES) != len(set(MODULES)):
        raise ValueError("模块表存在重复项")
    if set(MODULES) & set(REFERENCE):
        raise ValueError("模块同时出现在生成表与参考后端表：" + "、".join(sorted(set(MODULES) & set(REFERENCE))))
    functions = _module_functions()
    calls = _module_calls(functions)
    host = _host_calls(functions)
    used = _consumers_from(functions, host)
    reached_functions = _reachable_from(functions, calls, host)
    reached = {name for name in MODULES if functions[name] & reached_functions}
    for name in MODULES:
        if not functions[name]:
            raise ValueError(f"模块 {name} 没有顶层函数，请补入口或移入 REFERENCE")
        if name not in reached:
            raise ValueError(f"模块 {name} 的导出函数没有真实调用，请接入或移入 REFERENCE")
        if name in PROBE_ONLY:
            if used[name]:
                raise ValueError(f"模块 {name} 已有直接调用，应从 PROBE_ONLY 移除")
            consumer = PROBE_ONLY[name]
            if consumer not in MODULES:
                raise ValueError(f"模块 {name} 登记的消费者 {consumer} 不在模块表里")
            if consumer not in reached or not (calls[consumer] & functions[name]):
                raise ValueError(f"模块 {name} 登记的消费者 {consumer} 没有调用它")
    # 参考后端不能悄悄被画面调用，否则它会成为第二份未登记的生成源。
    reference_functions = set()
    for name in REFERENCE:
        for path in _module_files(name):
            reference_functions.update(DEFINE.findall(_read(path)))
    reference_calls = {word for word in reference_functions if word in host}
    if reference_calls:
        names = "、".join(sorted(reference_calls))
        raise ValueError(f"参考后端函数被真实画面调用，请移入 MODULES：{names}")
