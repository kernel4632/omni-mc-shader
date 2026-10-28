"""把 `omni-gfx/src` 里的 Slang 模块生成给 Iris 使用的 GLSL 330 文本。

调用位置：`omni-gfx/build.py generate` 与测试都会调用 `module_text`；
生成的 GLSL 只写入 `shaders/omni-gfx/`，不再保留第二份镜像。

调用示例：在仓库根目录执行 `python omni-gfx/build.py generate`。

设计原因与取舍：
    Slang 自带的 GLSL 后端只输出带入口点的完整程序，函数会被改名并带有 `#version 450`，
    不能作为光影库直接 `#include`。这里只转换本项目实际使用的一小组语法差异，
    遇到未知写法就报错，不静默复制；转换结果由 GPU 等值测试和 Iris 编译共同验证。
    生成结果不写时间戳，保证同一份源每次生成完全相同的字节。
"""
from __future__ import annotations

import hashlib  # 清单记录源文件与产物摘要，便于核对是否过期。
import catalog  # 模块顺序与仅探针状态只有一份来源。
import posixpath  # 模块引用按斜杠路径规范化，Windows 与 Linux 生成相同文本。
import re  # 只替换完整单词，避免把更长标识符拆坏。
from functools import lru_cache  # 同一次构建里重复读取同一模块时复用转换结果。
from pathlib import Path  # 项目内路径统一按相对位置计算。

LIB = Path(__file__).resolve().parent.parent  # omni-gfx 根目录。
ROOT = LIB.parent  # 仓库根目录，用于写入光影包。
SRC = LIB / "src"  # Slang 源文件目录，唯一手写算法来源。
SHADER_OUT = ROOT / "shaders" / "omni-gfx"  # 唯一生成位置，Minecraft 直接引入。
MANIFEST = LIB / "generated" / "manifest.json"  # 生成清单，不含时间戳。
MODULES = catalog.MODULES
DISPLAY = catalog.DISPLAY

# 类型名按从长到短排列，避免 `float3` 先把 `float3x3` 的前半段换掉。
# 三维纹理句柄排在最后，因为它们的名字不会与向量类型混淆；`float` 与 GLSL 同名，不放进表。
TYPE_WORDS = {
    "float4x4": "mat4", "float3x3": "mat3", "float2x2": "mat2",
    "float4": "vec4", "float3": "vec3", "float2": "vec2",
    "int4": "ivec4", "int3": "ivec3", "int2": "ivec2",
    "uint4": "uvec4", "uint3": "uvec3", "uint2": "uvec2",
    "Sampler3DShadow": "sampler3DShadow", "Usampler3D": "usampler3D", "Sampler3D": "sampler3D",
    "Usampler1D": "usampler1D", "Sampler1D": "sampler1D",
}  # 只列真正改名的类型；`int` 与 `uint` 在 GLSL 同名，不写空替换。

# 逐项替换的语法差异；每项都配一条原因，方便新会话判断能不能扩展。
# 表内每条都只做等价改写：改名字、改写法，不改算式与常数。
LOWERINGS = (
    (re.compile(r"\bstatic\s+const\b"), "const", "GLSL 全局常量不需要 static，写成 static 会编译失败。"),
    (re.compile(r"\bSampler2DShadow\b"), "sampler2DShadow", "阴影比较采样的句柄名与 GLSL 不同，必须先换更长的名字。"),
    (re.compile(r"\bSampler2D\b"), "sampler2D", "Slang 的纹理句柄类型名与 GLSL 不同。"),
    (re.compile(r"\brsqrt\s*\("), "inversesqrt(", "Slang 的平方根倒数在 GLSL 里叫 inversesqrt。"),
    (re.compile(r"\blerp\s*\("), "mix(", "Slang 的线性插值函数在 GLSL 里叫 mix。"),
    (re.compile(r"\batan2\s*\("), "atan(", "Slang 的两参数反正切在 GLSL 里叫 atan。"),
    (re.compile(r"\bddx\s*\("), "dFdx(", "Slang 的屏幕横向导数在 GLSL 里叫 dFdx。"),
    (re.compile(r"\bddy\s*\("), "dFdy(", "Slang 的屏幕纵向导数在 GLSL 里叫 dFdy。"),
    (re.compile(r"\basfloat\s*\("), "uintBitsToFloat(", "Slang 的按位重解释对应 GLSL 的 uintBitsToFloat。"),
    (re.compile(r"\basuint\s*\("), "floatBitsToUint(", "Slang 的取位对应 GLSL 的 floatBitsToUint。"),
    (re.compile(r"\basint\s*\("), "floatBitsToInt(", "Slang 的有符号取位对应 GLSL 的 floatBitsToInt。"),
)

# 纹理取像素的写法由 `_replace_loads` 用括号配对统一处理；这里只保留一维纹理的
# `Load(int2(位置, 层级))`，GLSL 的 `texelFetch` 仍然接收位置与层级两个参数。
LOAD1D = re.compile(r"(\w+)\.Load\(\s*int2\(\s*((?:[^(),]|\([^()]*\))+?)\s*,\s*([^()]+?)\s*\)\s*\)")  # 一维纹理只出现在方块光表。

# 带屏幕导数的采样：GLSL 用 `textureGrad`，两个导数决定各向异性层级。
SAMPLE_GRAD = re.compile(r"(\w+)\.SampleGrad\(\s*((?:[^(),]|\([^()]*\))+?)\s*,\s*([^(),]+?)\s*,\s*([^(),]+?)\s*\)")  # 坐标、横纵两个方向导数。

# 阴影比较采样：GLSL 把比较值塞进第三个分量，Slang 单独作为参数。
SAMPLE_CMP = re.compile(r"(\w+)\.SampleCmpLevelZero\(\s*((?:[^(),]|\([^()]*\))+?)\s*,\s*([^(),]+?)\s*\)")  # 两参数是纹理坐标与比较值。

# 生成文件里不能残留的 Slang 写法；漏掉一种就说明转换表需要补充。
# 这里故意连注释一起检查，宁可多报也不要让半转换的代码进入光影包。
LEFTOVER = re.compile(r"\b(?:float[234](?:x[234])?|Sampler1D|Usampler1D|Sampler2D|Sampler3D|Usampler3D|lerp|asfloat|asuint|asint)\b|\.Load\s*\(|\.SampleLevel\s*\(|\.SampleGrad\s*\(|\.SampleCmpLevelZero\s*\(")  # 成员采样与残留类型名都要拦住。

# 光影会把库嵌进自己的程序，库文件不能再声明语言版本。
VERSION = re.compile(r"(?m)^\s*#version\b")

# 模块之间的引用在 Slang 里按相对路径写，在光影里按根路径写。
# 只允许引用清单内的模块或同名文件夹里的子文件，拼错或引用光影文件都会在生成阶段失败。
# 子文件不单独生成 GLSL，也不单独编译探针；生成时按顺序内联进所属模块，
# 这样 48 个模块的产物、探针数量与玩家看到的光影文件都保持不变。
INCLUDE = re.compile(r'^\s*#include\s+"([\w./-]+)\.slang"\s*$', re.MULTILINE)


def _replace_types(text: str) -> str:
    """把 Slang 的向量类型名换成 GLSL 类型名，只替换完整单词。

    先处理较长的名字，避免 `float3x3` 被 `float3` 截断；下划线和字母数字都算
    单词的一部分，所以 `my_float3` 这类标识符不会被误改。
    """
    for slang_name, glsl_name in TYPE_WORDS.items():
        text = re.sub(rf"\b{slang_name}\b", glsl_name, text)  # 完整单词边界是唯一条件。
    return text  # 返回替换后的整段文本。


def _include_target(name: str, reference: str) -> str:
    """把相对引用规范化成 `src` 下的模块名或子文件名。

    `name` 是当前模块或子文件的路径，`reference` 是源文件里写的相对路径；
    结果不含 `.slang` 后缀，和 `MODULES` 的命名方式一致。
    """
    return posixpath.normpath(posixpath.join(posixpath.dirname(name), reference))


def _part_path(target: str) -> Path:
    """返回子文件的绝对路径，并拒绝跳出源码目录的引用。

    子文件是模块内部的实现分片，不是第二套模块；限制在 `src` 内，
    可以避免拼错路径时读到仓库外的文件。
    """
    path = (SRC / f"{target}.slang").resolve()
    if not path.is_relative_to(SRC.resolve()):
        raise ValueError(f"子文件引用跳出源码目录：{target}")
    return path


def _collect_parts(name: str, stack: tuple[str, ...] = ()) -> list[str]:
    """按出现顺序返回一个模块直接或间接引用的全部子文件。

    模块引用保留给生成后的 GLSL；只有不在 `MODULES` 里的 `.slang` 引用
    才当作子文件。循环引用直接报错，避免生成时无限展开。
    """
    source = (SRC / f"{name}.slang").read_text(encoding="utf-8")
    parts: list[str] = []
    for match in INCLUDE.finditer(source):
        target = _include_target(name, match[1])
        if target in MODULES:
            continue
        if target in stack or target == name:
            raise ValueError(f"子文件循环引用：{name} -> {target}")
        path = _part_path(target)
        if not path.is_file():
            raise ValueError(f"未知模块或子文件引用：{name} -> {match[1]}")
        if target not in parts:
            parts.append(target)
        parts.extend(item for item in _collect_parts(target, (*stack, name)) if item not in parts)
    return parts


def _expand_parts(name: str, text: str, stack: tuple[str, ...]) -> str:
    """把子文件引用替换成子文件正文，模块引用保持原样。

    为什么在语法降级前展开：子文件和主文件使用同一套 Slang 写法，
    先拼成完整模块再统一转换，才不会出现一半已转换、一半未转换的产物。
    """
    def replace(match: re.Match) -> str:
        target = _include_target(name, match[1])
        if target in MODULES:
            return match.group(0)
        if target in stack or target == name:
            raise ValueError(f"子文件循环引用：{name} -> {target}")
        path = _part_path(target)
        if not path.is_file():
            raise ValueError(f"未知模块或子文件引用：{name} -> {match[1]}")
        body = path.read_text(encoding="utf-8")
        return f"// 子文件：{target}.slang。\n" + _expand_parts(target, body, (*stack, name))
    return INCLUDE.sub(replace, text)


def _resolve_include(match: re.Match, name: str) -> str:
    """把 Slang 的相对引用改成光影根路径引用。

    `name` 是当前模块的路径；`../math.slang` 先按当前目录规范化成模块名，
    再换成 `/omni-gfx/...`。只允许引用清单内的模块，拼错时立刻报出。
    """
    reference = match[1]  # 引用里的相对路径，例如 `../math.slang`。
    target = posixpath.normpath(posixpath.join(posixpath.dirname(name), reference))  # 规范化斜杠路径。
    if target not in MODULES:  # 只允许引用真实生成的模块，拼错时立刻报出。
        raise ValueError(f"未知模块引用：{name} -> {reference}")
    return f'#include "/omni-gfx/{target}.glsl"'


def _replace_loads(text: str) -> str:
    """把任意嵌套的 `tex.Load(int3/pixel, level)` 换成 GLSL 的 `texelFetch`。

    为什么不用单条正则：深度表达式里会嵌套 `int2(...)`、`texelFetchSize(...)`，
    正则只允许一层括号就会漏掉，最后在残留检查里报错。这里用括号配对扫描，
    只改取格写法，不改坐标与层级表达式本身。
    """
    pattern = re.compile(r"(\w+)\.Load\(\s*int([34])\(")
    while True:
        match = pattern.search(text)
        if not match:
            return text
        body_start = match.end()
        depth = 1
        index = body_start
        while index < len(text) and depth > 0:
            if text[index] == "(":
                depth += 1
            elif text[index] == ")":
                depth -= 1
            index += 1
        if depth != 0:
            raise ValueError("纹理取格的括号不配对")
        coords = text[body_start:index - 1]
        close = index
        while close < len(text) and text[close] in " \t":
            close += 1
        if close >= len(text) or text[close] != ")":
            raise ValueError("纹理取格缺少外层右括号")
        parts = []
        part_start = 0
        part_depth = 0
        for position, character in enumerate(coords):
            if character == "(":
                part_depth += 1
            elif character == ")":
                part_depth -= 1
            elif character == "," and part_depth == 0:
                parts.append(coords[part_start:position].strip())
                part_start = position + 1
        parts.append(coords[part_start:].strip())
        if len(parts) != 2:
            raise ValueError("纹理取格必须有坐标与层级两个参数")
        replacement = f"texelFetch({match[1]}, {parts[0]}, {parts[1]})"
        text = text[:match.start()] + replacement + text[close + 1:]


def _split_arguments(text: str) -> list[str]:
    """按顶层逗号拆分函数参数，括号里的逗号不拆。"""
    parts = []
    start = 0
    depth = 0
    for position, character in enumerate(text):
        if character == "(":
            depth += 1
        elif character == ")":
            depth -= 1
        elif character == "," and depth == 0:
            parts.append(text[start:position].strip())
            start = position + 1
    parts.append(text[start:].strip())
    return parts


def _replace_sample_levels(text: str) -> str:
    """把任意嵌套的 `tex.SampleLevel(coord, lod)` 换成 `textureLod`。

    与取格同理：坐标表达式可能嵌套多层构造函数，单条正则会把合法写法留在
    残留检查里。这里用括号配对，只改调用写法。
    """
    pattern = re.compile(r"(\w+)\.SampleLevel\(")
    while True:
        match = pattern.search(text)
        if not match:
            return text
        depth = 1
        index = match.end()
        while index < len(text) and depth > 0:
            if text[index] == "(":
                depth += 1
            elif text[index] == ")":
                depth -= 1
            index += 1
        if depth != 0:
            raise ValueError("纹理采样的括号不配对")
        parts = _split_arguments(text[match.end():index - 1])
        if len(parts) != 2:
            raise ValueError("带层级采样必须有两个参数")
        text = text[:match.start()] + f"textureLod({match[1]}, {parts[0]}, {parts[1]})" + text[index:]


def _lower_text(text: str, name: str) -> str:
    """执行全部语法转换，并在返回前确认没有残留 Slang 写法。

    顺序有讲究：先换类型与关键字，再换纹理取像素，最后检查残留。
    一旦源文件用了转换表以外的新语法，这里直接失败，避免生成看似成功但编译不过的文件。
    """
    text = _replace_loads(text)  # 任意嵌套的取格先换，避免复杂深度表达式漏转。
    text = _replace_sample_levels(text)  # 任意嵌套的采样层级写法也先换成 GLSL 自由函数。
    text = LOAD1D.sub(lambda m: f"texelFetch({m[1]}, {m[2]}, {m[3]})", text)  # 一维取格只保留位置与层级。
    text = SAMPLE_CMP.sub(lambda m: f"textureLod({m[1]}, vec3({m[2]}, {m[3]}), 0.0)", text)  # 比较采样先展开成三分量坐标。
    text = SAMPLE_GRAD.sub(lambda m: f"textureGrad({m[1]}, {m[2]}, {m[3]}, {m[4]})", text)  # 带导数的采样换成 GLSL 自由函数。
    text = _replace_types(text)  # 类型名随后统一。
    for pattern, replacement, _reason in LOWERINGS:  # 逐项处理函数名与关键字。
        text = pattern.sub(replacement, text)
    text = INCLUDE.sub(lambda match: _resolve_include(match, name), text)  # 模块引用改成光影根路径。
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
        "源文件在库的源码目录中按效果分文件夹，改动后运行构建脚本的生成命令。\n"
        "用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。\n"
        "生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。\n"
        "*/\n"
    )


# 每个模块只保留一份转换实现，清单与写入共用同一份结果，避免两处产物不同。
# 模块顺序固定，清单里的顺序与生成文件的顺序因此可以逐项对照。
# 缓存没有上限：模块总数固定，缓存不会随运行次数增长。
@lru_cache(maxsize=None)  # 同一进程里每个模块只读取和转换一次，测试与清单共用结果。
def module_text(name: str) -> str:
    """返回一个模块完整的 GLSL 文本，包含生成说明与源文件原有内容。

    `name` 必须是 `MODULES` 里的模块；读取失败或转换失败都直接抛错，
    不返回半成品，调用方因此可以信任返回的文本就是可写入的最终产物。
    """
    source = (SRC / f"{name}.slang").read_text(encoding="utf-8")  # 唯一手写来源，允许按效果分文件夹。
    expanded = _expand_parts(name, source, (name,))  # 子文件按源码顺序拼成完整模块。
    body = _lower_text(expanded, name)  # 先转换，失败时不会写任何文件。
    return _header(name) + body  # 说明放在源文件注释之前。


def outputs() -> dict[Path, str]:
    """返回全部待写入文件及文本，供写入和过期检查共用。

    只写光影包需要的一份，避免同一份生成代码出现两个副本。
    """
    result: dict[Path, str] = {}  # 路径到文本的映射，按模块顺序填充。
    for name in MODULES:  # 每个模块生成一次，避免重复读取源文件。
        text = module_text(name)
        result[SHADER_OUT / f"{name}.glsl"] = text  # 唯一生成位置。
    return result


def write_modules() -> list[Path]:
    """写入全部 GLSL 产物并刷新清单，返回实际写入的路径。

    写入使用固定换行和 UTF-8，保证不同平台生成相同字节。
    清单只记录摘要与大小，不记录时间，重复生成不会产生无意义差异。
    旧布局留下的模块文件会先删除，保证生成位置只有一份当前产物。
    """
    written: list[Path] = []  # 记录本次真正写过的文件，便于命令行汇报。
    texts = outputs()  # 生成失败会在写入前抛出，不会留下半套文件。
    expected = set(texts)  # 当前模块应有的产物路径。
    for stale in sorted(SHADER_OUT.rglob("*.glsl")):  # 只清理生成目录里的旧 GLSL。
        if stale not in expected:
            stale.unlink()  # 模块已改名或拆分时移除旧文件，避免两份产物并存。
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
        shader_path = SHADER_OUT / f"{name}.glsl"  # 唯一产物路径。
        shader_text = texts[shader_path]  # 与写入内容完全相同的文本。
        entry = {
            "module": name,
            "source": source.relative_to(ROOT).as_posix(),
            "sourceSha256": hashlib.sha256(source_bytes).hexdigest(),
            "shader": shader_path.relative_to(ROOT).as_posix(),
            "glslSha256": hashlib.sha256(shader_text.encode("utf-8")).hexdigest(),
            "glslLines": len(shader_text.splitlines()),
        }
        parts = _collect_parts(name)  # 子文件也参与过期判断，改子文件不会留下旧产物。
        if parts:  # 没有拆分时省略空表，旧条目保持原样。
            entry["parts"] = [
                {"source": (SRC / f"{part}.slang").relative_to(ROOT).as_posix(),
                 "sha256": hashlib.sha256((SRC / f"{part}.slang").read_bytes()).hexdigest()}
                for part in parts
            ]
        entries.append(entry)
    payload = {"schemaVersion": 1, "tool": "omni-gfx/tools/generate.py", "modules": entries}
    return json.dumps(payload, ensure_ascii=False, indent=2) + "\n"  # 固定缩进与结尾换行。


def check_include_comments() -> None:
    """确认每条生成引用上一行都有中文说明。

    加载器要求说明放在引用上一行；源文件已按同一规则检查，这里再看最终产物，
    防止内联子文件时把说明与引用拆开，或者生成器以后改写顺序。
    """
    problems = []  # 一次报告全部位置，避免补一条又冒出下一条。
    for name in MODULES:
        lines = module_text(name).splitlines()
        for index, line in enumerate(lines):
            if not re.match(r'^\s*#include\s+"', line):
                continue  # 只看真实引用行。
            previous = lines[index - 1].strip() if index else ""
            if not re.search(r"[\u3400-\u9fff]", previous):
                problems.append(f"{name}.glsl:{index + 1}")
    if problems:
        raise ValueError("生成引用上一行缺少中文说明：" + "、".join(problems))


def check_modules() -> None:
    """确认磁盘上的生成文件与当前源一致，并检查产物里的引用说明。

    只读取和比较，不写文件；构建脚本的只读检查和回归测试都调用这里。
    """
    check_include_comments()  # 生成文本先满足加载器的引用说明规则。
    stale = []  # 收集所有不一致的路径，一次报告完整。
    for path, expected in outputs().items():  # 期望文本由当前源实时计算。
        actual = path.read_text(encoding="utf-8") if path.is_file() else None  # 缺失也按过期处理。
        if actual != expected:
            stale.append(path.relative_to(ROOT).as_posix())
    manifest = MANIFEST.read_text(encoding="utf-8") if MANIFEST.is_file() else None  # 清单同样要核对。
    if manifest != manifest_text():
        stale.append(MANIFEST.relative_to(ROOT).as_posix())
    expected = set(outputs())  # 当前模块应有的产物路径。
    for extra in sorted(SHADER_OUT.rglob("*.glsl")):  # 生成目录不能留下旧模块文件。
        if extra not in expected:
            stale.append(extra.relative_to(ROOT).as_posix())
    if stale:
        raise ValueError("omni-gfx 生成文件已过期，请运行构建脚本的生成命令：" + "、".join(stale))
