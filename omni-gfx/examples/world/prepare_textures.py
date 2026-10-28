"""准备测试世界用的 CC0 照片贴图与程序化植物卡片。

调用位置：
    开发者在仓库根目录执行 `python omni-gfx/examples/world/prepare_textures.py`；
    产物写入 `omni-gfx/examples/world/assets/`，提交一次后测试世界不再联网。
设计原因与取舍：
    纯程序化材质很难同时具备“远看颜色自然、近看有颗粒”的两层细节。
    这里从 Poly Haven 取 CC0 扫描贴图，保留颜色、法线、粗糙度三张图；
    下载的原始 1K 图先缓存到 `.dev`，再按 2×2 盒式降采样到 512，控制仓库体积。
    法线图保持线性数据，颜色图保持 sRGB 编码，上传时由渲染器选择对应内部格式。
    草叶与树叶卡片单独生成：照片贴图里没有合适的带透明通道叶丛，
    程序化绘制可以控制叶片数量、边缘透明和颜色范围，避免整张卡片像一块绿板。
    每一步都可重复执行，已存在的产物默认跳过，不会因为重跑改变画面。
"""
from __future__ import annotations

import math  # 叶片旋转与椭圆采样。
import random  # 固定种子生成叶片形状与分布。
import sys  # 调整模块搜索路径，复用 PNG 读写。
import urllib.request  # 下载 CC0 原始贴图。
import zipfile  # ambientCG 以压缩包分发颜色、法线与粗糙度。
from pathlib import Path  # 路径计算。

HERE = Path(__file__).resolve().parent  # 测试世界目录。
LIB = HERE.parent.parent  # omni-gfx 根目录。
ROOT = LIB.parent  # 仓库根目录。
ASSETS = HERE / "assets"  # 提交到仓库的成品贴图。
CACHE = ROOT / ".dev" / "omni-gfx" / "textures"  # 原始下载缓存，不进仓库。
sys.path.insert(0, str(HERE))  # 复用测试世界的 PNG 模块。
import png  # 只依赖标准库的 PNG 读写。

TARGET_SIZE = 512  # 成品边长；1K 原图正好二倍，盒式降采样没有余数。
USER_AGENT = "Omni-development/1 (CC0 texture preparation)"  # 下载时标明用途，便于服务端识别。

# 地面与道具材质：编号、Poly Haven 资源名、中文用途。
# 每项下载颜色、OpenGL 法线、粗糙度三张 1K PNG；法线与粗糙度不经过 sRGB 转换。
MATERIALS = (
    ("dirt", "brown_mud", "泥土与小径"),
    ("rock", "rock_face_03", "岩石与山体"),
    ("sand", "damp_beach_sand", "湖岸湿沙"),
    ("forest", "forest_ground_04", "树下腐殖土"),
    ("bark", "bark_brown_02", "树皮"),
)

# 草甸地面来自 ambientCG 的 Grass004：Poly Haven 的草地扫描偏干黄，
# 这张图的叶片更密、更绿，远看才像湿润的草甸。ambientCG 同为 CC0。
GRASS_GROUND = ("grass", "Grass004", "草甸地面",
                "https://ambientcg.com/get?file=Grass004_1K-PNG.zip")

# 天空使用 Poly Haven 的纯天空全景 HDR：真实云层与太阳位置比低分辨率体积云更可信。
SKY_HDR = ("sky_wasteland", "wasteland_clouds_puresky", "天空与云",
           "https://dl.polyhaven.org/file/ph-assets/HDRIs/hdr/1k/wasteland_clouds_puresky_1k.hdr")

# 草叶卡片由本工具程序化绘制；树叶与野花卡片同理，避免使用模型 UV 图集。


def download(url: str, destination: Path) -> Path:
    """下载一个文件到缓存；已存在时直接复用。

    只接受 https 地址；下载先写临时文件，完成后替换，网络中断不会留下半张图。
    """
    if not url.startswith("https://"):  # 只从加密地址取资源。
        raise ValueError(f"下载地址必须是 HTTPS：{url}")
    if destination.exists() and destination.stat().st_size > 0:  # 缓存完整就复用。
        return destination
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_name(destination.name + ".part")  # 先写临时文件。
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})  # 标注开发下载。
    print(f"下载 {destination.name}", flush=True)
    last_error = None  # 网络偶发断连时保留最后一次错误。
    for attempt in range(4):  # 最多重试三次，避免一次抖动打断整批下载。
        try:
            with urllib.request.urlopen(request, timeout=90) as response, temporary.open("wb") as output:
                while True:  # 分块复制，避免一次性把大图读进内存。
                    block = response.read(1 << 20)
                    if not block:
                        break
                    output.write(block)
            temporary.replace(destination)  # 完整后才替换缓存。
            return destination
        except Exception as error:  # 网络错误按次数重试，文件错误在后面暴露。
            last_error = error
            temporary.unlink(missing_ok=True)  # 清理本次半包。
            if attempt < 3:  # 前三次失败后等一会儿再试。
                print(f"重试 {destination.name}（{attempt + 1}/3）", flush=True)
                import time  # 延迟只为网络退避，不参与渲染。
                time.sleep(1.5 * (attempt + 1))
    raise RuntimeError(f"下载失败：{url}") from last_error


def box_downsample(width: int, height: int, channels: int, pixels: bytes, target: int) -> bytes:
    """把 1K 图像按 2×2 盒式平均降到目标边长。

    只处理整数倍缩小，目标必须整除原尺寸；不是整数倍时退回最近邻并在调用处说明。
    盒式平均比最近邻更少噪点，法线图也不会因为抽点出现方向跳变。
    """
    if width % target or height % target:  # 非整数倍时不能做整齐的盒式降采样。
        raise ValueError(f"目标尺寸 {target} 不能整除原图 {width}×{height}")
    factor = width // target  # 横向倍数；本工具只接受与纵向相同。
    if height // target != factor:  # 宽高倍数不同会让贴图拉伸。
        raise ValueError("只支持等比例缩小")
    stride = width * channels  # 原图一行字节数。
    out = bytearray(target * target * channels)  # 结果。
    area = factor * factor  # 每个输出像素覆盖的输入像素数。
    for y in range(target):  # 逐行输出。
        for x in range(target):  # 逐列输出。
            totals = [0] * channels  # 各通道累加。
            for sy in range(factor):  # 纵向子像素。
                row = (y * factor + sy) * stride
                for sx in range(factor):  # 横向子像素。
                    offset = row + (x * factor + sx) * channels
                    for channel in range(channels):  # 逐通道累加。
                        totals[channel] += pixels[offset + channel]
            base = (y * target + x) * channels
            for channel in range(channels):  # 写入平均值。
                out[base + channel] = totals[channel] // area
    return bytes(out)


def read_material(name: str, suffix: str) -> tuple[int, int, int, bytes]:
    """解压缓存里的 1K PNG，返回原始尺寸与像素。"""
    path = CACHE / "textures" / f"{name}_{suffix}_1k.png"  # 缓存文件名与下载地址一致。
    width, height, channels, pixels = png.read_png(path)
    return width, height, channels, pixels


def material_sources(asset: str) -> dict:
    """返回一种材质的三个原始地址，不触发下载。

    来源清单需要在跳过下载时也能写出完整地址，因此地址生成与下载分开。
    """
    return {role: f"https://dl.polyhaven.org/file/ph-assets/Textures/png/1k/{asset}/{asset}_{suffix}_1k.png"
            for suffix, role in (("diff", "albedo"), ("nor_gl", "normal"), ("rough", "rough"))}


def prepare_grass_ground() -> dict:
    """把 ambientCG 的草甸压缩包转成三张 512 PNG。

    压缩包里的颜色、法线、粗糙度都是 1K 八位 PNG；
    解压后只读取需要的三张，避免把二十兆字节的整包留在仓库。
    草叶颜色偏黄绿，脚本不做色相调整，着色器再按光照与远处雾气微调。
    """
    prefix, asset, purpose, url = GRASS_GROUND
    archive = download(url, CACHE / "ambientcg" / "Grass004_1K-PNG.zip")
    mapping = {"albedo": "Grass004_1K-PNG_Color.png",
               "normal": "Grass004_1K-PNG_NormalGL.png",
               "rough": "Grass004_1K-PNG_Roughness.png"}
    with zipfile.ZipFile(archive) as package:  # 只解压需要的三张，其余留在缓存。
        for role, member in mapping.items():
            raw = package.read(member)
            width, height, channels, pixels = png.read_png(raw)
            small = box_downsample(width, height, channels, pixels, TARGET_SIZE)
            if channels == 4:
                small = strip_alpha(small, TARGET_SIZE)
            png.write_rgb(ASSETS / f"{prefix}_{role}.png", TARGET_SIZE, TARGET_SIZE, top_down_to_opengl(small))
    return {"key": prefix, "asset": asset, "purpose": purpose,
            "sources": {"albedo": url, "normal": url, "rough": url}, "license": "CC0"}


def prepare_sky_hdr() -> dict:
    """下载纯天空 HDR 到资源目录，保留原始 Radiance 文件。

    HDR 已是最终格式，不再经过 PNG 降采样；测试世界启动时自行解码。
    """
    prefix, asset, purpose, url = SKY_HDR
    destination = ASSETS / f"{prefix}.hdr"
    download(url, destination)
    return {"key": prefix, "asset": asset, "purpose": purpose, "sources": {"hdr": url}}


def prepare_material(prefix: str, asset: str, purpose: str) -> dict:
    """下载并降采样一种 Poly Haven 材质，返回来源记录。

    Poly Haven 的文件地址有固定结构：资源名、贴图类型、1K 尺寸。
    这里只取颜色、法线（OpenGL 约定）与粗糙度三种。
    """
    sources = material_sources(asset)
    for suffix, role in (("diff", "albedo"), ("nor_gl", "normal"), ("rough", "rough")):
        url = sources[role]
        cached = download(url, CACHE / "textures" / f"{asset}_{suffix}_1k.png")  # 原始图只下载一次。
        width, height, channels, pixels = png.read_png(cached)
        if channels not in (3, 4):  # 扫描图一般是 RGB，少数带无用的透明通道。
            raise ValueError(f"材质颜色通道数异常：{cached} {channels}")
        small = box_downsample(width, height, channels, pixels, TARGET_SIZE)
        if channels == 4:  # 材质不需要透明通道，去掉以减少仓库体积。
            small = strip_alpha(small, TARGET_SIZE)
        png.write_rgb(ASSETS / f"{prefix}_{role}.png", TARGET_SIZE, TARGET_SIZE, top_down_to_opengl(small))
    return {"key": prefix, "asset": asset, "purpose": purpose, "sources": sources}


def strip_alpha(pixels: bytes, size: int) -> bytes:
    """把 RGBA 像素压成 RGB，材质不需要透明通道。"""
    out = bytearray(size * size * 3)  # 结果。
    for index in range(size * size):  # 逐像素复制三个颜色通道。
        out[index * 3:index * 3 + 3] = pixels[index * 4:index * 4 + 3]
    return bytes(out)


def top_down_to_opengl(pixels: bytes) -> bytes:
    """把自上而下的 RGB 像素翻成自下而上，供 `png.write_rgb` 输出正向图片。

    `write_rgb` 原本服务 OpenGL 截图，默认接收自下而上的数据；贴图预处理得到的是
    自上而下的普通图像，翻转一次后写出的文件方向才正确。
    """
    stride = TARGET_SIZE * 3  # 每行字节数。
    out = bytearray(len(pixels))  # 结果。
    for row in range(TARGET_SIZE):  # 逐行复制到相反位置。
        out[row * stride:(row + 1) * stride] = pixels[(TARGET_SIZE - 1 - row) * stride:(TARGET_SIZE - row) * stride]
    return bytes(out)


def prepare_grass_card() -> dict:
    """程序化生成一张草丛卡片：多片弯曲草叶从底边向上散开。

    照片素材里的草丛往往是三维模型的 UV 图集，直接当卡片会看到拼接碎片。
    这里按真实草叶的形态画：根在底边、叶尖变细、带一点弯曲和枯黄边。
    渲染时把卡片锚在草根处，两三张交叉就有一小丛草，近看仍是独立叶片。
    """
    rng = random.Random(20261027)  # 固定种子，产出一致。
    rgba = bytearray(TARGET_SIZE * TARGET_SIZE * 4)  # 全透明画布。
    # 每片草叶用一条二次贝塞尔中心线表示，沿线画宽度渐变的圆点。
    for blade in range(150):  # 一百五十片，边缘自然稀疏。
        root_x = TARGET_SIZE * 0.5 + rng.uniform(-0.40, 0.40) * TARGET_SIZE
        root_y = TARGET_SIZE + rng.uniform(0.0, 40.0)  # 根部略低于画布，裁切后贴地。
        height = rng.uniform(0.45, 0.98) * TARGET_SIZE  # 叶片高度。
        lean = rng.uniform(-0.34, 0.34) * TARGET_SIZE  # 叶尖横向偏移。
        bend = rng.uniform(-0.22, 0.22) * TARGET_SIZE  # 中段弯曲。
        width = rng.uniform(3.2, 7.0)  # 根部宽度。
        tip_x = root_x + lean
        tip_y = root_y - height
        control_x = root_x + lean * 0.5 + bend
        control_y = root_y - height * 0.60
        # 颜色沿叶片渐变：基部深绿，尖端偏黄，少量枯叶。
        dry = rng.random() < 0.14
        base_color = (rng.randint(42, 70), rng.randint(64, 96), rng.randint(20, 38)) if not dry else (94, 92, 48)
        tip_color = (rng.randint(96, 150), rng.randint(128, 172), rng.randint(38, 72)) if not dry else (150, 138, 82)
        steps = max(40, int(height / 1.4))  # 沿线采样，间隔约一点四像素。
        for step in range(steps + 1):  # 从根到尖。
            t = step / steps
            one_minus = 1.0 - t
            x = one_minus * one_minus * root_x + 2.0 * one_minus * t * control_x + t * t * tip_x
            y = one_minus * one_minus * root_y + 2.0 * one_minus * t * control_y + t * t * tip_y
            radius = width * (1.0 - t) ** 0.72 * 0.5 + 0.4  # 越靠叶尖越细。
            color = tuple(int(base_color[c] * (1.0 - t) + tip_color[c] * t) for c in range(3))
            min_x = max(0, int(x - radius - 1.5))
            max_x = min(TARGET_SIZE - 1, int(x + radius + 1.5))
            min_y = max(0, int(y - radius - 1.5))
            max_y = min(TARGET_SIZE - 1, int(y + radius + 1.5))
            for py in range(min_y, max_y + 1):  # 圆点光栅化，边缘按距离羽化。
                for px in range(min_x, max_x + 1):
                    dx = px + 0.5 - x
                    dy = py + 0.5 - y
                    distance = math.sqrt(dx * dx + dy * dy)
                    coverage = min(1.0, max(0.0, radius + 0.8 - distance))  # 一像素柔边。
                    if coverage <= 0.0:
                        continue
                    base = (py * TARGET_SIZE + px) * 4
                    old_alpha = rgba[base + 3] / 255.0
                    new_alpha = coverage
                    out_alpha = new_alpha + old_alpha * (1.0 - new_alpha)
                    for channel in range(3):  # 覆盖时混合颜色。
                        front = color[channel] * new_alpha
                        back = rgba[base + channel] * old_alpha * (1.0 - new_alpha)
                        rgba[base + channel] = min(255, int(front + back / max(out_alpha, 0.001)))
                    rgba[base + 3] = min(255, int(out_alpha * 255.0))
    png.write_rgba(ASSETS / "grass_card.png", TARGET_SIZE, TARGET_SIZE, bytes(rgba))
    return {"key": "grass_card", "asset": "procedural", "purpose": "草丛卡片", "sources": {}}


def draw_leaf(rgba: bytearray, center_x: float, center_y: float, length: float, width: float,
              angle: float, color: tuple[int, int, int], seed: random.Random) -> None:
    """在 RGBA 画布上画一片带柔边的椭圆叶，并叠一条更暗的主脉。

    叶片用解析椭圆判断覆盖度，边缘一像素内做透明过渡；
    主脉是一小段偏移的暗线，近看不会只剩一块纯色。
    """
    cos_a = math.cos(angle)  # 旋转余弦。
    sin_a = math.sin(angle)  # 旋转正弦。
    radius = length * 0.55  # 包围盒半径，够容纳整片叶子。
    min_x = max(0, int(center_x - radius - 2))  # 包围盒左界。
    max_x = min(TARGET_SIZE - 1, int(center_x + radius + 2))  # 右界。
    min_y = max(0, int(center_y - radius - 2))
    max_y = min(TARGET_SIZE - 1, int(center_y + radius + 2))
    shade = 0.82 + seed.random() * 0.30  # 每片叶子亮度不同。
    vein = tuple(max(0, int(channel * 0.62)) for channel in color)  # 主脉更暗。
    for y in range(min_y, max_y + 1):  # 逐像素光栅化。
        for x in range(min_x, max_x + 1):  # 当前像素。
            dx = x + 0.5 - center_x  # 相对叶心。
            dy = y + 0.5 - center_y
            local_x = dx * cos_a + dy * sin_a  # 沿叶长方向。
            local_y = -dx * sin_a + dy * cos_a  # 沿叶宽方向。
            half_length = length * 0.5  # 半长。
            half_width = width * 0.5  # 半宽。
            # 超椭圆指数小于二，叶尖收成尖角、叶身仍然圆润，比纯椭圆更像真实叶片。
            normalized = (abs(local_x) / half_length) ** 1.55 + (abs(local_y) / half_width) ** 1.75
            if normalized > 1.06:  # 包围形状外直接跳过。
                continue
            edge = min(1.0, max(0.0, (1.06 - normalized) / 0.12))  # 边缘一像素内渐隐。
            is_vein = abs(local_y) < width * 0.07 and abs(local_x) < half_length * 0.82  # 主脉。
            base = (y * TARGET_SIZE + x) * 4
            leaf_color = vein if is_vein else tuple(int(c * shade) for c in color)  # 主脉压暗。
            old_alpha = rgba[base + 3] / 255.0  # 已有覆盖度，叶片重叠时保留上层。
            new_alpha = edge  # 本叶片覆盖度。
            out_alpha = new_alpha + old_alpha * (1.0 - new_alpha)  # 标准覆盖合成。
            if out_alpha <= 0.001:  # 全透明像素不用写。
                continue
            for channel in range(3):  # 颜色按覆盖度混合。
                front = leaf_color[channel] * new_alpha
                back = rgba[base + channel] * old_alpha * (1.0 - new_alpha)
                rgba[base + channel] = min(255, int(front + back / max(out_alpha, 0.001)))
            rgba[base + 3] = int(min(255, out_alpha * 255.0))  # 写回覆盖度。


def prepare_leaf_card() -> dict:
    """生成一簇树叶卡片：多片椭圆叶围绕几根细枝，边缘留透明。

    树冠用几十张这样的卡片交叉堆叠；卡片本身不是整棵树，
    所以叶簇要密、叶片要小，重复时才不会看出同一张图。
    固定随机种子保证每次生成相同的文件，截图可以重复。
    """
    rng = random.Random(20261025)  # 固定种子。
    rgba = bytearray(TARGET_SIZE * TARGET_SIZE * 4)  # 全透明画布。
    palette = (
        (54, 92, 34), (66, 110, 40), (78, 124, 46), (96, 136, 52),
        (44, 82, 32), (108, 142, 58), (72, 102, 38),
    )  # 偏深的自然叶绿，避免过饱和。
    # 先画三根弯曲枝条，卡片边缘不会只剩飘着的叶片。
    for branch in range(4):  # 四根枝从中心向外。
        angle = branch * math.pi * 0.5 + rng.uniform(-0.35, 0.35)
        length = rng.uniform(0.28, 0.46) * TARGET_SIZE
        start_x = TARGET_SIZE * 0.5
        start_y = TARGET_SIZE * 0.5
        steps = int(length)  # 每像素一段。
        for step in range(steps):  # 沿枝干画细线。
            progress = step / steps
            x = start_x + math.cos(angle) * step + math.sin(progress * 7.0 + branch) * 3.0
            y = start_y + math.sin(angle) * step + math.cos(progress * 6.0 + branch) * 3.0
            if 0 <= x < TARGET_SIZE and 0 <= y < TARGET_SIZE:
                base = (int(y) * TARGET_SIZE + int(x)) * 4
                rgba[base:base + 3] = bytes((62, 46, 28))  # 枝条棕褐色。
                rgba[base + 3] = 235
    # 叶片围绕中心分布，密度向边缘降低，卡片外缘不会出现一条直边。
    for index in range(720):  # 固定数量，足够覆盖一张卡片。
        angle = rng.random() * math.tau
        radius = (rng.random() ** 0.55) * TARGET_SIZE * 0.45  # 中心更密。
        center_x = TARGET_SIZE * 0.5 + math.cos(angle) * radius
        center_y = TARGET_SIZE * 0.5 + math.sin(angle) * radius
        leaf_length = rng.uniform(26.0, 52.0) * (1.0 - radius / TARGET_SIZE * 0.45)  # 外圈叶片略小。
        leaf_width = leaf_length * rng.uniform(0.34, 0.52)  # 细长叶形。
        rotation = angle + rng.uniform(-1.1, 1.1)  # 叶片朝向围绕径向散开。
        draw_leaf(rgba, center_x, center_y, leaf_length, leaf_width, rotation, rng.choice(palette), rng)
    for index in range(TARGET_SIZE * TARGET_SIZE):  # 轻微清理极低覆盖度的杂点。
        if rgba[index * 4 + 3] < 8:
            rgba[index * 4:index * 4 + 4] = b"\x00\x00\x00\x00"
    png.write_rgba(ASSETS / "leaf_card.png", TARGET_SIZE, TARGET_SIZE, bytes(rgba))
    return {"key": "leaf_card", "asset": "procedural", "purpose": "树叶卡片", "sources": {}}


def prepare_flower_card() -> dict:
    """生成一小簇彩色野花卡片，给草甸前景加红、蓝、黄、白的花点。

    花心用暖黄，花瓣按四种颜色随机；背景透明，渲染时按 alpha 测试裁切。
    数量多、花头小，远看只是草地里的彩色亮点，不会像贴了一排图案。
    """
    rng = random.Random(20261026)  # 固定种子。
    rgba = bytearray(TARGET_SIZE * TARGET_SIZE * 4)  # 透明画布。
    palette = ((214, 74, 58), (86, 120, 190), (230, 196, 74), (236, 236, 224), (180, 96, 160))
    for flower in range(34):  # 一张卡片放三十四朵。
        center_x = TARGET_SIZE * 0.5 + rng.uniform(-0.38, 0.38) * TARGET_SIZE
        center_y = TARGET_SIZE * 0.5 + rng.uniform(-0.38, 0.38) * TARGET_SIZE
        radius = rng.uniform(8.0, 15.0)  # 花头半径。
        petal_color = rng.choice(palette)
        # 先画一根细茎，花头不会像悬空贴纸。
        stem_bottom = min(TARGET_SIZE - 2, int(center_y + radius * 2.6))
        for py in range(int(center_y), stem_bottom):
            px = int(center_x + math.sin(py * 0.09) * 2.0)
            if 0 <= px < TARGET_SIZE:
                base = (py * TARGET_SIZE + px) * 4
                rgba[base:base + 4] = bytes((54, 92, 40, 225))
        for petal in range(6):  # 六片花瓣。
            angle = petal / 6.0 * math.tau + rng.uniform(-0.12, 0.12)
            px = center_x + math.cos(angle) * radius * 0.62  # 花瓣中心。
            py = center_y + math.sin(angle) * radius * 0.62
            draw_leaf(rgba, px, py, radius * 0.95, radius * 0.52, angle, petal_color, rng)  # 用叶片画花瓣。
        for py in range(max(0, int(center_y - radius * 0.35)), min(TARGET_SIZE, int(center_y + radius * 0.35))):
            for px in range(max(0, int(center_x - radius * 0.35)), min(TARGET_SIZE, int(center_x + radius * 0.35))):
                dx = px + 0.5 - center_x
                dy = py + 0.5 - center_y
                if dx * dx + dy * dy <= (radius * 0.33) ** 2:  # 圆形花心。
                    base = (py * TARGET_SIZE + px) * 4
                    rgba[base:base + 4] = bytes((198, 154, 48, 255))
    png.write_rgba(ASSETS / "flower_card.png", TARGET_SIZE, TARGET_SIZE, bytes(rgba))
    return {"key": "flower_card", "asset": "procedural", "purpose": "野花卡片", "sources": {}}


def update_sources(records: list[dict]) -> None:
    """写出资源来源与许可证清单。

    清单与贴图一起提交，任何人拿到仓库都能查到每张图的原始地址；
    Poly Haven 全部素材为 CC0，程序化卡片由本项目生成。
    """
    lines = [
        "# 测试世界贴图来源",
        "",
        "这些文件只服务 `omni-gfx/examples/world` 的独立测试世界，不进入 Minecraft 光影包。",
        "Poly Haven 素材均为 CC0（公共领域），可商用、可修改、无需署名；下列署名用于说明来源。",
        "程序化卡片由 `examples/world/prepare_textures.py` 生成，没有第三方版权。",
        "",
        "| 文件 | 用途 | 来源 | 许可证 |",
        "| --- | --- | --- | --- |",
    ]
    for record in records:  # 每个资源一行，列出三个贴图地址。
        key = record["key"]
        if record["asset"] == "procedural":  # 程序化资源没有外部地址。
            lines.append(f"| `{key}` | {record['purpose']} | 本项目生成 | 项目自有 |")
            continue
        provider = "ambientCG" if record["asset"] == "Grass004" else "Poly Haven"
        source = f"{provider} `{record['asset']}`"
        if key == "sky_wasteland":  # HDR 是单文件，不是三种贴图。
            lines.append(f"| `{key}.hdr` | {record['purpose']} | {source} | CC0 |")
            lines.append(f"| `{key}.hdr` | {record['purpose']} | <{record['sources']['hdr']}> | CC0 |")
            continue
        lines.append(f"| `{key}_*.png` | {record['purpose']} | {source} | CC0 |")
    lines.extend((
        "",
        "## 参考照片",
        "",
        "并排对比使用的真实照片单独放在 `.dev/omni-gfx/reference/`，只用于本地对比图，",
        "不进入光影包；来源与许可证记录在同目录的 `SOURCES.md`。",
    ))
    (ASSETS / "SOURCES.md").write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")


def main() -> None:
    """执行全部准备步骤；已存在的成品默认跳过。"""
    ASSETS.mkdir(parents=True, exist_ok=True)  # 成品目录。
    CACHE.mkdir(parents=True, exist_ok=True)  # 下载缓存。
    records = []
    if all((ASSETS / f"grass_{role}.png").exists() for role in ("albedo", "normal", "rough")):
        print("已就绪 grass", flush=True)
        records.append({"key": "grass", "asset": "Grass004", "purpose": "草甸地面",
                        "sources": {"albedo": GRASS_GROUND[3], "normal": GRASS_GROUND[3],
                                    "rough": GRASS_GROUND[3]}})
    else:
        records.append(prepare_grass_ground())
    if (ASSETS / "sky_wasteland.hdr").exists():  # 天空 HDR 已提交时只记录来源。
        print("已就绪 sky_wasteland", flush=True)
        records.append({"key": "sky_wasteland", "asset": SKY_HDR[1], "purpose": "天空与云",
                        "sources": {"hdr": SKY_HDR[3]}})
    else:
        records.append(prepare_sky_hdr())
    for prefix, asset, purpose in MATERIALS:  # 五种扫描材质。
        if all((ASSETS / f"{prefix}_{role}.png").exists() for role in ("albedo", "normal", "rough")):
            print(f"已就绪 {prefix}", flush=True)
            records.append({"key": prefix, "asset": asset, "purpose": purpose,
                            "sources": material_sources(asset)})
            continue
        records.append(prepare_material(prefix, asset, purpose))
    for prepare in (prepare_grass_card, prepare_leaf_card, prepare_flower_card):  # 三张植物卡片。
        target = {"prepare_grass_card": "grass_card", "prepare_leaf_card": "leaf_card",
                  "prepare_flower_card": "flower_card"}[prepare.__name__]
        if (ASSETS / f"{target}.png").exists():  # 成品存在时只记录来源，不重复生成。
            print(f"已就绪 {target}", flush=True)
            records.append({"key": target, "asset": "procedural", "purpose": "植物卡片", "sources": {}})
            continue
        records.append(prepare())
    update_sources(records)  # 写来源清单。
    print(f"完成：{ASSETS}", flush=True)


if __name__ == "__main__":
    main()
