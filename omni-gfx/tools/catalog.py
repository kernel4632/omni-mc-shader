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

# 48 个模块的唯一顺序；多文件效果用同名文件夹，子文件不单独生成 GLSL。
MODULES = (
    "common/math", "common/color", "common/sampling", "common/sampling/anisotropic", "common/noise", "common/camera",
    "surface", "water", "upscale", "parallax", "planet", "accretion", "lpv", "gbuffer", "heldlight",
    "atmosphere/atmosphere", "atmosphere/model", "atmosphere/sky",
    "cloud/cloud", "cloud/volume", "cloud/layers", "cloud/planar",
    "fog/fog", "fog/volume", "shadow/shadow", "shadow/map",
    "voxel/voxel", "voxel/trace",
    "gi/gi", "gi/diffuse", "gi/indirect", "gi/ambientocclusion",
    "reflection/reflection", "reflection/wsr", "reflection/photonics", "reflection/specular",
    "post/post", "post/exposure", "post/scene", "lens/lens",
    "antialias/antialias", "antialias/taa", "antialias/fxaa",
    "weather/weather", "weather/rain", "weather/lightning",
    "world/end", "world/portal",
)

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
    "gi/diffuse": "漫反射光照",
    "gi/indirect": "间接光",
    "gi/ambientocclusion": "环境光遮蔽",
    "reflection/reflection": "反射",
    "reflection/wsr": "WSR 反射",
    "reflection/photonics": "Photonics 反射",
    "reflection/specular": "高光",
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
# 值必须是清单内的模块名：检查会沿着 `#include` 链确认它真的被那个模块带进来，
# 不接受“只靠探针或 profile 存活”的模块，也不接受写不出链路的假消费者。
PROBE_ONLY = {
    "gi/diffuse": "gi/gi",
    "gi/indirect": "gi/gi",
    "reflection/wsr": "reflection/specular",
    "shadow/map": "fog/volume",
    "voxel/trace": "shadow/map",
    "gi/ambientocclusion": "gi/gi",
    "post/scene": "post/post",
    "weather/lightning": "cloud/volume",
}

INCLUDE = re.compile(r'#include\s+"/omni-gfx/([\w./-]+)\.glsl"')
INCLUDE_SLANG = re.compile(r'^\s*#include\s+"([\w./-]+)\.slang"', re.MULTILINE)
SRC = LIB / "src"


def consumers() -> dict[str, set[str]]:
    """扫描非生成目录里的真实引用，返回 模块 → 引用它的文件集合。

    生成目录 `shaders/omni-gfx/` 自己引用自己，不算画面消费者；测试世界与
    光影效果文件是独立消费者，都会计入。
    """
    used = {name: set() for name in MODULES}
    for base in (ROOT / "shaders", LIB / "examples"):
        if not base.is_dir():
            continue
        for path in base.rglob("*"):
            if path.suffix not in {".glsl", ".frag", ".vert", ".slang", ".vsh", ".fsh"}:
                continue
            if path.as_posix().startswith((ROOT / "shaders" / "omni-gfx").as_posix()):
                continue
            text = path.read_text(encoding="utf-8", errors="replace")
            for name in INCLUDE.findall(text):
                if name in used:
                    used[name].add(path.relative_to(ROOT).as_posix())
    return used


def _module_files(name: str, stack: tuple[str, ...] = ()) -> list[Path]:
    """返回一个模块的主文件与全部子文件，供依赖分析使用。"""
    path = SRC / f"{name}.slang"  # 主文件一定存在；子文件由递归检查确认。
    files = [path]
    for reference in INCLUDE_SLANG.findall(path.read_text(encoding="utf-8")):
        target = _resolve_module(name, reference)  # 先按当前文件目录规范化。
        if target in MODULES or target in stack:
            continue  # 模块引用由主图处理，循环交给生成器报错。
        part = SRC / f"{target}.slang"
        if part.is_file():
            files.extend(_module_files_path(target, part, (*stack, name)))
    return files


def _module_files_path(target: str, path: Path, stack: tuple[str, ...]) -> list[Path]:
    """递归收集子文件；子文件之间只允许同目录引用，路径按子文件自己的位置解析。"""
    files = [path]
    for reference in INCLUDE_SLANG.findall(path.read_text(encoding="utf-8")):
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
            for reference in INCLUDE_SLANG.findall(path.read_text(encoding="utf-8")):
                target = _resolve_module(local, reference)
                if target in MODULES and target != name:
                    graph[name].add(target)
    return graph


def reachable() -> set[str]:
    """从真实画面文件出发，沿模块引用求可达集合。

    真实画面文件指 `shaders/`（排除生成目录）与测试世界；只要一个模块能被这些文件
    直接或间接引入，它就会进入真实编译，不再只是探针里的孤立代码。
    """
    graph = dependencies()
    seeds = {name for name, files in consumers().items() if files}
    reached = set(seeds)
    changed = True
    while changed:
        changed = False
        for name in list(reached):
            for dependency in graph[name]:
                if dependency not in reached:
                    reached.add(dependency)
                    changed = True
    return reached


def check_consumers() -> None:
    """核对模块表与真实引用：每个模块都要能追溯到画面文件。

    没有直接引用的模块必须登记在 `PROBE_ONLY` 里，并写明带它进入编译的效果模块；
    这里会沿 `#include` 链确认消费者真的依赖它，避免再出现“只靠探针或 profile”的模块。
    """
    if len(MODULES) != len(set(MODULES)):
        raise ValueError("模块表存在重复项")
    used = consumers()
    graph = dependencies()
    reached = reachable()
    for name in MODULES:
        if name not in reached:
            raise ValueError(f"模块 {name} 没有真实画面消费者，请接入或删除")
        if name in PROBE_ONLY:
            if used[name]:
                raise ValueError(f"模块 {name} 已有直接消费者，应从 PROBE_ONLY 移除")
            consumer = PROBE_ONLY[name]
            if consumer not in MODULES:
                raise ValueError(f"模块 {name} 登记的消费者 {consumer} 不在模块表里")
            # 消费者必须能沿引用链走到这个模块，否则登记就是假的。
            pending = [consumer]
            seen = set()
            while pending:
                current = pending.pop()
                if current == name:
                    break
                if current in seen:
                    continue
                seen.add(current)
                pending.extend(graph[current])
            else:
                raise ValueError(f"模块 {name} 登记的消费者 {consumer} 没有引用它")
        elif not used[name]:
            raise ValueError(f"模块 {name} 没有直接消费者，请接入或登记到 PROBE_ONLY")
