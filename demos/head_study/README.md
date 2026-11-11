# Loomis 基本面练习：男性 / 美少女

双击 `start.cmd` 启动，或用 Godot 4 导入本目录的 `project.godot` 后按 F5。原项目的小队竞技场入口不变。

## 现在的两个版本

以用户本次给的基本面参考图为复杂度上限。只保留额面、额侧面、两块眼窝面、大块面颊、下颌、下巴和简单鼻块；去掉眼睑轮廓、嘴唇、口轮、密集颧骨细分和三角拆分线。最多 19 个面片，包含不可见的背面与封底；男女使用相同数量的面。

- **男性 · 基本面**：较方的下颌，默认下巴半宽 0.24R，鼻块略突出。
- **美少女 · 基本面**：较窄的下巴，默认下巴半宽 0.16R，眉骨与鼻块较轻、眼窝大面略宽。保持既定高度比例，用轮廓差异表达风格，不增加五官细节。

顶部两个按钮一键切换，保留正在看的 yaw / pitch / roll 和侧圆尺寸。默认只显示大面、结构边线和虚线中线；彩色定位线、坐标轴、薄片等默认关闭。右侧只保留常用控制，其余收在“展开：球体、切片与比例设置”中。

## 操作

- **Yaw**：正值向人物自己的右侧转头。
- **Pitch**：正值低头点头。
- **Roll**：正值向人物自己的右侧歪头。
- “显示平面转折边线”切换结构线与纯明暗。
- “显示简单鼻块”切换鼻子。
- “比例线与文字”打开高度核对。
- 展开设置后可调下巴宽度、面部前伸、切片位置和薄片透明度，也可回到球体十字线练习。

姿态是绝对值，操作顺序不改变同一组角度的结果。

## 保留的比例与坐标

以球半径 R 为单位，X 朝左耳、Y 朝头顶、Z 朝脸前。侧圆半径 2R/3 时，切面距球心为 √5R/3 ≈ 0.745R。

| 定位 | 高度 |
| --- | --- |
| 发际 | +2R/3 |
| 眉骨 | 0 |
| 下眼睑定位 | −R/3 |
| 鼻底 | −2R/3 |
| 嘴线定位（默认不画嘴唇） | −R |
| 下巴 | −4R/3 |

耳朵仍从侧圆底部向上量 2R/3，用简单五边形表示，不画耳内细节。两个风格均不改变这些高度。面的形状按用户给定比例适配参考图，不宣称所有顶点都是原书公布的数值。

```text
q = Ry(−yaw) Rx(pitch) Rz(roll) p
纸上点 = 中心 + s · (qx, −qy)
```

原有球面模式仍保留：经线和赤道在球面上走弧线，到削平处接直线。面部使用少量多边形填色，遮挡查询由原生 TriangleMesh BVH 处理。转头不重建面片或 BVH。

## 验证

从仓库根目录运行（Godot 指向 Godot 4 可执行文件）：

```powershell
Godot --headless --path demos/head_study --script res://validate.gd
Godot --headless --path demos/head_study --script res://validate_loomis.gd
Godot --headless --path demos/head_study --script res://validate_secondary.gd
Godot --path demos/head_study --script res://validate_render.gd
Godot --path demos/head_study --script res://validate_render_secondary.gd
Godot --path demos/head_study --script res://benchmark.gd --disable-vsync -- --rotation-only --no-grid
Godot --path demos/head_study -- --capture
```

覆盖旋转方向与球面规则、原有比例、两个预设的实际按钮、54 组参数、面数/边数上限、男女轮廓差异、鼻子开关和极端视角。截图分别输出 `preview_male_*.png` / `preview_girl_*.png`，不提交版本管理。

RTX 3070 Laptop / Godot 4.6.2 上，默认连续旋转中位约 8ms/帧，95% 帧约 10ms 以内；不同设备会变化。
