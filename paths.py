"""开发目录边界：把工具自有输出限制在本项目 `.dev` 内，只在这里检查一次。

调用位置：`options.py` 保存配置和 `game.py` 保存本机设置前都调用它；这两处原本各写一份
相同的路径检查，合并到此处，避免两处规则走偏、改一处忘一处。

可复制示例：
    `destination = development_path(destination, ROOT)`            # 只要求留在 `.dev`
    `destination = development_path(destination, ROOT, ".json")`   # 同时要求扩展名

设计原因与取舍：工具写入的目录必须可随时删除，绝不能碰到玩家真实实例。
所以既做词法前缀检查，又逐段拒绝符号链接与目录联接，最后核对真实路径，
防止链接把输出转到 `.dev` 之外。`suffix` 留空时不限制扩展名。
"""
from __future__ import annotations

import os  # 规范化路径并解析真实路径。
from pathlib import Path  # 用项目相对路径固定检查范围。


def development_path(destination: Path, root: Path, suffix: str = "") -> Path:
    """确认 `destination` 留在 `root/.dev` 内并返回规范化路径，否则抛出 `ValueError`。

    输入边界：`destination` 是命令行或工具给出的目标路径，`root` 是项目根目录，
    `suffix` 非空时还要求扩展名匹配。检查在写入前只做一次，函数内部随后信任结果。
    """
    root_absolute = Path(os.path.abspath(os.fspath(root)))  # 先整理相对段，不在此处跟随链接。
    base = root_absolute / ".dev"  # 开发目录是唯一允许写入的位置。
    destination = Path(os.path.abspath(os.fspath(destination)))  # 沿用命令行相对当前目录的解释方式。
    if not destination.is_relative_to(base) or (suffix and destination.suffix != suffix):
        raise ValueError(f"输出必须是本项目 .dev 内的 {suffix} 文件" if suffix else "输出必须留在本项目 .dev 内")  # 词法越界或格式不符都拒绝。
    current = root_absolute  # 从项目内第一段开始检查，开发目录本身也不能是跳向别处的链接。
    for part in destination.relative_to(root_absolute).parts:  # 最终文件也检查，不能只检查它的父目录。
        current /= part  # 每一段都保留原始路径，避免解析链接后失去检查对象。
        if current.is_symlink() or current.is_junction():
            raise ValueError("输出不能经过符号链接或目录联接")  # 链接即使指回开发目录，也不作为合法输出通道。
    existing = destination  # 尚未创建的路径不能直接依赖存在性获取真实位置。
    missing = []  # 暂存缺少的尾段，等找到已有祖先后再按原顺序拼回。
    while not existing.exists():
        missing.append(existing.name)  # 从末端向上收集，不在边界确认前建立目录。
        existing = existing.parent  # 绝对路径最终会到达已有祖先，保持原有查找规则。
    canonical_existing = Path(os.path.realpath(os.fspath(existing)))  # 真实路径统一系统短名与长名，并解析已有路径。
    canonical_destination = canonical_existing.joinpath(*reversed(missing))  # 未创建的尾段接在已确认的真实祖先后。
    if not canonical_destination.is_relative_to(Path(os.path.realpath(os.fspath(base)))):
        raise ValueError("输出的真实路径越过本项目 .dev")  # 既兼容短路径，又保留真实路径边界。
    return destination  # 返回整理后的原输出路径，保存函数随后才能建目录和写文件。
