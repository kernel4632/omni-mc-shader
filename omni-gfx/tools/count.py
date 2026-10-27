"""统计 omni-gfx 的手写代码、生成代码与第三方代码行数。

调用位置：`omni-gfx/build.py count`；计划里的代码量口径以这里为准。
设计原因与取舍：
    手写量只统计核心源、构建工具和测试，生成文件与第三方代码分开列出，
    避免用生成物把行数冲高，也避免把下载的参考实现算成自己的工作量。
    行数按非空物理行统计，注释行单独再算一列，便于判断说明密度而不靠删注释凑数。
"""
from __future__ import annotations

import json  # 机器可读输出供验证记录引用。
from pathlib import Path  # 目录遍历与相对路径。

LIB = Path(__file__).resolve().parent.parent  # omni-gfx 根目录。
ROOT = LIB.parent  # 仓库根目录，生成文件有一部分写在光影包里。

# 每个分类给一个范围与说明；顺序固定，报告读起来稳定。
CATEGORIES = (
    ("核心源", (LIB / "src",), "Slang 模块，唯一手写算法来源"),
    ("构建工具", (LIB / "tools", LIB / "build.py"), "生成器、编译器封装与统计工具"),
    ("测试", (LIB / "tests",), "等值测试、编译探针与回归测试"),
    ("测试世界", (LIB / "examples",), "不启动 Minecraft 的程序化场景"),
    ("生成 GLSL", (LIB / "generated" / "glsl", ROOT / "shaders" / "omni-gfx"), "由 Slang 源自动生成，不手工修改"),
    ("第三方", (LIB / "vendor",), "外部代码，当前没有引入"),
)

# 只统计源码类型，避免把图片、二进制和缓存算成行数。
SOURCE_SUFFIXES = {".py", ".slang", ".glsl", ".vert", ".frag"}

# 这些目录是缓存或本机工具，不属于任何统计口径。
SKIP_PARTS = {"__pycache__", ".dev", ".venv"}


def _files(entries: tuple[Path, ...]) -> list[Path]:
    """展开分类里的文件；文件直接返回，目录递归并跳过缓存。

    `entries` 由分类表给出，只读不写；顺序排序后返回，保证统计稳定。
    """
    result: list[Path] = []  # 收集本次分类的文件。
    # 分类表可能同时给出目录与单个文件，两种都要能展开。
    for entry in entries:
        if entry.is_file():  # 单个文件直接加入。
            result.append(entry)
        elif entry.is_dir():  # 目录递归展开。
            result.extend(path for path in entry.rglob("*") if path.is_file())
    return sorted(path for path in result if path.suffix in SOURCE_SUFFIXES and not SKIP_PARTS.intersection(path.parts))  # 去缓存、去二进制。


def _line_stats(path: Path) -> tuple[int, int]:
    """返回一个文件的非空行数与注释行数。

    只做轻量识别：Python 的井号、GLSL 与 Slang 的斜杠注释都算注释。
    字符串里的井号可能被误算，这只影响说明密度参考，不影响手写总量口径。
    """
    text = path.read_text(encoding="utf-8", errors="replace")  # 源码都是文本，坏字节不让统计中断。
    nonempty = 0  # 非空物理行。
    comments = 0  # 只含注释的行，用于参考。
    in_block = False  # 跨行块注释状态。
    for raw in text.splitlines():
        line = raw.strip()  # 行首尾空白不参与判断。
        if not line:  # 空行不计。
            continue
        nonempty += 1
        if in_block:  # 正在块注释里，整行都算说明。
            comments += 1
            if "*/" in line:  # 本行结束块注释。
                in_block = False
            continue
        if line.startswith("/*"):  # 块注释开始。
            comments += 1
            in_block = "*/" not in line  # 同一行闭合时不用进入跨行状态。
        elif line.startswith("//") or line.startswith("#"):  # 行注释与 Python 注释。
            comments += 1
    return nonempty, comments


def collect() -> dict:
    """返回分类统计结果，字段包括文件数、非空行与注释行。

    结果是纯数据，报告和测试共用；不写入任何文件。
    """
    # 顶层口径只保留三个总数，表格明细放在分类列表里。
    report = {"categories": [], "handwrittenTotal": 0, "generatedTotal": 0, "thirdPartyTotal": 0}  # 顶层口径。
    # 按固定顺序统计，输出顺序不随文件系统变化。
    for name, entries, note in CATEGORIES:  # 按固定顺序统计。
        files = _files(entries)  # 当前分类的有效文件。
        nonempty = 0  # 当前分类非空行总数。
        comments = 0  # 当前分类注释行总数。
        for path in files:  # 逐个文件累计。
            file_nonempty, file_comments = _line_stats(path)
            nonempty += file_nonempty
            comments += file_comments
        item = {"name": name, "files": len(files), "lines": nonempty, "commentLines": comments, "note": note}  # 一行报告数据。
        report["categories"].append(item)
        if name in ("核心源", "构建工具", "测试"):  # 计划里的手写核心口径。
            report["handwrittenTotal"] += nonempty
        elif name == "生成 GLSL":
            report["generatedTotal"] += nonempty
        elif name == "第三方":
            report["thirdPartyTotal"] += nonempty
    report["handwrittenBudget"] = 17500  # 手写核心上限；第八批 WSR/Photonics 与 Eclipse 天空补充按实际规模上调，理由写入计划的决策记录。
    return report


def report(as_json: bool = False) -> None:
    """打印统计表或机器可读结果。

    `as_json` 为真时只输出一行 JSON，便于其他脚本读取；
    否则输出对齐的表格，并单独说明测试世界不计入手写核心。
    """
    data = collect()  # 统计只算一次。
    if as_json:
        print(json.dumps(data, ensure_ascii=False, indent=2))  # 机器可读输出保持中文分类名。
        return
    print(f"{'分类':<8}{'文件':>6}{'非空行':>8}{'注释行':>8}  说明")  # 表头。
    for item in data["categories"]:  # 每类一行。
        print(f"{item['name']:<8}{item['files']:>6}{item['lines']:>8}{item['commentLines']:>8}  {item['note']}")
    print(f"手写核心合计：{data['handwrittenTotal']} 行（上限 {data['handwrittenBudget']} 行，含核心源、构建工具与测试）")
    print(f"生成 GLSL：{data['generatedTotal']} 行；第三方：{data['thirdPartyTotal']} 行")
    print("测试世界单列在表格里，不冲淡手写核心口径。")
