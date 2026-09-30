///|
/// A ConfigMap event can affect a source or one of its managed targets.
/// Only matching ConfigMirrors are scheduled; unrelated cluster events stay
/// out of the reconcile queue.
pub fn enqueue_affected(
  mirrors : @reflector.Reflector,
  configmap_key : String,
) -> Int {
  let mut added = 0
  for mirror_key in mirrors.keys() {
    guard mirrors.get(mirror_key) is Some(mirror) else { continue }
    guard @configmirror.decode_spec(mirror) is Ok(spec) else { continue }
    let source_key = "\{spec.source_namespace()}/\{spec.source_name()}"
    let mut related = configmap_key == source_key
    for namespace_name in spec.targets() {
      if configmap_key == "\{namespace_name}/\{spec.source_name()}" {
        related = true
      }
    }
    if related {
      mirrors.enqueue(mirror_key)
      added = added + 1
    }
  }
  added
}
