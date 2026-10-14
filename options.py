"""选项与预设：读取效果旁的说明，生成加载器菜单和翻译。

由 build.py 调用。示例：options, groups = scan(Path('shaders'))。
默认值和范围只读取原生 #define，不在工具中另存一份。
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass
from pathlib import Path

LOCALES = ("zh_cn", "en_us")
NAME = re.compile(r"[A-Z][A-Z0-9_]*\Z")
NUMBER = re.compile(r"-?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?\Z")
DEFINE = re.compile(r"\s*(//\s*)?#define\s+(\w+)(?:\s+([^/\s]+))?\s*(?://\s*\[([^]]+)\])?\s*$")


@dataclass(frozen=True)
class Option:
    """已检查的游戏选项，source 指向唯一的原生定义。"""

    name: str
    default: str
    values: tuple[str, ...]
    label: dict[str, str]
    description: dict[str, str]
    slider: bool
    group: str
    source: Path
    line: int


@dataclass(frozen=True)
class Preset:
    """已检查的共享配置，文件名决定菜单中的预设名称。"""

    name: str
    label: dict[str, str]
    values: dict[str, str]


def metadata(text: str, location: str, allowed: set[str]) -> dict:
    """检查外部说明的字段与翻译，错误直接指出位置。"""
    data = json.loads(text)
    if not isinstance(data, dict) or set(data) - allowed:
        raise ValueError(f"{location}：说明必须是对象，且只能含 {sorted(allowed)}")
    for field in ("label", "description"):
        if field not in data and field == "description":
            continue
        translations = data.get(field)
        if not isinstance(translations, dict) or set(translations) != set(LOCALES):
            raise ValueError(f"{location}：{field} 必须同时提供 zh_cn 和 en_us")
        if any(not isinstance(value, str) or not value.strip() or "\n" in value
               or "\r" in value for value in translations.values()):
            raise ValueError(f"{location}：翻译必须是非空单行文字")
    if "slider" in data and not isinstance(data["slider"], bool):
        raise ValueError(f"{location}：slider 必须为 true 或 false")
    return data


def scan(shaders: Path) -> tuple[dict[str, Option], dict[str, dict[str, str]]]:
    """扫描效果文件的相邻说明和定义，返回选项与菜单分组。"""
    options: dict[str, Option] = {}
    groups: dict[str, dict[str, str]] = {}
    for source in sorted((shaders / "effects").rglob("*.glsl")):
        group = source.relative_to(shaders / "effects").parts[0].removesuffix(".glsl")
        if not re.fullmatch(r"[a-z][a-z0-9_]*", group):
            raise ValueError(f"{source}：效果名称只能使用小写英文、数字和下划线")
        lines = source.read_text(encoding="utf-8").splitlines()
        for index, line in enumerate(lines):
            stripped = line.strip()
            if stripped.startswith("// @effect "):
                data = metadata(stripped.removeprefix("// @effect "), str(source), {"label"})
                if group in groups and groups[group] != data["label"]:
                    raise ValueError(f"{source}：同一效果出现不同菜单名称")
                groups[group] = data["label"]
            if not stripped.startswith("// @option "):
                continue
            location = f"{source}:{index + 1}"
            data = metadata(stripped.removeprefix("// @option "), location,
                            {"label", "description", "slider"})
            definition = DEFINE.fullmatch(lines[index + 1]) if index + 1 < len(lines) else None
            if definition is None:
                raise ValueError(f"{location}：@option 下一行必须是原生 #define 选项")
            commented, name, default, values = definition.groups()
            if not NAME.fullmatch(name) or name in options:
                raise ValueError(f"{location}：选项名称无效或重复：{name}")
            choices = tuple(values.split()) if values else ("false", "true")
            if default is None:
                default = "false" if commented else "true"  # 原生布尔开关支持注释默认关闭。
                if values or data.get("slider", False):
                    raise ValueError(f"{location}：布尔开关不能声明数值范围或滑块")
            elif commented or not values or not all(NUMBER.fullmatch(v) for v in choices):
                raise ValueError(f"{location}：数值选项必须启用定义并提供数字范围")
            if default not in choices or len(set(choices)) != len(choices):
                raise ValueError(f"{location}：默认值不在范围内，或范围含重复值")
            options[name] = Option(name, default, choices, data["label"],
                                   data.get("description", {}), data.get("slider", False),
                                   group, source, index + 2)
    for option in options.values():
        if option.group not in groups:
            raise ValueError(f"{option.source}：有选项的效果需要 // @effect 菜单名称")
    return options, groups


def read_properties(source: Path) -> dict[str, str]:
    """读取项目的单行 properties 子集，拒绝重复键和含糊的续行。"""
    result = {}
    for index, line in enumerate(source.read_text(encoding="utf-8").splitlines(), 1):
        stripped = line.strip()
        if not stripped or stripped.startswith(("#", "!")):
            continue
        key, separator, value = stripped.partition("=")
        key, value = key.strip(), value.strip()
        if not separator or not key or key in result or stripped.endswith("\\"):
            raise ValueError(f"{source}:{index}：需要唯一的单行 key=value")
        result[key] = value
    return result


def presets(folder: Path, options: dict[str, Option]) -> list[Preset]:
    """自动收集预设，将未指定的选项补成默认值，并检查所有取值。"""
    result = []
    for source in sorted(folder.glob("*.properties")):
        if not re.fullmatch(r"[a-z][a-z0-9_]*", source.stem):
            raise ValueError(f"{source}：预设名称只能使用小写英文、数字和下划线")
        labels = [line.removeprefix("# @preset ") for line in
                  source.read_text(encoding="utf-8").splitlines() if line.startswith("# @preset ")]
        if len(labels) != 1:
            raise ValueError(f"{source}：需要一条 # @preset 菜单说明")
        label = metadata(labels[0], str(source), {"label"})["label"]
        changes = read_properties(source)
        for name, value in changes.items():
            if name not in options or value not in options[name].values:
                raise ValueError(f"{source}：未知选项或无效取值：{name}={value}")
        values = {name: changes.get(name, option.default) for name, option in options.items()}
        result.append(Preset(source.stem, label, values))
    return result


def profile_values(values: dict[str, str], options: dict[str, Option]) -> str:
    """将检查后的预设值写成加载器原生的 profile 设置。"""
    entries = []
    for name, value in values.items():
        if options[name].values == ("false", "true"):
            entries.append(name if value == "true" else "!" + name)
        else:
            entries.append(f"{name}={value}")
    return " ".join(entries)


def generated(shaders: Path, options: dict[str, Option], groups: dict,
              profiles: list[Preset]) -> dict[Path, str]:
    """从唯一来源生成菜单和翻译，返回文件内容，供检查或写入。"""
    pipeline = shaders / "rendering/pipeline.properties"
    settings = read_properties(pipeline)
    if any(key == "sliders" or key.startswith(("screen", "profile.")) for key in settings):
        raise ValueError(f"{pipeline}：菜单、滑块和预设由工具生成，不能重复维护")
    lines = ["# Generated by build.py; edit effects/, presets/ or rendering/pipeline.properties.",
             *(f"{key} = {value}" for key, value in settings.items()), "",
             "screen = " + " ".join((["<profile>"] if profiles else []) +
                                    [f"[{group.upper()}]" for group in sorted(groups)])]
    for group in sorted(groups):
        lines.append(f"screen.{group.upper()} = " + " ".join(
            option.name for option in options.values() if option.group == group))
    sliders = [option.name for option in options.values() if option.slider]
    if sliders:
        lines.append("sliders = " + " ".join(sliders))
    for preset in profiles:
        lines.append(f"profile.{preset.name} = {profile_values(preset.values, options)}")
    files = {shaders / "shaders.properties": "\n".join(lines) + "\n"}
    for locale in LOCALES:
        translations = ["# Generated by build.py; translations live beside effects and presets."]
        for group in sorted(groups):
            translations.append(f"screen.{group.upper()}={escape(groups[group][locale])}")
        for option in options.values():
            translations.append(f"option.{option.name}={escape(option.label[locale])}")
            if option.description:
                translations.append(f"option.{option.name}.comment={escape(option.description[locale])}")
        for preset in profiles:
            translations.append(f"profile.{preset.name}={escape(preset.label[locale])}")
        files[shaders / "lang" / f"{locale}.lang"] = "\n".join(translations) + "\n"
    return files


def escape(text: str) -> str:
    """转义 properties 的特殊字符，并以 Unicode 转义保持加载器编码兼容。"""
    text = text.replace("\\", "\\\\").replace("=", "\\=").replace(":", "\\:")
    return text.encode("ascii", "backslashreplace").decode("ascii")
