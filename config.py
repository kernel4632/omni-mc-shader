"""配置读写：在受控边界内导入、导出、对比和重置玩家分享配置与加载器属性。

调用位置：本模块的命令入口负责 `import`、`export`、`diff`、`reset` 四个动作；`options.py`
从这里读取 `unique_object` 与 `read_properties` 两个配置读取器；`build.py` 从这里读取
版本号格式、分享格式编号和版本比较。三处不再各写一份编号规则。
可复制示例：`python config.py export --input .dev/config/user.json --output .dev/config/share.json --format json`。
设计取舍：加载器 `properties` 是单行键值格式，分享 `JSON` 是带字段结构并携带格式与版本的数据，
因此两者只在明确的导入、导出边界转换。未知选项、重复字段和不合规版本直接报错，
避免分享者不知道配置已经丢失；下游只信任这里检查过的结果，不再重复猜测。
版本号格式与分享格式编号只在本文件定义一处，构建与配置校验共用，防止三份正则走偏。
"""

from __future__ import annotations

import argparse  # 配置分享命令入口。
import json  # 读取受控配置与机器说明。
import re  # 检查选项名称、数值与版本格式。
import sys  # 唯一入口报告错误。
from pathlib import Path  # 所有用户输出限制在开发目录。
from typing import TYPE_CHECKING  # 只在类型检查时引入选项数据定义，运行时不建立循环导入。
import paths  # 开发目录写入边界在专用模块里只检查一次。

if TYPE_CHECKING:  # 标注需要选项数据类型，但运行时导入 options 会与 options 互相导入。
    import options  # 仅用于类型说明，不在运行时求值。

SHARE_SCHEMA = 2  # JSON分享与打包清单共用这一个格式版本。
LEGACY_VERSION = "0.0.0-dev.3"  # 旧配置格式只描述效果开发前的调试选项。
# 版本号编号规则只在这里定义一处：三段数字加可选的 dev/alpha/beta/rc 后缀。
# 构建校验 VERSION、发布新版本、导入分享配置和比较版本先后都复用它，不允许再各写一份正则。
VERSION_PATTERN = r"(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)(?:-(?:dev|alpha|beta|rc)\.(?:0|[1-9]\d*))?"
VERSION_RE = re.compile(VERSION_PATTERN)  # 预编译一次，避免每次校验都重新解析。
OPTION_RENAMES = {  # 保留历史名称对照；旧配置按新名迁移，移植前的旧参数合并见 docs/parity.md 第十二节。
    "OMNI_SHADOW_RESOLUTION": "shadowMapResolution",  # 旧名迁移到新名。
    "OMNI_SHADOW_DISTANCE": "shadowDistance",  # 旧名迁移到新名。
    "OMNI_SHADOW_PENUMBRA": "OMNI_VARIABLE_PENUMBRA_SHADOWS",  # 旧名迁移到新名。
    "OMNI_SHADOW_PENUMBRA_QUALITY": "OMNI_VPS_QUALITY",  # 旧名迁移到新名。
    "OMNI_SHADOW_BLUR": "OMNI_SHADOW_BASIC_BLUR",  # 旧名迁移到新名。
    "OMNI_SHADOW_SOFTNESS": "OMNI_VPS_SPREAD",  # 旧名迁移到新名。
    "OMNI_MATERIAL_DETAIL": "OMNI_ENABLE_PBR",  # 旧名迁移到新名。
    "OMNI_VEGETATION_WIND": "OMNI_WAVING_PLANTS",  # 旧名迁移到新名。
    "OMNI_RAIN_WIND": "OMNI_RAIN_WIND_X",  # 旧名迁移到新名。
    "OMNI_NETHERFOG_DENSITY": "OMNI_NETHER_FOG_DENSITY",  # 旧名迁移到新名：补全单词分隔，与 `VFOG` 一系写法统一。
    "OMNI_WATERFOG_DENSITY": "OMNI_WATER_FOG_DENSITY",  # 旧名迁移到新名：同上。
    "OMNI_UNDERWATER_DENSITY": "OMNI_WATER_FOG_DENSITY",  # 旧名迁移到新名。
    "OMNI_VFOG_STEPS": "OMNI_VFOG_QUALITY",  # 旧名迁移到新名。
    "OMNI_AA_ENABLED": "OMNI_TAA",  # 旧名迁移到新名。
    "OMNI_TAA_WEIGHT": "OMNI_TAA_BLENDWEIGHT",  # 旧名迁移到新名。
    "OMNI_BLOOM_ENABLED": "OMNI_BLOOM",  # 旧名迁移到新名。
    "OMNI_BLOOM_STRENGTH": "OMNI_BLOOM_AMOUNT",  # 旧名迁移到新名。
    "OMNI_AUTO_EXPOSURE": "OMNI_MANUAL_EXPOSURE",  # 旧名迁移到新名。
    "OMNI_TONEMAP_MODE": "OMNI_TONEMAP_OPERATOR",  # 旧名迁移到新名。
    "OMNI_UPSCALE": "OMNI_FSR",  # 旧名迁移到新名。
    # iterationT 自带拼写错误的选项名，导入 iterationT 配置时按这里对照迁移到正确拼写。
    "OMNI_SEREEN_RATIO": "OMNI_SCREEN_RATIO",  # 旧名把屏幕一词拼错，按正确写法迁移。
    "OMNI_DOF_DEPTH_SMMOOTH_HALFLIFE": "OMNI_DOF_DEPTH_SMOOTH_HALFLIFE",  # 旧名把平滑一词多写了一个字母，按正确写法迁移。
    "OMNI_CLOUD_CLEAR_COVERY": "OMNI_CLOUD_CLEAR_COVERAGE",  # 旧名少写覆盖度一词的末尾字母，按正确写法迁移。
    "OMNI_CLOUD_RAIN_COVERY": "OMNI_CLOUD_RAIN_COVERAGE",  # 旧名少写覆盖度一词的末尾字母，按正确写法迁移。
    "OMNI_MOTION_BLUR_SUTTER_ANGLE": "OMNI_MOTION_BLUR_SHUTTER_ANGLE",  # 旧名把快门一词漏了一个字母，按正确写法迁移。
    "OMNI_ACCRETIONDISC_DETAIL_ALONG_LONGTITUDE": "OMNI_ACCRETIONDISC_DETAIL_ALONG_LONGITUDE",  # 旧名把经度一词拼错，按正确写法迁移。
    "OMNI_UPSCALE_STRENGTH": "OMNI_FSR_SHARPNESS",  # 旧名迁移到新名。
    "OMNI_CLOUD_COVERAGE": "OMNI_CLOUD_CLEAR_COVERAGE",  # 旧名迁移到新名。
    "OMNI_CLOUD_HEIGHT": "OMNI_CLOUD_CLEAR_ALTITUDE",  # 旧名迁移到新名。
    "OMNI_CLOUD_THICKNESS": "OMNI_CLOUD_CLEAR_THICKNESS",  # 旧名迁移到新名。
    "OMNI_CLOUD_DENSITY": "OMNI_CLOUD_CLEAR_DENSITY",  # 旧名迁移到新名。
    "OMNI_CLOUD_SCALE": "OMNI_CLOUD_CLEAR_SCALE",  # 旧名迁移到新名。
    "OMNI_CLOUD_SUNLIGHT": "OMNI_CLOUD_CLEAR_SUNLIGHTING",  # 旧名迁移到新名。
    "OMNI_CLOUD_SKYLIGHT": "OMNI_CLOUD_CLEAR_SKYLIGHTING",  # 旧名迁移到新名。
    "OMNI_CLOUD_RAIN_SUNLIGHT": "OMNI_CLOUD_RAIN_SUNLIGHTING",  # 旧名迁移到新名。
    "OMNI_CLOUD_RAIN_SKYLIGHT": "OMNI_CLOUD_RAIN_SKYLIGHTING",  # 旧名迁移到新名。
    "OMNI_CLOUD_BOTTOM": "OMNI_CLOUD_BOTTOM_BRIGHTNESS",  # 旧名迁移到新名。
    "OMNI_CLOUD_OUTSCATTER": "OMNI_CLOUD_OUTSCATTER_FACTOR",  # 旧名迁移到新名。
    "OMNI_CLOUD_NOISE_SCALE": "OMNI_CLOUD_DETAILED_NOISE_SCALE",  # 旧名迁移到新名。
    "OMNI_PC_COVERAGE": "OMNI_PLANAR_COVERAGE",  # 旧名迁移到新名：`PC` 与同文件 `PLANAR` 两种写法统一为 `PLANAR`。
    "OMNI_PC_NOISE_SCALE": "OMNI_PLANAR_NOISE_SCALE",  # 旧名迁移到新名：同上。
    "OMNI_PC_ALTITUDE": "OMNI_PLANAR_ALTITUDE",  # 旧名迁移到新名：同上。
    "OMNI_FTC_OFFSET": "OMNI_CLOUD_TIME_OFFSET",  # 旧名迁移到新名：把自造缩写 `FTC` 换成普通词 `CLOUD_TIME`。
    "OMNI_GRASS_HEIGHT": "OMNI_GRASS_BASE_HEIGHT",  # 单一草丛高度拆成普通草与矮草两套，旧名并入普通草高度。
}


def unique_object(pairs: list[tuple]) -> dict:
    """拒绝重复键，避免不同读取器得到不同配置。

    输入边界：只接收 `json.loads` 提供的键值对；同一对象中的键必须唯一。
    单源原因：后续流程只信任这里返回的对象，不再重复猜测哪个值才是有效值。
    """
    result = {}  # 输入对象不允许后值覆盖前值。
    for name, value in pairs:
        if name in result:
            raise ValueError(f"重复配置字段：{name}")  # 重复值必须由分享者明确修正。
        result[name] = value  # 检查后下游信任唯一键。
    return result


def read_properties(source: Path) -> dict[str, str]:
    """读取单行 `properties` 键值，拒绝重复键和含糊的续行。

    输入边界：只接受外部配置文件中的单行 `key=value`；空行和注释可存在，续行不接受。
    格式取舍：`properties` 是加载器直接读取的单行键值文本，没有分享对象的字段结构。
    工具额外写出的版本注释由 `shared` 单独读取，不会被这里当成玩家选项。
    """
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


def version_order(value: str) -> tuple[int, ...]:
    """把已检查的版本号拆成可比较的数字序列，供发布与迁移判断先后。

    三段主版本按数字比较，预发布阶段按 dev < alpha < beta < rc < 正式排序，
    阶段内序号按数字比较，避免 `dev.10` 排到 `dev.2` 前面。
    调用者需先用 `VERSION_RE` 校验格式，本函数只处理合法编号。
    """
    base, _, suffix = value.partition("-")  # 主版本与预发布后缀分开。
    stage, _, number = suffix.partition(".")  # 后缀拆成阶段名和阶段内序号。
    ranking = {"dev": 0, "alpha": 1, "beta": 2, "rc": 3, "": 4}  # 正式版本没有后缀，排在所有预发布阶段之后。
    return (*map(int, base.split(".")), ranking[stage], int(number or 0))  # 阶段内序号缺省用零占位。


def _older_or_equal(source: str, current: str) -> bool:
    """比较两个配置版本，供旧格式迁移判断先后顺序。

    先比较三个数字，再比较开发、测试、候选和正式阶段，最后比较阶段内序号。
    只有符合唯一版本格式的字符串才参与比较；无法识别的版本返回否，
    不能因为解析失败就获得旧版迁移资格。
    """
    if not VERSION_RE.fullmatch(source) or not VERSION_RE.fullmatch(current):  # 两边都必须是统一编号格式。
        return False  # 只有已知版本才能按历史迁移规则解释，不能用文字排序猜先后。
    return version_order(source) <= version_order(current)  # 相同版本也可按已有规则导入。


def shared(source: Path, found: dict[str, "options.Option"], shader_version: str, legacy: bool = False) -> dict:
    """读取分享配置或旧属性配置，并迁移为当前完整配置。

    输入边界：`.properties` 按加载器配置读取，其他后缀仍按分享 `JSON` 读取；所有字段、版本、
    选项名称和值都在这里一次检查。`found` 必须来自当前源码扫描，`shader_version` 必须来自
    唯一版本文件；`legacy` 只允许命令入口明确打开旧格式迁移。
    迁移原因：旧配置只有调试选项，当前配置增加了更多效果，不能把旧字段静默套到新含义上；
    迁移后补齐当前默认值，并保留未知选项错误，让分享者知道哪些内容无法导入。
    """
    if source.suffix == ".properties":
        data = _properties_share(source, shader_version, legacy)  # 键值格式先补上版本结构，再走共同检查。
    else:
        data = json.loads(source.read_text(encoding="utf-8"), object_pairs_hook=unique_object)  # 重复字段会产生不同解释，必须在读取时拒绝。
    # 格式版本必须是真整数；布尔值在语言中也能参与整数比较，但不是合法的版本号。
    if (not isinstance(data, dict)
            or set(data) != {"schemaVersion", "shaderVersion", "values"}
            or type(data["schemaVersion"]) is not int
            or data["schemaVersion"] not in (1, SHARE_SCHEMA)
            or not isinstance(data["values"], dict)):
        raise ValueError("分享配置必须包含格式版本、目标版本和选项对象")
    if not isinstance(data["shaderVersion"], str) or not VERSION_RE.fullmatch(data["shaderVersion"]):
        raise ValueError("分享配置的光影版本无效")
    if data["schemaVersion"] == SHARE_SCHEMA and data["shaderVersion"] != shader_version:
        raise ValueError("格式二只能导入当前光影版本")  # 当前格式不隐式猜测字段含义。
    if data["schemaVersion"] == 1 and (not _older_or_equal(data["shaderVersion"], LEGACY_VERSION)
                                       or not _older_or_equal(data["shaderVersion"], shader_version)):
        raise ValueError("格式一只接受开发准备阶段的旧版配置")  # 没有定义迁移的版本不能隐式套用旧规则。
    changes = data["values"]  # 分享数据进入已检查的选项边界。
    if data["schemaVersion"] == 1 and any(name != "OMNI_DEBUG_VIEW" or value not in ("0", "1", "2") for name, value in changes.items()):
        raise ValueError("旧版配置只能包含原有调试视图；当前选项请按当前格式导入")  # 不把当前水云等选项伪装成旧接口。
    # 取值必须都是字符串：JSON 允许把值写成对象或数组，若直接进迁移表会触发不可哈希异常，先在这里统一拒绝。
    if any(not isinstance(value, str) for value in changes.values()):
        raise ValueError("分享配置的每个选项取值都必须是字符串")  # 结构错误在读取边界报可读原因，不留给下游抛类型错误。
    changes = rename(changes)  # 旧名先按对照表迁移，玩家改过名的设置不丢，改过名又写错才在这里报错。
    dropped = sorted(name for name in changes if name in REMOVED_OPTIONS)  # 已被算法整体替换掉的选项：导入时忽略，但要报出来。
    for name in dropped:
        del changes[name]  # 这些选项当前源码里没有对应计算，留着只会让人以为生效了。
    if dropped:
        print("提示：以下选项在当前版本已被整体替换，导入时忽略：" + "、".join(dropped))  # 明确告知，不是静默丢弃。
    for name, value in changes.items():  # 逐项报告未知名称与非法取值，不把拼写错误当成缺省值。
        if name not in found or not isinstance(value, str) or value not in found[name].values:
            raise ValueError(f"未知选项或无效取值：{name}={value}")  # 静默忽略会让分享者误以为配置已完整生效。
    values = {name: changes.get(name, option.default) for name, option in found.items()}  # 缺少的当前选项补源码默认值，导入总是完整替换。
    return {"schemaVersion": SHARE_SCHEMA, "shaderVersion": shader_version, "values": values}  # 旧格式只升级结构，不臆测或重命名未知字段。


VALUE_RENAMES = {  # 选项从开关改成多档时，旧配置里的真假值要换成对应档位，否则导入会当作非法取值被拒。
    "OMNI_CLOUD_CUMULONIMBUS": {"true": "1", "false": "0"},  # 积雨云由开关改成关/中/强三档：开着对应中档，关着仍是关。
    "OMNI_GRASS_BASE_HEIGHT": {"1.5": "1.0", "2.0": "1.0"},  # 草丛高度改按 Eclipse 的普通草高度取 0.5–1.0，旧的超高取值收到上限而不是报错。
}
REMOVED_OPTIONS = {  # 被新算法整体替换、已无对应计算的选项：导入时忽略并提示，不让旧配置直接报未知选项。
    "OMNI_LPV_STEPS": "简易体积光的步数被 Eclipse 的彩色光传播体积整体替换（见 CHANGELOG 的 dev.141）。",
}


def rename(values: dict[str, str]) -> dict[str, str]:
    """把旧选项名按 `OPTION_RENAMES` 迁移到当前名，旧真假值按 `VALUE_RENAMES` 迁移到新档位。

    输入边界：`values` 是外部配置里的键值，必须先检查是字典才能进来。
    为什么单独成函数：导入路径与预设读取都要用同一份对照表，写两遍迟早会不一致。
    行为：旧名出现就换名；新旧名同时出现直接报错，避免同一项出现两个互相矛盾的取值；
    名字迁移后再看取值，只替换登记过的旧值，其余取值原样交给选项边界报错。
    未知名字原样保留，交给后面的选项边界统一报错，不在这里静默丢弃。
    """
    result = {}  # 迁移后的键值。
    for name, value in values.items():
        current = OPTION_RENAMES.get(name, name)  # 没有登记的名字保持原样。
        if current in result or (current != name and current in values):
            raise ValueError(f"配置里同时给了旧名与新名：{name}、{current}")  # 两个来源冲突时不能替玩家猜哪个优先。
        result[current] = VALUE_RENAMES.get(current, {}).get(value, value)  # 旧真假值换成新档位，未登记的取值不动。
    return result


def _properties_share(source: Path, shader_version: str, legacy: bool) -> dict:
    """给加载器键值配置补上分享结构，让两种输入使用相同的版本与取值检查。

    版本注释不影响游戏读取；没有注释时默认按当前版解释，只有显式旧格式参数才启用旧版规则。
    本函数只整理外部文件格式，不替调用方检查选项，避免两种输入各自维护一套范围判断。
    """
    lines = source.read_text(encoding="utf-8").splitlines()  # 从原始注释读版本，不把它混入玩家选项。
    versions = [line.removeprefix("# @shaderVersion ").strip()
                for line in lines if line.startswith("# @shaderVersion ")]  # 只识别约定前缀，不从任意说明猜版本。
    if len(versions) > 1:
        raise ValueError("properties 配置只能有一个 @shaderVersion")  # 即使两个标记相同，也要求作者消除重复来源。
    source_version = versions[0] if versions else (LEGACY_VERSION if legacy else shader_version)  # 有明确标记时优先尊重文件，而非命令猜测。
    return {
        "schemaVersion": 1 if legacy else SHARE_SCHEMA,  # 当前配置不会因缺少版本注释被误标成旧格式。
        "shaderVersion": source_version,  # 后续共同边界负责验证版本是否合法且可迁移。
        "values": read_properties(source),  # 原始键值读取仍拒绝重复键和续行。
    }


def save(destination: Path, values: dict, shader_version: str, root: Path) -> None:
    """把完整分享 `JSON` 写入项目 `.dev`，不修改玩家设置。

    输入边界：本函数用 `paths.development_path` 检查 `destination`；`values` 必须是已经检查过的完整选项，
    `shader_version` 必须来自当前版本来源。`JSON` 保存格式版本和目标光影版本，便于分享与迁移。
    """
    destination = paths.development_path(destination, root, ".json")  # 格式与路径同时在写入边界检查。
    destination.parent.mkdir(parents=True, exist_ok=True)  # 只在确认边界后建立输出目录。
    content = {"schemaVersion": SHARE_SCHEMA, "shaderVersion": shader_version, "values": values}  # 版本信息与值一起分享，读取者才知道该用哪套规则解释。
    destination.write_text(json.dumps(content, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")  # 保留中文和稳定缩进，方便人阅读与比较。


def save_properties(destination: Path, values: dict[str, str], shader_version: str, root: Path) -> None:
    """写出可直接交给加载器的完整 `properties`，并保留工具版本标记。

    输入边界：目标路径必须通过 `paths.development_path`，`values` 必须是完整且已检查的选项值。
    格式取舍：这里输出加载器能直接读取的单行键值，而不是带对象结构的分享 `JSON`；版本注释
    只供本工具迁移读取，不改变加载器的选项语法。
    """
    destination = paths.development_path(destination, root, ".properties")  # 加载器配置沿用同一受控输出边界。
    destination.parent.mkdir(parents=True, exist_ok=True)  # 输出边界检查后才创建目录。
    content = [
        f"# @shaderVersion {shader_version}",  # 版本放注释里，加载器仍只接收原来的选项键值。
        "# Omni \\u5171\\u4eab\\u914d\\u7f6e\\uff1b\\u6bcf\\u4e2a\\u9009\\u9879\\u503c\\u6765\\u81ea\\u6548\\u679c\\u6e90\\u7801\\u7684\\u539f\\u751f\\u5b9a\\u4e49\\u3002",  # 说明保留原有转义内容与顺序。
        *(f"{name}={value}" for name, value in values.items()),  # 已检查的字符串原样写入，不重新格式化数字。
    ]
    destination.write_text("\n".join(content) + "\n", encoding="ascii")  # 中文说明使用转义，键和值保持加载器可读编码。


def _arguments() -> tuple[argparse.Namespace, argparse.ArgumentParser]:
    """读取并检查命令参数组合，返回参数和保留原错误出口的解析器。

    参数名、帮助文字和拒绝顺序保持原样。先拒绝不相关参数，再扫描源码，避免错误命令触发文件操作。
    """
    parser = argparse.ArgumentParser(description="Omni 配置分享")  # 参数错误继续通过解析器退出，保留命令退出码。
    parser.add_argument("command", choices=("import", "export", "diff", "reset"))  # 每条命令完成一个玩家动作。
    parser.add_argument("--input", type=Path)  # 分享操作显式指定外部输入，不隐式读取玩家设置。
    parser.add_argument("--other", type=Path)  # 另一份配置只允许用于只读比较。
    parser.add_argument("--output", type=Path)  # 文件后缀与内容格式必须一致，避免导出文件名误导玩家。
    parser.add_argument("--legacy", action="store_true", help="按开发准备阶段格式一导入旧properties")  # 旧属性没有自带格式结构，必须由用户明确选择。
    parser.add_argument("--format", choices=("json", "properties"), help="输出格式；export默认properties，import与reset默认json")  # 显式格式只开放给导出命令。
    args = parser.parse_args()  # 参数不匹配时在任何输出文件写入前拒绝。
    if args.legacy and (args.command != "import" or not args.input or args.input.suffix != ".properties"):
        parser.error("--legacy 只能用于 import 的旧properties输入")
    if args.other and args.command != "diff":
        parser.error("--other 只能用于 diff")  # 不把第二份输入误当成导出或导入对象。
    if args.format and args.command != "export":
        parser.error("--format 只能用于 export")  # 此处已覆盖对比、导入和重置，无需再次检查相同组合。
    if args.output and args.command == "diff":
        parser.error("diff 不写入文件，不能指定 --output")  # 对比只打印差异，不创建配置。
    if args.command == "reset" and args.input:
        parser.error("reset 从源码重置，不接受 --input")  # 重置的唯一数据源是原生默认值。
    return args, parser  # 文件后缀仍在确定最终输出格式后用同一解析器报错。


def main() -> None:
    """执行配置导入、导出、对比和重置命令。

    命令边界：参数由 `_arguments` 检查，外部配置由 `shared` 检查，保存时统一检查输出路径。
    外部行为：保留现有命令名、参数名、默认输出路径和中文结果文字，方便脚本继续调用。
    模块末尾统一报告可预期错误；未知选项、路径越界或格式错误都不会被静默跳过。
    """
    import build  # 延迟引入：build 已从本模块读取版本格式，这里再引入不会形成运行期循环。
    import options  # 选项扫描属于选项菜单模块，按需引入而不在本模块复制一份。
    args, parser = _arguments()  # 参数检查完成后才读取当前源码与版本。
    found, _ = options.scan(build.SHADERS)  # 当前所有取值仍来自效果原生定义。
    release = build.version()  # 文件目标版本只来自唯一版本文件，不在命令中硬编码。
    if args.format:
        output_format = args.format  # 显式指定优先，后面仍要检查后缀一致。
    elif args.command == "export" and not args.output:
        output_format = "properties"  # 没指定目标的导出默认生成加载器可读配置。
    else:
        output_format = "properties" if args.output and args.output.suffix == ".properties" else "json"  # 其余情况沿用原来的后缀推断规则。
    filename = f".dev/config/load.{output_format}" if args.command == "export" else ".dev/config/user.json"  # 保留各命令的默认目标。
    destination = args.output or build.ROOT / filename  # 指定目标时沿用用户路径，不自动替换后缀。
    if destination.suffix != "." + output_format:
        parser.error("--format 必须与 --output 的文件后缀一致")  # 内容格式和文件名不符时在写盘前拒绝。
    defaults = {name: option.default for name, option in found.items()}  # 默认值来自真实声明，不来自旧配置或预设。
    if args.command == "reset":
        if output_format == "properties":
            save_properties(destination, defaults, release, build.ROOT)  # 选到 properties 后缀时重置也写加载器可读属性，内容与文件名一致。
        else:
            save(destination, defaults, release, build.ROOT)  # 默认写工具管理的共享配置。
        print("已重置开发共享配置")  # 保留现有成功文字，供用户和脚本识别。
        return  # 重置无需输入文件，不进入分享读取流程。
    if not args.input:
        parser.error("此命令需要 --input")  # 导入、导出与对比均需明确输入。
    current = shared(args.input, found, release, args.legacy)["values"]  # 检查后内部只使用完整且合法的配置。
    if args.command == "diff":
        other = shared(args.other, found, release)["values"] if args.other else defaults  # 不给另一份配置时与源码默认值对比。
        for name in found:  # 仅显示两份完整配置实际不同的值。
            if current[name] != other[name]:
                print(f"{name}: {other[name]} → {current[name]}")  # 箭头继续从对照值指向输入值。
        return  # 对比到此结束，不触发任何保存函数。
    if output_format == "properties":
        save_properties(destination, current, release, build.ROOT)  # 后缀或格式选到properties时，任何命令都写加载器可直接读的完整属性。
    else:
        save(destination, current, release, build.ROOT)  # 分享对象保留格式和目标光影版本。
    print("共享配置已保存到开发目录")  # 只有实际保存成功后才报告完成。


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")  # 成功信息和差异文字保持中文可读。
    sys.stderr.reconfigure(encoding="utf-8")  # 参数错误与配置错误采用相同编码。
    try:
        main()  # 所有命令走同一条检查、读取和反馈主线。
    except (ValueError, OSError) as error:
        print(f"错误：{error}", file=sys.stderr)  # 配置与文件错误统一报告原因，不吞掉异常内容。
        sys.exit(1)  # 保留失败退出码，让调用脚本能识别保存失败。
