"""选项与预设：读取效果旁的说明，生成加载器菜单和翻译。

由 build.py 调用。示例：options, groups = scan(Path('shaders'))。
默认值和范围只读取原生 #define，不在工具中另存一份。
"""

from __future__ import annotations

import argparse  # 配置分享命令入口。
import json  # 读取受控配置与机器说明。
import os  # 规范化Windows短路径和长路径表示。
import re  # 检查选项名称与数值格式。
import sys  # 唯一入口报告错误。
from dataclasses import dataclass  # 保存已检查的选项数据。
from pathlib import Path  # 所有用户输出限制在开发目录。

LOCALES = ("zh_cn", "en_us")  # 菜单同时支持中文与英文玩家。
SHARE_SCHEMA = 2  # JSON分享与打包清单共用这一个格式版本。
LEGACY_VERSION = "0.0.0-dev.3"  # 旧配置格式只描述效果开发前的调试选项。
NAME = re.compile(r"[A-Z][A-Z0-9_]*\Z")  # 接口名称保持加载器可识别。
NUMBER = re.compile(r"-?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?\Z")  # 原生数值范围不允许任意表达式。
DEFINE = re.compile(r"\s*(//\s*)?#define\s+(\w+)(?:\s+([^/\s]+))?\s*(?://\s*\[([^]]+)\])?\s*$")
CONST = re.compile(r"\s*const\s+(int|float)\s+(\w+)\s*=\s*([^;\s]+)\s*;\s*//\s*\[([^]]+)\]\s*$")  # Iris原生常量菜单需要字面量范围。
CONST_OPTIONS = {"shadowMapResolution":"int","shadowDistance":"float"}  # 名称来自Iris源码白名单。
OPTION_RENAMES = {"OMNI_SHADOW_RESOLUTION":"shadowMapResolution","OMNI_SHADOW_DISTANCE":"shadowDistance"}  # 迁移旧配置名。

def unique_object(pairs: list[tuple]) -> dict:
    """拒绝分享文件与菜单说明中的重复键，避免不同读取器得到不同配置。"""
    result = {}  # 输入对象不允许后值覆盖前值。
    for name,value in pairs:
        if name in result: raise ValueError(f"重复配置字段：{name}")  # 重复值必须由分享者明确修正。
        result[name] = value  # 检查后下游信任唯一键。
    return result


@dataclass(frozen=True)
class Option:
    """已检查的游戏选项，source 指向唯一的原生定义。"""

    name: str  # 对玩家稳定的选项名称。
    default: str  # 唯一原生定义读取的默认值。
    values: tuple[str, ...]  # 原生范围中的合法取值。
    label: dict[str, str]  # 菜单名称翻译。
    description: dict[str, str]  # 画面影响与依赖说明。
    slider: bool  # 数值是否用滑块显示。
    group: str  # 文件位置决定菜单分组。
    source: Path  # 定义来源用于可读错误。
    line: int  # 原始源文件行号。
    declaration: str = "define"  # 选项来自普通宏还是Iris原生常量。


@dataclass(frozen=True)
class Preset:
    """已检查的共享配置，文件名决定菜单中的预设名称。"""

    name: str  # 文件名就是共享配置名称。
    label: dict[str, str]  # 预设菜单翻译。
    values: dict[str, str]  # 完整配置保证切换不残留旧值。


def metadata(text: str, location: str, allowed: set[str]) -> dict:
    """检查外部说明的字段与翻译，错误直接指出位置。"""
    data = json.loads(text,object_pairs_hook=unique_object)  # 用户写入的机器说明在边界检查一次。
    if not isinstance(data, dict) or set(data) - allowed:
        raise ValueError(f"{location}：说明必须是对象，且只能含 {sorted(allowed)}")
    for field in ("label", "description"):  # 名称必填，帮助说明可选。
        if field not in data and field == "description":  # 菜单帮助可以省略，名称必须提供。
            continue  # 未提供的帮助不会生成空说明。
        translations = data.get(field)  # 两种语言必须来自同一条说明。
        if not isinstance(translations, dict) or set(translations) != set(LOCALES):
            raise ValueError(f"{location}：{field} 必须同时提供 zh_cn 和 en_us")
        if any(not isinstance(value, str) or not value.strip() or "\n" in value
               or "\r" in value for value in translations.values()):
            raise ValueError(f"{location}：翻译必须是非空单行文字")
    if "slider" in data and not isinstance(data["slider"], bool):  # 滑块不能被文字真假值误启用。
        raise ValueError(f"{location}：slider 必须为 true 或 false")
    return data  # 下游信任已检查的字段。


def scan(shaders: Path) -> tuple[dict[str, Option], dict[str, dict[str, str]]]:
    """扫描效果文件的相邻说明和定义，返回选项与菜单分组。"""
    options: dict[str, Option] = {}  # 效果源码是默认值唯一来源。
    groups: dict[str, dict[str, str]] = {}  # 文件主体自动形成菜单。
    for source in sorted((shaders / "effects").rglob("*.glsl")):  # 文件新增后自动登记，不改中央表。
        group = source.relative_to(shaders / "effects").parts[0].removesuffix(".glsl")  # 效果名称来自目录主体。
        if not re.fullmatch(r"[a-z][a-z0-9_]*", group):
            raise ValueError(f"{source}：效果名称只能使用小写英文、数字和下划线")
        lines = source.read_text(encoding="utf-8").splitlines()  # 保留原始行号便于定位错误。
        for index, line in enumerate(lines):
            stripped = line.strip()  # 说明允许缩进但不允许跨行。
            if stripped.startswith("// @effect "):  # 每个效果提供自己的菜单标题。
                data = metadata(stripped.removeprefix("// @effect "), str(source), {"label"})
                if group in groups and groups[group] != data["label"]:
                    raise ValueError(f"{source}：同一效果出现不同菜单名称")
                groups[group] = data["label"]  # 同一效果只维护一个菜单名称。
            if not stripped.startswith("// @option "):
                continue  # 普通业务注释不参与菜单生成。
            location = f"{source}:{index + 1}"  # 输入错误指出维护文件。
            data = metadata(stripped.removeprefix("// @option "), location,
                            {"label", "description", "slider"})
            definition = DEFINE.fullmatch(lines[index + 1]) if index + 1 < len(lines) else None  # 说明紧贴原生宏或受支持常量。
            constant = CONST.fullmatch(lines[index + 1]) if index + 1 < len(lines) else None
            if definition is None and constant is None:
                raise ValueError(f"{location}：@option 下一行必须是原生 #define 或受支持的 const 选项")
            declaration = "define"
            if constant:
                declaration,name,default,values = constant.groups()  # Iris直接扫描原生常量声明，不能用宏代替。
                if CONST_OPTIONS.get(name)!=declaration: raise ValueError(f"{location}：Iris不支持这个const选项名称或类型")
                if declaration=="int" and not all(re.fullmatch(r"\d+",value) for value in values.split()): raise ValueError(f"{location}：整数const范围必须是整数字面量")
                if declaration=="float" and not all(NUMBER.fullmatch(value) for value in values.split()): raise ValueError(f"{location}：浮点const范围必须是数字字面量")
                commented = None
            else:
                commented, name, default, values = definition.groups()  # 区分原生布尔与数值。
            if (not NAME.fullmatch(name) or name in options) and not constant:
                raise ValueError(f"{location}：选项名称无效或重复：{name}")
            if constant and name in options:
                raise ValueError(f"{location}：选项名称重复：{name}")
            choices = tuple(values.split()) if values else ("false", "true")  # 常量与宏都从原生范围生成取值。
            if constant:
                choices = tuple(values.split())  # Iris原生常量直接成为数值菜单选项。
            if default is None:  # 没有数值的原生宏就是开关。
                default = "false" if commented else "true"  # 原生布尔开关支持注释默认关闭。
                if values or data.get("slider", False):
                    raise ValueError(f"{location}：布尔开关不能声明数值范围或滑块")
            elif (not constant and (commented or not values)) or not all(NUMBER.fullmatch(v) for v in choices):
                raise ValueError(f"{location}：数值选项必须启用定义并提供数字范围")
            if default not in choices or len(set(choices)) != len(choices):
                raise ValueError(f"{location}：默认值不在范围内，或范围含重复值")
            options[name] = Option(name, default, choices, data["label"],
                                   data.get("description", {}), data.get("slider", False),
                                   group, source, index + 2, declaration)
    for option in options.values():  # 菜单分组不能没有玩家看得懂的名称。
        if option.group not in groups:
            raise ValueError(f"{option.source}：有选项的效果需要 // @effect 菜单名称")
    return options, groups  # 新效果只需新增主体文件。


def read_properties(source: Path) -> dict[str, str]:
    """读取项目的单行 properties 子集，拒绝重复键和含糊的续行。"""
    result = {}  # 同一个键只允许定义一次。
    for index, line in enumerate(source.read_text(encoding="utf-8").splitlines(), 1):
        stripped = line.strip()  # 配置输入先整理空白。
        if not stripped or stripped.startswith(("#", "!")):
            continue  # 空行与说明不影响玩家值。
        key, separator, value = stripped.partition("=")  # 只支持明确的单行键值。
        key, value = key.strip(), value.strip()  # 键值分别规范化。
        if not separator or not key or key in result or stripped.endswith("\\"):
            raise ValueError(f"{source}:{index}：需要唯一的单行 key=value")
        result[key] = value  # 下游再检查具体选项范围。
    return result  # 不悄悄覆盖重复配置。


def presets(folder: Path, options: dict[str, Option]) -> list[Preset]:
    """自动收集预设，将未指定的选项补成默认值，并检查所有取值。"""
    result = []  # 自动登记可分享配置。
    for source in sorted(folder.glob("*.properties")):  # 固定预设顺序便于可重复生成。
        if not re.fullmatch(r"[a-z][a-z0-9_]*", source.stem):
            raise ValueError(f"{source}：预设名称只能使用小写英文、数字和下划线")
        labels = [line.removeprefix("# @preset ") for line in
                  source.read_text(encoding="utf-8").splitlines() if line.startswith("# @preset ")]
        if len(labels) != 1:
            raise ValueError(f"{source}：需要一条 # @preset 菜单说明")
        label = metadata(labels[0], str(source), {"label"})["label"]  # 外部预设说明同样检查翻译。
        changes = read_properties(source)  # 预设同样经过配置边界检查。
        for name, value in changes.items():  # 玩家分享的取值必须属于真实选项范围。
            if name not in options or value not in options[name].values:
                raise ValueError(f"{source}：未知选项或无效取值：{name}={value}")
        values = {name: changes.get(name, option.default) for name, option in options.items()}  # 每套补齐全部值。
        result.append(Preset(source.stem, label, values))  # 文件名直接登记。
    return result


def profile_values(values: dict[str, str], options: dict[str, Option]) -> str:
    """将检查后的预设值写成加载器原生的 profile 设置。"""
    entries = []  # 转换为加载器原生预设语法。
    for name, value in values.items():  # 完整配置写入每个原生选项。
        if options[name].values == ("false", "true"):
            entries.append(name if value == "true" else "!" + name)  # 布尔关闭使用加载器原生否定。
        else:
            entries.append(f"{name}={value}")  # 数值保留原生字符串。
    return " ".join(entries)


def generated(shaders: Path, options: dict[str, Option], groups: dict,
              profiles: list[Preset]) -> dict[Path, str]:
    """从唯一来源生成菜单和翻译，返回文件内容，供检查或写入。"""
    pipeline = shaders / "rendering/pipeline.properties"  # 绘制设置只有一个维护文件。
    settings = read_properties(pipeline)  # 不手工改生成产物。
    if any(key == "sliders" or key.startswith(("screen", "profile.")) for key in settings):
        raise ValueError(f"{pipeline}：菜单、滑块和预设由工具生成，不能重复维护")
    lines = ["# \\u7531 build.py \\u751f\\u6210\\uff1b\\u8bf7\\u4fee\\u6539 effects/\\u3001presets/ \\u6216 rendering/pipeline.properties \\u540e\\u91cd\\u65b0\\u751f\\u6210\\u3002"]
    for line in pipeline.read_text(encoding="utf-8").splitlines():
        if line.strip().startswith("#"):
            lines.append(line.encode("ascii","backslashreplace").decode("ascii"))  # 保留来源的中文业务说明并转成兼容编码。
        elif line.strip():
            key = line.partition("=")[0].strip()
            lines.append(f"{key} = {settings[key]}")  # 已检查的键值保持唯一来源。
    lines += ["", "screen = " + " ".join((["<profile>"] if profiles else []) + [f"[{group.upper()}]" for group in sorted(groups)])]
    for group in sorted(groups):  # 顺序固定便于跨系统对比。
        lines.append(f"screen.{group.upper()} = " + " ".join(
            option.name for option in options.values() if option.group == group))
    sliders = [option.name for option in options.values() if option.slider]  # 滑块自动从效果说明读取。
    if sliders:
        lines.append("sliders = " + " ".join(sliders))
    for preset in profiles:  # 玩家选择预设时设置所有参数，不保留旧风格。
        lines.append(f"profile.{preset.name} = {profile_values(preset.values, options)}")
    files = {shaders / "shaders.properties": "\n".join(lines) + "\n"}  # 返回内容由构建统一写入。
    for locale in LOCALES:  # 两套翻译由同一源同步生成。
        translations = ["# \\u7531 build.py \\u751f\\u6210\\uff1b\\u7ffb\\u8bd1\\u4f4d\\u4e8e effects/ \\u4e0e presets/ \\u65c1\\u8fb9\\u3002"]
        for group in sorted(groups):
            translations.append(f"screen.{group.upper()}={escape(groups[group][locale])}")
        for option in options.values():  # 名称与帮助都来自效果旁的说明。
            translations.append(f"option.{option.name}={escape(option.label[locale])}")
            if option.description:  # 不生成没有意义的空帮助。
                translations.append(f"option.{option.name}.comment={escape(option.description[locale])}")
        for preset in profiles:
            translations.append(f"profile.{preset.name}={escape(preset.label[locale])}")
        files[shaders / "lang" / f"{locale}.lang"] = "\n".join(translations) + "\n"
    return files  # 检查命令可直接对比，无需先覆盖旧文件。


def escape(text: str) -> str:
    """转义 properties 的特殊字符，并以 Unicode 转义保持加载器编码兼容。"""
    text = text.replace("\\", "\\\\").replace("=", "\\=").replace(":", "\\:")  # 不让说明改变属性语法。
    return text.encode("ascii", "backslashreplace").decode("ascii")  # 加载器读取兼容的转义中文。

def shared(source: Path, found: dict[str, Option], shader_version: str, legacy: bool = False) -> dict:
    """读取分享配置或旧属性配置，迁移后严格检查未知键与取值。"""
    if source.suffix==".properties":
        lines = source.read_text(encoding="utf-8").splitlines()  # 从原始说明读取版本，不混入玩家选项。
        versions = [line.removeprefix("# @shaderVersion ").strip() for line in lines if line.startswith("# @shaderVersion ")]
        if len(versions)>1: raise ValueError("properties 配置只能有一个 @shaderVersion")
        source_version = versions[0] if versions else (LEGACY_VERSION if legacy else shader_version)  # 无标记默认按当前加载器配置读入；旧版必须显式选择。
        data = {"schemaVersion":1 if legacy else SHARE_SCHEMA,"shaderVersion":source_version,"values":read_properties(source)}  # 当前预设不会被错误标为旧版。
    else:
        data = json.loads(source.read_text(encoding="utf-8"),object_pairs_hook=unique_object)  # 只接受唯一键的显式共享结构。
    if not isinstance(data,dict) or set(data)!={"schemaVersion","shaderVersion","values"} or type(data["schemaVersion"]) is not int or data["schemaVersion"] not in (1,SHARE_SCHEMA) or not isinstance(data["values"],dict):
        raise ValueError("分享配置必须包含格式版本、目标版本和选项对象")
    if not isinstance(data["shaderVersion"],str) or not re.fullmatch(r"\d+\.\d+\.\d+(?:-(?:dev|alpha|beta|rc)\.\d+)?",data["shaderVersion"]):
        raise ValueError("分享配置的光影版本无效")
    if data["schemaVersion"]==SHARE_SCHEMA and data["shaderVersion"]!=shader_version:
        raise ValueError("格式二只能导入当前光影版本")  # 当前格式不隐式猜测字段含义。
    if data["schemaVersion"]==1 and (not _older_or_equal(data["shaderVersion"],LEGACY_VERSION) or not _older_or_equal(data["shaderVersion"],shader_version)):
        raise ValueError("格式一只接受开发准备阶段的旧版配置")  # 没有定义迁移的版本不能隐式套用旧规则。
    changes = data["values"]  # 分享数据进入已检查的选项边界。
    if data["schemaVersion"]==1 and any(name!="OMNI_DEBUG_VIEW" or value not in ("0","1","2") for name,value in changes.items()):
        raise ValueError("旧版配置只能包含原有调试视图；当前选项请按当前格式导入")  # 不把当前水云等选项伪装成旧接口。
    for name,value in changes.items():  # 逐项报告未知名称与非法取值。
        if name not in found or not isinstance(value,str) or value not in found[name].values:
            raise ValueError(f"未知选项或无效取值：{name}={value}")  # 未知值不能静默丢弃。
    values = {name:changes.get(name,option.default) for name,option in found.items()}  # 导入总是完整替换。
    return {"schemaVersion":SHARE_SCHEMA,"shaderVersion":shader_version,"values":values}  # 名称未变，只迁移结构。

def _older_or_equal(source: str, current: str) -> bool:
    """比较同一发布序列的配置版本，迁移不维护分散版本白名单。"""
    pattern = re.compile(r"^(\d+)\.(\d+)\.(\d+)(?:-(dev|alpha|beta|rc)\.(\d+))?$")
    left,right = pattern.fullmatch(source),pattern.fullmatch(current)
    if not left or not right: return False
    stage = {"dev":0,"alpha":1,"beta":2,"rc":3,None:4}  # 正式版本排在预发布之后。
    return tuple(map(int,left.group(1,2,3)))+(stage[left.group(4)],int(left.group(5) or 0)) <= tuple(map(int,right.group(1,2,3)))+(stage[right.group(4)],int(right.group(5) or 0))

def output_path(destination: Path, root: Path, suffix: str) -> Path:
    """验证配置写入边界，开发目录本身的链接也不能扩大边界。"""
    root_absolute = Path(os.path.abspath(os.fspath(root)))  # 比较边界先使用同一种词法路径表示，兼容Windows 8.3短名。
    base = root_absolute/".dev"
    destination = Path(os.path.abspath(os.fspath(destination)))
    if not destination.is_relative_to(base) or destination.suffix!=suffix:
        raise ValueError(f"配置输出必须是本项目 .dev 内的 {suffix} 文件")
    current = root_absolute
    for part in destination.relative_to(root_absolute).parts:
        current /= part
        if current.is_symlink() or current.is_junction(): raise ValueError("配置输出不能经过符号链接或目录联接")  # 所有输出文件在写入前检查一次。
    existing = destination
    missing = []
    while not existing.exists():
        missing.append(existing.name)
        existing = existing.parent
    canonical_existing = Path(os.path.realpath(os.fspath(existing)))
    canonical_destination = canonical_existing.joinpath(*reversed(missing))
    if not canonical_destination.is_relative_to(Path(os.path.realpath(os.fspath(base)))):
        raise ValueError("配置输出的真实路径越过本项目 .dev")  # 既兼容短路径，又保留真实路径边界。
    return destination

def save(destination: Path, values: dict, shader_version: str, root: Path) -> None:
    """只写开发目录中的自有JSON配置，不修改玩家设置。"""
    destination = output_path(destination,root,".json")  # 格式与路径同时在写入边界检查。
    destination.parent.mkdir(parents=True,exist_ok=True)  # 只建立工具管理的目录。
    destination.write_text(json.dumps({"schemaVersion":SHARE_SCHEMA,"shaderVersion":shader_version,"values":values},ensure_ascii=False,indent=2)+"\n",encoding="utf-8")

def save_properties(destination: Path, values: dict[str,str], shader_version: str, root: Path) -> None:
    """写出可直接交给加载器的完整 properties，同时保留工具版本标记。"""
    destination = output_path(destination,root,".properties")  # 加载器配置沿用同一受控输出边界。
    destination.parent.mkdir(parents=True,exist_ok=True)  # 输出边界检查后才创建目录。
    content = [f"# @shaderVersion {shader_version}","# Omni \\u5171\\u4eab\\u914d\\u7f6e\\uff1b\\u6bcf\\u4e2a\\u9009\\u9879\\u503c\\u6765\\u81ea\\u6548\\u679c\\u6e90\\u7801\\u7684\\u539f\\u751f\\u5b9a\\u4e49\\u3002",*(f"{name}={value}" for name,value in values.items())]
    destination.write_text("\n".join(content)+"\n",encoding="ascii")  # 说明使用Unicode转义，键和值保持加载器可读ASCII。

def main() -> None:
    """导入、导出、对比与重置共享配置，统一报告边界错误。"""
    import build  # 延迟引入避免构建与配置循环初始化。
    parser = argparse.ArgumentParser(description="Omni 配置分享")
    parser.add_argument("command",choices=("import","export","diff","reset"))  # 每条命令完成一个玩家动作。
    parser.add_argument("--input",type=Path)  # 所有分享操作都指定被检查的外部输入。
    parser.add_argument("--other",type=Path)  # 对比可选择另一份完整配置。
    parser.add_argument("--output",type=Path)  # 文件后缀显式选择JSON分享或加载器properties。
    parser.add_argument("--legacy",action="store_true",help="按开发准备阶段格式一导入旧properties")
    parser.add_argument("--format",choices=("json","properties"),help="输出格式；export默认properties，import与reset默认json")
    args = parser.parse_args()  # 参数不匹配时在任何输出文件写入前拒绝。
    if args.legacy and (args.command!="import" or not args.input or args.input.suffix!=".properties"):
        parser.error("--legacy 只能用于 import 的旧properties输入")
    if args.other and args.command!="diff": parser.error("--other 只能用于 diff")  # 另一份配置只用于只读比较，避免写入第二份用户文件。
    if args.format and args.command not in ("export",): parser.error("--format 只能用于 export")  # 格式选择不改变导入边界。
    if args.output and args.command=="diff": parser.error("diff 不写入文件，不能指定 --output")  # 对比命令只返回差异文字，不创建配置。
    if args.format and args.command=="diff": parser.error("diff 不导出文件，不能指定 --format")  # 对比命令不改变配置格式。
    if args.command in ("import","reset") and args.format=="properties": parser.error("导入和重置保存JSON，加载器properties请使用export")  # 格式转换只由export执行。
    if args.command=="reset" and args.input: parser.error("reset 从源码重置，不接受 --input")
    found,_ = scan(build.SHADERS)  # 当前所有取值仍来自效果原生定义。
    release = build.version()  # 文件目标版本只来自VERSION，不在命令中硬编码。
    output_format = args.format or ("properties" if args.command=="export" and not args.output else ("properties" if args.output and args.output.suffix==".properties" else "json"))  # 后缀与显式格式一致，避免文件扩展名撒谎。
    destination = args.output or build.ROOT/(f".dev/config/load.{output_format}" if args.command=="export" else ".dev/config/user.json")
    if destination.suffix!="."+output_format: parser.error("--format 必须与 --output 的文件后缀一致")  # 玩家拿到文件时格式名称与真实内容一致。
    defaults = {n:o.default for n,o in found.items()}  # 重置从原生定义读取。
    if args.command=="reset":  # 重置使用当前源码默认值，避免版本配置漂移。
        save(destination,defaults,release,build.ROOT)
        print("已重置开发共享配置")
        return
    if not args.input: parser.error("此命令需要 --input")  # 导入与对比不能隐式使用上次配置。
    current = shared(args.input,found,release,args.legacy)["values"]  # 检查后内部信任配置。
    if args.command=="diff":  # 对比只读输入，不写用户文件。
        other = shared(args.other,found,release)["values"] if args.other else defaults  # 不给另一配置时与默认对比。
        for name in found:  # 仅显示两份完整配置实际不同的值。
            if current[name]!=other[name]: print(f"{name}: {other[name]} → {current[name]}")
        return
    if args.command=="export" and destination.suffix==".properties":
        save_properties(destination,current,release,build.ROOT)  # 导出的完整属性可直接交给加载器。
    else:
        save(destination,current,release,build.ROOT)  # JSON分享保留格式与目标光影版本。
    print("共享配置已保存到开发目录")

if __name__=="__main__":
    sys.stdout.reconfigure(encoding="utf-8"); sys.stderr.reconfigure(encoding="utf-8")  # 中文参数错误可读。
    try: main()
    except (ValueError,OSError) as error: print(f"错误：{error}",file=sys.stderr); sys.exit(1)  # 不静默忽略非法配置。
