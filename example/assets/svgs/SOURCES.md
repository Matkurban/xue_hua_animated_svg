# SVG demo sources

All demo SVGs under this folder are **original assets authored for this package example**,
except where noted. They are intentionally small and focused so each one exercises a
specific animation path supported by `xue_hua_animated_svg`.

| File | Technique exercised | Origin |
|------|---------------------|--------|
| `elephant.svg` | SMIL `animateTransform` (scale/rotate), stroke styling | Existing package example asset (kept) |
| `pulse_circle.svg` | SMIL `<animate>` on `r` / `opacity` | Original for this showcase |
| `spin_card.svg` | SMIL `<animateTransform>` rotate + additive scale | Original for this showcase |
| `orbit_probe.svg` | `<animateMotion rotate="auto">` + `<mpath>` | Original for this showcase |
| `css_spinner.svg` | CSS `@keyframes` + `transform-origin` | Original for this showcase |
| `path_morph.svg` | Isomorphic path morph (`attributeName="d"`) | Original for this showcase |
| `dash_draw.svg` | `stroke-dasharray` / `stroke-dashoffset` + `pathLength` | Original for this showcase |
| `discrete_steps.svg` | SMIL `calcMode="discrete"` | Original for this showcase |

## 扩充的 100 款多样化动态 SVG 资产库

示例现包含 10 大分类共 100 款原创动态矢量资产，涵盖天气、自然、太空、科技、交互、生活、交通、动物、运动与艺术领域，全面覆盖 SMIL `<animate>`, `<animateTransform>`, `<animateMotion>`, 路径形变以及 CSS `@keyframes` 动画：

- **天气与气象 (`weather_*.svg`, 10款)**：晴空金阳、细雨霏霏、雷暴闪电、落雪晶莹、清风拂动、龙卷狂澜、晴后彩虹、月朗星稀、晨雾朦胧、极光幻境。
- **自然与生态 (`nature_*.svg`, 10款)**：破土新芽、百花绽放、水落涟漪、营地篝火、沧海波涛、熔岩火山、秋叶飘零、扶疏青木、劲节翠竹、山峦日出。
- **太空与天文 (`space_*.svg`, 10款)**：星际火箭、太空漫游、土星光环、飞碟引力、深空黑洞、流星破空、通信卫星、螺旋星系、天文望远镜、火星漫游车。
- **科技与电子 (`tech_*.svg`, 10款)**：智能芯片、无线信号、电池充电、振动手机、代码终端、云端机架、军工雷达、心率手表、飞行动拍、机械智灵。
- **界面与动效 (`ui_*.svg`, 10款)**：双环加载、波浪三连点、成功对勾、预警提示、通知铃铛、双齿轮啮合、下载加载、炽热心跳、流金沙漏、探索发现。
- **日常生活与美食 (`life_*.svg`, 10款)**：浓香热咖、珍珠奶茶、香脆披萨、美味汉堡、甜筒雪糕、胶片相机、温馨台灯、灵感灯泡、流金时钟、惊喜礼盒。
- **交通与出行 (`trans_*.svg`, 10款)**：疾驰跑车、云端客机、高铁穿梭、轻享单车、乘风破浪、幻彩热气球、救援直升机、路口信号灯、深海潜艇、速递电摩。
- **动物与生命 (`animal_*.svg`, 10款)**：金鱼摆尾、彩蝶翩跹、喵趣猫咪、忠诚小狗、蜂鸟凌空、幽蓝水母、企鹅漫步、静夜猫头鹰、慢悠蜗牛、横行小蟹。
- **运动与健身 (`sport_*.svg`, 10款)**：热血篮球、绿茵足球、疾风网球、力量举重、荣耀奖牌、冠军金杯、竞速秒表、百步穿杨、满月弯弓、禅意瑜伽。
- **艺术、音乐与抽象 (`art_*.svg`, 10款)**：跃动乐符、黑胶唱机、画师调色、幸运骰子、奇迹魔杖、万花流光、赛博霓虹、等轴积木、无限涡旋、流体有机液滴。


The in-memory **CyberCore** composite preset (`AnimatedSvgShowcasePresets.cyberCoreCompositeSvg`)
is defined in the package library (not an asset file). It combines 3D CSS transforms,
streaming gradients, dash growth, path morphing, and orbit motion in one scene.

## Network demo

The example catalog entry **网络大象** uses `AnimatedSvgPicture.network` with:

`https://raw.githubusercontent.com/Matkurban/xue_hua_animated_svg/main/example/assets/svgs/elephant.svg`

Local file loading (`AnimatedSvgPicture.file`) is documented in the README; the showcase app
does not ship a file-picker demo (web-incompatible).
