"""把 `omni-gfx/src` 里的 Slang 模块生成给 Iris 使用的 GLSL 330 文本。

调用位置：`omni-gfx/build.py generate` 与测试都会调用 `module_text`；
生成的 GLSL 同时写入 `shaders/omni-gfx/` 和 `omni-gfx/generated/glsl/`。

设计原因与取舍：
    Slang 自带的 GLSL 后端只输出带入口点的完整程序，函数会被改名并带有 `#version 450`，
    不能作为光影库直接 `#include`。这里只转换本项目实际使用的一小组语法差异，
    遇到未知写法就报错，不静默复制；转换结果由 GPU 等值测试和 Iris 编译共同验证。
    生成结果不写时间戳，保证同一份源每次生成完全相同的字节。
"""
from __future__ import annotations

import hashlib  # 清单记录源文件与产物摘要，便于核对是否过期。
import re  # 只替换完整单词，避免把更长标识符拆坏。
from functools import lru_cache  # 同一次构建里重复读取同一模块时复用转换结果。
from pathlib import Path  # 项目内路径统一按相对位置计算。

LIB = Path(__file__).resolve().parent.parent  # omni-gfx 根目录。
ROOT = LIB.parent  # 仓库根目录，用于写入光影包。
SRC = LIB / "src"  # Slang 源文件目录，唯一手写算法来源。
SHADER_OUT = ROOT / "shaders" / "omni-gfx"  # Minecraft 直接引入的位置。
GENERATED_OUT = LIB / "generated" / "glsl"  # 独立库查看与分发的副本。
MANIFEST = LIB / "generated" / "manifest.json"  # 生成清单，不含时间戳。
MODULES = ("math", "color", "sampling", "noise", "atmosphere", "cloud", "water", "fog",
           "shadow", "gi", "reflection", "post", "antialias",
           "weather", "surface", "voxel", "upscale", "parallax",
           "planet", "accretion", "atmosphere_model", "cloud_volume", "fog_volume")  # 阶段一二的核心模块、阶段三的九个效果模块与第二批迁移的独立模块。

# 生成说明里使用中文模块名，避免机器产物出现裸英文单词。
DISPLAY = {
    "math": "数学",
    "color": "颜色",
    "sampling": "采样",
    "noise": "噪声",
    "atmosphere": "大气",
    "cloud": "云",
    "water": "水面",
    "fog": "雾",
    "shadow": "阴影",
    "gi": "全局光",
    "reflection": "反射",
    "post": "后期",
    "antialias": "抗锯齿",
    "weather": "天气",
    "surface": "表面",
    "voxel": "体素",
    "upscale": "放大",
    "parallax": "视差",
    "planet": "行星",
    "accretion": "吸积盘",
    "atmosphere_model": "大气查表",
    "cloud_volume": "体积云",
    "fog_volume": "体积雾",
}  # 每个生成文件头里的中文模块名，顺序与模块表一致。

# 类型名按从长到短排列，避免 `float3` 先把 `float3x3` 的前半段换掉。
# 三维纹理句柄排在最后，因为它们的名字不会与向量类型混淆。
TYPE_WORDS = {
    "float4x4": "mat4", "float3x3": "mat3", "float2x2": "mat2",
    "float4": "vec4", "float3": "vec3", "float2": "vec2", "float": "float",
    "int4": "ivec4", "int3": "ivec3", "int2": "ivec2", "int": "int",
    "uint4": "uvec4", "uint3": "uvec3", "uint2": "uvec2", "uint": "uint",
    "Sampler3DShadow": "sampler3DShadow", "Usampler3D": "usampler3D", "Sampler3D": "sampler3D",
}  # 三维纹理的句柄名也必须替换，体积云与体素追踪都靠它取格。

# 逐项替换的语法差异；每项都配一条原因，方便新会话判断能不能扩展。
# 表内每条都只做等价改写：改名字、改写法，不改算式与常数。
LOWERINGS = (
    (re.compile(r"\bstatic\s+const\b"), "const", "GLSL 全局常量不需要 static，写成 static 会编译失败。"),
    (re.compile(r"\bSampler2DShadow\b"), "sampler2DShadow", "阴影比较采样的句柄名与 GLSL 不同，必须先换更长的名字。"),
    (re.compile(r"\bSampler2D\b"), "sampler2D", "Slang 的纹理句柄类型名与 GLSL 不同。"),
    (re.compile(r"\brsqrt\s*\("), "inversesqrt(", "Slang 的平方根倒数在 GLSL 里叫 inversesqrt。"),
    (re.compile(r"\blerp\s*\("), "mix(", "Slang 的线性插值函数在 GLSL 里叫 mix。"),
    (re.compile(r"\basfloat\s*\("), "uintBitsToFloat(", "Slang 的按位重解释对应 GLSL 的 uintBitsToFloat。"),
    (re.compile(r"\basuint\s*\("), "floatBitsToUint(", "Slang 的取位对应 GLSL 的 floatBitsToUint。"),
    (re.compile(r"\basint\s*\("), "floatBitsToInt(", "Slang 的有符号取位对应 GLSL 的 floatBitsToInt。"),
)

# 纹理取像素的写法：`tex.Load(int3(pixel, level))` 与 GLSL 的 `texelFetch` 一一对应。
# 生成器只认这一种取格写法，换别的形式会落到残留检查里报错。
LOAD = re.compile(r"(\w+)\.Load\(\s*int3\(\s*((?:[^(),]|\([^()]*\))+?)\s*,\s*([^()]+?)\s*\)\s*\)")  # 坐标参数允许再套一层构造函数。

# 带细节层级的采样：Slang 用成员方法，GLSL 用自由函数；参数里允许一层括号，够放构造函数。
SAMPLE_LEVEL = re.compile(r"(\w+)\.SampleLevel\(\s*((?:[^(),]|\([^()]*\))+?)\s*,\s*([^(),]+?)\s*\)")  # 参数里允许一层括号，够放构造函数。

# 阴影比较采样：GLSL 把比较值塞进第三个分量，Slang 单独作为参数。
SAMPLE_CMP = re.compile(r"(\w+)\.SampleCmpLevelZero\(\s*((?:[^(),]|\([^()]*\))+?)\s*,\s*([^(),]+?)\s*\)")  # 两参数是纹理坐标与比较值。

# 生成文件里不能残留的 Slang 写法；漏掉一种就说明转换表需要补充。
LEFTOVER = re.compile(r"\b(?:float[234](?:x[234])?|Sampler2D|Sampler3D|Usampler3D|lerp|asfloat|asuint|asint)\b|\.Load\s*\(|\.SampleLevel\s*\(|\.SampleCmpLevelZero\s*\(")  # 成员采样与残留类型名都要拦住。

# 光影会把库嵌进自己的程序，库文件不能再声明语言版本。
VERSION = re.compile(r"(?m)^\s*#version\b")

# 模块之间的引用在 Slang 里按相对路径写，在光影里按根路径写。
# 只允许引用清单内的模块，拼错或引用光影文件都会在生成阶段失败。
INCLUDE = re.compile(r'^\s*#include\s+"([\w./-]+)\.slang"\s*$', re.MULTILINE)


def _replace_types(text: str) -> str:
    """把 Slang 的向量类型名换成 GLSL 类型名，只替换完整单词。

    先处理较长的名字，避免 `float3x3` 被 `float3` 截断；下划线和字母数字都算
    单词的一部分，所以 `my_float3` 这类标识符不会被误改。
    """
    for slang_name, glsl_name in TYPE_WORDS.items():
        text = re.sub(rf"\b{slang_name}\b", glsl_name, text)  # 完整单词边界是唯一条件。
    return text  # 返回替换后的整段文本。


def _resolve_include(match: re.Match) -> str:
    """把 Slang 的相对引用改成光影根路径引用。

    `math.slang` 生成后位于 `/omni-gfx/math.glsl`，采样与颜色模块都靠它取共用常数。
    """
    name = match[1]  # 引用里的模块名，例如数学模块。
    if name not in MODULES:  # 只允许引用真实生成的模块，拼错时立刻报出。
        raise ValueError(f"未知模块引用：{name}")
    return f'#include "/omni-gfx/{name}.glsl"'


def _lower_text(text: str) -> str:
    """执行全部语法转换，并在返回前确认没有残留 Slang 写法。

    顺序有讲究：先换类型与关键字，再换纹理取像素，最后检查残留。
    一旦源文件用了转换表以外的新语法，这里直接失败，避免生成看似成功但编译不过的文件。
    """
    text = LOAD.sub(lambda m: f"texelFetch({m[1]}, {m[2]}, {m[3]})", text)  # 先换取像素，此时 `int3` 还没改名。
    text = SAMPLE_CMP.sub(lambda m: f"textureLod({m[1]}, vec3({m[2]}, {m[3]}), 0.0)", text)  # 比较采样先展开成三分量坐标。
    text = SAMPLE_LEVEL.sub(lambda m: f"textureLod({m[1]}, {m[2]}, {m[3]})", text)  # 带层级采样换成 GLSL 自由函数。
    text = _replace_types(text)  # 类型名随后统一。
    for pattern, replacement, _reason in LOWERINGS:  # 逐项处理函数名与关键字。
        text = pattern.sub(replacement, text)
    text = INCLUDE.sub(_resolve_include, text)  # 模块引用改成光影根路径。
    leftover = LEFTOVER.search(text)  # 注释和代码一起查，宁可多报也不放过。
    if leftover:
        raise ValueError(f"有未转换的 Slang 写法：{leftover.group(0)}")
    if VERSION.search(text):
        raise ValueError("库文件不能声明 #version，版本由宿主入口决定")
    return text


def _header(name: str) -> str:
    """生成文件头，说明来源、用途和重新生成方式。

    这段文字会进入光影包，因此只用中文；文件名和命令属于代码引用，
    审计会按引用跳过，不会当成英文说明。
    """
    return (
        "/*\n"
        f"生成文件：{DISPLAY[name]}模块的 GLSL 330 版本，请勿手工修改。\n"
        "源文件在库的源码目录中的同名模块，改动后运行构建脚本的生成命令。\n"
        "用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。\n"
        "生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。\n"
        "*/\n"
    )


# 每个模块只保留一份转换实现，清单与写入共用同一份结果，避免两处产物不同。
# 缓存没有上限：模块总数固定，缓存不会随运行次数增长。
@lru_cache(maxsize=None)  # 同一进程里每个模块只读取和转换一次，测试与清单共用结果。
def module_text(name: str) -> str:
    """返回一个模块完整的 GLSL 文本，包含生成说明与源文件原有内容。

    `name` 必须是 `MODULES` 里的模块；读取失败或转换失败都直接抛错，
    不返回半成品，调用方因此可以信任返回的文本就是可写入的最终产物。
    """
    source = (SRC / f"{name}.slang").read_text(encoding="utf-8")  # 唯一手写来源。
    body = _lower_text(source)  # 先转换，失败时不会写任何文件。
    return _header(name) + body  # 说明放在源文件注释之前。


def outputs() -> dict[Path, str]:
    """返回全部待写入文件及文本，供写入和过期检查共用。

    同一份文本写两个位置：光影包需要它，独立库也要能单独查看。
    两处内容必须完全一致，避免测试通过而游戏读到旧副本。
    """
    result: dict[Path, str] = {}  # 路径到文本的映射，按模块顺序填充。
    for name in MODULES:  # 每个模块生成一次，避免重复读取源文件。
        text = module_text(name)
        result[SHADER_OUT / f"{name}.glsl"] = text  # 光影包内的正式位置。
        result[GENERATED_OUT / f"{name}.glsl"] = text  # 独立库内的镜像位置。
    return result


def write_modules() -> list[Path]:
    """写入全部 GLSL 产物并刷新清单，返回实际写入的路径。

    写入使用固定换行和 UTF-8，保证不同平台生成相同字节。
    清单只记录摘要与大小，不记录时间，重复生成不会产生无意义差异。
    """
    written: list[Path] = []  # 记录本次真正写过的文件，便于命令行汇报。
    texts = outputs()  # 生成失败会在写入前抛出，不会留下半套文件。
    for path, text in sorted(texts.items()):  # 排序让写入顺序稳定。
        path.parent.mkdir(parents=True, exist_ok=True)  # 首次生成时创建目录。
        path.write_text(text, encoding="utf-8", newline="\n")  # 固定换行，避免平台差异。
        written.append(path)
    MANIFEST.parent.mkdir(parents=True, exist_ok=True)
    MANIFEST.write_text(manifest_text(texts), encoding="utf-8", newline="\n")  # 清单也使用固定换行。
    written.append(MANIFEST)
    return written


def manifest_text(texts: dict[Path, str] | None = None) -> str:
    """生成可复现的清单文本：记录每个源文件与产物的摘要。

    `texts` 省略时重新生成一遍，测试用它可以比较磁盘与当前源是否一致。
    路径使用仓库相对路径，换机器后仍能对照，不泄露本机目录。
    """
    import json  # 只在写清单时用到，模块导入保持轻量。

    texts = outputs() if texts is None else texts  # 允许调用方复用已生成的文本。
    entries = []  # 每项包含来源、产物与摘要。
    for name in MODULES:  # 一个模块一条记录，顺序固定。
        source = SRC / f"{name}.slang"  # 模块源文件。
        source_bytes = source.read_bytes()  # 按字节计算摘要，不受换行转换影响。
        shader_path = SHADER_OUT / f"{name}.glsl"  # 公开产物路径。
        generated_path = GENERATED_OUT / f"{name}.glsl"  # 镜像产物路径。
        shader_text = texts[shader_path]  # 与写入内容完全相同的文本。
        entries.append({
            "module": name,
            "source": source.relative_to(ROOT).as_posix(),
            "sourceSha256": hashlib.sha256(source_bytes).hexdigest(),
            "shader": shader_path.relative_to(ROOT).as_posix(),
            "generated": generated_path.relative_to(ROOT).as_posix(),
            "glslSha256": hashlib.sha256(shader_text.encode("utf-8")).hexdigest(),
            "glslLines": len(shader_text.splitlines()),
        })
    payload = {"schemaVersion": 1, "tool": "omni-gfx/tools/generate.py", "modules": entries}
    return json.dumps(payload, ensure_ascii=False, indent=2) + "\n"  # 固定缩进与结尾换行。


def check_modules() -> None:
    """确认磁盘上的生成文件与当前源一致，过期时报告需要执行的命令。

    只读取和比较，不写文件；构建脚本的只读检查和回归测试都调用这里。
    """
    stale = []  # 收集所有不一致的路径，一次报告完整。
    for path, expected in outputs().items():  # 期望文本由当前源实时计算。
        actual = path.read_text(encoding="utf-8") if path.is_file() else None  # 缺失也按过期处理。
        if actual != expected:
            stale.append(path.relative_to(ROOT).as_posix())
    manifest = MANIFEST.read_text(encoding="utf-8") if MANIFEST.is_file() else None  # 清单同样要核对。
    if manifest != manifest_text():
        stale.append(MANIFEST.relative_to(ROOT).as_posix())
    if stale:
        raise ValueError("omni-gfx 生成文件已过期，请运行构建脚本的生成命令：" + "、".join(stale))
