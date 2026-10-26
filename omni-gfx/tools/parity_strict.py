"""生成严格函数对照的机器可读 JSON，并暴露仍未逐行核对的算法。

调用位置：`python omni-gfx/build.py strict-parity`；修改参考包、库源码或
`strict_review.json` 后重新运行。产物是 `omni-gfx/tools/parity_report.json`
与 `docs/gfx-functions-strict.md`。

为什么不能只看名字：
    同名函数可能只是同一家族。例如 Eclipse 的 `ToneMap_AgX_minimal_merlin`
    与库里的 `ogxAgx` 都叫 AgX，但动态范围端点和 `agxLook` 不同；把两者写成
    exact 会让后续审查误以为颜色空间一致。因此严格结论只来自人工 ledger，
    代码只负责校验目标存在、拼出证据行号并统计。

为什么默认不是 exact：
    `parity_map.json` 的旧条目回答“由谁承接”，不回答“常数与采样顺序是否一致”。
    没写进 `strict_review.json` 的映射一律先记为 approximate，避免把旧覆盖表
    直接升级成严格结论。真正核对过的一对才写进 exact。

为什么 mc_glue 要单独列：
    菜单、属性表、实体编号与坐标约定不是算法，允许留在 Minecraft 侧；但它们
    必须逐条写明理由。剩下的未映射函数默认记 missing，进入缺口清单。
"""
from __future__ import annotations

import json  # 读写机器可读对照。
import re  # 从函数体里统计采样次数，作为差异说明的一部分。
import sys  # 目标不存在时以非零状态退出。
from pathlib import Path  # 统一定位参考包与库源码。

ROOT = Path(__file__).resolve().parents[2]  # 仓库根目录。
LIB = ROOT / "omni-gfx"  # 通用库目录。
sys.path.insert(0, str(LIB / "tools"))  # 复用同名解析器，不复制括号匹配代码。
import parity  # 参考包与库共用的函数解析器。
MAP = LIB / "tools" / "parity_map.json"  # 旧的承接表。
REVIEW = LIB / "tools" / "strict_review.json"  # 严格结论。
REPORT = LIB / "tools" / "parity_report.json"  # 机器可读产物。
DOC = ROOT / "docs" / "gfx-functions-strict.md"  # 人类可读摘要。

SAMPLE = re.compile(r"\b(?:texture|textureLod|textureGrad|texelFetch|texture2D|texture3D|"
                    r"SampleLevel|SampleGrad|Load|SampleCmpLevelZero)\b")  # 采样调用计数口径。


def load_json(path: Path) -> dict:
    """读取 JSON，缺文件时给出明确路径，不返回空表。"""
    return json.loads(path.read_text(encoding="utf-8"))


def function_index() -> dict[str, dict]:
    """返回 `模块.函数` 到源码位置的索引，用来校验人工目标真实存在。"""
    index = {}
    for path in sorted((LIB / "src").glob("*.slang")):
        for item in parity.parse_functions(path):
            index[f"{path.stem}.{item['name']}"] = {
                "path": path.relative_to(ROOT).as_posix(),
                "line": item["line"],
            }
    return index


def reference_rows() -> list[dict]:
    """收集两份参考包的函数，同名跨包只保留第一次出现，统计口径与旧表一致。"""
    mapping = load_json(MAP)
    index = parity.library_index()
    rows = parity.collect_reference()
    parity.classify(rows, index, mapping)
    return rows


def build_records(rows: list[dict], library: dict[str, dict], review: dict) -> tuple[list[dict], list[str]]:
    """把参考函数、旧承接表与人工严格结论合并成一条条记录。"""
    exact = review.get("exact", {})
    glue = review.get("mcGlue", {})
    approximate = review.get("approximate", {})
    missing = review.get("missing", {})
    errors = []
    records = []
    for row in rows:
        name = row["name"]
        source = f"{row['path']}:{row['line']}"
        target = row["target"]
        status = "approximate"
        difference = "not reviewed line by line; old map only records the receiving function"
        evidence = source
        if name in exact:
            entry = exact[name]
            target = entry.get("target", target)
            status = "exact"
            difference = entry.get("difference", "none")
        elif name in glue:
            target = ""
            status = "mc_glue"
            difference = glue[name].get("evidence", "host-only glue")
        elif name in approximate:
            entry = approximate[name]
            target = entry.get("target", target)
            status = "approximate"
            difference = entry.get("difference", "known approximate replacement")
        elif name in missing:
            target = ""
            status = "missing"
            difference = missing[name].get("evidence", "algorithm not migrated")
        elif not target:
            status = "missing"
            difference = "no receiving function and no glue justification"
        if target:
            if target not in library:
                errors.append(f"{name} -> {target}")
                continue
            evidence = f"{source} -> {library[target]['path']}:{library[target]['line']}"
        records.append({
            "referenceFile": row["path"],
            "referenceLine": row["line"],
            "referenceFunction": name,
            "package": row["pack"],
            "profile": "iterationT" if row["pack"] == "iterationT" else "Eclipse",
            "currentImplementation": target,
            "status": status,
            "algorithm": status != "mc_glue",
            "difference": difference,
            "evidencePath": evidence,
            "referenceSamples": len(SAMPLE.findall(row["body"])),
        })
    return records, errors


def summarize(records: list[dict]) -> dict:
    """按包与状态统计，给发布说明和缺口清单提供同一份数字。"""
    statuses = ("exact", "approximate", "mc_glue", "missing")
    totals = {status: sum(1 for r in records if r["status"] == status) for status in statuses}
    by_package = {}
    for package in ("iterationT", "Eclipse"):
        subset = [r for r in records if r["package"] == package]
        by_package[package] = {
            status: sum(1 for r in subset if r["status"] == status) for status in statuses
        }
        by_package[package]["total"] = len(subset)
    algorithm = [r for r in records if r["algorithm"]]
    totals["referenceFunctions"] = len(records)
    totals["algorithmFunctions"] = len(algorithm)
    totals["exactCoverage"] = round(totals["exact"] / max(1, len(algorithm)), 4)
    return {"totals": totals, "byPackage": by_package}


def render_doc(records: list[dict], summary: dict) -> str:
    """写中文摘要；明细只列非 exact，避免把已核对结果重复成噪声。"""
    totals = summary["totals"]
    lines = [
        "# 严格函数对照：iterationT、Eclipse 与 omni-gfx",
        "",
        "本文件由 `python omni-gfx/build.py strict-parity` 生成。机器可读版本在",
        "`omni-gfx/tools/parity_report.json`，字段名固定为 ASCII。",
        "",
        "## 结论",
        "",
        f"- 参考函数共 {totals['referenceFunctions']} 个；算法函数 {totals['algorithmFunctions']} 个。",
        f"- exact：{totals['exact']} 个；approximate：{totals['approximate']} 个；"
        f"mc_glue：{totals['mc_glue']} 个；missing：{totals['missing']} 个。",
        f"- exact 覆盖率（按算法函数）：{totals['exactCoverage'] * 100:.1f}%。",
        "",
        "| 参考包 | exact | approximate | mc_glue | missing |",
        "| --- | --- | --- | --- | --- |",
    ]
    for package, counts in summary["byPackage"].items():
        lines.append(f"| {package} | {counts['exact']} | {counts['approximate']} | "
                     f"{counts['mc_glue']} | {counts['missing']} |")
    lines += ["", "## 未达 exact 的函数", "", "| 函数 | 包 | 状态 | 当前承接 | 差异 | 证据 |",
              "| --- | --- | --- | --- | --- | --- |"]
    for row in records:
        if row["status"] == "exact":
            continue
        target = f"`{row['currentImplementation']}`" if row["currentImplementation"] else "—"
        difference = row["difference"].replace("|", "\\|")
        evidence = row["evidencePath"]
        lines.append(f"| `{row['referenceFunction']}` | {row['package']} | {row['status']} | "
                     f"{target} | {difference} | `{evidence}` |")
    lines += ["", "## 重新生成", "", "```text", "python omni-gfx/build.py strict-parity", "```", ""]
    return "\n".join(lines)


def main() -> None:
    """入口：读取三份数据、校验目标、写 JSON 与中文摘要并打印统计。"""
    review = load_json(REVIEW)
    library = function_index()
    rows = reference_rows()
    records, errors = build_records(rows, library, review)
    if errors:
        sys.exit("严格对照指向不存在的函数：\n" + "\n".join(errors))
    summary = summarize(records)
    payload = {
        "schemaVersion": 1,
        "generatedBy": "omni-gfx/tools/parity_strict.py",
        "statusValues": ["exact", "approximate", "mc_glue", "missing"],
        "summary": summary,
        "records": records,
    }
    REPORT.write_text(json.dumps(payload, ensure_ascii=True, indent=2) + "\n",
                      encoding="utf-8", newline="\n")
    DOC.write_text(render_doc(records, summary), encoding="utf-8", newline="\n")
    totals = summary["totals"]
    print(f"严格对照：{totals['referenceFunctions']} 个函数；exact {totals['exact']}，"
          f"approximate {totals['approximate']}，mc_glue {totals['mc_glue']}，"
          f"missing {totals['missing']}；产物 {REPORT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
