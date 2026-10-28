// 数学模块图案工具：拜尔抖动、切线基、旋转矩阵、径向曲线与夜视。
// 调用位置：由 `common/math.slang` 内联引入，后期、天空与吸积盘共用。
// 可复制示例：`float b = ogxInterleavedGradientNoise(pixelCoord);`
// 设计原因与取舍：图案函数保持原来的常数与矩阵展开顺序，避免画面抖动改变。

// --- 算法说明与边界 ---
// 交错梯度噪声用像素坐标的点积与小数部分，输出均匀分布在零到一。
// 拜尔矩阵从二乘二递归翻倍，每一级把旧矩阵复制到四个象限并加偏移。
// 切线基由屏幕导数构造，退化时选一个不平行的参考轴，避免叉乘得到零向量。
// 夜视只改暗部颜色，亮度越高越接近原色，避免亮处偏蓝。
// 图案与矩阵工具：交错梯度噪声、拜尔矩阵、切线基、HSV、旋转矩阵、径向曲线与夜视。
// 拜尔矩阵按二乘二递归生成到一百二十八，给逐像素抖动使用。
// 切线基由屏幕导数构造，旋转矩阵用于天空与行星；夜视把暗部颜色向偏蓝亮度混合。
// 交错梯度噪声用像素坐标的点积与小数部分，输出均匀分布在零到一。
// 拜尔矩阵从二乘二递归翻倍，每一级把旧矩阵复制到四个象限并加偏移。
// 切线基由屏幕导数构造，退化时选一个不平行的参考轴，避免叉乘得到零向量。
// 夜视只改暗部颜色，亮度越高越接近原色，避免亮处偏蓝。


// --- 抖动表、切线基与颜色图案 ---

// 交错梯度噪声：一个像素一个值，适合做抖动，常数来自原始论文。
float ogxInterleavedGradientNoise(float2 coordinate)
{
    // 两个大常数来自原始论文，乘完取小数就是每像素稳定的伪随机值，不需要纹理。
    return fract(52.9829189 * fract(0.06711056 * coordinate.x + 0.00583715 * coordinate.y));
}

// 二乘二拜尔矩阵：四个格子依次得到零、四分之一、二分之一、四分之三。
float ogxBayer2(float2 a)
{
    // 先取整：同一格里的不同小数必须得到同一个阈值，否则抖动会退化成噪点。
    a = floor(a);
    // 二乘二矩阵的四个值由这两个系数交错得到，范围正好是零到四分之三。
    return fract(dot(a, float2(0.5, a.y * 0.75)));
}

// 四乘四拜尔矩阵：由二乘二嵌套得到，用来做稳定抖动。
// 四乘四由二乘二嵌套：低频层乘四分之一，高频层原样，阈值均匀铺满十六格。
float ogxBayer4(float2 a) { return ogxBayer2(0.5 * a) * 0.25 + ogxBayer2(a); }

// 八乘八拜尔矩阵。
// 八乘八继续嵌套；低频用四阶、高频用二阶，是拜尔矩阵的递推写法。
float ogxBayer8(float2 a) { return ogxBayer4(0.5 * a) * 0.25 + ogxBayer2(a); }

// 十六乘十六拜尔矩阵：四层二乘二矩阵嵌套，抖动级别比八乘八细四倍。
// 十六阶开始两层都用四阶，频率间隔更大，适合时间累积前的初始抖动。
float ogxBayer16(float2 a) { return ogxBayer4(0.25 * a) * 0.0625 + ogxBayer4(a); }

// 三十二乘三十二拜尔矩阵：低频一档换成八乘八，级别再细四倍。
// 三十二阶用八阶低频加四阶高频，格数翻倍但只多一次二阶调用。
float ogxBayer32(float2 a) { return ogxBayer8(0.25 * a) * 0.0625 + ogxBayer4(a); }

// 六十四乘六十四拜尔矩阵：范围大，适合时间累积前的初始偏移。
// 六十四阶两层都用八阶；0.015625 是六十四分之一，保证总和落回零到一。
float ogxBayer64(float2 a) { return ogxBayer8(0.125 * a) * 0.015625 + ogxBayer8(a); }

// 一百二十八乘一百二十八拜尔矩阵：目前最细的一档，给低步数光追分摊首帧噪点。
// 一百二十八阶是当前最细一档，低频十六阶、高频八阶，用于低步数光追的首帧分摊。
float ogxBayer128(float2 a) { return ogxBayer16(0.125 * a) * 0.015625 + ogxBayer8(a); }

// 切线基的三个方向；用结构体而不是矩阵，避免两种语言的行列顺序不同造成转置错误。
struct OgxTangentBasis
{
    float3 tangent;
    float3 bitangent;
    float3 normal;
};

// 由位置与纹理导数构造切线基：先叉乘得到法线，再解切线与副切线。
// 模型没提供切线时只能这样反推；返回结构体，调用方按字段读取。
// 切线基为什么用导数反推：Minecraft 的方块模型不一定带切线，顶点阶段也拿不到接缝信息；
// 用屏幕空间的位置差与纹理差构造，能在任意几何上得到一致的法线贴图方向。
// 退化时（位置差共线）叉乘接近零，最后除以模长会把方向压回单位长度，不产生无穷大。
OgxTangentBasis ogxTangentBasis(float3 dp1, float3 dp2, float2 duv1, float2 duv2)
{
    float3 normal = normalize(cross(dp1, dp2));
    float3 dp2perp = cross(dp2, normal);
    float3 dp1perp = cross(normal, dp1);
    float3 tangent = normalize(dp2perp * duv1.x + dp1perp * duv2.x);
    float3 bitangent = normalize(dp2perp * duv1.y + dp1perp * duv2.y);
    float invmax = 1.0 / sqrt(max(dot(tangent, tangent), dot(bitangent, bitangent)));
    OgxTangentBasis basis;
    basis.tangent = tangent * invmax;
    basis.bitangent = bitangent * invmax;
    basis.normal = normal;
    return basis;
}

// 色相、饱和度、明度：按最大通道选扇区，再算色相与饱和度。
// 为什么放在数学模块：宿主的公共数学包装与体积光编码都要用，属于共享颜色工具。
// 输入假设在零到一之间，超出范围时取模结果会绕回，调用方要先夹紧。
// 色相以六分之一圈为单位，除以六段再取小数，和参考实现完全一致。
// 色相、饱和度、明度：按最大通道选扇区，再算色相与饱和度。
// 为什么放在颜色模块：表面湿润、体素着色与光传播编码都要把颜色拆成 HSV，属于共享颜色工具。
float3 ogxRgbToHsv(float3 color)
{
    static const float4 K = float4(0.0, -1.0, 2.0, -3.0) / 3.0;
    const float e = 1.0e-10;
    float4 p = lerp(float4(color.bg, K.wz), float4(color.gb, K.xy), step(color.b, color.g));
    float4 q = lerp(float4(p.xyw, color.r), float4(color.r, p.yzx), step(p.x, color.r));
    float d = q.x - min(q.w, q.y);
    return float3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

// 色相、饱和度、明度的拆解在颜色模块；这里只保留图案与坐标工具。

// 三个轴的旋转合成：先俯仰、再偏航、最后滚转，供吸积盘与末地行星摆正自己的坐标系。
// 这里保留原程序的扁平构造参数顺序：生成 GLSL 后由 GLSL 的列主序规则解释，
// 因此运行时矩阵与旧实现完全相同；不要在 Slang 侧改成按列传入，否则生成文本会换序。
float3x3 ogxRotateMatrix(float x, float y, float z)
{
    float3x3 matx = float3x3(1.0, 0.0, 0.0, 0.0, cos(x), sin(x), 0.0, -sin(x), cos(x)); // 绕横轴俯仰。
    float3x3 maty = float3x3(cos(y), 0.0, -sin(y), 0.0, 1.0, 0.0, sin(y), 0.0, cos(y)); // 绕纵轴偏航。
    float3x3 matz = float3x3(cos(z), sin(z), 0.0, -sin(z), cos(z), 0.0, 0.0, 0.0, 1.0); // 绕前后轴滚转。
    return maty * matx * matz; // 三个旋转按原程序的顺序合成。
}

// 绕纵轴的旋转矩阵：末地天空、行星与雾相位共用同一份，避免各自抄一遍符号。
float3x3 ogxRotationY(float angle)
{
    return float3x3(cos(angle), 0.0, sin(angle), 0.0, 1.0, 0.0, -sin(angle), 0.0, cos(angle)); // 与参考实现的偏航矩阵逐项一致。
}

// 先俯仰再偏航的旋转：行星与末地雾用同一套 y 轴朝上的天球坐标。
// 为什么单独成函数：两处原来各写三行矩阵，符号一旦改错会让雾和行星的相位对不上。
float3x3 ogxRotationXThenY(float angleX, float angleY)
{
    float3x3 rotationX = float3x3(1.0, 0.0, 0.0, 0.0, cos(angleX), -sin(angleX), 0.0, sin(angleX), cos(angleX)); // 俯仰。
    return rotationX * ogxRotationY(angleY); // 参考实现的相乘顺序。
}

// 环形径向轮廓：中心亮、边缘按四次方乘线性衰减，用于光晕。
float ogxRadialCurve(float x){
    float x2 = x * x;
    return 12.207 * x2 * x2 * (1.0 - x);
}

// 夜视：把颜色往偏蓝的亮度上拉一半，暗处看得清但保留一点原色。
// 为什么保留在通用数学：宿主的公共数学包装 `DoNightEye` 直接调用它，多个阶段共用；
// 它不是某一个效果的私有算法。
void ogxDoNightEye(inout float3 color)
{
    float luma = ogxLuminance(color); // 原色亮度。
    color = lerp(color, luma * float3(0.7771, 1.0038, 1.6190), float3(0.5)); // 偏蓝亮度与原色各占一半。
}
