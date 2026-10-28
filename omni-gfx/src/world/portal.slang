/*
Omni 通用图形库末地传送门模块：每层旋转、缩放与平移的传送门纹理矩阵。
调用位置：末地传送门表面与需要层叠流动纹理的世界效果；由 `/omni-gfx/world/portal.glsl` 引入。
可复制示例：
    float4x4 clip = ogxEndPortalLayer(3.0, frameTime); // 取该层的矩阵。
设计原因与取舍：
    十六层各自不同旋转与平移，矩阵按参考实现的乘法顺序展开，调用方直接乘贴图坐标。
当前状态：由 `shaders/effects/entity/entity.glsl` 的 `end_portal_layer` 调用 `ogxEndPortalLayer`。
*/

// --- 算法说明与边界 ---
// 十六层各自不同旋转与平移，层号参与角度与缩放，叠起来才有流动感。
// 先缩放再旋转，最后乘贴图缩放平移；顺序反过来会让缩放中心跟着旋转，层与层错位。
// 末地传送门每层一个旋转、缩放与平移矩阵，十六层叠出流动纹理。
// 先缩放再旋转，最后乘贴图缩放平移；顺序反过来会让每层缩放中心跟着旋转，层与层之间错位。

#ifndef OGX_WORLD_PORTAL_INCLUDED
#define OGX_WORLD_PORTAL_INCLUDED

// 数学提供夹紧、矩阵列展开、相函数与光线求交。
#include "../common/math.slang"

// 末地传送门层：每层一个旋转、缩放与平移，叠出会流动的传送门纹理。
// 为什么先缩放再旋转：缩放要作用在贴图坐标上，旋转与平移描述层的运动；
// 顺序反过来会让每层的缩放中心跟着旋转，层与层之间出现错位。
// 平移量取层号的比例，层数越多流动越慢，和参考实现的视觉速度一致。
float4x4 ogxEndPortalLayer(float layer, float timeSeconds)
{
    float4x4 translate = float4x4(1.0, 0.0, 0.0, 17.0 / layer,
                                  0.0, 1.0, 0.0, (2.0 + layer / 1.5) * (timeSeconds * 0.0005),
                                  0.0, 0.0, 1.0, 0.0,
                                  0.0, 0.0, 0.0, 1.0); // 每层不同的平移。
    float angle = radians((layer * layer * 4321.0 + layer * 9.0) * 2.0); // 每层不同的旋转角。
    float s = (4.5 - layer / 4.0) * 2.0; // 与参考实现相同的均匀缩放。
    float4x4 scaleRotate = float4x4(s * cos(angle), -s * sin(angle), 0.0, 0.0,
                                    s * sin(angle), s * cos(angle), 0.0, 0.0,
                                    0.0, 0.0, 1.0, 0.0,
                                    0.0, 0.0, 0.0, 1.0); // 按列填写的缩放旋转矩阵。
    float4x4 uvScaleTranslate = float4x4(0.5, 0.0, 0.0, 0.25,
                                         0.0, 0.5, 0.0, 0.25,
                                         0.0, 0.0, 1.0, 0.0,
                                         0.0, 0.0, 0.0, 1.0); // 贴图坐标从零到一压到四分之一到四分之三。
    float4x4 scaledTranslate; // 缩放旋转乘平移。
    float4x4 result; // 再乘贴图缩放。
    for (int column = 0; column < 4; column++) // 逐列展开矩阵乘法。
    {
        for (int row = 0; row < 4; row++) // 逐行点积。
        {
            scaledTranslate[column][row] = scaleRotate[0][row] * translate[column][0] + scaleRotate[1][row] * translate[column][1]
                + scaleRotate[2][row] * translate[column][2] + scaleRotate[3][row] * translate[column][3]; // 第一段乘积。
            result[column][row] = scaledTranslate[0][row] * uvScaleTranslate[column][0] + scaledTranslate[1][row] * uvScaleTranslate[column][1]
                + scaledTranslate[2][row] * uvScaleTranslate[column][2] + scaledTranslate[3][row] * uvScaleTranslate[column][3]; // 第二段乘积。
        }
    }
    return result; // 参考实现的乘法顺序。
}

// 十六层各自不同旋转与平移，层号参与角度与缩放。
// 先缩放再旋转，最后乘贴图缩放平移。
// 顺序反过来会让缩放中心跟着旋转，层与层错位。
// 平移量取层号比例，层数越多流动越慢。
// 矩阵按列存放，调用方直接乘贴图坐标。
// 时间单位为秒，调用方传入累计秒数。
// 层号为零时平移项会除以零，调用方从一开始。
// 函数不修改输入，返回新矩阵。

// 每层矩阵先做旋转缩放，再做平移，最后乘贴图缩放。
// 层号从一开始，零层没有定义，调用方不要传零。
// 时间偏移只影响纵向平移，旋转角固定。
// 贴图坐标压到四分之一到四分之三，避免边缘采样。
// 矩阵乘法逐列展开，避免两种语言的行列顺序差异。
// 返回值是四乘四矩阵，调用方直接乘齐次坐标。
// 层数增加时平移变慢，视觉速度保持一致。
// 所有常数来自参考程序，不要用近似值替换。

#endif
