"""Omni 通用图形库的唯一构建入口：生成 GLSL、编译 SPIR-V、运行测试世界和统计行数。

调用位置：开发者在仓库根目录或本目录执行；Minecraft 光影构建不调用这里。
调用示例：
    python omni-gfx/build.py generate
    python omni-gfx/build.py spirv
    python omni-gfx/build.py demo --frames 240 --screenshot .dev/omni-gfx/world-phase3.png
    python omni-gfx/build.py test-gpu
    python omni-gfx/build.py count
设计原因与取舍：
    一个命令覆盖从源到产物的整条链，避免手工记多个脚本与参数。
    GLSL 生成不依赖 Slang 编译器，保证没有工具链的机器也能检查光影包是否最新；
    SPIR-V 才需要编译器，缺少时明确报错，不悄悄跳过。
"""
from __future__ import annotations

import argparse  # 明确的子命令与参数，错误在入口一次报出。
import hashlib  # 记录 SPIR-V 摘要，便于判断产物是否变化。
import subprocess  # 运行测试世界和 GPU 测试，保持各自独立进程。
import sys  # 用当前解释器执行子脚本。
from pathlib import Path  # 项目内路径统一计算。

LIB = Path(__file__).resolve().parent  # omni-gfx 根目录。
ROOT = LIB.parent  # 仓库根目录。
sys.path.insert(0, str(LIB / "tools"))  # 工具目录不是包，直接加入搜索路径。

import generate  # 生成器只依赖标准库。
import slang  # 编译器定位与调用。
import count  # 行数统计，输出口径集中在单独文件。


def command_generate() -> None:
    """生成全部 GLSL 并写入两个位置，然后报告文件数与行数。

    生成失败会在写文件前抛出，因此不会留下半套产物。
    """
    written = generate.write_modules()  # 生成并写入清单。
    lines = sum(len(path.read_text(encoding="utf-8").splitlines()) for path in written if path.suffix == ".glsl")  # 产物总行数用于快速核对。
    print(f"生成完成：{len(generate.MODULES)} 个模块，{len(written)} 个文件，GLSL 共 {lines} 行")


def command_check() -> None:
    """只读检查生成文件是否与源一致，并审计两个测试世界的着色器中文说明。

    这条命令适合提交前快速确认，和项目根目录的完整验证互不替代。
    测试世界的 Python 是开发期消费者，不进入光影 ZIP，也不参与库注释比例；
    真正会被加载器编译的 GLSL 仍按中文说明规则检查。生成文件由 `generate` 校验。
    """
    generate.check_modules()  # 过期或缺失都会列出具体路径。
    sys.path.insert(0, str(ROOT))  # 复用项目根的中文说明审计器。
    import audit  # 审计规则只有一份，库不另写一套。
    world = audit.check(LIB / "examples" / "world" / "shaders")  # 户外测试世界。
    lighting = audit.check(LIB / "examples" / "lighting" / "shaders")  # 光影验证场景。
    print(f"生成文件与源一致：{len(generate.MODULES)} 个模块；"
          f"测试世界着色器中文说明审计通过 {len(world)} 个文件，光影验证场景 {len(lighting)} 个文件")


def command_spirv(download: bool) -> None:
    """把每个模块探针编译成 SPIR-V，并写可复现的清单。

    `download` 为真时才联网获取编译器；普通构建不会自动下载。
    产物放在 `generated/spirv`，二进制由忽略规则排除，不入仓库。
    模块缺少探针时直接失败：探针缺口会让某类写法从未经过编译器，
    这种“跳过”看起来像通过，所以不保留跳过路径。
    """
    generate.check_modules()  # 先确保 GLSL 与源一致，避免两套产物来自不同源。
    missing = [name for name in generate.MODULES if not (slang.PROBES / f"{name}.slang").is_file()]  # 每个模块都要有探针。
    if missing:  # 缺口一次报全，避免补一个又冒出下一个。
        raise ValueError("缺少模块探针，请补齐后再编译：" + "、".join(missing))
    if download:
        print("下载 Slang 编译器到本机工具目录……")
        print("编译器位置：" + str(slang.download()))
    entries = []  # 每个模块一条记录，写进清单。
    for module in generate.MODULES:  # 逐模块编译，互不影响。
        output = slang.SPIRV_OUT / f"{module}.spv"  # 输出与模块同名。
        slang.compile_probe(module, output)  # 失败时带回编译器前几行错误。
        data = output.read_bytes()  # 读回实际产物计算大小与摘要。
        entries.append({"module": module, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()})  # 清单只记录可复现信息。
    import json  # 清单格式简单，局部导入保持顶部依赖精简。
    manifest = {"schemaVersion": 1, "compiler": slang.version(), "probes": entries}  # 版本号是复现条件之一。
    slang.SPIRV_OUT.mkdir(parents=True, exist_ok=True)
    (slang.SPIRV_OUT / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")  # 固定换行与缩进。
    print(f"SPIR-V 生成完成：{len(entries)} 个模块，编译器 {manifest['compiler']}")


def command_demo(extra: list[str]) -> None:
    """运行不启动 Minecraft 的程序化测试世界，参数原样交给示例脚本。

    示例脚本自己创建窗口、渲染和截图；这里只负责用当前解释器启动，
    避免在构建入口复制一套相机与场景参数。
    """
    render = LIB / "examples" / "world" / "render.py"  # 测试世界入口。
    subprocess.run([sys.executable, str(render), *extra], cwd=ROOT, check=True)  # 参数和退出码直接透传。


def command_lighting(extra: list[str]) -> None:
    """运行光影验证场景：简单地形、材质球、水面、雾与体积云。

    与 `demo` 分开是因为两者验收目标不同：`demo` 追求户外照片氛围，
    这里只检验太阳、天空、阴影、环境光、雾、云与水面是否各自成立。
    """
    render = LIB / "examples" / "lighting" / "render.py"  # 光影验证场景入口。
    subprocess.run([sys.executable, str(render), *extra], cwd=ROOT, check=True)  # 参数透传。


def command_gpu() -> None:
    """运行旧库与新库的 GPU 等值测试。

    需要真实 OpenGL 上下文；不放在项目根目录的十秒检查里，
    因为它依赖显卡与窗口系统，不能作为离线构建的门禁。
    """
    script = LIB / "tests" / "equivalence.py"  # 等值测试入口。
    subprocess.run([sys.executable, str(script)], cwd=ROOT, check=True)  # 成功与失败都由测试脚本报告。


def command_count(as_json: bool) -> None:
    """统计手写、生成和第三方代码行数，按计划规定的口径分开报告。

    `as_json` 为真时输出机器可读结果，方便写进验证记录。
    """
    count.report(as_json=as_json)  # 统计规则只在统计模块维护一份。


def command_parity() -> None:
    """重新生成函数级覆盖对照表，并打印一行统计。

    这一步只读参考源码与库源码，不联网、不改生成物，因此可以随时运行。
    """
    script = LIB / "tools" / "parity.py"  # 对照表生成器。
    subprocess.run([sys.executable, str(script)], cwd=ROOT, check=True)  # 失败由脚本以非零状态报告。


def main() -> None:
    """解析子命令并执行，未知参数由参数解析器统一拒绝。

    默认展示帮助，避免误执行耗时或联网的步骤。
    """
    parser = argparse.ArgumentParser(description="omni-gfx 构建与验证入口")  # 中文帮助文本。
    sub = parser.add_subparsers(dest="command")  # 每个子命令一个功能。
    sub.add_parser("generate", help="生成 GLSL 330 到光影包与 generated 目录")  # 纯本地生成。
    sub.add_parser("check", help="只读检查生成文件是否过期")  # 提交前快速检查。
    spirv = sub.add_parser("spirv", help="把模块探针编译成 SPIR-V")  # 需要 Slang 编译器。
    spirv.add_argument("--download", action="store_true", help="缺少编译器时从官方发布页下载")  # 显式联网。
    demo = sub.add_parser("demo", help="运行程序化测试世界并截图")  # 需要显卡与窗口系统。
    demo.add_argument("rest", nargs=argparse.REMAINDER, help="传给测试世界的参数")  # 不在两层重复定义参数。
    lighting = sub.add_parser("lighting", help="运行光影验证场景并截图")  # 需要显卡与窗口系统。
    lighting.add_argument("rest", nargs=argparse.REMAINDER, help="传给光影验证场景的参数")  # 参数透传。
    sub.add_parser("test-gpu", help="运行旧库与新库的 GPU 等值测试")  # 需要显卡。
    counter = sub.add_parser("count", help="统计各类代码行数")  # 只读统计。
    counter.add_argument("--json", action="store_true", help="输出机器可读结果")  # 方便写入记录。
    sub.add_parser("parity", help="重新生成函数级覆盖对照表")  # 只读参考源码与库源码。
    args = parser.parse_args()  # 解析失败时参数解析器自行退出。
    if args.command == "generate":
        command_generate()
    elif args.command == "check":
        command_check()
    elif args.command == "spirv":
        command_spirv(args.download)
    elif args.command == "demo":
        command_demo(args.rest)
    elif args.command == "lighting":
        command_lighting(args.rest)
    elif args.command == "test-gpu":
        command_gpu()
    elif args.command == "count":
        command_count(args.json)
    elif args.command == "parity":
        command_parity()
    else:
        parser.print_help()  # 没有子命令时只显示帮助，不执行任何动作。


if __name__ == "__main__":
    main()
