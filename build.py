"""光影构建：生成菜单、检查代码、打包和同步到独立游戏实例。

命令示例：python build.py check；python build.py build；python build.py sync。
所有位置相对本文件，换工作目录执行不会创建第二份项目数据。
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

import options as menu

ROOT = Path(__file__).resolve().parent
SHADERS = ROOT / "shaders"
INCLUDE = re.compile(r'^[ \t]*#include[ \t]+"([^"\n]+)"[ \t]*$', re.MULTILINE)
STAGES = {".vsh": ".vert", ".fsh": ".frag", ".gsh": ".geom", ".csh": ".comp"}


def version(root: Path = ROOT) -> str:
    """读取并检查唯一版本来源，拒绝不能用于文件名或标签的值。"""
    value = (root / "VERSION").read_text(encoding="utf-8").strip()
    if not re.fullmatch(r"(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)(?:-(?:dev|alpha|beta|rc)\.(?:0|[1-9]\d*))?", value):
        raise ValueError("VERSION 必须是 x.y.z 或 x.y.z-dev.N 等版本号")
    return value


def validate_tag(tag: str, root: Path = ROOT) -> None:
    """发布前检查标签与 VERSION 一致，避免发布错版本。"""
    if tag != "v" + version(root):
        raise ValueError(f"发布标签 {tag!r} 与 VERSION 不一致")


def tool(name: str) -> Path:
    """寻找项目内已安装的检查器；缺失时给出准备命令。"""
    names = {"glslang": ("glslangValidator", "glslang"), "actionlint": ("actionlint",)}
    folder = ROOT / ".dev/tools" / name
    for base in names[name]:
        matches = sorted(folder.rglob(base + (".exe" if sys.platform == "win32" else "")))
        if matches:
            return matches[0]
    raise ValueError(f"缺少项目内 {name}，请执行 python dev.py setup")


def source_path(reference: str, parent: Path, shaders: Path) -> Path:
    """在引用边界检查路径，禁止跨出光影目录或引用不存在的文件。"""
    if "\\" in reference or "\x00" in reference:
        raise ValueError(f"{parent}：引用必须使用正斜杠")
    source = ((shaders / reference[1:]) if reference.startswith("/")
              else parent.parent / reference).resolve()
    if not source.is_relative_to(shaders.resolve()) or not source.is_file():
        raise ValueError(f"{parent}：引用越界或文件不存在：{reference}")
    return source


def expand(source: Path, shaders: Path = SHADERS, stack: tuple[Path, ...] = ()) -> str:
    """展开加载器风格的 include，显式检查循环，供离线编译与显卡测试使用。"""
    source = source.resolve()
    if source in stack:
        raise ValueError("循环引用：" + " → ".join(path.name for path in (*stack, source)))
    text = source.read_text(encoding="utf-8")
    # 注释中的示例不属于真实引用，先屏蔽块注释，保留换行便于对应原文。
    masked = re.sub(r"/\*.*?\*/", lambda match: "".join(
        "\n" if character == "\n" else " " for character in match[0]), text, flags=re.DOTALL)
    for line in masked.splitlines():
        if re.match(r"\s*#include\b", line) and not INCLUDE.fullmatch(line):
            raise ValueError(f"{source}：#include 行只保留引用，说明放到上一行以兼容 Iris")
    for match in reversed(list(INCLUDE.finditer(masked))):
        included = source_path(match[1], source, shaders)
        content = expand(included, shaders, (*stack, source))
        if re.search(r"^\s*#version", content, re.MULTILINE):
            raise ValueError(f"{included}：被引用文件不能再次声明 #version")
        text = text[:match.start()] + content.rstrip() + text[match.end():]
    return text


def entrypoints(shaders: Path = SHADERS) -> list[Path]:
    """检查可执行入口配对，返回加载器识别的程序。"""
    entries = sorted(path for path in shaders.rglob("*") if path.suffix in STAGES)
    if not entries:
        raise ValueError("光影包至少需要一组可执行入口")
    for source in entries:
        text = source.read_text(encoding="utf-8")
        if not text.startswith("#version "):
            raise ValueError(f"{source}：#version 必须放第一行")
        partner = {".vsh": ".fsh", ".fsh": ".vsh", ".gsh": ".vsh"}.get(source.suffix)
        if partner and not source.with_suffix(partner).is_file():
            raise ValueError(f"{source}：缺少配对入口 {partner}")
        expand(source, shaders)  # 入口检查时就验证全部实际引用。
    return entries


def configuration() -> tuple[dict, list, dict]:
    """读取效果和共享预设，返回生成产物，供全部命令共用。"""
    options, groups = menu.scan(SHADERS)
    profiles = menu.presets(ROOT / "presets", options)
    return options, profiles, menu.generated(SHADERS, options, groups, profiles)


def generate() -> None:
    """更新菜单与翻译，只在内容改变时写入，避免触发无意义的重载。"""
    _, _, files = configuration()
    for path, content in files.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        if not path.exists() or path.read_text(encoding="utf-8") != content:
            path.write_text(content, encoding="utf-8", newline="\n")


def option_source(text: str, options: dict, values: dict[str, str]) -> str:
    """为一个已检查的预设替换原生定义，保留其余源代码不变。"""
    result = []
    for line in text.splitlines():
        definition = menu.DEFINE.fullmatch(line)
        if definition and definition[2] in options:
            name = definition[2]
            value = values[name]
            if options[name].values == ("false", "true"):
                line = ("#define " if value == "true" else "//#define ") + name
            else:
                line = f"#define {name} {value}"
        result.append(line)
    return "\n".join(result) + "\n"


def variants(options: dict, profiles: list) -> list[tuple[str, dict]]:
    """检查默认值、预设和各选项的单独取值；不声称穷举所有组合。"""
    defaults = {name: option.default for name, option in options.items()}
    candidates = [("default", defaults)] + [(preset.name, preset.values) for preset in profiles]
    for name, option in options.items():
        for value in option.values:
            candidates.append((f"{name}_{value}", defaults | {name: value}))
    result, seen = [], set()
    for label, values in candidates:
        signature = tuple(sorted(values.items()))
        if signature not in seen:
            seen.add(signature)
            result.append((label, values))
    return result


def compile_shaders(entries: list[Path], options: dict, profiles: list) -> None:
    """用 glslang 编译并链接各组入口，失败时保留检查器原始原因。"""
    validator = tool("glslang")
    expanded = {source: expand(source) for source in entries}
    for name in options:
        if not any(re.search(r"^\s*#define\s+" + re.escape(name) + r"\b|^\s*//\s*#define\s+" + re.escape(name) + r"\b", text, re.MULTILINE)
                   for text in expanded.values()):
            raise ValueError(f"选项 {name} 没有接入任何实际入口，加载器无法显示")
    with tempfile.TemporaryDirectory(prefix="omni-glsl-") as temporary:
        folder = Path(temporary)
        for label, values in variants(options, profiles):
            programs: dict[Path, list[Path]] = {}
            for source, text in expanded.items():
                relative = source.relative_to(SHADERS)
                target = folder / relative.with_suffix(STAGES[source.suffix])
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(option_source(text, options, values), encoding="utf-8")
                programs.setdefault(relative.with_suffix(""), []).append(target)
            for program, sources in programs.items():
                result = subprocess.run([str(validator), "-l", *map(str, sources)],
                                        capture_output=True, text=True, encoding="utf-8", errors="replace")
                if result.returncode:
                    raise ValueError(f"GLSL 编译/链接失败：{program} / {label}\n{result.stdout}{result.stderr}")
    print(f"GLSL 编译与链接通过：{len(variants(options, profiles))} 种配置")


def check() -> None:
    """验证版本、入口、选项、预设、生成文件及工作流，失败直接中止。"""
    version()
    entries = entrypoints()
    options, profiles, files = configuration()
    for path, expected in files.items():
        if not path.exists() or path.read_text(encoding="utf-8") != expected:
            raise ValueError(f"{path.relative_to(ROOT)} 未生成或已过期，请运行 python build.py generate")
    # 占位文件也检查引用，防止未接入的文件长期积累失效路径。
    for source in SHADERS.rglob("*.glsl"):
        expand(source)
    compile_shaders(entries, options, profiles)
    result = subprocess.run([str(tool("actionlint")), "-shellcheck=", "-pyflakes=",
                             *map(str, sorted((ROOT / ".github/workflows").glob("*.yml")))],
                            cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace")
    if result.returncode:
        raise ValueError(f"GitHub 工作流检查失败\n{result.stdout}{result.stderr}")
    print(f"检查通过：{len(entries)} 个入口，{len(options)} 个选项，{len(profiles)} 套预设")


def archive(path: Path, files: dict[str, bytes]) -> None:
    """生成顺序和时间戳固定的 ZIP，让相同源码产生相同校验值。"""
    path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as output:
        for name, content in sorted(files.items()):
            info = zipfile.ZipInfo(name, date_time=(2020, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            output.writestr(info, content)


def pack() -> list[Path]:
    """只打包游戏资源和生成产物，预设另外打包，避免带入开发环境。"""
    release = version()
    options, profiles, _ = configuration()
    files = {"shaders/" + path.relative_to(SHADERS).as_posix(): path.read_bytes()
             for path in SHADERS.rglob("*") if path.is_file() and
             path.suffix in {*STAGES, ".glsl", ".properties", ".lang", ".png", ".bin"}}
    files.pop("shaders/rendering/pipeline.properties", None)  # 加载器设置已合并到产物。
    files["VERSION"] = (release + "\n").encode()
    output = ROOT / "dist" / f"Omni-{release}.zip"
    archive(output, files)
    presets = {f"{preset.name}.properties": ("\n".join(f"{key}={value}" for key, value in
               preset.values.items()) + "\n").encode("ascii") for preset in profiles}
    presets["manifest.json"] = (json.dumps({"schemaVersion": 1, "shaderVersion": release,
                                            "presets": [preset.name for preset in profiles]},
                                           ensure_ascii=False, indent=2) + "\n").encode()
    presets["README.md"] = (ROOT / "presets/README.md").read_bytes()
    preset_output = ROOT / "dist" / f"Omni-presets-{release}.zip"
    archive(preset_output, presets)
    sums = ROOT / "dist/SHA256SUMS.txt"
    sums.write_text("".join(f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.name}\n"
                            for path in (output, preset_output)), encoding="ascii", newline="\n")
    return [output, preset_output, sums]


def sync() -> None:
    """同步当前构建到项目内调试实例，只覆盖工具自己管理的光影包。"""
    destination = ROOT / ".dev/minecraft/shaderpacks/Omni-dev.zip"
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(pack()[0], destination)
    print("已同步 .dev/minecraft/shaderpacks/Omni-dev.zip，在游戏中按重载键更新")


def main() -> None:
    """处理命令参数，并在唯一入口报告可读错误。"""
    parser = argparse.ArgumentParser(description="Omni 光影构建与检查")
    parser.add_argument("command", choices=("generate", "check", "build", "sync", "version"))
    parser.add_argument("--tag", help="检查发布标签是否与 VERSION 一致")
    args = parser.parse_args()
    if args.tag:
        validate_tag(args.tag)
    if args.command == "version":
        print(version())
        return
    if args.command == "generate":
        generate()
        print("选项菜单和翻译已生成")
        return
    if args.command == "check":
        check()
        return
    generate()
    check()
    if args.command == "sync":
        sync()
    else:
        for path in pack():
            print(path.relative_to(ROOT))


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
    try:
        main()
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        print(f"错误：{error}", file=sys.stderr)
        sys.exit(1)
