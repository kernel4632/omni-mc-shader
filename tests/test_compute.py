"""计算路径回归：验证计算阶段登记、SSBO 用法与离线编译错误定位。

示例 python -m unittest discover -s tests；只运行离线编译器，不建立显卡上下文。
"""
import subprocess  # 使用项目内真实编译器检查计算阶段。
import tempfile  # 编译产物放临时目录，不污染源码。
import unittest  # 保留标准测试入口。
from pathlib import Path  # 临时文件固定在自有目录。
import build  # 读取真实流程表与编译器位置。
import options  # 读取生成菜单，确认能力开关登记。

class ComputeTests(unittest.TestCase):
    """检查计算着色器基础设施与失败可读性。"""
    def test_compute_entry_and_capability_registered(self):
        """计算入口按维度登记，Iris 计算能力开关写入流程设置。"""
        files = build.program_files()  # 读取真实流程表。
        for dimension in ("world0","world-1","world1"):
            path = build.SHADERS/dimension/"setup.csh"; self.assertIn(path,files)  # 每个维度登记计算入口。
            self.assertTrue(files[path].startswith("#version 430")); self.assertIn("#define OMNI_COMPUTE",files[path])  # 计算阶段需要更高版本与选择宏。
        settings = options.read_properties(build.SHADERS/"rendering/pipeline.properties")  # 流程设置是唯一来源。
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
        """光传播体积登记计算传播与片元采样，关闭时保持屏幕空间回退。"""
        found,_,_ = build.configuration()  # 读取真实原生选项。
        self.assertEqual(found["OMNI_LPV_ENABLED"].values,("false","true"))  # 体积光为开关选项。
        self.assertEqual(found["OMNI_LPV_STEPS"].values,("2","4","6"))  # 传播步数保持偶数，末尾回到源图像。
        scene = build.expand(build.SHADERS/"world0/setup.csh")  # 从计算入口展开。
        self.assertIn("void omniLpvSeed",scene); self.assertIn("void omniLpvSpreadAB",scene)  # 注入与传播接入计算入口。
        effect = (build.SHADERS/"effects/lpv.glsl").read_text(encoding="utf-8")  # 效果主体。
        self.assertIn("vec3 omniLpvSample",effect)  # 片元采样独立成函数。
        composite = build.expand(build.SHADERS/"world0/composite.fsh")  # 从合成入口展开。
        self.assertIn("omniLpvSample",composite)  # 间接光阶段包含体积采样。
        settings = options.read_properties(build.SHADERS/"rendering/pipeline.properties")  # 流程设置唯一来源。
        self.assertIn("image.omniLpvA",settings); self.assertIn("image.omniLpvB",settings)  # 体积格在流程设置登记。
