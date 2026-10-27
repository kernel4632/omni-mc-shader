"""解析参考 GLSL 与库内 Slang 的函数签名，给严格对照提供可复核的机器证据。

调用位置：`omni-gfx/tools/parity_strict.py`；修改参考包、库源码或解析规则后重新运行
`python omni-gfx/build.py strict-parity`。本模块只读源码，不写任何文件。

它回答四个问题：
    1. 两个函数的返回类型是否同一种；
    2. 参数个数、顺序、方向（in/out/inout）和类型是否同一种；
    3. 采样调用的次数与顺序是否一致；
    4. 函数体用到的数值常数（含具名常数）是否一致。

为什么不能只比名字：
    Eclipse 的 `circlemap` 返回二维向量，`circlemapL` 返回三维向量，两者只差一个
    字母。旧工具按名字把它们都指向 `ogxCircleMap`（返回二维），审查表却写成 exact；
    这种错误会让后续移植以为三维版本已经存在。签名比较能直接把它拦下来。

为什么常数要解析具名常量：
    参考源码写 `i * goldenAngle`，库里写 `i * OGX_GOLDEN_ANGLE`。只比字面量会漏掉
    常数变化；只比名字又会把重命名当差异。这里把两边的常量算成数值再比，数值在
    容差内才算一致。

为什么采样只比次数与顺序：
    参考包采样 `noisetex`，库函数把贴图作为参数传入，名字必然不同。贴图身份由调用方
    保证，库函数能对齐的是“第几次采样、取样还是取像素”。顺序错了，画面就会换一个
    结果，因此顺序必须严格一致。
"""
from __future__ import annotations

import math  # 计算常量表达式和比较浮点容差。
import re  # 解析签名、常数与采样调用。
from pathlib import Path  # 统一使用路径对象。

# 基础类型别名：GLSL 与 Slang 对同一种数据用不同拼写。
TYPE_ALIASES = {
    "vec2": "float2", "vec3": "float3", "vec4": "float4",
    "ivec2": "int2", "ivec3": "int3", "ivec4": "int4",
    "uvec2": "uint2", "uvec3": "uint3", "uvec4": "uint4",
    "bvec2": "bool2", "bvec3": "bool3", "bvec4": "bool4",
    "mat2": "float2x2", "mat3": "float3x3", "mat4": "float4x4",
    "mat2x2": "float2x2", "mat3x3": "float3x3", "mat4x4": "float4x4",
    "mat2x3": "float2x3", "mat2x4": "float2x4",
    "mat3x2": "float3x2", "mat3x4": "float3x4",
    "mat4x2": "float4x2", "mat4x3": "float4x3",
    "sampler2d": "sampler2d", "sampler3d": "sampler3d", "samplercube": "samplercube",
    "sampler2dshadow": "sampler2dshadow", "sampler2darray": "sampler2darray",
    # 库里的结构体带 Ogx 前缀，参考包直接用短名；类型身份相同，字段由人工核对。
    "ogxeclipserayhit": "rayhit", "ogxeclipserayjob": "rayjob",
    "ogxeclipsetranslucenthit": "translucenthit",
    "ogxmaterialmask": "materialmask", "ogxgiview": "giview",
}

# 参数前的修饰词不是类型的一部分，但 in/out/inout 会改变调用约定，必须保留。
QUALIFIERS = {"in", "out", "inout", "const", "highp", "mediump", "lowp", "precise"}

# 采样调用分类：取样和取像素的代价、过滤方式与边界行为都不同，不能混为一谈。
SAMPLE_CALLS = {
    "texture": "sample", "texture2D": "sample", "texture3D": "sample",
    "textureLod": "sample", "textureGrad": "sample", "textureCube": "sample",
    "textureCubeLod": "sample", "Sample": "sample", "SampleLevel": "sample",
    "SampleGrad": "sample", "SampleBias": "sample",
    "texelFetch": "fetch", "Load": "fetch", "imageLoad": "fetch",
    "textureGather": "gather", "Gather": "gather",
    "SampleCmpLevelZero": "sample", "SampleCmp": "sample",
}

CALL_PATTERN = re.compile(r"\b([A-Za-z_]\w*)\s*\(")  # 函数调用候选。
NUMBER_PATTERN = re.compile(r"(?<![\w.])[-+]?(?:\d+\.\d*|\.\d+|\d+)(?:[eE][-+]?\d+)?[fFuU]?(?![\w.])")
BUILTIN_MATH = {"sqrt": math.sqrt, "rsqrt": lambda x: 1.0 / math.sqrt(x), "abs": abs,
                "acos": math.acos, "asin": math.asin, "atan": math.atan, "cos": math.cos,
                "sin": math.sin, "tan": math.tan, "exp": math.exp, "log": math.log,
                "pow": math.pow, "floor": math.floor, "ceil": math.ceil,
                "min": min, "max": max, "clamp": lambda x, a, b: min(max(x, a), b),
                "int": int, "uint": int}


def normalize_type(raw: str) -> str:
    """把类型文本统一成小写别名，去掉 const、精度和参数名残留。"""
    text = re.sub(r"\[[^\]]*\]", "", raw)  # 数组长度不参与类型身份比较。
    words = [word for word in re.split(r"\s+", text.strip()) if word]
    words = [word for word in words if word not in QUALIFIERS]  # 修饰词另由参数方向描述。
    if not words:
        return ""
    name = words[-1].lower()  # 参数名可能跟在类型后面，取最后一个词之前要先识别。
    if name in TYPE_ALIASES:
        return TYPE_ALIASES[name]
    # Slang 的结构体名与 GLSL 的 struct 名可能不同，交给结构字段比较，不在这里下结论。
    return words[0].lower()


def split_top_level(text: str, separator: str = ",") -> list[str]:
    """按顶层分隔符切分，括号里的逗号不当作参数分隔。"""
    parts, depth, start = [], 0, 0
    for index, char in enumerate(text):
        if char in "([{":
            depth += 1
        elif char in ")]}":
            depth -= 1
        elif char == separator and depth == 0:
            parts.append(text[start:index])
            start = index + 1
    parts.append(text[start:])
    return [part.strip() for part in parts if part.strip()]


def parse_params(text: str) -> list[dict]:
    """解析参数表，保留方向、类型与名字；空参数表返回空列表。"""
    params = []
    for part in split_top_level(text):
        cleaned = re.sub(r"//[^\n]*", " ", part)  # 行内注释不参与解析。
        cleaned = cleaned.split("=")[0].strip()  # 默认值不影响签名身份。
        words = [word for word in re.split(r"\s+", cleaned) if word]
        direction = "in"
        for word in words:
            if word in ("out", "inout"):
                direction = word
        type_words = [word for word in words if word not in QUALIFIERS]
        if not type_words:
            continue
        # 最后一个词通常是参数名；只有类型时（少见）也按类型处理。
        if len(type_words) >= 2 and re.fullmatch(r"[A-Za-z_]\w*", type_words[-1]) and \
                not type_words[-1].lower().startswith(("sampler", "vec", "mat", "float", "int", "uint", "bool")):
            type_text = " ".join(type_words[:-1])
        else:
            type_text = " ".join(type_words)
        name = type_words[-1] if len(type_words) >= 2 else ""
        params.append({"direction": direction, "type": normalize_type(type_text), "raw": cleaned,
                       "name": name})
    return params


def strip_comments(text: str) -> str:
    """去掉注释但保留长度与换行，行号定位不会错位。"""
    text = re.sub(r"/\*.*?\*/", lambda m: re.sub(r"[^\n]", " ", m.group(0)), text, flags=re.S)
    return re.sub(r"//[^\n]*", lambda m: " " * len(m.group(0)), text)


def evaluate_condition(expression: str, defines: dict[str, str]) -> bool:
    """计算 `#if` 表达式；未知名字按零处理，和 C 预处理器一致。"""
    text = expression.strip()
    # profile 用 `!OMNI_X` 关闭开关；这类值写成 0，在 #ifdef 视角下应视为未定义。
    # 否则 `#ifdef OMNI_ATMO_HORIZON` 会在关闭时仍然进入地面反弹分支，采样数直接翻倍。
    defined = {name for name, value in defines.items() if value not in ("0", "")}
    text = re.sub(r"defined\s*\(\s*(PROGRAM_[A-Za-z0-9_]+)\s*\)", "1", text)
    text = re.sub(r"defined\s*\(\s*([A-Za-z_]\w*)\s*\)",
                  lambda m: "1" if m.group(1) in defined else "0", text)
    text = re.sub(r"defined\s+(PROGRAM_[A-Za-z0-9_]+)", "1", text)
    text = re.sub(r"defined\s+([A-Za-z_]\w*)",
                  lambda m: "1" if m.group(1) in defined else "0", text)
    text = re.sub(r"\b(PROGRAM_[A-Za-z0-9_]+)\b", "1", text)
    text = re.sub(r"\b([A-Za-z_]\w*)\b", lambda m: defines.get(m.group(1), "0") or "1", text)
    text = re.sub(r"\btrue\b", "1", text)
    text = re.sub(r"\bfalse\b", "0", text)
    text = re.sub(r"(\d+)[uUfF]\b", r"\1", text)
    text = text.replace("&&", " and ").replace("||", " or ")
    text = re.sub(r"!(?!=)", " not ", text)
    if re.search(r"[^0-9eE+\-*/().<>=! andornot\t]", text):
        return False
    try:
        return bool(eval(text, {"__builtins__": {}}, {}))
    except Exception:
        return False


def preprocess(text: str, defines: dict[str, str]) -> str:
    """按默认宏配置去掉未选中的条件分支，保留行数以便行号仍然有效。

    为什么需要它：参考包大量使用 `#if MC_VERSION >= 11605` 在两个贴图通道之间二选一。
    不处理预处理器就会把两个分支的采样都算进去，严格对照会得到虚假的采样数差异。
    """
    out = []
    stack: list[list[bool]] = []  # 每层保存 [父层是否有效, 当前分支是否有效, 是否已有分支命中]。
    active = True
    for line in text.splitlines(keepends=True):
        stripped = line.strip()
        directive = stripped.startswith("#")
        keep = active
        if directive:
            # 预处理指令后的 `//` 注释不能进入条件表达式，否则 `#if !FLAG // 说明`
            # 会因为无法求值被当成假，整段主世界代码被裁掉。
            directive_text = re.sub(r"//.*$", "", stripped).strip()
            match = re.match(r"#\s*(\w+)\s*(.*)", directive_text)
            keyword = match.group(1) if match else ""
            rest = match.group(2).strip() if match else ""
            if keyword in ("if", "ifdef", "ifndef"):
                parent = active
                if keyword == "if":
                    condition = evaluate_condition(rest, defines)
                elif keyword == "ifdef":
                    name = rest.split()[0] if rest else ""
                    condition = name.startswith("PROGRAM_") or defines.get(name, "0") not in ("0", "")
                else:
                    name = rest.split()[0] if rest else ""
                    condition = not (name.startswith("PROGRAM_") or defines.get(name, "0") not in ("0", ""))
                stack.append([parent, condition, condition])
                active = parent and condition
                keep = False
            elif keyword == "elif" and stack:
                parent, _, seen = stack[-1]
                condition = evaluate_condition(rest, defines) and not seen
                stack[-1][1] = condition
                stack[-1][2] = seen or condition
                active = parent and condition
                keep = False
            elif keyword == "else" and stack:
                parent, _, seen = stack[-1]
                active = parent and not seen
                stack[-1][1] = active
                stack[-1][2] = True
                keep = False
            elif keyword == "endif" and stack:
                parent, _, _ = stack.pop()
                active = parent
                keep = False
        newline = "\n" if line.endswith("\n") else ""
        out.append(line if keep else newline)
    return "".join(out)


def preprocess_first_branch(text: str) -> str:
    """保留每个条件编译的第一分支，用来读取默认配置未启用的参考函数。

    为什么需要：体素、Photonics 与调试函数常被 `#ifdef` 整段包住，默认预处理后
    函数根本不存在。严格对照仍要核对它们的算式；这里固定选第一分支，作为“功能
    开启时”的唯一变体，避免把 `#else` 的两套采样混在一起。
    """
    out = []
    stack: list[bool] = []
    active = True
    for line in text.splitlines(keepends=True):
        stripped = line.strip()
        keyword = ""
        if stripped.startswith("#"):
            match = re.match(r"#\s*(\w+)", stripped)
            keyword = match.group(1) if match else ""
        if keyword in ("if", "ifdef", "ifndef"):
            stack.append(active)
            active = True
            keep = False
        elif keyword in ("elif", "else"):
            active = False
            keep = False
        elif keyword == "endif" and stack:
            active = stack.pop()
            keep = False
        else:
            keep = active
        newline = "\n" if line.endswith("\n") else ""
        out.append(line if keep else newline)
    return "".join(out)


def collect_defines(paths: list[Path], base: dict[str, str] | None = None) -> dict[str, str]:
    """收集默认配置下的对象式宏；迭代三遍让条件里的宏也稳定下来。

    头文件保护宏不能进入全局表：把 `#ifndef GUARD` 后面的 `#define GUARD` 当成普通
    开关，会让第二次预处理把整个文件当成“已包含”而清空。这里识别紧跟的
    `#ifndef` 同名字样并跳过。
    """
    defines = dict(base or {})
    for _ in range(3):
        updated = dict(defines)
        for path in paths:
            original = strip_comments(path.read_text(encoding="utf-8", errors="replace"))
            guards = set()
            previous = None
            for line in original.splitlines():
                stripped = line.strip()
                match = re.match(r"#\s*ifndef\s+([A-Za-z_]\w*)", stripped)
                if match:
                    previous = match.group(1)
                    guards.add(previous)
                    continue
                match = re.match(r"#\s*define\s+([A-Za-z_]\w*)", stripped)
                if match and match.group(1) == previous:
                    previous = None
                elif stripped and not stripped.startswith("#"):
                    previous = None
            text = preprocess(original, defines)
            for line in text.splitlines():
                stripped = line.strip()
                match = re.match(r"#\s*define\s+([A-Za-z_]\w*)(?:\s+([^\n]*))?$", stripped)
                if not match:
                    continue
                name = match.group(1)
                if name in guards:  # 头文件保护宏不向外传播。
                    continue
                updated[name] = (match.group(2) or "1").strip()
        if updated == defines:
            break
        defines = updated
    return defines


def read_profile_defines(path: Path) -> dict[str, str]:
    """从 `shaders.properties` 的默认 profile 读取选项开关，作为宿主层预处理配置。"""
    defines: dict[str, str] = {}
    text = path.read_text(encoding="utf-8", errors="replace")
    match = re.search(r"(?m)^profile\.default\s*=\s*(.+)$", text)
    if not match:
        return defines
    for token in match.group(1).split():
        if token.startswith("!"):
            defines[token[1:]] = "0"
        elif "=" in token:
            name, value = token.split("=", 1)
            defines[name] = value
        else:
            defines[token] = "1"
    return defines


def parse_functions(path: Path, defines: dict[str, str] | None = None,
                    first_branch: bool = False) -> list[dict]:
    """解析一个源文件的函数定义，返回名字、行号、返回类型、参数与函数体。

    判据与旧对照工具一致：行首是返回类型，名字后紧跟参数表，参数表右括号后只能有
    空白再接左大括号。这样宏、控制流和函数声明不会被误认成定义。
    传入 `defines` 时先按默认配置预处理，未选中的条件分支不会进入签名比较。
    """
    raw = path.read_text(encoding="utf-8", errors="replace")
    if first_branch:
        text = strip_comments(preprocess_first_branch(raw))
    else:
        text = strip_comments(preprocess(raw, defines) if defines is not None else raw)
    found = []
    for match in re.finditer(r"\b([A-Za-z_]\w*)\s*\(", text):
        name = match.group(1)
        if name in {"if", "for", "while", "switch", "return", "else", "do"}:
            continue
        line_start = text.rfind("\n", 0, match.start()) + 1
        prefix = text[line_start:match.start()].strip()
        if not prefix or prefix.startswith("#"):
            continue
        if any(char in prefix for char in "=;,+-*/"):
            continue  # 赋值、声明残留或表达式不是返回类型。
        words = prefix.split()
        first = words[0]
        lowered = first.lower()
        known = lowered in TYPE_ALIASES or lowered in {
            "void", "bool", "int", "uint", "float", "double", "float2", "float3", "float4",
            "int2", "int3", "int4", "uint2", "uint3", "uint4", "bool2", "bool3", "bool4",
            "float2x2", "float3x3", "float4x4", "float2x3", "float2x4", "float3x2",
            "float3x4", "float4x2", "float4x3", "sampler2d", "sampler3d", "samplercube",
        }
        # 自定义结构体可能小写开头（例如 `gfx_atmosphere_model`）；前缀只有类型词时放行。
        if first in {"if", "for", "while", "switch", "return", "else", "do"}:
            continue
        if not known and (len(words) > 2 or not re.fullmatch(r"[A-Za-z_]\w*", first)):
            continue
        if not known and len(words) == 1 and not first[:1].isupper() and "_" not in first:
            continue
        depth, index = 0, match.end() - 1
        while index < len(text):
            if text[index] == "(":
                depth += 1
            elif text[index] == ")":
                depth -= 1
                if depth == 0:
                    break
            index += 1
        if index >= len(text):
            continue
        rest = text[index + 1:]
        brace = rest.find("{")
        if brace < 0 or rest[:brace].strip():
            continue
        body_start = index + 1 + brace
        depth, cursor = 0, body_start
        while cursor < len(text):
            if text[cursor] == "{":
                depth += 1
            elif text[cursor] == "}":
                depth -= 1
                if depth == 0:
                    break
            cursor += 1
        if cursor >= len(text):
            continue
        found.append({
            "name": name,
            "line": text[:match.start()].count("\n") + 1,
            "return": normalize_type(prefix),
            "returnRaw": prefix,
            "params": parse_params(text[match.end():index]),
            "body": text[body_start:cursor + 1],
            "bodyStart": body_start,
            "bodyEnd": cursor + 1,
        })
    return found


def function_index(paths: list[Path], defines: dict[str, str] | None = None) -> dict[str, dict]:
    """建立 `模块.函数名` 到完整签名的索引；同名重载按出现顺序都保留。"""
    index = {}
    for path in sorted(paths):
        for item in parse_functions(path, defines):
            key = f"{path.stem}.{item['name']}"
            variant = 1
            while key in index:  # 重载不能互相覆盖，编号后分别参与比较。
                variant += 1
                key = f"{path.stem}.{item['name']}#{variant}"
            item["path"] = path.as_posix()
            index[key] = item
    return index


def global_constant_table(paths: list[Path], defines: dict[str, str] | None = None) -> dict[str, list[float]]:
    """收集顶层常量，返回 名字 → 数值列表；向量常量按分量拆开。

    只扫描函数体之外的内容，避免把局部常量当全局常量；同名常量值冲突时记为不可解析，
    因为无法判断参考函数引用的究竟是哪一个。
    """
    table: dict[str, list[float] | None] = {}
    for path in sorted(paths):
        raw = path.read_text(encoding="utf-8", errors="replace")
        text = strip_comments(preprocess(raw, defines) if defines is not None else raw)
        for item in sorted(parse_functions(path, defines), key=lambda entry: -entry["bodyStart"]):
            # 用空格覆盖函数体，保留换行与长度，后面的正则不会读到局部声明。
            start, end = item["bodyStart"], item["bodyEnd"]
            text = text[:start] + re.sub(r"[^\n]", " ", text[start:end]) + text[end:]
        for match in re.finditer(r"(?m)^[ \t]*(?:static\s+)?const\s+(?:\w+\s+)+([A-Za-z_]\w*)\s*=\s*([^;]+);", text):
            name, expression = match.group(1), match.group(2)
            value = evaluate_constant(expression, table)
            if value is None:
                table[name] = None
            elif name in table and table[name] != value:
                table[name] = None  # 同名不同值无法确定引用目标。
            else:
                table[name] = value
        # 为什么用 [ \t] 而不是 \s：选项文件里有不带值的开关宏（如 OMNI_HELDLIGHT_SHADOW），
        # \s 会跨过换行把下一条 #define 吞成它的值，后面的常数就整条消失。
        for match in re.finditer(r"(?m)^[ \t]*#define[ \t]+([A-Za-z_]\w*)(?:[ \t]+([^\n]*))?$", text):
            name, expression = match.group(1), (match.group(2) or "1").strip()
            if "(" in expression.split("//")[0] and name in expression:
                continue
            value = evaluate_constant(expression, table)
            if value is not None:
                table[name] = value
    return {name: value for name, value in table.items() if value is not None}


def evaluate_constant(expression: str, table: dict) -> list[float] | None:
    """把常量表达式算成数值列表；无法安全求值时返回 None，不猜结果。"""
    text = expression.strip()
    if text == "true":
        return [1.0]
    if text == "false":
        return [0.0]
    text = re.sub(r"//.*$", "", text).strip()
    ternary = split_ternary(text)
    if ternary is not None:
        condition, when_true, when_false = ternary
        bool_table = {name: bool(value[0]) for name, value in table.items()
                      if value is not None and len(value) == 1}
        value = evaluate_bool_expression(condition, bool_table)
        if value is not None:
            text = when_true if value else when_false
    text = re.sub(r"\b(?:float|vec2|vec3|vec4|float2|float3|float4|mat2|mat3|mat4|"
                  r"float2x2|float3x3|float4x4)\s*\(", "(", text)
    text = re.sub(r"\bPI\b", f"({math.pi!r})", text)
    text = re.sub(r"\bTAU\b", f"({math.tau!r})", text)
    text = re.sub(r"(\d)[fFuU]\b", r"\1", text)  # 去掉 C 风格数字后缀。
    # 把已知常量名字换成数值；长名字优先，避免 A 抢先匹配 AB。
    for name in sorted(table, key=len, reverse=True):
        value = table.get(name)
        if value is None:
            continue
        replacement = "(" + "+".join(f"({number!r})" for number in value) + ")"
        text = re.sub(rf"\b{re.escape(name)}\b", replacement, text)
    if re.search(r"(?<![0-9.])[A-Za-z_]\w*", text):  # 还有未知名字就不猜；科学计数法的 e 不算名字。
        unknown = set(re.findall(r"(?<![0-9.])[A-Za-z_]\w*", text)) - set(BUILTIN_MATH)
        if unknown:
            return None
    # 只允许数字、运算符、括号、已知数学函数名与空白；不允许引号、方括号或属性链。
    if re.search(r"[^0-9eE+\-*/().,\sA-Za-z_]", text) or "__" in text:
        return None
    try:
        value = eval(text, {"__builtins__": {}}, dict(BUILTIN_MATH))  # 输入已限制为数字与数学函数。
    except Exception:
        return None
    return flatten_numbers(value)


def flatten_numbers(value) -> list[float] | None:
    """把标量、向量或嵌套元组摊平成浮点列表；遇到非数字返回 None。"""
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        return [float(value)]
    if isinstance(value, (list, tuple)):
        result = []
        for item in value:
            part = flatten_numbers(item)
            if part is None:
                return None
            result.extend(part)
        return result
    return None


def local_constants(body: str, table: dict) -> dict[str, list[float]]:
    """收集函数体内只赋值一次的局部常量，后续数字统计能解析这些名字。

    参考代码常写 `float a = 2.51;` 再多次引用，而不是 `const`。只接受字面量或已解析
    常量的表达式；后面被重新赋值的变量不能当常量，否则会把运行时的值算错。
    """
    local = {}
    pattern = re.compile(
        r"(?:const\s+)?(?:float|int|uint|float2|float3|float4|int2|int3|int4|"
        r"vec2|vec3|vec4|ivec2|ivec3|ivec4)\s+([A-Za-z_]\w*)\s*=\s*([^;]+);")
    for match in pattern.finditer(body):
        name, expression = match.group(1), match.group(2)
        rest = body[match.end():]
        if re.search(rf"\b{re.escape(name)}\s*(?:[+\-*/]?=)", rest):
            continue  # 后面还会变，不能当常量。
        value = evaluate_constant(expression, {**table, **local})
        if value is not None:
            local[name] = value
    return local


def local_bools(body: str, values: dict[str, bool] | None = None) -> dict[str, bool]:
    """收集只赋值一次的局部布尔量，用来判断哪些 `if` 分支在默认配置下根本不会执行。

    为什么需要：参考包用 `#ifdef ATMO_HORIZON` 把整段地面反弹删掉；库里改成运行时
    `bool groundBounce` 后，采样调用仍留在源码里，严格对照会把关闭的 7 次采样也算进去。
    这里只在实参或局部布尔能静态确定为 false/true 时裁剪分支，运行时值不猜。
    `values` 给出已经知道的外层布尔实参，局部量可以依赖它们继续折叠。
    """
    local: dict[str, bool] = dict(values or {})
    for match in re.finditer(r"(?:const\s+)?bool\s+([A-Za-z_]\w*)\s*=\s*([^;]+);", body):
        name, expression = match.group(1), match.group(2)
        rest = body[match.end():]
        if re.search(rf"\b{re.escape(name)}\s*(?:[+\-*/]?=)", rest):
            continue
        value = evaluate_bool_expression(expression, local)
        if value is not None:
            local[name] = value
    return local


def evaluate_bool_expression(expression: str, values: dict[str, bool]) -> bool | None:
    """把只含布尔名字、真值、比较和逻辑运算的表达式算成真或假；算不出时返回空。

    逻辑运算按短路规则处理：`false && 未知` 一定是假，`true || 未知` 一定是真。
    这样默认配置关闭的地面反弹分支会被裁掉，而真正依赖运行时变量的条件保持原样。
    """
    text = expression.strip()
    while text.startswith("(") and text.endswith(")") and matching_delimiter(text, 0, "(", ")") == len(text) - 1:
        text = text[1:-1].strip()
    if not text:
        return None
    # 三元表达式：条件已知时只保留被选中的分支，`localLighting ? 查询 : false` 才能在默认关闭时折叠。
    ternary = split_ternary(text)
    if ternary is not None:
        condition, when_true, when_false = ternary
        value = evaluate_bool_expression(condition, values)
        if value is None:
            return None
        return evaluate_bool_expression(when_true if value else when_false, values)
    or_parts = split_bool_operator(text, "||")
    if len(or_parts) > 1:
        results = [evaluate_bool_expression(part, values) for part in or_parts]
        if any(value is True for value in results):
            return True
        return False if all(value is False for value in results) else None
    and_parts = split_bool_operator(text, "&&")
    if len(and_parts) > 1:
        results = [evaluate_bool_expression(part, values) for part in and_parts]
        if any(value is False for value in results):
            return False
        return True if all(value is True for value in results) else None
    if text.startswith("!") and not text.startswith("!="):
        inner = evaluate_bool_expression(text[1:], values)
        return None if inner is None else not inner
    for operator in ("==", "!=", ">=", "<=", ">", "<"):
        parts = split_bool_operator(text, operator)
        if len(parts) == 2:
            table = {name: [1.0 if value else 0.0] for name, value in values.items()}
            left = evaluate_constant(parts[0], table)
            right = evaluate_constant(parts[1], table)
            if left is None or right is None or len(left) != 1 or len(right) != 1:
                return None
            a, b = left[0], right[0]
            return {"==": a == b, "!=": a != b, ">=": a >= b, "<=": a <= b,
                    ">": a > b, "<": a < b}[operator]
    if text in ("true", "1"):
        return True
    if text in ("false", "0"):
        return False
    if text in values:
        return values[text]
    return None


def split_ternary(text: str) -> tuple[str, str, str] | None:
    """在顶层把 `条件 ? 真分支 : 假分支` 拆开；嵌套三元按最外层处理。"""
    depth, question = 0, -1
    for index, char in enumerate(text):
        if char in "([":
            depth += 1
        elif char in ")]":
            depth -= 1
        elif char == "?" and depth == 0:
            question = index
            break
    if question < 0:
        return None
    depth = 0
    for index in range(question + 1, len(text)):
        char = text[index]
        if char in "([":
            depth += 1
        elif char in ")]":
            depth -= 1
        elif char == ":" and depth == 0:
            return text[:question].strip(), text[question + 1:index].strip(), text[index + 1:].strip()
    return None


def split_bool_operator(text: str, operator: str) -> list[str]:
    """按顶层逻辑运算符切分；括号里的同名运算符不切。"""
    parts, depth, start, index = [], 0, 0, 0
    while index <= len(text) - len(operator):
        char = text[index]
        if char in "([":
            depth += 1
        elif char in ")]":
            depth -= 1
        elif depth == 0 and text.startswith(operator, index):
            parts.append(text[start:index].strip())
            index += len(operator)
            start = index
            continue
        index += 1
    if not parts:
        return [text.strip()]
    parts.append(text[start:].strip())
    return parts


def nearest_declaration(text: str, position: int, name: str) -> str | None:
    """在循环前找同名局部声明的右侧表达式，解决同名局部量在不同作用域重复声明。

    参考函数里 SSS 循环和 VPS 循环都写 `const float steps = ...`，但取值不同。
    只按名字查全局作用域会把两个循环都算成后一个值，采样次数因此失真。
    这里从循环位置向前找最近一次声明，取它自己的右侧表达式。
    """
    pattern = re.compile(
        rf"(?:const\s+)?(?:float|int|uint)\s+{re.escape(name)}\s*=\s*([^;]+);")
    last = None
    for match in pattern.finditer(text, 0, position):
        last = match
    return last.group(1).strip() if last else None


def unroll_constant_loops(body: str, scope: dict) -> str:
    """把边界能静态求值的 `for` 循环按迭代次数展开，供采样与常数统计使用。

    为什么需要：参考写 `for (int i = 0; i < 3; i++) texture(...)`，一个采样调用点
    实际执行三次；库为了性能把循环手写展开成三次调用。只数调用点会把两者判成
    2 对 4 的假差异。这里按常数边界展开参考循环，让比较的是运行次数而不是写法。
    边界含运行时变量或次数过大时保持原样，不猜。
    """
    pattern = re.compile(
        r"\bfor\s*\(\s*(?:int|uint|float)\s+([A-Za-z_]\w*)\s*=\s*([^;]+);"
        r"\s*\1\s*(<=|<)\s*([^;]+);\s*[^)]*\)\s*\{")
    text = body
    for _ in range(64):
        changed = False
        for match in reversed(list(pattern.finditer(text))):
            start_value = evaluate_constant(match.group(2), scope)
            end_expression = match.group(4).strip()
            end_value = None
            if re.fullmatch(r"[A-Za-z_]\w*", end_expression):
                declaration = nearest_declaration(text, match.start(), end_expression)
                if declaration is not None:
                    end_value = evaluate_constant(declaration, scope)
            if end_value is None:
                end_value = evaluate_constant(end_expression, scope)
            if not start_value or not end_value or len(start_value) != 1 or len(end_value) != 1:
                continue
            start, end = start_value[0], end_value[0]
            count = int(end - start) + (1 if match.group(3) == "<=" else 0)
            if count <= 0 or count > 64:
                continue
            brace = text.find("{", match.end() - 1)
            if brace < 0:
                continue
            brace_end = matching_delimiter(text, brace, "{", "}")
            if brace_end < 0:
                continue
            inner = unroll_constant_loops(text[brace + 1:brace_end], scope)
            text = text[:match.start()] + inner * count + text[brace_end + 1:]
            changed = True
            break
        if not changed:
            break
    return text


def prune_static_branches(body: str, values: dict[str, bool]) -> str:
    """删掉条件能静态确定的 `if` 分支，只保留默认配置会执行的部分。

    只处理带大括号的 `if`；条件里出现未知运行时名字时保持原样。这样不会改变真正
    依赖运行时数据的代码，只把 `if (false)` 里为另一种配置准备的采样移出统计。
    """
    text = body
    for _ in range(64):
        changed = False
        for match in reversed(list(re.finditer(r"\bif\s*\(", text))):
            open_paren = text.find("(", match.start())
            close_paren = matching_delimiter(text, open_paren, "(", ")")
            if close_paren < 0:
                continue
            value = evaluate_bool_expression(text[open_paren + 1:close_paren], values)
            if value is None:
                continue
            cursor = close_paren + 1
            while cursor < len(text) and text[cursor].isspace():
                cursor += 1
            if cursor >= len(text) or text[cursor] != "{":
                continue
            block_end = matching_delimiter(text, cursor, "{", "}")
            if block_end < 0:
                continue
            taken_start, taken_end = (cursor + 1, block_end) if value else (block_end + 1, block_end + 1)
            after = block_end + 1
            cursor = after
            while cursor < len(text) and text[cursor].isspace():
                cursor += 1
            if text.startswith("else", cursor):
                else_start = cursor + 4
                cursor = else_start
                while cursor < len(text) and text[cursor].isspace():
                    cursor += 1
                if cursor < len(text) and text[cursor] == "{":
                    else_end = matching_delimiter(text, cursor, "{", "}")
                    if else_end < 0:
                        continue
                    if not value:
                        taken_start, taken_end = cursor + 1, else_end
                    after = else_end + 1
            replacement = text[taken_start:taken_end] if value or taken_start != taken_end else ""
            text = text[:match.start()] + replacement + text[after:]
            changed = True
            break
        if not changed:
            break
    return text


def matching_delimiter(text: str, start: int, opening: str, closing: str) -> int:
    """返回与 `start` 处左括号配对的右括号位置；找不到返回负一。"""
    depth = 0
    for index in range(start, len(text)):
        if text[index] == opening:
            depth += 1
        elif text[index] == closing:
            depth -= 1
            if depth == 0:
                return index
    return -1


def remove_local_declarations(body: str) -> str:
    """把局部变量声明的类型与名字换成空格，保留右侧表达式。

    为什么保留右侧：`float4 c = tex.SampleLevel(...);` 里的采样是真实采样，不能因为
    它写在声明里就漏掉；只去掉 `float4 c =` 前缀即可。
    """
    pattern = re.compile(
        r"(?:const\s+)?(?:float|int|uint|float2|float3|float4|int2|int3|int4|"
        r"vec2|vec3|vec4|ivec2|ivec3|ivec4)\s+[A-Za-z_]\w*\s*=(?!=)")
    return pattern.sub(lambda m: " " * len(m.group(0)), body)


def strip_bracket_indices(text: str) -> str:
    """把方括号里的数组下标换成空格，下标数字不是算式常数。"""
    return re.sub(r"\[[^\[\]\n]*\]", lambda m: "[" + " " * (len(m.group(0)) - 2) + "]", text)


def numeric_signature(body: str, table: dict) -> tuple[list[float], list[str]]:
    """返回函数体实际使用的数值列表与无法解析的名字。

    做法：先摘掉局部常量声明，记住这些名字的数值；再把每个被引用的具名常量展开成
    数值分量，最后收集剩下的字面量。这样参考写 `goldenAngle`、库里写
    `OGX_GOLDEN_ANGLE` 时比较的是同一个数，而声明位置不同不会制造假差异。
    """
    local = local_constants(body, table)
    scope = {**table, **local}
    text = remove_local_declarations(body)  # 声明本身不计入使用次数。
    text = strip_bracket_indices(text)  # 数组下标不是常数。
    values = []
    unresolved = []
    for match in re.finditer(r"\b[A-Za-z_]\w*\b", text):
        name = match.group(0)
        if name not in scope:
            continue
        before = text[max(0, match.start() - 1)]
        after = text[match.end()] if match.end() < len(text) else ""
        if before == "." or after == "(":  # 结构字段、swizzle 与函数名不是常量引用。
            continue
        values.extend(scope[name])
        # 同一个名字只保留一次展开，避免重复计数；数值比较看的是集合内容。
        text = text[:match.start()] + " " * len(name) + text[match.end():]
    numbers = list(values)
    for match in NUMBER_PATTERN.finditer(text):
        raw = match.group(0)
        try:
            numbers.append(float(raw.rstrip("fFuU")))
        except ValueError:
            unresolved.append(raw)
    return dedupe(numbers), unresolved


def dedupe(values: list[float]) -> list[float]:
    """排序并合并近似相等的数，只保留“用过哪些常数”，不把重复次数当差异。

    为什么忽略次数：参考把 `0.6` 存进局部常量再引用三次，库可能直接内联三次；
    次数不同不代表曲线不同，数值集合才是能复核的口径。
    """
    result: list[float] = []
    for value in sorted(values):
        if result and math.isclose(result[-1], value, rel_tol=2e-5, abs_tol=1e-7):
            continue
        result.append(value)
    return result


def sample_signature(body: str) -> list[str]:
    """按源码顺序返回采样种类，例如 `sample`、`fetch`。"""
    sequence = []
    for match in CALL_PATTERN.finditer(body):
        kind = SAMPLE_CALLS.get(match.group(1))
        if kind:
            sequence.append(kind)
    return sequence


# 语言内建函数不进入调用图：它们没有代码，也不会贡献采样或常数。
BUILTINS = {
    "abs", "acos", "all", "any", "asin", "atan", "bitfieldExtract", "ceil", "clamp", "cos",
    "cosh", "cross", "degrees", "determinant", "distance", "dot", "equal", "exp", "exp2",
    "faceforward", "floor", "fma", "fract", "frexp", "greaterThan", "greaterThanEqual",
    "inverse", "inversesqrt", "isinf", "isnan", "ldexp", "length", "lessThan",
    "lessThanEqual", "log", "log2", "matrixCompMult", "max", "min", "mix", "mod", "modf",
    "normalize", "not", "notEqual", "pow", "radians", "reflect", "refract", "round",
    "roundEven", "sign", "sin", "sinh", "smoothstep", "sqrt", "step", "tan", "tanh",
    "texelFetch", "texture", "textureGrad", "textureLod", "textureSize", "transpose",
    "trunc", "uintBitsToFloat", "floatBitsToUint", "asfloat", "asuint", "asint", "lerp",
    "saturate", "static_cast", "reinterpret_cast",
    "float2", "float3", "float4", "int2", "int3", "int4", "uint2", "uint3", "uint4",
    "bool2", "bool3", "bool4", "float2x2", "float3x3", "float4x4",
    "vec2", "vec3", "vec4", "ivec2", "ivec3", "ivec4", "uvec2", "uvec3", "uvec4",
    "bvec2", "bvec3", "bvec4", "mat2", "mat3", "mat4",
}


def call_sites(body: str) -> list[tuple[str, int]]:
    """按出现顺序返回函数调用名与实参个数，内建函数不计。"""
    sites = []
    for match in CALL_PATTERN.finditer(body):
        name = match.group(1)
        if name in BUILTINS or name in SAMPLE_CALLS or name in ("if", "for", "while", "switch"):
            continue
        depth, cursor = 0, match.end() - 1
        while cursor < len(body):
            if body[cursor] == "(":
                depth += 1
            elif body[cursor] == ")":
                depth -= 1
                if depth == 0:
                    break
            cursor += 1
        inner = body[match.end():cursor]
        args = 0 if not inner.strip() else 1
        level = 0
        for char in inner:
            if char in "([{":
                level += 1
            elif char in ")]}":
                level -= 1
            elif char == "," and level == 0:
                args += 1
        sites.append((name, args))
    return sites


def evaluate_argument(argument: str, scope: dict, bool_scope: dict) -> list[float] | None:
    """把调用实参算成常数；支持 `bool(...)`、`int(...)` 这类显式转换。

    Host 层常把选项宏写成 `bool(OMNI_COLORED_SHADOWS)`。直接求值会失败，循环和
    分支因此无法折叠，严格对照会把另一种配置的采样也算进来。这里先剥掉转换，
    用内部表达式的数值决定真假；只处理能静态求值的实参。
    """
    value = evaluate_constant(argument, scope)
    if value is not None:
        return value
    text = argument.strip()
    match = re.fullmatch(r"(?:bool|int|uint)\s*\((.*)\)", text, flags=re.S)
    if match:
        inner = evaluate_constant(match.group(1).strip(), scope)
        if inner is not None and len(inner) == 1:
            return [1.0 if inner[0] != 0.0 else 0.0]
    bool_value = evaluate_bool_expression(argument, bool_scope)
    if bool_value is not None:
        return [1.0 if bool_value else 0.0]
    return None


def collect_tree(item: dict, index: dict[str, list[dict]], constants: dict[str, list[float]],
                 depth: int = 0, stack: tuple[str, ...] = (),
                 cache: dict[tuple, tuple[list[float], list[str], list[str]]] | None = None,
                 bindings: dict[str, list[float]] | None = None,
                 resource_calls: dict[str, dict] | None = None
                 ) -> tuple[list[float], list[str], list[str]]:
    """沿调用图收集数值、采样顺序与无法解析的常量名。

    为什么沿调用图：宿主层函数通常只有一行转发，算法在通用库里；只看外层会得到
    “没有常数、没有采样”的假一致。调用图把真正的算式算进来，同时保留调用顺序。

    为什么把实参绑到形参：参考包的 `FLASHLIGHT_FOV` 是编译期常数，库函数把它改成显式
    参数 `fov`。只比较函数体时，库里的 `8.0 / fov` 无法折叠，参考里的 `8.0 / 0.25`
    却会折叠出额外的 32，制造假差异。调用点已知的常数实参绑定到形参后，两边都会
    得到同一组数值；绑定只接受能静态求值的实参，运行时值不参与。

    `resource_calls` 声明参考调用已被显式资源替代。命中时不再展开被调函数的内部
    常数，只按台账补上资源读取的采样类别；这样密度场、光表等外部输入可以严格
    对应一张纹理，而不会把生产者的菜单常数错算进消费者。

    结果按函数缓存；否则大气与光照的调用图会在每次比较时重复展开很多次。
    """
    cache = {} if cache is None else cache
    resource_calls = resource_calls or {}
    bindings = bindings or {}
    binding_key = tuple(sorted((name, tuple(value)) for name, value in bindings.items()))
    resource_key = tuple(sorted((name, tuple(sorted((key, repr(value)) for key, value in spec.items())))
                                for name, spec in resource_calls.items()))
    key = (item.get("path", ""), item.get("line", 0), item["name"], binding_key, resource_key)
    if key in cache:
        return cache[key]
    if key in stack:
        return [], [], []
    body = item["body"]
    # 参数名和局部声明会遮蔽同名全局常量；不排除会把 `x`、`m` 这类常用名字误当常数。
    parameter_names = {p["raw"].split()[-1] for p in item["params"] if p["raw"].split()}
    declared_names = set(re.findall(
        r"(?:const\s+)?(?:float|int|uint|bool|float2|float3|float4|int2|int3|int4|"
        r"vec2|vec3|vec4|ivec2|ivec3|ivec4|mat2|mat3|mat4|float2x2|float3x3|float4x4|"
        r"sampler2d|sampler3d|samplercube)\s+([A-Za-z_]\w*)\s*(?=[=;,\[])", body))
    base_scope = {name: value for name, value in constants.items()
                  if name not in parameter_names and name not in declared_names}
    # 只把调用点能静态求值的实参放进作用域；其余形参仍按运行时值处理，不猜。
    param_types = {p['raw'].split()[-1]: p['type'] for p in item['params'] if p['raw'].split()}
    bound_names = {name for name in bindings if name in parameter_names}
    base_scope.update({name: value for name, value in bindings.items()
                       if name in parameter_names and param_types.get(name) != 'bool'})
    # 布尔实参与局部布尔量单独记录：它们决定 `if` 分支是否在默认配置下执行，
    # 不能混进数值常数集合，否则 0 和 1 会被误当成算式常数。
    bool_bindings = {}
    for name, value in bindings.items():
        if name in parameter_names and param_types.get(name) == 'bool' and len(value) == 1:
            bool_bindings[name] = bool(value[0])
    # 布尔实参在分支裁剪里按真假使用；计算局部常量时也给出 1/0，
    # 否则 `bool ? 13 / 2 : 1` 这类循环次数无法折叠。
    numeric_bool_scope = {name: [1.0 if value else 0.0] for name, value in bool_bindings.items()}
    local = local_constants(body, {**base_scope, **numeric_bool_scope})
    scope = {**base_scope, **local}
    bool_scope = local_bools(body, bool_bindings)
    body = prune_static_branches(body, bool_scope)
    body = unroll_constant_loops(body, scope)
    text = remove_local_declarations(body)
    text = strip_bracket_indices(text)  # 数组下标不是常数。
    numbers: list[float] = []
    samples: list[str] = []
    unresolved: list[str] = []
    tokens: list[tuple[int, str, str, int]] = []
    for match in CALL_PATTERN.finditer(text):
        tokens.append((match.start(), "call", match.group(1), match.end() - 1))
    for match in NUMBER_PATTERN.finditer(text):
        tokens.append((match.start(), "number", match.group(0), match.end()))
    for match in re.finditer(r"\b([A-Za-z_]\w*)\b", text):
        name = match.group(1)
        if name in scope:
            tokens.append((match.start(), "constant", name, match.end()))
    tokens.sort()
    consumed: set[int] = set()
    for position, kind, token, end in tokens:
        if position in consumed:
            continue
        if kind == "number":
            try:
                numbers.append(float(token.rstrip("fFuU")))
            except ValueError:
                unresolved.append(token)
            continue
        if kind == "constant":
            before = text[position - 1] if position else ""
            after = text[end] if end < len(text) else ""
            if before == "." or after == "(":
                continue  # 结构字段或函数名不是常量引用。
            # 局部常量的值由右侧表达式算出来，右侧的字面量与全局常数已经计入；
            # 再把局部名展开成结果会重复计入派生值（例如 H=sqrt(6420²-6360²) 的 875.671），
            # 参考能折叠而显式参数化的实现不能折叠时就会制造假差异。
            # 绑定形参同理：实参本身的常数在调用点已经计入，展开派生值会多出中间结果。
            if token not in local and token not in bound_names:
                numbers.extend(scope[token])
            consumed.update(range(position, end))
            continue
        if token in SAMPLE_CALLS:
            samples.append(SAMPLE_CALLS[token])
            continue
        if token in resource_calls:
            # 显式资源替代：不展开生产者内部常数，只记录这一次资源读取。
            samples.extend(resource_calls[token].get("samples", []))
            continue
        # 函数调用：按实参个数挑同名重载；找不到时只当作未知调用跳过。
        args = arguments_at(text, end)
        candidates = [entry for entry in index.get(token, []) if len(entry["params"]) == args]
        if len(candidates) > 1:
            # 同名同参数个数的重载优先取调用者所在文件的定义。参考包的
            # `CalculateCameraVelocity` 在 TAA 与 MotionBlur 各有一份，参数个数相同但
            # 类型不同；只按参数个数取第一个会把十次深度采样算进动态模糊。
            same_file = [entry for entry in candidates
                         if Path(entry.get("path", "")).name == Path(item.get("path", "")).name]
            if same_file:
                candidates = same_file
        if not candidates or token in stack or depth >= 12:
            continue
        callee = candidates[0]  # 同名同参数个数的重载极少；仍有多个时取同文件或源码顺序第一个。
        arg_texts = argument_texts(text, end)
        callee_bindings = {}
        if len(arg_texts) == len(callee["params"]):
            for param, arg in zip(callee["params"], arg_texts):
                param_name = param["raw"].split()[-1] if param["raw"].split() else ""
                value = evaluate_argument(arg, scope, bool_scope)
                if param_name and value is not None:
                    callee_bindings[param_name] = value
        sub_numbers, sub_samples, sub_unresolved = collect_tree(
            callee, index, constants, depth + 1, (*stack, key), cache, callee_bindings, resource_calls)
        numbers.extend(sub_numbers)
        samples.extend(sub_samples)
        unresolved.extend(sub_unresolved)
    result = (numbers, samples, unresolved)
    cache[key] = result
    return result


def argument_texts(text: str, open_paren: int) -> list[str]:
    """返回左括号处调用的顶层实参文本，用来把常数实参绑定到形参。"""
    depth, cursor = 0, open_paren
    while cursor < len(text):
        if text[cursor] == "(":
            depth += 1
        elif text[cursor] == ")":
            depth -= 1
            if depth == 0:
                break
        cursor += 1
    if cursor >= len(text):
        return []
    return split_top_level(text[open_paren + 1:cursor])


def arguments_at(text: str, open_paren: int) -> int:
    """返回左括号处调用的实参个数；括号不配对时返回负一。"""
    depth, cursor = 0, open_paren
    while cursor < len(text):
        if text[cursor] == "(":
            depth += 1
        elif text[cursor] == ")":
            depth -= 1
            if depth == 0:
                break
        cursor += 1
    if cursor >= len(text):
        return -1
    inner = text[open_paren + 1:cursor]
    if not inner.strip():
        return 0
    count, level = 1, 0
    for char in inner:
        if char in "([{":
            level += 1
        elif char in ")]}":
            level -= 1
        elif char == "," and level == 0:
            count += 1
    return count


def index_by_function_name(paths: list[Path], defines: dict[str, str] | None = None,
                           first_branch: bool = False) -> dict[str, list[dict]]:
    """按函数名分组，供调用图按实参个数挑选重载。"""
    index: dict[str, list[dict]] = {}
    for path in sorted(paths):
        for item in parse_functions(path, defines, first_branch):
            item["path"] = path.as_posix()
            index.setdefault(item["name"], []).append(item)
    return index


def normalize_body(body: str) -> str:
    """把函数体压成只含标识符与数字的文本，用于判断两个参考函数是否完全相同。"""
    text = re.sub(r"\s+", "", body)
    return text


TEXTURE_PREFIXES = ("sampler", "usampler", "isampler")
MATRIX_TYPES = {"float2x2", "float3x3", "float4x4", "float2x3", "float2x4",
                "float3x2", "float3x4", "float4x2", "float4x3"}


def is_texture_type(type_name: str) -> bool:
    """判断参数类型是否为纹理句柄；采样器在库外由调用方绑定。"""
    return type_name.startswith(TEXTURE_PREFIXES)


def is_matrix_type(type_name: str) -> bool:
    """判断参数类型是否为矩阵；矩阵来自相机或阴影阶段。"""
    return type_name in MATRIX_TYPES


def struct_definitions(paths: list[Path], defines: dict[str, str] | None = None) -> dict[str, list[str]]:
    """收集结构体字段类型，供“资源结构体必须含纹理或矩阵”检查使用。"""
    table: dict[str, list[str]] = {}
    for path in sorted(paths):
        raw = path.read_text(encoding="utf-8", errors="replace")
        text = strip_comments(preprocess(raw, defines) if defines is not None else raw)
        for match in re.finditer(r"\bstruct\s+([A-Za-z_]\w*)\s*\{", text):
            name = match.group(1)
            brace = text.find("{", match.start())
            end = matching_delimiter(text, brace, "{", "}")
            if end < 0:
                continue
            fields = []
            for line in text[brace + 1:end].split(";"):
                cleaned = line.strip()
                if not cleaned:
                    continue
                words = [word for word in re.split(r"\s+", cleaned) if word not in QUALIFIERS]
                if len(words) >= 2:
                    fields.append(normalize_type(" ".join(words[:-1])))
            table[name.lower()] = fields
            table[normalize_type(name)] = fields
    return table


def resource_issue(param: dict, kind: str, impl: dict, structs: dict[str, list[str]]) -> str | None:
    """检查一个新增参数是否真的属于已声明的宿主资源。

    允许四类资源：纹理、矩阵、结构体与显式数值。结构体必须至少含一个纹理或矩阵
    字段，避免把普通业务数据伪装成资源参数；任何新增参数都必须在函数体里出现，
    否则只是把签名撑长，没有把输入真正接进算法。
    """
    name = param.get("name", "")
    if not name:
        return f"资源参数缺少名字：{param['raw']}"
    if not re.search(rf"\b{re.escape(name)}\b", impl["body"]):
        return f"资源参数未在函数体使用：{name}"
    if kind == "texture":
        if not is_texture_type(param["type"]):
            return f"资源参数 {name} 不是纹理：{param['type']}"
        return None
    if kind == "matrix":
        if not is_matrix_type(param["type"]):
            return f"资源参数 {name} 不是矩阵：{param['type']}"
        return None
    if kind == "struct":
        fields = structs.get(param["type"], [])
        if not fields:
            return f"资源结构体 {param['type']} 没有定义"
        return None
    if kind == "value":
        if is_texture_type(param["type"]) or is_matrix_type(param["type"]):
            return f"数值资源 {name} 实际是纹理或矩阵：{param['type']}"
        return None
    return f"未知资源类别：{name}={kind}"


def compare(ref: dict, impl: dict, ref_constants: dict, lib_constants: dict,
            structs: dict[str, list[str]] | None = None,
            ref_index: dict[str, list[dict]] | None = None,
            impl_index: dict[str, list[dict]] | None = None,
            allow_extra_constants: bool = False,
            resources: dict[str, str] | None = None,
            bindings: dict[str, float] | None = None,
            resource_calls: dict[str, dict] | None = None) -> dict:
    """比较两份签名与算式，返回可直接写进报告的差异列表与证据字段。

    `ref_index` 与 `impl_index` 给出时沿调用图收集常数与采样；否则只比较函数体本身。
    `allow_extra_constants` 用于宿主转发层：参考常数必须全部出现，实现多出的常量
    可能来自显式化的宿主参数，不算缺失，但会记录在证据里供人工复核。

    `resources` 给出参考签名之后允许追加的宿主资源参数，键是参数名，值是
    texture/matrix/struct/value。参考参数必须逐项出现在实现参数表的最前面；
    追加参数必须有声明、在函数体使用，纹理与矩阵的类型还要对得上。这样算法可以
    在库里显式接收阴影图、深度图和相机矩阵，而不是把整个效果藏在宿主胶水里。
    `bindings` 给新增数值参数提供默认值。参考里的选项宏通常是常数，显式参数化后
    常数会消失；绑定值必须真的出现在参考常数集合里，才允许补回实现侧。
    """
    issues = []
    if ref["return"] != impl["return"]:
        issues.append(f"return {ref['returnRaw']} != {impl['returnRaw']}")
    ref_params = [(p["direction"], p["type"]) for p in ref["params"]]
    impl_params = [(p["direction"], p["type"]) for p in impl["params"]]
    if resources is None:
        if len(ref_params) != len(impl_params):
            issues.append(f"param count {len(ref_params)} != {len(impl_params)}")
        else:
            for index, (left, right) in enumerate(zip(ref_params, impl_params), start=1):
                if left != right:
                    issues.append(f"param {index} {left[1]}/{left[0]} != {right[1]}/{right[0]}")
    else:
        if len(impl_params) < len(ref_params):
            issues.append(f"param count {len(ref_params)} > {len(impl_params)}")
        else:
            for index, (left, right) in enumerate(zip(ref_params, impl_params), start=1):
                if left != right:
                    issues.append(f"param {index} {left[1]}/{left[0]} != {right[1]}/{right[0]}")
            declared = dict(resources)
            extras = impl["params"][len(ref["params"]):]
            present = {param.get("name", "") for param in extras}
            for name in declared:
                if name not in present:
                    issues.append(f"资源参数不存在：{name}")
            table = structs or {}
            for param in extras:
                name = param.get("name", "")
                if name not in declared:
                    issues.append(f"未声明的追加参数：{name}")
                    continue
                problem = resource_issue(param, declared[name], impl, table)
                if problem:
                    issues.append(problem)
            impl_numbers_extra = []
            for name, value in (bindings or {}).items():
                if name not in declared:
                    issues.append(f"绑定值没有对应资源参数：{name}")
                    continue
                if isinstance(value, bool):
                    continue
                if isinstance(value, (list, tuple)):
                    impl_numbers_extra.extend(float(item) for item in value)
                else:
                    impl_numbers_extra.append(float(value))
    if ref_index is not None and impl_index is not None:
        ref_numbers_raw, ref_samples, ref_unknown = collect_tree(
            ref, ref_index, ref_constants, resource_calls=resource_calls)
        impl_numbers_raw, impl_samples, impl_unknown = collect_tree(
            impl, impl_index, lib_constants,
            bindings={name: ([float(item) for item in value] if isinstance(value, (list, tuple))
                             else [1.0 if value is True else 0.0 if value is False else float(value)])
                      for name, value in (bindings or {}).items()})
        if resources is not None:
            impl_numbers_raw = list(impl_numbers_raw) + impl_numbers_extra
        ref_numbers = dedupe(ref_numbers_raw)
        impl_numbers = dedupe(impl_numbers_raw)
    else:
        ref_samples = sample_signature(ref["body"])
        impl_samples = sample_signature(impl["body"])
        ref_numbers, ref_unknown = numeric_signature(ref["body"], ref_constants)
        impl_numbers, impl_unknown = numeric_signature(impl["body"], lib_constants)
    if ref_samples != impl_samples:
        issues.append(f"samples {ref_samples} != {impl_samples}")
    missing = [value for value in ref_numbers
               if not any(math.isclose(value, other, rel_tol=2e-5, abs_tol=1e-7) for other in impl_numbers)]
    extra = [value for value in impl_numbers
             if not any(math.isclose(value, other, rel_tol=2e-5, abs_tol=1e-7) for other in ref_numbers)]
    if missing or (extra and not allow_extra_constants):
        detail = []
        if missing:
            detail.append("missing " + ", ".join(f"{value:g}" for value in missing[:8]))
        if extra and not allow_extra_constants:
            detail.append("extra " + ", ".join(f"{value:g}" for value in extra[:8]))
        issues.append("constants " + "; ".join(detail))
    return {
        "referenceSignature": signature_text(ref),
        "implementationSignature": signature_text(impl),
        "referenceSamples": ref_samples,
        "implementationSamples": impl_samples,
        "referenceNumbers": len(ref_numbers),
        "implementationNumbers": len(impl_numbers),
        "missingNumbers": [round(value, 12) for value in missing[:32]],
        "extraNumbers": [round(value, 12) for value in extra[:32]],
        "unresolved": sorted(set(ref_unknown + impl_unknown)),
        "issues": issues,
    }


def signature_text(item: dict) -> str:
    """把签名拼成一行，报告和文档直接展示。"""
    params = ", ".join(f"{p['direction'] + ' ' if p['direction'] != 'in' else ''}{p['type']}"
                       for p in item["params"])
    return f"{item['return']} {item['name']}({params})"
