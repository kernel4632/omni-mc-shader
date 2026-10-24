// 测试世界的大气底色：天空渐变、太阳圆盘与太阳光晕，不含云。
// 调用位置：天空着色器、地形雾、水面反射的公共底色；由这些文件按需引入。
// 设计原因与取舍：只做解析近似，不追求物理大气；目标是让地形、水面和云有统一的远景颜色。
// 太阳颜色用通用库的黑体拟合生成，顺便验证生成的 GLSL 在真实场景里可用。
#include "/omni-gfx/color.glsl"

uniform vec3 uSunDirection;  // 太阳方向，世界空间单位向量，由场景传入。

// 太阳的线性颜色：五千八百开接近真实日光，亮度归一化后由调用方决定强度。
vec3 sunColor()
{
    vec3 color = ogxBlackbody(5800.0);  // 黑体拟合给出偏暖的白。
    return color / max(ogxLuminance(color), 1e-4);  // 归一化亮度，避免色温改变整体曝光。
}

// 天空底色：地平线偏白、天顶偏蓝，地平线以下混入灰蓝色雾。
vec3 skyBase(vec3 direction)
{
    float height = max(direction.y, 0.0);  // 只看地平线以上的高度。
    vec3 horizon = vec3(0.56, 0.71, 0.90);  // 地平线的空气散射色。
    vec3 zenith = vec3(0.035, 0.13, 0.44);  // 天顶的深蓝。
    vec3 color = mix(horizon, zenith, pow(height, 0.42));  // 高度越高越蓝。
    color = mix(vec3(0.52, 0.62, 0.74), color, smoothstep(-0.12, 0.03, direction.y));  // 地平线以下用灰蓝雾。
    float sunAmount = max(dot(direction, normalize(uSunDirection)), 0.0);  // 与太阳的夹角余弦。
    color += sunColor() * (pow(sunAmount, 2200.0) * 9.0 + pow(sunAmount, 12.0) * 0.22);  // 圆盘与柔和光晕。
    return color;  // 线性高动态范围颜色。
}
