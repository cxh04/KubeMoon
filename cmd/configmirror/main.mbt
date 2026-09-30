///|
async fn main {
  let host = @env.get_env_var("KUBERNETES_SERVICE_HOST").unwrap_or("")
  let port = @env.get_env_var("KUBERNETES_SERVICE_PORT").unwrap_or("")
  let token = @fs.read_file(
    "/var/run/secrets/kubernetes.io/serviceaccount/token",
  ).text()
  let config = match
    @config.ClientConfig::try_in_cluster(
      host~,
      port~,
      service_account_token=token,
    ) {
    Ok(config) => config
    Err(message) => fail(message)
  }
  let client = @client.DynamicClient::DynamicClient(config)
  let mirror_transport = @httptransport.HttpTransport::connect(config)
  defer mirror_transport.close()
  let configmap_transport = @httptransport.HttpTransport::connect(config)
  defer configmap_transport.close()
  let reconcile_transport = @httptransport.HttpTransport::connect(config)
  defer reconcile_transport.close()
  let reconciler = @operator.ConfigMirrorReconciler::ConfigMirrorReconciler(
    reconcile_transport, client,
  )
  let mirrors = @reflector.Reflector::Reflector()
  let configmaps = @reflector.Reflector::Reflector()
  let configmap_resource = @resource.GroupVersionResource(
    group="",
    version="v1",
    resource="configmaps",
  )
  @async.with_task_group() <| group => {
    group.spawn_bg() <| () => {
      @runtime.run(
        mirror_transport,
        client,
        @operator.configmirrors(),
        Cluster,
        mirrors,
      )
    }
    group.spawn_bg() <| () => {
      @runtime.run(
        configmap_transport,
        client,
        configmap_resource,
        Cluster,
        configmaps,
      )
    }
    group.spawn_bg() <| () => {
      @controller.run(mirrors, (key, object) => {
        reconciler.reconcile(key, object)
      })
    }
    group.spawn_bg() <| () => {
      for ;; {
        match configmaps.next_key() {
          Some(key) => {
            ignore(@operator.enqueue_affected(mirrors, key))
            configmaps.done(key)
          }
          None => {
            @async.sleep(50)
            configmaps.advance(50)
          }
        }
      }
    }
  }
}
