# MonkeyDev Xcode Templates

这里维护完整的 MonkeyDev Xcode 模板，包括模板配置、向导选项和项目源码。MonkeyDev 安装器直接下载、校验并安装，不再覆盖源码或修改模板配置。

当前适配范围为 Apple Silicon Mac、Xcode 27 和 iPhoneOS arm64。MonkeyApp 提供普通 Objective-C / CaptainHook、Logos internal、fishhook、Debug LLDBTools 与 Trace；Reveal 使用用户本机 SDK，不捆绑 Cycript 或旧 Substrate 运行库。

Logos Tweak、CaptainHook Tweak、Command-line Tool 创建时可在 Package Scheme 选择 `rootless`（默认）、`rootful` 或 `roothide`。roothide 需配套支持该方案的新版 MonkeyDev，以及设备上的 roothide 兼容 ElleKit；已验证普通 App 的 Logos / CaptainHook 方法 Hook。Command-line Tool 的 C 示例已验证 roothide 自动安装与 SSH 执行，无需 Hook 框架。 仅 roothide 方案提供官方 `<roothide.h>` 路径 API；未调用时不会保留运行库依赖，rootless/rootful 不引入 SDK。

安装和使用见 [MonkeyDev](https://github.com/AloneMonkey/MonkeyDev)。在 MonkeyDev 源码目录测试本地模板：

```bash
sudo env MONKEYDEV_SOURCE_DIR="$PWD" \
  MONKEYDEV_TEMPLATES_DIR="$(dirname "$PWD")/MonkeyDev-Xcode-Templates" \
  /bin/bash bin/md-install
```

更新只影响之后创建的项目，不改动 Xcode.app 或已有工程。其他历史模板尚未纳入本轮兼容验收。

模板回归检查（macOS / Apple Silicon / 完整 Xcode）：

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -v
```

## 模板结构参考

工程模块配置:

* Identifier 
	
	模板的唯一标示符
* Kind 

	Xcode.Xcode3.ProjectTemplateUnitKind 都是这个值
* Concrete

	设置为YES的模板才可以显示在new project的dialog中，此时这个模板不能被其他模板继承
* Ancestors

	父模版，从父模版那里继承一些模板的基础属性，可以有多个父类
* Description

	新建工程时，模版的描述
* Targets

	Target的一些设置，包括编译设置
* Platforms

	运行平台
* Project

	项目的一些设置
* Options

	定义新建工程中的storyboard等
* Nodes

	定义添加到工程模版中的文件
* Definitions

	将Nodes中定义的文件添加到项目中
	
### Base模板
主要是继承一些通过父模板

* 单元测试
* deb打包
* 设置显示

Target的编译设置，安装的设备，编译时是否安装等等。

项目的设置:

TARGETED_DEVICE_FAMILY 1,2  Iphone/Ipad

文件导入以及pch文件。

### Debian Package
Package的一些编译设置。

增加文件:
Package/DEBIAN/contrl

以及文件里面的内容。

### PreferenceLoader
是否显示在设置里面。

### Unit Tests
单元测试。

### CaptainHook Tweak
类型:
动态库
编译设置:
安装路径
编译脚本

增加修改文件，编译文件，hook的对象，control内容。

### Logos Tweak
同上。
