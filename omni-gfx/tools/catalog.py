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

# 没有顶层画面入口的模块：只有编译探针、profile 或库内其它生成模块间接引用。
# 文件头必须写明这个状态；接入真实入口后再从表里删除。
PROBE_ONLY = {
    "common/sampling/anisotropic": "各向异性过滤目前只有编译探针覆盖，还没有顶层采样入口。",
    "gbuffer": "延迟缓冲解码目前只有探针覆盖，宿主仍直接读取附件布局。",
    "cloud/layers": "层状体积云目前只有探针与 profile 覆盖，顶层云入口仍走体积云与平面云。",
    "shadow/map": "阴影贴图写入目前只被库内其它生成模块间接引用，没有顶层画面入口。",
    "voxel/trace": "体素求交目前只被库内反射与阴影模块间接引用，没有独立画面入口。",
    "gi/diffuse": "漫反射光照目前只被库内 Photonics 模块间接引用，没有顶层画面入口。",
    "gi/indirect": "间接光目前只被库内反射模块间接引用，没有顶层画面入口。",
    "gi/ambientocclusion": "独立环境光遮蔽目前只有探针覆盖，顶层画面走 gi/gi 的多切片实现。",
    "reflection/wsr": "WSR 反射目前只被库内高光模块间接引用，没有顶层画面入口。",
    "reflection/photonics": "Photonics 反射目前只被库内高光模块间接引用，没有顶层画面入口。",
    "reflection/specular": "高光合成目前只被库内反射模块间接引用，没有顶层画面入口。",
    "post/exposure": "曝光与泛光目前只被库内后期模块间接引用，没有顶层画面入口。",
    "post/scene": "画面效果入口目前只有探针覆盖，顶层画面仍由各效果文件分别处理。",
    "lens/lens": "镜头光斑目前只有探针覆盖，还没有顶层画面入口。",
    "antialias/taa": "时间取样目前只被库内抗锯齿模块间接引用，没有顶层画面入口。",
    "antialias/fxaa": "FXAA 目前只有探针覆盖，顶层抗锯齿走 antialias/antialias。",
    "weather/rain": "雨纹目前只被库内水面模块间接引用，没有独立画面入口。",
    "weather/lightning": "闪电目前只被库内反射模块间接引用，没有独立画面入口。",
    "world/end": "末地效果目前只有探针与 profile 覆盖，顶层末地入口尚未接入。",
    "world/portal": "末地传送门矩阵目前只有探针覆盖，顶层入口尚未接入。",
}

INCLUDE = re.compile(r'#include\s+"/omni-gfx/([\w./-]+)\.glsl"')


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


def check_consumers() -> None:
    """核对模块表与真实引用：仅探针模块不能有顶层消费者，其余必须有。

    只读检查，不修改文件；测试和生成前的自检都调用这里，避免文件头与事实脱节。
    """
    if len(MODULES) != len(set(MODULES)):
        raise ValueError("模块表存在重复项")
    used = consumers()
    for name in MODULES:
        if name in PROBE_ONLY and used[name]:
            raise ValueError(f"模块 {name} 已声明仅探针，但被这些文件引用：" + "、".join(sorted(used[name])))
        if name not in PROBE_ONLY and not used[name]:
            raise ValueError(f"模块 {name} 没有顶层消费者，请接入或登记到 PROBE_ONLY")
