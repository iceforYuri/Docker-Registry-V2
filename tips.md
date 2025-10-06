## Pull request有感

一个健壮的实现会在 PutManifest 的时候，将 Content-Type 和 manifest 内容一起存储。例如，在 manifest 的 blob 旁边存一个小的元数据文件，或者使用支持元数据的文件系统/对象存储。然后在 GetManifest 时读取并返回这个被存储的 Content-Type。

## DELETE 简化

| **特性**     | **我的简化实现 (**DELETE**by Tag)**                      | **官方规范 (**DELETE**by Digest)**               |
| ------------------ | -------------------------------------------------------------------- | ------------------------------------------------------------ |
| **目标**     | **/v2/{name}/manifests/latest**                                | **/v2/{name}/manifests/sha256:abcdef...**              |
| **操作**     | **删除一个**指针**（tag link 文件）**                          | **删除**清单本身**（manifest blob 的一个引用）**       |
| **核心问题** | **“我不想再让** **latest** **指向这个镜像了。”** | **“我想从系统中彻底删除这个清单（如果可能的话）。”** |
| **复杂度**   | **非常低**：就是一个 **os.Remove()** **操作。**    | **非常高**：需要实现引用计数和原子性检查。             |

## ManifestPut修改

* 第二次推送 (alpine:3.18) 开始。此时 latest tag 指向 alpine:3.17 的 Manifest。
* PutManifest 函数 被调用。它进入了 "Case B: Tag 已存在" 的逻辑。
* 代码读取了 alpine:3.17 的内容，发现它是一个单架构 Manifest，而不是 list。
* 于是，代码进入了这个分支："Subcase B2: 已存在的是一个单架构 manifest。我们需要从它创建一个新的 manifest list。"

此时修改了分片逻辑仍未解决

对于同一个tag，同一个manifest应该被替换而不是被追加，但是在执行完替换后，worklist中仅剩一个条目

服务器在 GET /manifests/latest 时，实际返回的 Docker-Content-Digest 头。而测试脚本却错误地信任了 docker inspect 的结果作为“预期值”，它受到了本地缓存的污染，我们应该从服务器的响应中获取真实的条目。

### 两种方案对比

元数据文件（完整项目中更合适）：

* 在 PutManifest 时，除了写入 data 文件，还在旁边创建一个 metadata.json 文件，内容是 {"Content-Type": "...", "digest": "..."}。
* 在 GetManifest 时，先读取 metadata.json 获取 Content-Type，然后再读取 data 文件获取内容。
* 容易导致该文件读写的原子性问题

内容中推断：

* 在 GetManifest 时，先读取 data 文件的全部内容
* 尝试将内容解析为一个只包含 mediaType 字段的最小化 JSON 结构。
* 如果解析成功，就使用这个 mediaType 作为 Content-Type。
* 如果未来需要支持一种没有 mediaType 字段的新 manifest 格式，这个方案就会失效。

## 存储理解

* 语义差别：
  * 删除 tag（删除 tags/`<tag>`/current/link）只是移除一个标签对某个 digest 的引用 —— manifest 仍被视为“仓库内存在”的修订（revisions 条目仍在）。这是“取消标签”的行为，不等同于从仓库中删除 manifest。
  * 删除 revision（删除 revisions/`<alg>`/`<hex>` 目录及其 link）才是真正把该 digest 从该仓库的元数据中移除——也就是“从仓库中删除”这个 manifest（但不删除全局 content-addressed blob 数据，GC 另作处理）。
* 为什么要改为删除 revisions：
  * Registry 的语义是：manifest 是仓库级的实体，其存在状态由仓库的元数据（revisions + tag links）决定。要把 manifest 从仓库中删除，必须移除 revisions 记录；单纯删除某个 tag 不足以代表 manifest 被删除。
  * 这样可以区分「有无标签但仍为仓库修订」与「完全从仓库中移除」，与上游 Registry 的行为一致，并便于实现垃圾回收策略（只移除仓库元数据，真正的 blob 数据由 GC 在确认没有任何仓库引用后清理）。
