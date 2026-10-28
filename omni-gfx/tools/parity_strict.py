"""生成严格函数对照，并把“同名但签名不同”的假 exact 拦下来。

调用位置：`python omni-gfx/build.py strict-parity`；修改参考包、库源码或
`strict_review.json` 后重新运行。产物是 `omni-gfx/tools/parity_report.json`
与 `docs/gfx-functions-strict.md`。
可复制示例：在仓库根目录执行 `python omni-gfx/build.py strict-parity`。

为什么不再只看名字：
    Eclipse 的 `circlemap` 返回二维向量，`circlemapL` 返回三维向量；旧台账把两者
    都指向 `ogxCircleMap`（返回二维）却写成 exact。现在 exact 必须同时满足：
        1. 返回类型、参数个数、参数类型与方向一致；
        2. 采样调用的次数与顺序一致；
        3. 参考用到的数值常数全部能在实现里找到。

为什么常数允许实现多出：
    宿主层函数会把参考里的全局量（时间、湿度、屏幕尺寸）改成显式参数。这些参数
    带进来的新常数不改变参考算式，因此宿主层允许“实现多出常数”，但参考常数一个
    都不能少。通用库函数仍要求两边常数完全一致。

为什么沿调用图收集：
    宿主层通常只写一行转发，算法在 `omni-gfx`。只看外层会把所有转发函数都判成
    “没有常数、没有采样”，反而制造假 exact。调用图把真正的算式算进来。

为什么先预处理：
    参考包用 `#if MC_VERSION >= 11605` 在两个贴图通道间二选一。不预处理会把两个
    分支的采样都算进去，得到虚假的采样数差异。默认配置取自参考包的设置文件与
    光影的 `profile.default`。
"""
from __future__ import annotations

import json  # 读写机器可读台账与报告。
import sys  # 校验失败时以非零状态退出。
from collections import defaultdict  # 按承接函数分组，检查多个参考函数指向同一实现。
from functools import lru_cache  # 同一份参考配置只解析一次，避免重复扫描整棵参考树。
from pathlib import Path  # 统一定位参考包与库源码。

ROOT = Path(__file__).resolve().parents[2]  # 仓库根目录。
LIB = ROOT / "omni-gfx"  # 通用库目录。
sys.path.insert(0, str(LIB / "tools"))
import parity  # 只复用“参考函数名单”的收集口径。
import signature  # 签名、常数、采样与调用图解析。

MAP = LIB / "tools" / "parity_map.json"  # 旧的承接表，仅作缺省目标参考。
REVIEW = LIB / "tools" / "strict_review.json"  # 人工严格结论。
REPORT = LIB / "tools" / "parity_report.json"  # 机器可读产物。
DOC = ROOT / "docs" / "gfx-functions-strict.md"  # 人类可读摘要。
VERSION = "11605"  # 默认按 1.16.5 以上的贴图布局预处理参考代码。

REFERENCE_ROOTS = {
    "iterationT": ROOT / "references/iterationT/shaders",
    "Eclipse": ROOT / "references/Eclipse/shaders",
}
IMPL_PATHS = sorted((ROOT / "shaders").rglob("*.glsl")) + sorted((LIB / "src").rglob("*.slang"))


def load_json(path: Path) -> dict:
    """读取 JSON，缺文件时给出明确路径，不返回空表。"""
    return json.loads(path.read_text(encoding="utf-8"))


REFERENCE_DEFINES: dict[str, dict[str, str]] = {}  # 默认宏表，供按条目切换参考配置时复用。


def reference_environment() -> tuple[dict, dict, dict]:
    """建立两份参考包的函数索引、常数表与预处理宏。

    返回 `(index, constants, defines)`；键是包名。索引按函数名分组，同名重载都保留。
    """
    index, constants, defines = {}, {}, {}
    for pack, root in REFERENCE_ROOTS.items():
        if not root.is_dir():
            raise FileNotFoundError(f"参考目录不存在：{root.relative_to(ROOT)}")  # 缺目录不能当成零函数。
        paths = sorted(root.rglob("*.glsl"))
        macro = signature.collect_defines(paths, {"MC_VERSION": VERSION})
        defines[pack] = macro
        active = signature.index_by_function_name(paths, macro)
        # 默认配置未启用的函数被预处理器整段删掉；再按“第一分支”解析一次，
        # 只补缺失的名字，活动函数仍使用默认配置，避免改变已有严格结论。
        raw = signature.index_by_function_name(paths, first_branch=True)
        for name, items in raw.items():
            if name not in active:
                active[name] = items
        index[pack] = active
        constants[pack] = signature.global_constant_table(paths, macro)
        raw_constants = signature.global_constant_table(paths)
        for name, value in raw_constants.items():
            constants[pack].setdefault(name, value)
    REFERENCE_DEFINES.clear()
    REFERENCE_DEFINES.update(defines)
    return index, constants, defines


@lru_cache(maxsize=None)
def reference_variant(pack: str, overrides_key: str) -> tuple[dict, dict]:
    """按一条台账给出的宏覆盖重新解析参考包。

    为什么需要：Eclipse 把体素反射整段放在默认关闭的 `#if` 里。`first_branch`
    会把互相矛盾的 `#ifdef` 与 `#else` 同时保留，得到参考里并不存在的采样次数。
    条目声明 `refDefines` 后，这里用同一份默认宏加上覆盖值重新预处理，只保留
    该功能实际启用的分支；常数表也按同一份宏解析，选项数值不会错位。
    """
    overrides = json.loads(overrides_key)
    macro = dict(REFERENCE_DEFINES[pack])
    macro.update({name: str(value) for name, value in overrides.items()})
    paths = sorted(REFERENCE_ROOTS[pack].rglob("*.glsl"))
    return (signature.index_by_function_name(paths, macro),
            signature.global_constant_table(paths, macro))


def implementation_environment() -> tuple[dict, dict, dict, dict]:
    """建立宿主层与通用库的索引、常数表、预处理宏和路径索引。

    宿主层优先使用 `shaders.properties` 的默认 profile；这样 `#ifdef OMNI_*`
    分支与玩家默认看到的画面一致。通用库没有预处理器，宏表只影响宿主层。
    """
    defines = signature.read_profile_defines(ROOT / "shaders/shaders.properties")
    defines["MC_VERSION"] = VERSION
    # 默认对照看主世界片元：这两个宏由加载器按程序注入，不在 profile 文本里。
    # 不补的话，宿主文件外层的 `#ifdef OMNI_OVERWORLD` 会把整段主世界算法裁掉，
    # 严格对照看到的是空函数，常数与采样全部误报为缺失。
    defines.setdefault("OMNI_OVERWORLD", "1")
    defines.setdefault("OMNI_FRAGMENT", "1")
    # 宿主里很多兼容重载写在 `#if defined OMNI_COMPOSITE3_PASS` 之类的程序分支内。
    # 对照要看到所有分支的实现，不能因为默认 profile 没写这些程序宏就当成缺失。
    for program in ("OMNI_COMPOSITE3_PASS", "OMNI_COMPOSITE4_PASS", "OMNI_COMPOSITE5_PASS",
                    "OMNI_COMPOSITE7_PASS", "OMNI_DEFERRED0_PASS", "OMNI_DEFERRED1_PASS",
                    "OMNI_FINAL_PASS", "OMNI_SHADOW_PASS", "OMNI_ENTITIES_PASS",
                    "OMNI_BLOCK_PASS", "OMNI_HAND_PASS", "OMNI_TRANSLUCENT_PASS",
                    "OMNI_TERRAIN_PASS", "OMNI_CLOUD_DENSITY_PASS", "OMNI_CLOUD_SHADOW_PASS"):
        defines.setdefault(program, "1")
    defines = signature.collect_defines(sorted((ROOT / "shaders").rglob("*.glsl")), defines)
    index = signature.index_by_function_name(IMPL_PATHS, defines)
    constants = signature.global_constant_table(IMPL_PATHS, defines)
    by_path = {}
    for group in index.values():
        for item in group:
            by_path[f"{item['path']}:{item['name']}"] = item
    return index, constants, defines, by_path


def signature_of(item: dict) -> tuple:
    """返回可比较的签名键：返回类型、参数方向与类型。"""
    return (item["return"], tuple((p["direction"], p["type"]) for p in item["params"]))


def pick_variant(refs: list[dict], candidates: list[dict]) -> tuple[dict, dict] | None:
    """在参考重载与实现重载中选一对签名相同的组合。"""
    for ref in refs:
        for candidate in candidates:
            if signature_of(ref) == signature_of(candidate):
                return ref, candidate
    return None


def pick_resource_variant(refs: list[dict], candidates: list[dict]) -> tuple[dict, dict] | None:
    """选一对“参考签名是前缀、实现尾部追加资源参数”的组合。

    为什么单独一条路径：参考函数经常不把阴影图、深度图或相机矩阵写进参数表，
    这些输入由宿主全局量提供。显式迁进库后实现签名会更长，但它仍然是同一个算法；
    只要参考参数逐项出现在最前面，尾部参数再由台账声明为资源，就可以继续严格核对。
    """
    for ref in refs:
        ref_params = [(p["direction"], p["type"]) for p in ref["params"]]
        for candidate in candidates:
            if candidate["return"] != ref["return"]:
                continue
            candidate_params = [(p["direction"], p["type"]) for p in candidate["params"]]
            if len(candidate_params) < len(ref_params):
                continue
            if candidate_params[:len(ref_params)] == ref_params:
                return ref, candidate
    return None


def resolve_implementation(name: str, refs: list[dict], entry: dict,
                           library: dict, path_index: dict, impl_index: dict) -> tuple[dict, dict, str] | None:
    """给一条参考记录选实现：优先台账目标，其次宿主层同名函数。

    返回 `(参考重载, 实现, 层名)`。层名用于决定常数是否允许实现多出。
    没有同签名候选时仍返回最接近的一对，让报告能写出具体差异，而不是只报“找不到”。
    台账声明资源参数时允许实现尾部追加显式资源参数。
    """
    target = entry.get("target", "")
    resources = entry.get("resources")
    picker = pick_resource_variant if resources is not None else pick_variant
    ledger = library.get(target) or library.get(target.split("#")[0]) or path_index.get(target)
    if ledger is None and ":" in target:
        ledger = next(iter(impl_index.get(target.rsplit(":", 1)[1], [])), None)
    if ledger is not None:
        pair = picker(refs, [ledger])
        if pair:
            return pair[0], pair[1], "library"
    pair = picker(refs, impl_index.get(name, []))
    if pair:
        return pair[0], pair[1], "host"
    if ledger is not None:
        return refs[0], ledger, "library"
    candidates = impl_index.get(name, [])
    if candidates:
        return refs[0], candidates[0], "host"
    return None


def build_records(review: dict, raw_rows: list[dict]) -> tuple[list[dict], list[str]]:
    """把参考函数、人工台账与自动核对合并成一条条记录。"""
    ref_index, ref_constants, _ = reference_environment()
    impl_index, impl_constants, impl_defines, path_index = implementation_environment()
    impl_structs = signature.struct_definitions(IMPL_PATHS, impl_defines)
    library = signature.function_index(sorted((LIB / "src").rglob("*.slang")), root=LIB / "src", strict=True)
    exact = review.get("exact", {})
    glue = review.get("mcGlue", {})
    broken = review.get("referenceBroken", {})
    approximate = review.get("approximate", {})
    missing = review.get("missing", {})
    errors: list[str] = []
    records = []
    shared_cache: dict = {}  # 无参考宏覆盖的条目共用调用图缓存；参考与实现的同名函数不会互相覆盖键。

    for row in raw_rows:
        name = row["name"]
        source = f"{row['path']}:{row['line']}"
        package = row["pack"]
        entry = exact.get(name) or broken.get(name) or {}
        overrides = entry.get("refDefines")
        overrides_key = json.dumps(overrides, sort_keys=True) if overrides else ""
        if name in broken:
            # 参考正文本身不能编译时不能伪造 exact。记录仍指向已迁移的实现，
            # 但状态单独列出，并在差异栏写明缺哪个声明或哪段被注释掉。
            record = base_record(row, source, "reference_broken", broken[name].get("target", ""),
                                 broken[name].get("evidence", "参考正文不能编译"), "")
            target = broken[name].get("target", "")
            ledger = library.get(target) or library.get(target.rsplit("#", 1)[0]) if target else None
            if ledger is None and target and ":" in target:
                ledger = next(iter(impl_index.get(target.rsplit(":", 1)[1], [])), None)
            if target and ledger is None:
                errors.append(f"{name} 的 referenceBroken 目标不存在：{target}")
            elif ledger is not None:
                record["currentImplementation"] = ledger["name"]
                record["implementationPath"] = ledger["path"].replace("\\", "/")
                record["implementationLine"] = ledger["line"]
                record["layer"] = "library"
                record["evidencePath"] = f"{source} -> {ledger['path'].replace(chr(92), '/')}:{ledger['line']}"
            records.append(record)
            continue
        refs = []
        # 条目可以声明参考宏覆盖，让默认关闭的功能按它自己的分支解析。没有覆盖时
        # 继续使用全局默认索引，已有结论不受影响。
        source_index = ref_index
        source_constants = ref_constants
        if overrides_key:
            variant_index, variant_constants = reference_variant(package, overrides_key)
            source_index = dict(ref_index)
            source_constants = dict(ref_constants)
            source_index[package] = variant_index
            source_constants[package] = variant_constants
        for pack in ("iterationT", "Eclipse"):
            for item in source_index[pack].get(name, []):
                item["pack"] = pack
                refs.append(item)
        if not refs:
            records.append(base_record(row, source, "mc_glue", "",
                                       "参考默认配置未启用该函数，不参与画面", "inactive"))
            continue
        if name in exact:
            resolved = resolve_implementation(name, refs, entry, library, path_index, impl_index)
            if resolved is None:
                records.append(base_record(row, source, "approximate", entry.get("target", ""),
                                           "找不到实现；台账目标不存在", ""))
                continue
            ref, impl, layer = resolved
            resources = entry.get("resources")
            bindings = entry.get("bindings") or {}
            allow_extra = (layer == "host" or bool(entry.get("adapter"))
                           or bool(entry.get("allowExtraConstants"))) \
                and "--strict-constants" not in sys.argv[1:]
            # 参考包有时在不同目录定义同名同签名的变体（例如 `luma` 的 601 标准与
            # 另一套权重）。实现只要与其中一个变体完全一致就算 exact，不能因为排序
            # 先读到另一个变体就误判。
            candidates = []
            for item in refs:
                item_params = [(p["direction"], p["type"]) for p in item["params"]]
                if resources is None:
                    if (item["return"], item_params) == (impl["return"],
                                                         [(p["direction"], p["type"]) for p in impl["params"]]):
                        candidates.append(item)
                elif item["return"] == impl["return"] and \
                        [(p["direction"], p["type"]) for p in impl["params"]][:len(item_params)] == item_params:
                    candidates.append(item)
            result = None
            best_ref = ref
            cache = shared_cache if not overrides_key else {}  # 参考宏覆盖的条目单独建缓存，避免分支串味。
            for candidate in candidates or [ref]:
                current = signature.compare(candidate, impl, source_constants[candidate["pack"]], impl_constants,
                                            impl_structs, source_index[candidate["pack"]], impl_index, allow_extra,
                                            resources, bindings, entry.get("resourceCalls"), cache)
                if result is None or len(current["issues"]) < len(result["issues"]):
                    result = current
                    best_ref = candidate
                if not current["issues"]:
                    break
            ref = best_ref
            status = "exact" if not result["issues"] else "approximate"
            difference = "none" if status == "exact" else "; ".join(result["issues"])
            records.append({
                "referenceFile": ref["path"].replace("\\", "/"),
                "referenceLine": ref["line"],
                "referenceFunction": name,
                "package": package,
                "profile": "iterationT" if package == "iterationT" else "Eclipse",
                "currentImplementation": impl["name"],
                "implementationPath": impl["path"].replace("\\", "/"),
                "implementationLine": impl["line"],
                "layer": layer,
                "status": status,
                "algorithm": True,
                "difference": difference,
                "evidencePath": f"{ref['path'].replace(chr(92), '/')}:{ref['line']} -> "
                                f"{impl['path'].replace(chr(92), '/')}:{impl['line']}",
                "referenceSignature": result["referenceSignature"],
                "implementationSignature": result["implementationSignature"],
                "referenceSamples": result["referenceSamples"],
                "implementationSamples": result["implementationSamples"],
                "missingConstants": result["missingNumbers"],
                "extraConstants": result["extraNumbers"],
                "resources": [{"name": name, "kind": kind} for name, kind in (resources or {}).items()],
                "resourceCalls": entry.get("resourceCalls") or {},
            })
            continue
        if name in glue:
            records.append(base_record(row, source, "mc_glue", "", glue[name].get("evidence", "host-only glue"),
                                       glue[name].get("category", "host")))
            continue
        if name in approximate:
            entry = approximate[name]
            record = base_record(row, source, "approximate", entry.get("target", ""),
                                 entry.get("difference", "known approximate replacement"), "")
            record["referenceSignature"] = entry.get("referenceSignature", "")
            record["implementationSignature"] = entry.get("implementationSignature", "")
            records.append(record)
            continue
        if name in missing:
            records.append(base_record(row, source, "missing", "", missing[name].get("evidence", "算法未迁移"), ""))
            continue
        records.append(base_record(row, source, "approximate", "",
                                   "没有同签名实现，旧承接表也没有给出可核对的目标", ""))
    return records, errors


def base_record(row: dict, source: str, status: str, target: str, difference: str, category: str) -> dict:
    """给非 exact 记录填统一字段，避免下游缺少键。"""
    return {
        "referenceFile": row["path"].replace("\\", "/"),
        "referenceLine": row["line"],
        "referenceFunction": row["name"],
        "package": row["pack"],
        "profile": "iterationT" if row["pack"] == "iterationT" else "Eclipse",
        "currentImplementation": target,
        "implementationPath": "",
        "implementationLine": 0,
        "layer": category,
        "status": status,
        "algorithm": status != "mc_glue",
        "difference": difference,
        "evidencePath": source,
        "referenceSignature": "",
        "implementationSignature": "",
        "referenceSamples": [],
        "implementationSamples": [],
        "missingConstants": [],
        "extraConstants": [],
        "resources": [],
    }


def check_single_target(records: list[dict]) -> list[str]:
    """多个参考函数指向同一实现时，只允许两者的参考函数体与签名完全相同。"""
    errors = []
    groups = defaultdict(list)
    for record in records:
        if record["status"] != "exact":
            continue
        key = f"{record['implementationPath']}:{record['implementationLine']}:{record['currentImplementation']}"
        groups[key].append(record)
    for key, group in groups.items():
        if len(group) < 2:
            continue
        # referenceSignature 里带函数名，同名不同大小写或别名会让字符串永远不同；
        # 这里只比较返回类型与参数表，名字不参与“是否同一份实现”的判断。
        signatures = {(record["referenceSignature"].split("(", 1)[0].split()[0],
                       record["referenceSignature"].split("(", 1)[1]) for record in group}
        if len(signatures) == 1:
            continue  # 同名同签名的真正别名可以共用一个实现。
        names = "、".join(r["referenceFunction"] for r in group)
        errors.append(f"多个参考函数共用 {key}：{names}")
    return errors


def summarize(records: list[dict]) -> dict:
    """按包与状态统计，给发布说明和缺口清单提供同一份数字。"""
    statuses = ("exact", "approximate", "reference_broken", "mc_glue", "missing")
    totals = {status: sum(1 for r in records if r["status"] == status) for status in statuses}
    by_package = {}
    for package in ("iterationT", "Eclipse"):
        subset = [r for r in records if r["package"] == package]
        by_package[package] = {status: sum(1 for r in subset if r["status"] == status)
                               for status in statuses}
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
        "`omni-gfx/tools/parity_report.json`。",
        "",
        "## 结论",
        "",
        f"- 参考函数共 {totals['referenceFunctions']} 个；算法函数 {totals['algorithmFunctions']} 个。",
        f"- exact：{totals['exact']} 个；approximate：{totals['approximate']} 个；"
        f"reference_broken：{totals['reference_broken']} 个；"
        f"mc_glue：{totals['mc_glue']} 个；missing：{totals['missing']} 个。",
        f"- exact 覆盖率（按算法函数）：{totals['exactCoverage'] * 100:.1f}%。",
        "",
        "| 参考包 | exact | approximate | reference_broken | mc_glue | missing |",
        "| --- | --- | --- | --- | --- | --- |",
    ]
    for package, counts in summary["byPackage"].items():
        lines.append(f"| {package} | {counts['exact']} | {counts['approximate']} | "
                     f"{counts['reference_broken']} | {counts['mc_glue']} | {counts['missing']} |")
    lines += ["", "## 未达 exact 的函数", "",
              "| 函数 | 包 | 状态 | 参考签名 | 当前承接 | 差异 |",
              "| --- | --- | --- | --- | --- | --- |"]
    for row in records:
        if row["status"] == "exact":
            continue
        target = f"`{row['currentImplementation']}`" if row["currentImplementation"] else "—"
        difference = row["difference"].replace("|", "\\|")
        lines.append(f"| `{row['referenceFunction']}` | {row['package']} | {row['status']} | "
                     f"`{row['referenceSignature'] or '—'}` | {target} | {difference} |")
    lines += ["", "## 判定口径", "",
              "- exact：返回类型、参数类型/方向、采样次数与顺序一致；参考常数全部命中。",
              "- 显式资源：参考签名是实现的参数前缀；尾部追加的纹理、矩阵、结构体或数值"
              "必须在台账声明、在函数体使用，纹理/矩阵类型要对得上。这样参考没带缓冲的"
              "算法仍能迁进通用库，而不是留在宿主胶水里。",
              "- 宿主层允许实现多出常数：显式化的时间、湿度、屏幕尺寸等参数会带入新常数；"
              "通用库仍要求常数集合完全一致，除非台账写明理由。",
              "- approximate：有承接实现，但签名、常数或采样存在差异。",
              "- reference_broken：参考正文依赖被注释掉的全局声明或缺失的包含文件，"
              "原文不能编译；实现按可执行语义迁移并记录编译证据，不能算 exact。",
              "- mc_glue：入口、标题、调试文字、群系表或默认配置未启用的宿主代码。",
              "- missing：既无承接实现，也无宿主理由。",
              "", "## 重新生成", "", "```text", "python omni-gfx/build.py strict-parity", "```", ""]
    return "\n".join(lines)


def main() -> None:
    """入口：读取台账、自动核对、写 JSON 与中文摘要并打印统计。

    `--report` 只生成报告，不因 exact 未通过而退出；用于生成待迁移清单。
    """
    report_only = "--report" in sys.argv[1:]
    review = load_json(REVIEW)
    raw_rows = parity.collect_reference()
    records, errors = build_records(review, raw_rows)
    errors.extend(check_single_target(records))
    summary = summarize(records)
    payload = {
        "schemaVersion": 3,
        "generatedBy": "omni-gfx/tools/parity_strict.py",
        "statusValues": ["exact", "approximate", "reference_broken", "mc_glue", "missing"],
        "summary": summary,
        "records": records,
    }
    REPORT.write_text(json.dumps(payload, ensure_ascii=True, indent=2) + "\n",
                      encoding="utf-8", newline="\n")
    DOC.write_text(render_doc(records, summary), encoding="utf-8", newline="\n")
    totals = summary["totals"]
    if errors and not report_only:
        sys.exit("严格对照未通过：\n" + "\n".join(errors[:40]))
    print(f"严格对照：{totals['referenceFunctions']} 个函数；exact {totals['exact']}，"
          f"approximate {totals['approximate']}，reference_broken {totals['reference_broken']}，"
          f"mc_glue {totals['mc_glue']}，missing {totals['missing']}；产物 {REPORT.relative_to(ROOT)}")
    if errors:
        print("未通过的 exact 条目：\n" + "\n".join(errors[:20]))


if __name__ == "__main__":
    main()
