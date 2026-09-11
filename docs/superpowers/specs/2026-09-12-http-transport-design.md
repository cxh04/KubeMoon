# 原生 HTTP/TLS 执行器设计札记

## 为什么单独建立 `httptransport`

此前的 `transport` 只定义请求和响应值，`fake` 则用同步脚本验证上层状态机。我没有把 socket、TLS 和异步运行时直接塞进这两个包，而是增加 native-only 的 `httptransport`：基础数据模型继续轻量，真实网络依赖集中在明确的边界内，未来的 Watch 流执行器也可以复用同一套请求语义。

实现基于 [`moonbitlang/async/http`](https://skills.mooncakes.io/docs/moonbitlang/async/http) `0.21.3`。`HttpTransport::connect` 为一个 API Server 建立连接，`send` 把 KubeMoon 的 GET、POST、PUT、PATCH、DELETE、headers 和可选 body 映射到异步 HTTP 客户端，再把状态码与完整响应体收回现有 `Response`。

## 我把 origin 校验放在写入之前

`DynamicClient` 生成绝对 URL，底层 HTTP Client 却绑定一个 origin 并接收相对 path。简单删除字符串前缀会把 `https://cluster.example.evil/...` 误认为同源，所以我同时要求剩余部分为空或以 `/` 开头。校验失败会抛出包含 expected/actual 的 `RequestOriginMismatch`，而且发生在 headers 和 body 写入连接之前。这个约束的意义不只是 URL 正确，更是防止 Bearer Token 随错误请求目标传播。

## TLS 信任不是一个 `verify=false` 开关

没有显式 CA 时使用系统信任根；`ClientConfig.ca_file` 存在时转换为 `CustomPemFile`，仅信任该 PEM 文件中的根证书。in-cluster 配置已经指向 ServiceAccount 的 `ca.crt`，所以不需要为集群内场景关闭证书验证。当前测试验证了信任策略映射，真正的私有 CA 握手会在 kind E2E 中与 API Server 一起验证。

## 这批选择缓冲响应

Discovery 与普通 CRUD 都需要完整 JSON，先用 `read_all` 可以把网络闭环做小，并复用现有解码器和错误分类。Watch 不适合这条路径：它必须长期持有连接，把任意 chunk 逐步交给 `watch.Decoder`，还要处理取消与重连。因此本批没有用“HTTP 已通”提前宣称 Watch 网络流已经完成，也没有加入连接池、并发复用、代理或超时策略。

## 实际验证轨迹

黑盒测试先因 `HttpTransport` 不存在而失败。最小实现后，本地服务器在同一连接上依次收到带认证头的 `GET /apis` 和带 JSON body 的 ConfigMap `POST`，证明了连接复用、方法、headers、body 和响应映射。编译器随后指出 `Iter[(K,V)]` 的循环变量误解，以及多余包前缀、保留字和 `StringView` 所有权写法；这些都按实际诊断逐项收紧。最终定向测试 4 项，全库测试 52 项。
