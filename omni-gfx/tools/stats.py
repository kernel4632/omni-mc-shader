"""生成并核对文档里的当前统计，避免 README、对照表与验证记录各写一套数字。

调用位置：`python omni-gfx/build.py stats`；测试调用 `check()` 确认文档没有过期。
设计原因与取舍：
    模块数、源文件数、生成 GLSL 行数与函数对照都从真实文件重新计算，不手工抄写。
    历史验证章节保留当时的数字，只有带标记的“当前统计”块会随本轮结果更新。
"""
from __future__ import annotations

import json
from pathlib import Path

import catalog
import parity

LIB = Path(__file__).resolve().parent.parent
ROOT = LIB.parent
BEGIN = "<!-- stats:begin -->"
END = "<!-- stats:end -->"
TARGETS = (ROOT / "README.md", LIB / "docs" / "verification.md")


def _parity_counts() -> tuple[int, int, int, int]:
    """重新判定参考函数，返回总数、已迁入、MC 专用与缺失数量。"""
    rows = parity.collect_reference()
    mapping = json.loads(parity.MAP.read_text(encoding="utf-8"))
    parity.classify(rows, parity.library_index(), mapping)
    total = len(rows)
    migrated = sum(1 for row in rows if row["status"] == "已迁入")
    mc = sum(1 for row in rows if row["status"] == "MC 专用")
    missing = sum(1 for row in rows if row["status"] == "缺失")
    return total, migrated, mc, missing


def _strict_counts() -> dict[str, int]:
    """读取严格对照报告的最新统计；报告不存在时明确报错。"""
    path = LIB / "tools" / "parity_report.json"
    if not path.is_file():
        raise FileNotFoundError("缺少严格对照报告，请先运行 strict-parity")
    payload = json.loads(path.read_text(encoding="utf-8"))
    return payload["summary"]["totals"]


def render() -> str:
    """返回当前统计块，数字全部来自真实源码与生成物。"""
    source_files = len(list((LIB / "src").rglob("*.slang")))
    generated = list((ROOT / "shaders" / "omni-gfx").rglob("*.glsl"))
    generated_lines = sum(len(path.read_text(encoding="utf-8").splitlines()) for path in generated)
    total, migrated, mc, missing = _parity_counts()
    strict = _strict_counts()
    text = (
        f"当前统计：{len(catalog.MODULES)} 个模块、{source_files} 个 Slang 源文件、"
        f"{generated_lines} 行生成 GLSL；函数对照 {total} 个，已迁入 {migrated}、"
        f"MC 专用 {mc}、缺失 {missing}；严格对照 exact {strict['exact']}、"
        f"approximate {strict['approximate']}、reference_broken {strict['reference_broken']}、"
        f"mc_glue {strict['mc_glue']}、missing {strict['missing']}。"
    )
    return f"{BEGIN}\n{text}\n{END}"


def _replace_block(text: str, block: str) -> str:
    """替换标记之间的内容；没有标记时插入到第一个标题之后。"""
    if BEGIN in text and END in text:
        start = text.index(BEGIN)
        end = text.index(END) + len(END)
        return text[:start] + block + text[end:]
    lines = text.splitlines()
    insert = 1
    for index, line in enumerate(lines):
        if line.startswith("# "):
            insert = index + 1
            break
    return "\n".join(lines[:insert] + ["", block] + lines[insert:]) + "\n"


def write() -> None:
    """把统计块写入 README 与验证记录。"""
    block = render()
    for path in TARGETS:
        text = path.read_text(encoding="utf-8")
        path.write_text(_replace_block(text, block), encoding="utf-8", newline="\n")


def check() -> None:
    """确认两份文档里的统计块与当前源码一致。"""
    block = render()
    for path in TARGETS:
        text = path.read_text(encoding="utf-8")
        if block not in text:
            raise ValueError(f"{path.relative_to(ROOT)} 的当前统计已过期，请运行 stats")


if __name__ == "__main__":
    write()
    print(render())
