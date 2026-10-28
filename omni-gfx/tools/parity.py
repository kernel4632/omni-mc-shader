"""生成函数级覆盖对照表：参考包里的每个函数在 omni-gfx 里由谁承接，或为什么没有。

调用位置：`python omni-gfx/build.py parity`，输出 `docs/gfx-functions.md` 与
`.dev/omni-gfx/gaps.txt`；修改 `omni-gfx/src/` 或参考包后重新运行。
产物是审查覆盖范围的唯一入口，对照表的第一行结论直接引用这里的统计。

判定顺序：
    1. `parity_map.json` 的人工对照优先，键是参考函数名，值是 `模块.函数`，
       或写成 `{"target": ..., "evidence": ...}` 并附一条可复核的算法对应说明；
    2. 去掉 `ogx` 前缀后完全同名，视为已迁入；
    3. 函数体里出现 Minecraft 或 Iris 专有符号，视为宿主专用，并把符号逐个写进表；
    4. 其余记为缺失，进入缺口清单，按参考实现的行数排序。

为什么不用模糊匹配：
    名字相似但算法不同是最容易犯的错。例如参考包的 `ACES` 是一条自定义拟合，
    库里的 `ogxTonemapAcesFilm` 是另一条曲线；只按名字相似就写“已覆盖”，
    会让接手者以为移植完成，比诚实标缺失危险得多。
    同理，`AgXConfigurable1` 是带参数滑块的版本，`ogxAgx` 固定了其中一组参数，
    两者只能算同一算法家族，不能算同一个接口。

为什么先判人工对照再判同名：
    参考包的命名是驼峰，库里的命名是 `ogx` 加驼峰，多数情况同名直配就够；
    少数函数在移植时改了名字（`GetPlanarCloudsDensity` → `ogxPlanarDensity`），
    这些必须靠人工对照，否则会被误判成缺失。

为什么宿主符号要逐个列出：
    审查者需要能自己验证“这个函数确实离不开游戏”。只写“依赖 Minecraft”是空话；
    写出 `colortex0`、`mc_Entity`、`gbufferProjectionInverse` 这类名字，
    任何人都能在参考源码里搜到同一行，判定可以被推翻也可以被确认。

统计口径：
    同名函数在两份参考包里只算一次，位置取第一次出现的那份。
    这样总数等于“需要移植的算法数量”，而不是“两份包的函数定义总和”。

生成结果的可复现性：
    脚本不写时间戳，文件按路径与行号排序，同一份源码每次运行得到相同字节。
    对照组表是否过期，只要重新运行再看 `git diff` 即可。
"""
from __future__ import annotations

import json  # 读取人工对照数据。
import re  # 解析函数定义。
import sys  # 自检失败时以非零状态退出。
from pathlib import Path  # 统一使用路径对象。

ROOT = Path(__file__).resolve().parents[2]  # 仓库根目录。
LIB = ROOT / "omni-gfx"  # 通用库目录。
DOC = ROOT / "docs" / "gfx-functions.md"  # 生成的对照表。
GAPS = ROOT / ".dev" / "omni-gfx" / "gaps.txt"  # 缺口清单。
MAP = LIB / "tools" / "parity_map.json"  # 人工对照数据。
REFERENCE_FUNCTION_COUNT = 505  # 两份参考包去重后的函数总数；目录缺失或解析失败时不能悄悄变成零。

# 只服务 Minecraft 或 Iris 的符号：缓冲名、材质与实体属性、游戏时间与阶段变量。
# `gl_FragCoord` 与 `text.` 属于屏幕叠加：调试打印函数用它们定位并写字符，
# 不是通用库能承接的算法，但证据必须落到具体符号，不能只写“调试用”。
HOST_SYMBOLS = (
    "colortex", "gaux", "shadowtex", "shadowcolor", "depthtex", "noisetex", "normals",
    "mc_Entity", "mc_midTexCoord", "entityId", "blockEntityId", "entityColor",
    "biome", "heldItemId", "heldBlockLightValue", "isEyeInWater", "blindness", "nightVision",
    "frameTimeCounter", "worldTime", "worldDay", "moonPhase", "frameCounter", "rainStrength",
    "wetness", "eyeBrightness", "eyeAltitude", "screenBrightness", "sunAngle", "shadowAngle",
    "fogColor", "skyColor", "ambientColor", "lightColor", "cameraPosition",
    "previousCameraPosition", "gbufferModelView", "gbufferProjection", "shadowModelView",
    "gbufferPreviousProjection", "gbufferPreviousModelView", "dhProjection", "dhFarPlane",
    "gl_ModelViewMatrix", "gl_ProjectionMatrix", "gl_ModelViewProjectionMatrix",
    "gl_NormalMatrix", "gl_MultiTexCoord", "gl_Vertex", "gl_Color", "gl_Normal",
    "atlasSize", "shadowMapResolution", "viewWidth", "viewHeight", "blockEntity",
    "lightningBoltPosition", "sunElevation", "gl_FragCoord", "text.",
)

# 返回类型白名单：库里的函数还会返回自定义结构体，另按大写开头放行。
TYPE_WORDS = {
    "void", "bool", "int", "uint", "float", "double",
    "vec2", "vec3", "vec4", "ivec2", "ivec3", "ivec4", "uvec2", "uvec3", "uvec4",
    "bvec2", "bvec3", "bvec4", "mat2", "mat3", "mat4", "mat2x2", "mat3x3", "mat4x4",
    "float2", "float3", "float4", "int2", "int3", "int4", "uint2", "uint3", "uint4",
    "float4x4", "float3x3",
    "sampler2D", "sampler3D", "samplerCube", "sampler2DShadow",
}

# 控制流关键字不是函数名，扫到时要跳过。
KEYWORDS = {"if", "for", "while", "switch", "return", "else", "do"}


def strip_comments(text: str) -> str:
    """去掉注释但保留长度与换行，后面对行号的定位才不会错位。"""
    text = re.sub(r"/\*.*?\*/", lambda m: re.sub(r"[^\n]", " ", m.group(0)), text, flags=re.S)  # 块注释按字符换成空格。
    return re.sub(r"//[^\n]*", lambda m: " " * len(m.group(0)), text)  # 行注释同样只换成空格。


def parse_functions(path: Path) -> list[dict]:
    """严格解析一份源文件的函数定义，返回名字、行号、函数体与有效行数。

    判据：行首是返回类型，名字后紧跟参数表，参数表的右括号后面必须是左大括号。
    这样预处理器宏、`if (...)` 与多行声明残留都不会被当成函数定义；
    括号用深度配对而不是找换行，单行函数也能正确切出来。
    """
    text = strip_comments(path.read_text(encoding="utf-8", errors="replace"))  # 先去掉注释，避免注释里的括号干扰配对。
    found = []  # 收集本文件的函数。
    for match in re.finditer(r"\b([A-Za-z_]\w*)\s*\(", text):  # 逐个候选位置。
        name = match.group(1)  # 候选函数名。
        if name in KEYWORDS or name in TYPE_WORDS:  # 控制流与类型名不是函数。
            continue
        line_start = text.rfind("\n", 0, match.start()) + 1  # 当前行的起点。
        prefix = text[line_start:match.start()].strip()  # 名字前面的返回类型。
        if not prefix or prefix.startswith("#"):  # 没有返回类型或是宏定义。
            continue
        first = prefix.split()[0]  # 返回类型的第一个词。
        # 返回类型可以是语言内建类型，也可以是项目里的结构体（按大写开头的命名约定）。
        if first not in TYPE_WORDS and not first[:1].isupper():
            continue
        depth = 0  # 参数表括号深度。
        index = match.end() - 1  # 从左括号开始数。
        while index < len(text):  # 找到参数表的右括号。
            if text[index] == "(":  # 进入一层。
                depth += 1
            elif text[index] == ")":  # 退出一层。
                depth -= 1
                if depth == 0:  # 回到零说明参数表结束。
                    break
            index += 1
        rest = text[index + 1:]  # 右括号之后的内容。
        brace = rest.find("{")  # 函数体起点。
        if brace < 0 or rest[:brace].strip():  # 不是定义（例如只是声明）。
            continue
        start = index + 1 + brace  # 左大括号的绝对位置。
        depth = 0  # 函数体大括号深度。
        cursor = start  # 从函数体起点开始配对。
        while cursor < len(text):  # 逐字符找匹配的右大括号。
            if text[cursor] == "{":  # 进入一层。
                depth += 1
            elif text[cursor] == "}":  # 退出一层。
                depth -= 1
                if depth == 0:  # 配平，函数体结束。
                    break
            cursor += 1
        if cursor >= len(text):  # 文件被截断时跳过，不能猜结束位置。
            continue
        body = text[start:cursor + 1]  # 完整函数体。
        found.append({  # 记录后续要用到的字段。
            "name": name,  # 函数名。
            "line": text[:match.start()].count("\n") + 1,  # 定义所在行，从一起算。
            "body": body,  # 函数体文本，用于找宿主符号。
            "lines": len([row for row in body.splitlines() if row.strip()]),  # 有效行数，用来衡量迁移成本。
        })
    return found  # 按出现顺序返回。


def library_index() -> dict[str, str]:
    """返回 小写函数名 → `模块.函数` 的索引，供同名直配使用。

    模块名取 `src` 下的相对路径，文件夹会出现在键里；这样 `cloud/layers`
    这类变体文件不会和顶层模块重名。
    """
    index = {}  # 名字到下标的映射。
    for path in sorted((LIB / "src").rglob("*.slang")):  # 逐个模块。
        module = path.relative_to(LIB / "src").with_suffix("").as_posix()
        for item in parse_functions(path):  # 逐个函数定义。
            key = item["name"][3:].lower() if item["name"].startswith("ogx") else item["name"].lower()  # 去掉统一前缀再比。
            index.setdefault(key, f"{module}.{item['name']}")  # 同名重载只留第一个。
    return index  # 供判定与自检使用。


def host_hits(body: str) -> list[str]:
    """返回函数体里出现的宿主符号，顺序与白名单一致。"""
    return [symbol for symbol in HOST_SYMBOLS if symbol in body]


def collect_reference() -> list[dict]:
    """按固定顺序收集两份参考包的函数定义，同名只保留第一次出现。

    目录缺失或函数总数不等于登记值时直接失败：零个函数会让“缺失为零”的测试
    看起来通过，实际上没有读到任何参考源码。
    """
    rows = []  # 结果列表。
    seen = set()  # 已出现过的函数名。
    for root, pack in ((ROOT / "references/iterationT/shaders/Lib", "iterationT"),  # 第一份参考包。
                       (ROOT / "references/Eclipse/shaders/lib", "Eclipse")):  # 第二份参考包。
        if not root.is_dir():
            raise FileNotFoundError(f"参考目录不存在：{root.relative_to(ROOT)}")  # 不把缺目录当成零函数。
        for path in sorted(root.rglob("*.glsl")):  # 按路径排序，输出才稳定。
            for item in parse_functions(path):  # 逐个函数。
                if item["name"] in seen:  # 另一份里出现过同一个名字。
                    continue
                seen.add(item["name"])  # 记下名字。
                item["pack"] = pack  # 来源包，统计要分开算。
                item["path"] = path.relative_to(ROOT).as_posix()  # 仓库内相对路径。
                rows.append(item)  # 收集。
    if len(rows) != REFERENCE_FUNCTION_COUNT:
        raise ValueError(f"参考函数数量应为 {REFERENCE_FUNCTION_COUNT}，实际读到 {len(rows)}；解析规则或参考目录已变化")
    return rows  # 总数等于需要移植的算法数量。


def classify(rows: list[dict], index: dict[str, str], mapping: dict) -> None:
    """给每条记录写状态、承接函数与证据，并检查人工对照是否指向真实函数。"""
    mapped = mapping["mapped"]  # 人工对照。
    manual = mapping["manual"]  # 人工覆盖的状态。
    notes = mapping.get("modules", {})  # 模块说明表，写在数据文件里避免代码里堆长字符串。
    missing_targets = []  # 指向不存在函数的人工对照。
    for row in rows:  # 逐条判定。
        name = row["name"]  # 参考函数名。
        if name in manual:  # 人工覆盖优先，用来写“调试输出”等特殊状态。
            row["status"] = manual[name]["status"]  # 状态。
            row["target"] = ""  # 没有承接函数。
            row["evidence"] = manual[name]["evidence"]  # 人工写的证据。
            continue
        if name in mapped:  # 人工对照。
            entry = mapped[name]  # 目标可以带一条证据：同名算法在库里换了名字时，必须写清为什么仍是同一算法。
            target = entry["target"] if isinstance(entry, dict) else entry  # 两种写法都接受，旧条目不必重写。
            module, function = target.split(".")  # 拆成模块与函数名。
            if f"{module}.{function}" not in set(index.values()):  # 目标必须真实存在。
                missing_targets.append(f"{name} → {target}")  # 记下错误，最后统一退出。
            row["status"] = "已迁入"  # 有承接函数。
            row["target"] = target  # 写进表里。
            row["evidence"] = entry.get("evidence", f"承接算法：{notes.get(module, module)}") if isinstance(entry, dict) \
                else f"承接算法：{notes.get(module, module)}"  # 人工证据优先，没有就按模块说明。
            continue
        if name.lower() in index:  # 去掉前缀后同名。
            target = index[name.lower()]  # 目标函数。
            module = target.split(".")[0]  # 模块名。
            row["status"] = "已迁入"  # 同名即已迁入。
            row["target"] = target  # 写进表里。
            row["evidence"] = f"同名迁移：{notes.get(module, module)}"  # 同上。
            continue
        hits = host_hits(row["body"])  # 找宿主符号。
        if hits:  # 直接读游戏数据。
            row["status"] = "MC 专用"  # 状态名固定，方便统计。
            row["target"] = ""  # 没有通用库承接。
            row["evidence"] = "函数体直接读取宿主符号：" + "、".join(f"`{h}`" for h in hits)  # 逐个列出，可复核。
            continue
        row["status"] = "缺失"  # 剩下的是真正缺口。
        row["target"] = ""  # 没有承接函数。
        row["evidence"] = f"参考实现 {row['lines']} 行，库里没有对应算法"  # 行数表示迁移成本。
    if missing_targets:  # 有错误就整体失败，不能带着错表继续。
        sys.exit("人工对照指向不存在的函数：\n" + "\n".join(missing_targets))


def render(rows: list[dict]) -> str:
    """把记录渲染成可读文档，返回完整文本。"""
    counts = {}  # 按包与状态统计。
    for row in rows:  # 逐条累加。
        counts[(row["pack"], row["status"])] = counts.get((row["pack"], row["status"]), 0) + 1  # 计数。
    total = len(rows)  # 总函数数。
    lines = [  # 文档头部与结论。
        "# 函数级覆盖对照：iterationT、Eclipse 与 omni-gfx",  # 标题。
        "",  # 空行。
        "本文件由 `python omni-gfx/build.py parity` 从源码生成，不要手工修改。",  # 说明来源。
        "它回答一个问题：参考光影里的每个函数，在 `omni-gfx` 里由谁承接，或者为什么没有承接。",  # 用途。
        "",  # 空行。
        "## 结论",  # 小节标题。
        "",  # 空行。
    ]
    lines.append(f"- 参考函数共 {total} 个（同名跨包只算一次）："
                 f"iterationT {sum(1 for r in rows if r['pack'] == 'iterationT')} 个，"
                 f"Eclipse {sum(1 for r in rows if r['pack'] == 'Eclipse')} 个。")  # 总数拆分。
    for status in ("已迁入", "MC 专用", "缺失", "调试输出"):  # 四种状态分别计数。
        count = sum(1 for r in rows if r["status"] == status)  # 该状态的数量。
        lines.append(f"- {status}：{count} 个。")  # 写成列表项。
    lines += ["", "| 参考包 | 已迁入 | MC 专用 | 缺失 | 调试输出 |", "| --- | --- | --- | --- | --- |"]  # 分表头。
    for pack in ("iterationT", "Eclipse"):  # 两份参考包分别统计。
        lines.append("| " + " | ".join([pack] + [str(counts.get((pack, status), 0))
                                                 for status in ("已迁入", "MC 专用", "缺失", "调试输出")]) + " |")  # 一行统计。
    lines += [  # 判定口径一节。
        "",  # 空行。
        "## 判定口径",  # 小节标题。
        "",  # 空行。
        "- **已迁入**：`omni-gfx/src` 里存在承接同一算法的函数，表里写出 `模块.函数`。",  # 第一种状态。
        "- **MC 专用**：函数体直接读取 Minecraft 或 Iris 的缓冲、实体、选项、阶段变量；",  # 第二种状态。
        "  表里逐个列出命中的符号，符号名可以在参考源码里直接搜到。屏幕叠加的调试打印也记在这里：",  # 调试叠加归入宿主专用。
        "  证据写明它用 `gl_FragCoord` 或 `text.` 定位并输出字符，不参与任何画面效果。",  # 证据要求。
        "- **缺失**：库里还没有对应实现，进入文末缺口清单。",  # 第三种状态。
        "- **调试输出**：只在屏幕上打印数字或文字，不参与任何画面效果，也不进入通用库。",  # 第四种状态。
        "- 名字相似但曲线不同的函数（例如 `ACES` 与 `ogxTonemapAcesFilm`）按实际算法判断，不按名字。",  # 反例。
        "",  # 空行。
        "## 明细",  # 明细小节。
        "",  # 空行。
    ]
    for pack in ("iterationT", "Eclipse"):  # 逐份参考包输出。
        lines.append(f"### {pack}")  # 三级标题。
        lines.append("")  # 空行。
        current = None  # 当前文件，用来插入小标题。
        for row in sorted((r for r in rows if r["pack"] == pack), key=lambda r: (r["path"], r["line"])):  # 按文件与行号排序。
            if row["path"] != current:  # 换了文件就重新写表头。
                current = row["path"]  # 记下当前文件。
                lines += ["", f"`{current}`", "", "| 函数 | 行 | 承接 | 状态 | 证据 |", "| --- | --- | --- | --- | --- |"]  # 文件与表头。
            target = f"`{row['target']}`" if row["target"] else "—"  # 没有承接函数时写短横。
            lines.append(f"| `{row['name']}` | {row['line']} | {target} | {row['status']} | {row['evidence']} |")  # 一行明细。
        lines.append("")  # 文件之间留空行。
    gaps = sorted((r for r in rows if r["status"] == "缺失"), key=lambda r: -r["lines"])  # 缺口按行数降序。
    lines += ["## 缺口清单", "", f"共 {len(gaps)} 个，按参考实现的行数从多到少排列。", "",
              "| 函数 | 参考位置 | 行数 | 参考做什么 |", "| --- | --- | --- | --- |"]  # 缺口表头。
    for row in gaps:  # 逐条缺口。
        lines.append(f"| `{row['name']}` | `{row['path']}:{row['line']}` | {row['lines']} | {row['evidence']} |")  # 缺口一行。
    lines += ["", "## 重新生成", "", "```text", "python omni-gfx/build.py parity", "```", ""]  # 用法。
    return "\n".join(lines)  # 拼成完整文档。


def main() -> None:
    """入口：解析、判定、写文档与缺口清单，并打印一行统计。"""
    mapping = json.loads(MAP.read_text(encoding="utf-8"))  # 读人工对照。
    index = library_index()  # 读库里的函数名。
    rows = collect_reference()  # 读参考包的函数。
    classify(rows, index, mapping)  # 判定每条记录。
    DOC.parent.mkdir(parents=True, exist_ok=True)  # 文档目录可能还不存在。
    DOC.write_text(render(rows), encoding="utf-8", newline="\n")  # 写对照表，固定使用 UTF-8 与换行。
    gaps = sorted((r for r in rows if r["status"] == "缺失"), key=lambda r: -r["lines"])  # 缺口按成本降序。
    GAPS.parent.mkdir(parents=True, exist_ok=True)  # 缺口文件放在开发目录。
    GAPS.write_text("".join(f"{r['lines']}\t{r['name']}\t{r['path']}:{r['line']}\n" for r in gaps),
                    encoding="utf-8", newline="\n")  # 每行一个缺口，方便继续迁移。
    counts = {}  # 汇总统计。
    for row in rows:  # 逐条累加。
        counts[row["status"]] = counts.get(row["status"], 0) + 1  # 计数。
    print(f"函数级对照：{len(rows)} 个函数，统计 {counts}，缺口 {len(gaps)} 个 → {DOC}")  # 一行结果。


if __name__ == "__main__":
    main()
