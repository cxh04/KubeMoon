///|
test "finalizer patch preserves other owners and uses resource version" {
  let object = @object.DynamicObject::from_json(
    @json.parse(
      "{\"metadata\":{\"name\":\"mirror\",\"resourceVersion\":\"7\",\"finalizers\":[\"other.example/cleanup\"]}}",
    ),
  )
  let body = @controller.finalizer_patch(
      object,
      "kubemoon.example/cleanup",
      remove=false,
    )
    .unwrap()
    .unwrap()
  let parsed = @json.parse(body)
  guard parsed is Object(fields) &&
    fields.get("metadata") is Some(Object(metadata)) else {
    fail("bad patch")
  }
  assert_eq(metadata.get("resourceVersion"), Some(Json::string("7")))
  assert_eq(
    metadata.get("finalizers"),
    Some(
      Json::array([
        Json::string("other.example/cleanup"),
        Json::string("kubemoon.example/cleanup"),
      ]),
    ),
  )
  assert_true(
    @controller.finalizer_patch(object, "other.example/cleanup", remove=false).unwrap()
    is None,
  )
}

///|
test "deleting object can only remove an existing finalizer" {
  let object = @object.DynamicObject::from_json(
    @json.parse(
      "{\"metadata\":{\"name\":\"mirror\",\"resourceVersion\":\"8\",\"deletionTimestamp\":\"2026-09-30T00:00:00Z\",\"finalizers\":[\"kubemoon.example/cleanup\"]}}",
    ),
  )
  assert_true(@controller.is_deleting(object))
  assert_true(
    @controller.finalizer_patch(object, "new.example/cleanup", remove=false)
    is Err(_),
  )
  assert_true(
    @controller.finalizer_patch(object, "kubemoon.example/cleanup", remove=true).unwrap()
    is Some(_),
  )
}
