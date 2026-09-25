# [新手指导](https://github.com/wukongdaily/AutoBuildImmortalWrt/wiki) 👈🏻
# ImmortalWrt-ImageBuilder

**⚠️ 重要声明**

> **本项目为个人独立维护的第三方项目(脚本)，与 ImmortalWrt 官方没有关联。** <br>
> **项目中使用了 ImmortalWrt 官方 ImageBuilder 工具打包生成固件。<br>
> 但用户自行定制产生的任何 bug，均不代表 ImmortalWrt 官方固件的 bug**<br>
> **为了不给 ImmortalWrt 上游维护者增加额外负担和麻烦，所有相关问题请勿在 ImmortalWrt 群内反馈**。  <br>
> **建议各位在本项目 [Discussions](https://github.com/wukongdaily/ImmortalWrt-ImageBuilder/discussions) 中提问或讨论**


---

[![GitHub](https://img.shields.io/github/license/wukongdaily/AutoBuildImmortalWrt.svg?label=LICENSE&logo=github&logoColor=%20)](https://github.com/wukongdaily/AutoBuildImmortalWrt/blob/master/LICENSE)
![GitHub Stars](https://img.shields.io/github/stars/wukongdaily/AutoBuildImmortalWrt.svg?style=flat&logo=appveyor&label=Stars&logo=github)
![GitHub Forks](https://img.shields.io/github/forks/wukongdaily/AutoBuildImmortalWrt.svg?style=flat&logo=appveyor&label=Forks&logo=github)

## 🤔 这是什么？
> **本仓库已精简：只保留本机型（NanoPi R5C）所在的唯一工作流 `build-rockchip-25.12.x.yml`。**<br>
基于 CI 的 ImageBuilder 工作流，用于自动化构建 ImmortalWrt 固件。
> 1、支持自定义固件大小 默认1GB 不建议设置过大 推荐1G-2G 更大需求可通过自定义插件里的扩容插件自行扩容<br>
> 2、支持可选预安装docker（可选）支持在UI上勾选是否集成商店 （24.10.6以下）<br>
> 3、支持按需增加[第三方软件](https://github.com/wukongdaily/store/blob/master/README.md)  如何集成 https://github.com/wukongdaily/AutoBuildImmortalWrt/discussions/209 <br>
> 4、点击这里查看👉🏻[全部支持的机型列表](https://github.com/wukongdaily/AutoBuildImmortalWrt/blob/master/SUPPORT.md) 👈🏻<br>
> 5、在UI上 新增luci版本的可选项，默认最新版25.12.x https://github.com/wukongdaily/AutoBuildImmortalWrt/discussions/426<br>
> 6、支持设置管理地址的ip 比如192.168.100.1 这里强调 这项功能仅针对多网口机型 单网口的逻辑还是自动获取ip模式（dhcp）无固定ip<br>
> 7、对于[插件追新的用户 建议前往run项目 下载run后 ](https://github.com/wukongdaily/RunFilesBuilder/discussions/41)用命令sh xx.run 覆盖安装 <br>
> 8、**本仓库已精简**：仅保留唯一工作流 `build-rockchip-25.12.x.yml`（Rockchip / Luci 25.12.x），默认机型 friendlyarm_nanopi-r5c

## [基本用法步骤](https://github.com/wukongdaily/AutoBuildImmortalWrt/wiki) 👈🏻
1、fork本项目<br>
2、在fork后的项目中 点击【action】 找到 `Build 25.12.x Rockchip` 工作流后 run-workflow<br>

## 如何查询imm仓库内有哪些插件
https://mirrors.sjtug.sjtu.edu.cn/immortalwrt/releases/25.12.1/packages/aarch64_generic/luci/
## 如何查询imm仓库外目前可以集成哪些插件
https://github.com/wukongdaily/store
> 具体方法 https://github.com/wukongdaily/AutoBuildImmortalWrt/discussions/209
## 【视频教程】如何集成第三方插件？
https://www.youtube.com/watch?v=KN6AJYV1hBI <br>
https://www.youtube.com/watch?v=7i6BQeitUtE

## 旁路由的用户必读
近期不少用户修改配置文件中的默认ip地址，误认为这个工作流可以直接设置旁路ip。这是巨大的误解，这样设置就乱套了。<br>
旁路的逻辑应该是单网口模式。根据下面的固件属性可知。单网口默认采取`dhcp模式`，用户应当自行在上一级路由器查看给imm路由器分配的ip地址。
然后通过该ip来访问imm后台页面，在imm后台页面中，根据自己主路由的网段 自行配置旁路的ip地址。

## 正常路由模式必读
所谓正常的路由模式 就是指多网口用户，多网口的意思就是2个或者2个以上网口的情况。<br>
一般wan用于拨号或者自动获取ip <br>
而其他lan一般是给其他设备分配dhcp<br>
这种情况下 你可以修改路由器的默认ip  `192.168.100.1` 比如你可以修改为`192.168.80.1 ` 诸如此类。<br>
没错，修改此ip 无非就是为了避免跟光猫或者跟家庭中的其他路由器网段冲突。大多数用户，无需更改。

## 该固件默认属性？(必读)
- 该固件刷入【单网口设备】默认采用DHCP模式,自动获得ip。类似NAS的做法
- 该固件刷入【多网口设备】默认WAN口采用DHCP模式，LAN 口ip为  `192.168.100.1` <br>其中eth0为WAN 其余网口均为LAN
- 若用户在工作流中勾选了拨号信息 则WAN口模式为pppoe拨号模式。
- 建议拨号用户使用之前重启一次光猫。
- 综合上述特点，【单网口设备】应该先接路由器，先在上级路由器查看一下它的ip 再访问。
- 上述特点 你都可以通过 `99-custom.sh` 配置和调整

## 特别说明
本项目构建的固件 为了易用性 wan口防火墙规则入站 是开启的，待首次调试完毕后，建议自行关闭。操作方法如下
网络——防火墙—— wan 的入站 选择拒绝 然后保存并应用即可。更多讨论[ 请参考这个话题](https://github.com/wukongdaily/AutoBuildImmortalWrt/discussions/341)
<img width="3860" height="870" alt="image" src="https://github.com/user-attachments/assets/d826bccd-f0df-4d4a-877d-b711b81fcf1a" />
同时此项设置的相关代码详见 `files/etc/uci-defaults/99-custom.sh` 行首

## ❤️其它GitHub Action项目推荐🌟 （建议收藏）⬇️
- ### [一键生成run插件] 🆕
- https://github.com/wukongdaily/RunFilesBuilder<br>
- ### [一键生成docker离线镜像] 🆕
- https://github.com/wukongdaily/DockerTarBuilder<br>
- ### [OpenWrt/Armbian IMG安装器ISO] 🆕
- https://github.com/wukongdaily/img-installer


## ❤️如何构建docker版ImmortalWrt（建议收藏）⬇️
https://wkdaily.cpolar.cn/15
# 🎉鸣谢

感谢以下项目与作者对本项目的贡献与灵感 ❤️

<div align="left">

<a href="https://github.com/immortalwrt"><img src="https://avatars.githubusercontent.com/immortalwrt?v=4&s=80" width="80" height="80" alt="immortalwrt" /></a>
<a href="https://github.com/Openwrt-Passwall"><img src="https://avatars.githubusercontent.com/Openwrt-Passwall?v=4&s=80" width="80" height="80" alt="Openwrt-Passwall" /></a>
<a href="https://github.com/sirpdboy"><img src="https://avatars.githubusercontent.com/sirpdboy?v=4&s=80" width="80" height="80" alt="sirpdboy" /></a>
<a href="https://github.com/ophub"><img src="https://avatars.githubusercontent.com/ophub?v=4&s=80" width="80" height="80" alt="ophub" /></a>
<a href="https://github.com/linkease"><img src="https://avatars.githubusercontent.com/linkease?v=4&s=80" width="80" height="80" alt="linkease" /></a>

<a href="https://github.com/coolsnowwolf"><img src="https://avatars.githubusercontent.com/coolsnowwolf?v=4&s=80" width="80" height="80" alt="coolsnowwolf" /></a>
<a href="https://github.com/stackia"><img src="https://avatars.githubusercontent.com/stackia?v=4&s=80" width="80" height="80" alt="stackia" /></a>
<a href="https://github.com/kiddin9"><img src="https://avatars.githubusercontent.com/kiddin9?v=4&s=80" width="80" height="80" alt="kiddin9" /></a>
<a href="https://github.com/sbwml"><img src="https://avatars.githubusercontent.com/sbwml?v=4&s=80" width="80" height="80" alt="sbwml" /></a>
<a href="https://github.com/kenzok8"><img src="https://avatars.githubusercontent.com/kenzok8?v=4&s=80" width="80" height="80" alt="kenzok8" /></a>

<a href="https://github.com/timsaya"><img src="https://avatars.githubusercontent.com/timsaya?v=4&s=80" width="80" height="80" alt="timsaya" /></a>
<a href="https://github.com/AdguardTeam"><img src="https://avatars.githubusercontent.com/AdguardTeam?v=4&s=80" width="80" height="80" alt="AdguardTeam" /></a>
<a href="https://github.com/Thaolga"><img src="https://avatars.githubusercontent.com/Thaolga?v=4&s=80" width="80" height="80" alt="Thaolga" /></a>
<a href="https://github.com/eamonxg"><img src="https://avatars.githubusercontent.com/eamonxg?v=4&s=80" width="80" height="80" alt="eamonxg" /></a>
<a href="https://github.com/nikkinikki-org"><img src="https://avatars.githubusercontent.com/nikkinikki-org?v=4&s=80" width="80" height="80" alt="nikkinikki-org" /></a>

<a href="https://github.com/gdy666"><img src="https://avatars.githubusercontent.com/gdy666?v=4&s=80" width="80" height="80" alt="gdy666" /></a>
<a href="https://github.com/lwb1978"><img src="https://avatars.githubusercontent.com/lwb1978?v=4&s=80" width="80" height="80" alt="lwb1978" /></a>
<a href="https://github.com/Tokisaki-Galaxy"><img src="https://avatars.githubusercontent.com/Tokisaki-Galaxy?v=4&s=80" width="80" height="80" alt="Tokisaki-Galaxy" /></a>
<a href="https://github.com/QiuSimons"><img src="https://avatars.githubusercontent.com/QiuSimons?v=4&s=80" width="80" height="80" alt="QiuSimons" /></a>
<a href="https://xz.vumstar.com/"><img src="https://xz.vumstar.com/static/img/logo.png" width="80" height="80" alt="wukongdaily" /></a>

</div>

## ❤️赞助作者 ⬇️⬇️

<a href="https://wkdaily.cpolar.top/01" target="_blank">
  <img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png"
       alt="Buy Me A Coffee"
       style="width:15%; height:auto;">
</a>
