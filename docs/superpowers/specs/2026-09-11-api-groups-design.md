# Named API Group 版本选择设计

## 为什么先补 `/apis`

上一批的 `/api` 解码只覆盖 core API。Kubernetes 的 Deployment、Job 等常用资源位于 named group；如果没有 `/apis` 的 `APIGroupList`，动态客户端即使会解析单份资源清单，也不知道集群实际公开了哪些组和版本。因此我先补齐目录入口，再进入真实 HTTP/TLS，而不是让网络层返回一段无人负责解释的 JSON。

## 我保留服务端事实，不替集群做策略

`groups` 和每组的 `versions` 都按 API Server 返回顺序保存，不排序、不去重。`preferredVersion` 代表服务端给出的首选项，不等同于客户端永远应使用的版本；这一批只验证并呈现它，不加入版本协商或回退策略。

公开结果通过只读 `ArrayView` 暴露。调用者可以按名称查找 group、按版本字符串查找版本条目，也能明确看到某组没有提供 `preferredVersion`。我没有把“缺少 preferred”当作错误，因为它在 API 定义中不是必需字段，支持版本列表本身仍然有用。

## 一致性比部分可用更重要

每个版本条目的 `groupVersion` 必须等于 `group name + "/" + version`。若存在 `preferredVersion`，它还必须完整出现在 `versions` 中。任何 group 或 version 出错都会拒绝整份结果，错误路径包含 `groups[i].versions[j]`；这样后续请求构造不会在已经矛盾的目录上继续猜测。

未知字段与 `serverAddressByClientCIDRs` 暂时忽略。前者保证面对 API Server 扩展字段时仍可向前兼容，后者已经不影响本项目当前的资源寻址目标，不值得提前扩大公共接口。

## 开发中实际遇到的边界

黑盒测试最初因 `decode_api_group_list` 尚不存在而得到 E4021，这确认测试确实跨包使用公开接口。最小实现完成后，我又补了缺失版本字段、错误 preferred 类型以及查找不存在项的用例。当前 MoonBit 格式化器同时修正了仓库旧文件中的尾逗号，我将那次纯格式变化单独记录，没有把它混入 Discovery 功能提交。

## 本批没有越过的线

这次不发起网络请求，不缓存或刷新目录，不实现 Aggregated Discovery v2，也不选择“最稳定”或“最新”的版本。下一批 HTTP/TLS 执行器只负责可靠取得响应；Discovery 的数据含义和版本策略继续留在这个包内演进。
