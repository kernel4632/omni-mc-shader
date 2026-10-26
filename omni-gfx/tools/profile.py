"""生成并编译两个严格 profile 的 GLSL 汇总文件。

调用位置：`python omni-gfx/build.py profiles`；修改生成模块或 profile 定义后重新运行。
产物：`omni-gfx/profiles/iterationt/profile.frag`、`omni-gfx/profiles/eclipse/profile.frag`
与各自 `profile.json`。两个文件都包含全部库模块，只由 profile 宏与严格函数集合区分。

为什么用汇总文件而不是让 glslang 直接读 `#include`：
    glslang 默认不启用 include 扩展，不同版本的 `-I` 行为也不一致。这里用与
    光影构建相同的递归展开规则，把每个模块只展开一次；产物因此是自包含的，
    可以直接交给任何 GLSL 编译器复核。

为什么两个 profile 要分开编译：
    Eclipse 与 iterationT 的大气、色调映射和云模型不是同一套算法。共用一个
    profile 时，同名函数只能保留一份，后编译的一方会覆盖前一方；分开后每个
    profile 都能保留自己的常数与采样顺序，差异不会被“合并”掉。
"""
from __future__ import annotations

import hashlib  # 记录输入与产物的摘要，判断是否需要重新编译。
import json  # 写 profile 元数据。
import re  # 解析 include 行。
import subprocess  # 调用 glslang 做编译验证。
import sys  # 缺编译器时以非零状态退出。
from pathlib import Path  # 统一路径。

LIB = Path(__file__).resolve().parent.parent  # omni-gfx 根目录。
ROOT = LIB.parent  # 仓库根目录。
SHADER_LIB = ROOT / "shaders" / "omni-gfx"  # 已生成的 GLSL。
PROFILE_DIR = LIB / "profiles"  # profile 输出目录。
INCLUDE = re.compile(r'^\s*#include\s+"([^"]+)"\s*$', re.MULTILINE)  # 光影根路径引用。

PROFILES = {
    "iterationt": {
        "macro": "OGX_PROFILE_ITERATIONT",
        "display": "iterationT 3.2.0 严格 profile",
        "probe": (
            "vec3 ogxProfileTone(vec3 color)\n"
            "{\n"
            "    return ogxAces(color, true) + ogxAgxConfigurable(color);\n"
            "}\n\n"
            "vec3 ogxProfileSurface()\n"
            "{\n"
            "    return ogxItxTextureLighting(vec3(0.5), 1.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0,\n"
            "        0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, vec3(1.0), 0, true);\n"
            "}\n"
        ),
    },
    "eclipse": {
        "macro": "OGX_PROFILE_ECLIPSE",
        "display": "Eclipse 严格 profile",
        "probe": (
            "vec3 ogxProfileTone(vec3 color)\n"
            "{\n"
            "    return ogxToneMapAgx(color) + ogxToneMapAgxMerlin(color) + ogxTonemapReinhardJodie(color);\n"
            "}\n\n"
            "vec3 ogxProfileSky()\n"
            "{\n"
            "    return ogxEclipseSkyDensity(7000.0, 6731e3, vec2(8.0e3, 1.2e3));\n"
            "}\n"
        ),
    },
}  # 两个 profile 的编译期开关与各自的代表性函数；两组函数不会互相混用。

MODULES = (
    "math", "color", "sampling", "noise", "atmosphere", "atmosphere_model",
    "cloud", "cloud_volume", "water", "fog", "fog_volume", "shadow", "gi",
    "reflection", "post", "antialias", "weather", "surface", "voxel",
    "upscale", "parallax", "planet", "accretion", "lpv",
)  # 与生成器模块表一致；顺序固定，展开结果可复现。


def _expand(name: str, stack: tuple[str, ...], seen: set[str]) -> str:
    """展开一个模块的全部库引用，同一个模块只输出一次。"""
    if name in seen:
        return ""
    if name in stack:
        raise ValueError("模块引用成环：" + " -> ".join((*stack, name)))
    path = SHADER_LIB / f"{name}.glsl"
    if not path.is_file():
        raise FileNotFoundError(f"缺少生成模块：{path.relative_to(ROOT)}")
    text = path.read_text(encoding="utf-8")
    seen.add(name)

    def replace(match: re.Match) -> str:
        reference = match.group(1)
        if reference.startswith("/omni-gfx/") and reference.endswith(".glsl"):
            return _expand(Path(reference).stem, (*stack, name), seen)
        raise ValueError(f"{name} 引用了非库文件：{reference}")

    return INCLUDE.sub(replace, text)


def profile_text(name: str, meta: dict) -> str:
    """拼出一个自包含的 fragment 源文件，保留全部中文说明。"""
    seen: set[str] = set()
    body = ""
    for module in MODULES:
        body += "\n" + _expand(module, (), seen)
    header = (
        "/*\n"
        f"生成文件：{meta['display']}。\n"
        "源文件是 omni-gfx 的生成模块与两个 profile 的严格函数集合，请勿手工修改。\n"
        "用途：不启动 Minecraft、不依赖具体引擎，验证两个 profile 的 GLSL 能独立编译。\n"
        "重新生成：python omni-gfx/build.py profiles\n"
        "*/\n"
        "#version 330 compatibility\n"
        f"#define {meta['macro']} 1\n"
    )
    tail = (
        "\n" + meta["probe"] +
        "\nvoid main()\n{\n"
        "    // 空入口只用于链接验证；函数体全部由编译器检查。\n"
        "    vec3 color = ogxProfileTone(vec3(0.18));\n"
        "    gl_FragColor = vec4(color, 1.0);\n"
        "}\n"
    )
    return header + body + tail


def compiler() -> Path | None:
    """返回本机 glslang 可执行文件；没有时返回 None，由调用方明确报错。"""
    candidates = (
        ROOT / ".dev" / "tools" / "glslang" / "bin" / "glslang.exe",
        ROOT / ".dev" / "tools" / "glslang" / "bin" / "glslang",
    )
    for path in candidates:
        if path.is_file():
            return path
    return None


def generate(compile_output: bool = True) -> dict:
    """写出两个 profile 并编译，返回机器可读摘要。"""
    PROFILE_DIR.mkdir(parents=True, exist_ok=True)
    validator = compiler()
    result = {"schemaVersion": 1, "profiles": {}}
    for name, meta in PROFILES.items():
        text = profile_text(name, meta)
        directory = PROFILE_DIR / name
        directory.mkdir(parents=True, exist_ok=True)
        shader = directory / "profile.frag"
        shader.write_text(text, encoding="utf-8", newline="\n")
        entry = {
            "package": "iterationT" if name == "iterationt" else "Eclipse",
            "macro": meta["macro"],
            "shader": shader.relative_to(ROOT).as_posix(),
            "sha256": hashlib.sha256(text.encode("utf-8")).hexdigest(),
            "lines": len(text.splitlines()),
            "compiled": False,
            "compiler": validator.name if validator else "",
        }
        if compile_output:
            if validator is None:
                sys.exit("缺少 glslang，无法编译 profile；请先运行 python dev.py setup --graphics")
            process = subprocess.run([str(validator), "-l", str(shader)], capture_output=True,
                                     text=True, encoding="utf-8", errors="replace")
            entry["compiled"] = process.returncode == 0
            entry["compilerOutput"] = (process.stdout + process.stderr).strip()[:4000]
            if process.returncode != 0:
                print(entry["compilerOutput"])
                sys.exit(f"profile 编译失败：{name}")
        result["profiles"][name] = entry
        (directory / "profile.json").write_text(
            json.dumps(entry, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    return result


def main() -> None:
    """命令行入口：生成、编译并打印一行结果。"""
    result = generate(True)
    for name, entry in result["profiles"].items():
        print(f"{name}: {entry['lines']} 行，编译 {'通过' if entry['compiled'] else '失败'}")


if __name__ == "__main__":
    main()
