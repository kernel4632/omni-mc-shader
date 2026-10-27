"""计算路径回归：验证计算阶段登记、SSBO 用法与离线编译错误定位。

示例 python -m unittest discover -s tests；只运行离线编译器，不建立显卡上下文。
"""
import subprocess  # 使用项目内真实编译器检查计算阶段。
import tempfile  # 编译产物放临时目录，不污染源码。
import unittest  # 保留标准测试入口。
from pathlib import Path  # 临时文件固定在自有目录。
import build  # 读取真实流程表与编译器位置。
import options  # 读取生成菜单，确认能力开关登记。
import support  # 共享展开缓存，避免重复展开计算入口。

class ComputeTests(unittest.TestCase):
    """检查计算着色器基础设施与失败可读性。"""
    def test_compute_entry_and_capability_registered(self):
        """计算入口按维度登记，Iris 计算能力开关写入流程设置。"""
        files = build.program_files()  # 读取真实流程表。
        for dimension in ("world0","world-1","world1"):
            path = build.SHADERS/dimension/"setup.csh"; self.assertIn(path,files)  # 每个维度登记计算入口。
            self.assertTrue(files[path].startswith("#version 430")); self.assertIn("#define OMNI_COMPUTE",files[path])  # 计算阶段需要更高版本与选择宏。
        settings = options.read_pipeline(build.SHADERS/"rendering/pipeline.properties")  # 流程设置是唯一来源。
        self.assertIn("COMPUTE_SHADERS",settings["iris.features.optional"])  # 计算能力登记为可选。
        _,_,generated = build.configuration(); text = generated[build.SHADERS/"shaders.properties"]  # 生成菜单同样带出能力开关。
        self.assertIn("COMPUTE_SHADERS",text)  # 能力开关不丢失。

    def test_minimal_compute_and_ssbo_compiles(self):
        """最小计算着色器与 SSBO 用法必须被项目内编译器接受。"""
        source = "#version 430\nlayout(local_size_x=8,local_size_y=8,local_size_z=8) in;\nlayout(std430) buffer Cells { vec4 cells[]; } lpv;\nvoid main(){ uint i=gl_GlobalInvocationID.x; if(i<64u) lpv.cells[i]=vec4(0.0); }\n"  # 最小三维工作组与缓冲存储。
        with tempfile.TemporaryDirectory() as temporary:
            shader = Path(temporary)/"probe.comp"; shader.write_text(source,encoding="utf-8")  # 临时计算源码。
            result = subprocess.run([str(build.tool("glslang")),"-l",str(shader)],capture_output=True,text=True,encoding="utf-8",errors="replace")
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)  # 通过才说明计算路径可用。

    def test_compute_compile_error_reports_source(self):
        """计算着色器错误必须报告文件名与行号，便于定位维护文件。"""
        source = "#version 430\nlayout(local_size_x=1) in;\nvoid main(){ omniMissingSymbol(); }\n"  # 故意引用不存在的函数。
        with tempfile.TemporaryDirectory() as temporary:
            shader = Path(temporary)/"broken.comp"; shader.write_text(source,encoding="utf-8")  # 临时错误源码。
            result = subprocess.run([str(build.tool("glslang")),"-l",str(shader)],capture_output=True,text=True,encoding="utf-8",errors="replace")
            self.assertNotEqual(result.returncode,0)  # 错误必须失败而不是静默通过。
            message = result.stdout+result.stderr; self.assertIn(shader.name,message); self.assertIn(":3",message)  # 报错包含文件名与出错行。

    def test_lpv_grid_and_sampling_registered(self):
        """光传播体积登记 setup 与 shadowcomp 两个计算阶段、四张图像与片元混光。"""
        found,_,_ = support.configuration()  # 读取真实原生选项。
        self.assertIn(found["OMNI_LPV_ENABLED"].values, (("false", "true"), ("0", "1")))  # 体积光为开关选项。
        self.assertEqual(found["OMNI_LPV_SIZE"].values,("6","7","8"))  # 体积边长保持三档。
        settings = options.read_pipeline(build.SHADERS/"rendering/pipeline.properties")  # 流程设置唯一来源。
        for name in ("image.omniLpv1","image.omniLpv2","image.omniLpvVoxel","image.omniLpvBlocks"):  # 两张传播缓冲、体素图与方块光表。
            self.assertIn(name,settings)  # 体积图像在流程设置登记。
        scene = support.expand(build.SHADERS/"world0/shadowcomp.csh")  # 从传播计算入口展开。
        self.assertIn("omniLpvMixNeighbours",scene)  # 邻居混合接入传播阶段。
        self.assertIn("omniLpvReadAt",scene)  # 上一帧体积值读取接入传播阶段。
        effect = support.code("effects/shared/lpv.glsl")  # 效果主体。
        self.assertIn("uvec2 omniLpvBlockData",effect)  # 方块光表独立成函数。
        self.assertIn("vec3 omniLpvApply",effect)  # 片元混光独立成函数。

    def test_lpv_image_writes_have_visibility_barriers(self):
        """传播只在单次派发里写一张图、读另一张图，靠共享缓冲与一次工作组同步，不需要图像屏障。"""
        source = support.text("rendering/lpv.glsl")  # 读取计算主体而不是复制实现。
        self.assertNotIn("memoryBarrierImage",source)  # 读写的不是同一张图，没有同派发内的先后依赖。
        self.assertEqual(source.count("barrier();"),1)  # 共享缓冲填充完成后同步一次工作组。
        self.assertRegex(source, r"(defined\s+)?OMNI_LPV_ENABLED\s*&&\s*defined\s+IRIS_FEATURE_CUSTOM_IMAGES")  # 关闭或缺少能力时不读写图像。

    def test_wave_simulation_compute_and_images_registered(self):
        """波浪模拟登记三个计算阶段与三张图像，选项默认关闭，采样接入水面片元。"""
        found,_,_ = support.configuration()  # 读取真实原生选项。
        self.assertIn(found["OMNI_WAVE_SIMULATION"].values, (("false", "true"), ("0", "1")))  # 波浪模拟为开关选项。
        self.assertIn(found["OMNI_WAVE_SIMULATION"].default, ("false", "0"))  # 默认关闭，默认画面不变。
        files = build.program_files()  # 读取真实流程表。
        for name,stage in (("prepare","OMNI_WAVE_SIM_PREPARE"),("prepare1","OMNI_WAVE_SIM_SPREAD"),("prepare2","OMNI_WAVE_SIM_GRADIENT")):  # 三个阶段各自一个计算入口。
            path = build.SHADERS/"world0"/(name + ".csh")  # 主世界的该阶段入口。
            self.assertIn(path,files)  # 阶段在流程表登记。
            self.assertIn("#define " + stage,files[path])  # 入口带对应阶段宏。
        settings = options.read_pipeline(build.SHADERS/"rendering/pipeline.properties")  # 流程设置唯一来源。
        for key in ("image.omniWaveSim","image.omniWaveSim2","image.omniWaveState"):  # 两张模拟场加一张跨帧状态图像。
            self.assertIn(key,settings)  # 三张图像在流程设置登记。
        self.assertIn("omniWaveSimStep",support.text("rendering/watersim.glsl"))  # 推进公式在计算主体里。
        self.assertIn("omniWaveSimNormal",support.code("effects/shared/water/wavesim.glsl"))  # 片元采样独立成函数。
        self.assertIn("omniWaveSimNormal",support.text("rendering/translucent.glsl"))  # 模拟法线接入水面片元。
