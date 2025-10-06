# Docker It Yourself 设计心得

本项目通过Go语言实现了一个符合 [Docker Registry HTTP API V2 规范](https://docs.docker.com/reference/api/registry/latest/) 的简化后端服务，其本质上依旧是一个Web应用

## 设计思路

题目中的要求并不多，主要的程序部分在于实现文档中所规定的4+7个接口。由于Go与docker的兼容性，方便在Debian GNU/Linux 13中进行测试，本人最终选择了Go语言开发+WSL2+docker的方案

在阅读三种操作流程时我了解到这一个registry的使用逻辑，并决定初步实现实体类定义和一些文件系统的基础操作。在此之后，再在实现接口的过程中逐步完善文件系统的操作（服务层）

由于本人并不是很熟悉Go应用的web开发，在花费了一段时间速通了Go语言基础后，我借助网上搜索的资料和Gemini的提示，最终采用了经典的分层架构设计，这与常用的Java Spring 开发有异曲同工之妙

在接口开发的规划中，我将接口开发分类为三个模块，逐步实现开发，并在功能测试的最后完成内部错误的处理。

详细的设计内容在[初步设计与实现文档](设计与实现文档.md)和[完整接口实现文档](接口实现文档.md)下

## 问题摘要

### DELETE 删除设计

在设计删除接口之初，我本以为只需要像数据库中一样，使用简单的命令即可。

但是文件系统并不具备像MySQL一样的系统生态，一个完全符合规范的 DELETE 需要实现复杂的引用计数和并发锁机制，以防止意外删除被其他 tag 引用的共享 Manifest

在这个功能的权衡上，我优先采取了更简易的删除 tag 功能，但在之后又根据文档具体要求，重新规范该功能：

#### tag 设计

tag 实际上是一个“指向某个 manifest digest 的链接文件

路径格式：

```
<root>/v2/repositories/<repoName>/_manifests/tags/<tag>/current/link
```

在 `link` 文件的内容中存储了 manifest 的 digest

在删除 tag 时，不会删除 manifest blob 文件，也不会删除镜像层（layer）文件，只是让这个 tag 在仓库中“消失”，即用户再也查不到这个 tag 了

### digest 指定

规范中明确指出，删除操作必须通过 digest 指定，并且只能删除未被任何 tag 引用的 manifest。因此，程序需要重构添加一些功能：

1. 修改了 Handler 层 :
   handleManifestDelete 开始时校验传入的 reference，确保它是一个 digest
2. 引入了核心的引用检查逻辑:
   在 storage.DeleteManifest 函数中，重新加入了遍历仓库 tags 目录的逻辑。在删除一个 manifest 之前，程序会检查所有 tag 的 link 文件，确认没有任何一个 tag 指向要删除的 digest。
3. 增加了并发安全措施:
   显然，“检查”和“删除”之间存在竞态条件的风险。为此，引入了文件锁 (flock) 机制，确保在执行引用检查和删除操作的整个过程中，仓库的元数据不会被其他并发请求（如 docker push）修改。

但是这时候只修改Delete函数又引伸出了一些别的问题：

#### PutManifest 修订

通过调试发现，DeleteManifest 函数在执行引用检查之前，会首先检查要删除的 manifest 是否“属于”当前仓库。我们定义这个“属于”关系的标准，是检查 _manifests/revisions/ 目录下是否存在对应的修订链接 (revision link)。然而，在原来的 PutManifest 函数中，只有tag链接，需要重新在Put部分添加revisions记录的存储

#### GetManifest 修订

修改Delete之后通过调试又发现，即使使用删除功能，getmanifest仍能找到。回顾修改发现，DeleteManifest 从删除tag变成了只是移除了仓库级的 revision 元数据（revisions/`<alg>`/`<hex>`），但 GetManifest 在以 digest 请求时仍然可能绕过对 revision 存在性的检查去直接读取全局 blob 或通过 tag 去解析，导致删除后仍能访问到该 manifest

因此在最后部分，通过在GetManifest的开始验证digest的修订链接是否在revisions中存在来使核验与Delete一直

## 优缺点分析与疑惑

### 语言选择

在项目初期的语言选择中，我比较疑惑为什么推荐用 Go？明明感觉 Java 的逻辑层次更清晰。

但是在实际的开发中我的感觉并不一样：

**Java**拥有高度抽象的框架：依赖注入 (@Autowired) 隐藏了对象的组装过程，@ControllerAdvice 集中了错误处理，Service 层明确了业务逻辑的边界。这是一种自顶向下的、由框架引导的清晰。

**Go**语言在项目结构规划的合理的情况下其实也可以拥有如同Java一样优秀的框架，但其如C一样的简易感，每一处error都需要手动定义处理却要求开发者拥有更高的专注度和自由度。相比Java，Go拥有更好的性能和资源效率优势，并且由于自底向上开发，我们也能够更好的了解其底层原理
