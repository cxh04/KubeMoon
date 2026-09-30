///|
fn configmaps() -> @resource.GroupVersionResource {
  GroupVersionResource(group="", version="v1", resource="configmaps")
}

///|
pub fn configmirrors() -> @resource.GroupVersionResource {
  GroupVersionResource(
    group="kubemoon.cxh04.github.io",
    version="v1alpha1",
    resource="configmirrors",
  )
}

///|
pub struct ConfigMirrorReconciler {
  transport : @httptransport.HttpTransport
  client : @client.DynamicClient
}

///|
pub fn ConfigMirrorReconciler::ConfigMirrorReconciler(
  transport : @httptransport.HttpTransport,
  client : @client.DynamicClient,
) -> ConfigMirrorReconciler {
  { transport, client, }
}

///|
async fn ConfigMirrorReconciler::fetch(
  self : ConfigMirrorReconciler,
  resource : @resource.GroupVersionResource,
  scope : @resource.Scope,
  name : String,
) -> Result[@object.DynamicObject?, String] {
  let response = self.transport.send(
    self.client.get_request(resource, scope, name),
  )
  if response.status() == 404 {
    return Ok(None)
  }
  if !response.is_success() {
    return Err("GET \{name} failed with HTTP \{response.status()}")
  }
  let raw = @json.parse(response.body()) catch {
    _ => return Err("GET \{name} returned invalid JSON")
  }
  match @object.DynamicObject::try_from_json(raw) {
    Ok(object) => Ok(Some(object))
    Err(message) => Err("GET \{name}: \{message}")
  }
}

///|
async fn ConfigMirrorReconciler::write(
  self : ConfigMirrorReconciler,
  request : @transport.Request,
) -> Result[Unit, String] {
  let response = self.transport.send(request)
  if response.is_success() {
    Ok(())
  } else {
    Err(
      "\{request.verb().http_name()} \{request.path()} failed with HTTP \{response.status()}: \{response.body()}",
    )
  }
}

///|
fn status_of(mirror : @object.DynamicObject) -> Json? {
  guard mirror.raw() is Object(root) else { return None }
  root.get("status")
}

///|
fn generation_of(mirror : @object.DynamicObject) -> Json {
  guard mirror.raw() is Object(root) &&
    root.get("metadata") is Some(Object(metadata)) else {
    return Json::number(0.0)
  }
  metadata.get("generation").unwrap_or(Json::number(0.0))
}

///|
fn ready_status(
  mirror : @object.DynamicObject,
  hash : String,
  targets : ArrayView[String],
) -> Json {
  let synced : Array[Json] = []
  for target in targets {
    synced.push(Json::string(target))
  }
  Json::object({
    "observedGeneration": generation_of(mirror),
    "contentHash": Json::string(hash),
    "syncedTargets": Json::array(synced),
    "conditions": Json::array([
      Json::object({
        "type": Json::string("Ready"),
        "status": Json::string("True"),
        "reason": Json::string("Synced"),
        "observedGeneration": generation_of(mirror),
      }),
    ]),
  })
}

///|
fn failed_status(
  mirror : @object.DynamicObject,
  reason : String,
  message : String,
) -> Json {
  Json::object({
    "observedGeneration": generation_of(mirror),
    "contentHash": Json::string(""),
    "syncedTargets": Json::array([]),
    "conditions": Json::array([
      Json::object({
        "type": Json::string("Ready"),
        "status": Json::string("False"),
        "reason": Json::string(reason),
        "message": Json::string(message),
        "observedGeneration": generation_of(mirror),
      }),
    ]),
  })
}

///|
async fn ConfigMirrorReconciler::set_status(
  self : ConfigMirrorReconciler,
  mirror : @object.DynamicObject,
  desired : Json,
) -> Result[Unit, String] {
  if status_of(mirror) == Some(desired) {
    return Ok(())
  }
  guard mirror.namespace_name() is Some(namespace_name) else {
    return Err("ConfigMirror has no namespace")
  }
  let body = Json::object({ "status": desired }).stringify()
  self.write(
    self.client.patch_status_request(
      configmirrors(),
      Namespace(namespace_name),
      mirror.name(),
      body,
    ),
  )
}

///|
async fn ConfigMirrorReconciler::report_failure(
  self : ConfigMirrorReconciler,
  mirror : @object.DynamicObject,
  reason : String,
  message : String,
) -> Result[Unit, String] {
  match self.set_status(mirror, failed_status(mirror, reason, message)) {
    Ok(_) => Err(message)
    Err(status_error) =>
      Err("\{message}; status update failed: \{status_error}")
  }
}

///|
async fn ConfigMirrorReconciler::remove_targets(
  self : ConfigMirrorReconciler,
  mirror : @object.DynamicObject,
  spec : @configmirror.MirrorSpec,
) -> Result[Unit, String] {
  let mut pending = false
  for namespace_name in spec.targets() {
    let current = match
      self.fetch(configmaps(), Namespace(namespace_name), spec.source_name()) {
      Ok(current) => current
      Err(message) => return Err(message)
    }
    match current {
      Some(target) if @configmirror.owned_by(target, mirror) => {
        if target.uid().is_empty() {
          return Err("Managed target ConfigMap has no UID")
        }
        let request = self.client.delete_with_uid_request(
          configmaps(),
          Namespace(namespace_name),
          target.name(),
          target.uid(),
        )
        let response = self.transport.send(request)
        if response.status() == 404 {
          ()
        } else if response.is_success() {
          pending = true
        } else {
          return Err(
            "DELETE \{namespace_name}/\{target.name()} failed with HTTP \{response.status()}",
          )
        }
      }
      _ => ()
    }
  }
  if pending {
    Err("Waiting for target ConfigMaps to disappear")
  } else {
    Ok(())
  }
}

///|
/// Idempotent reconciliation of one ConfigMirror. Status and finalizer writes
/// use the CRD subresource and metadata resourceVersion respectively. A
/// conflict is returned to the queue for a fresh pass.
pub async fn ConfigMirrorReconciler::reconcile(
  self : ConfigMirrorReconciler,
  _key : String,
  mirror : @object.DynamicObject?,
) -> Result[Unit, String] {
  guard mirror is Some(mirror) else { return Ok(()) }
  guard mirror.namespace_name() is Some(namespace_name) else {
    return Err("ConfigMirror has no namespace")
  }
  let spec = match @configmirror.decode_spec(mirror) {
    Ok(spec) => spec
    Err(message) => return self.report_failure(mirror, "InvalidSpec", message)
  }
  if @controller.is_deleting(mirror) {
    match self.remove_targets(mirror, spec) {
      Ok(_) => ()
      Err(message) => return Err(message)
    }
    match
      @controller.finalizer_patch(
        mirror,
        @configmirror.finalizer_key,
        remove=true,
      ) {
      Ok(Some(body)) =>
        self.write(
          self.client.patch_request(
            configmirrors(),
            Namespace(namespace_name),
            mirror.name(),
            MergePatch,
            body,
          ),
        )
      Ok(None) => Ok(())
      Err(message) => Err(message)
    }
  } else {
    match
      @controller.finalizer_patch(
        mirror,
        @configmirror.finalizer_key,
        remove=false,
      ) {
      Ok(Some(body)) =>
        return self.write(
          self.client.patch_request(
            configmirrors(),
            Namespace(namespace_name),
            mirror.name(),
            MergePatch,
            body,
          ),
        )
      Ok(None) => ()
      Err(message) => return Err(message)
    }
    let source = match
      self.fetch(
        configmaps(),
        Namespace(spec.source_namespace()),
        spec.source_name(),
      ) {
      Ok(Some(source)) => source
      Ok(None) =>
        return self.report_failure(
          mirror, "SourceMissing", "Source ConfigMap not found",
        )
      Err(message) =>
        return self.report_failure(mirror, "SourceReadFailed", message)
    }
    for target_namespace in spec.targets() {
      let current = match
        self.fetch(configmaps(), Namespace(target_namespace), source.name()) {
        Ok(current) => current
        Err(message) =>
          return self.report_failure(mirror, "TargetReadFailed", message)
      }
      let action = match
        @configmirror.plan_target(mirror, source, target_namespace, current) {
        Ok(action) => action
        Err(message) =>
          return self.report_failure(mirror, "InvalidTarget", message)
      }
      let request = match action {
        Create(body) =>
          Some(
            self.client.create_request(
              configmaps(),
              Namespace(target_namespace),
              body.stringify(),
            ),
          )
        Replace(body) =>
          Some(
            self.client.replace_request(
              configmaps(),
              Namespace(target_namespace),
              source.name(),
              body.stringify(),
            ),
          )
        Unchanged => None
        Conflict =>
          return self.report_failure(
            mirror,
            "TargetConflict",
            "Unowned target ConfigMap \{target_namespace}/\{source.name()}",
          )
      }
      if request is Some(request) {
        match self.write(request) {
          Ok(_) => ()
          Err(message) =>
            return self.report_failure(mirror, "ApplyFailed", message)
        }
      }
    }
    let hash = match @configmirror.content_hash(source) {
      Ok(hash) => hash
      Err(message) =>
        return self.report_failure(mirror, "InvalidSource", message)
    }
    self.set_status(mirror, ready_status(mirror, hash, spec.targets()))
  }
}
