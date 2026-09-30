///|
test "ConfigMirror spec preserves targets and rejects duplicates" {
  let mirror = @object.DynamicObject::from_json(
    @json.parse(
      "{\"metadata\":{\"name\":\"demo\",\"uid\":\"uid-1\"},\"spec\":{\"source\":{\"namespace\":\"source\",\"name\":\"settings\"},\"targets\":[\"east\",\"west\"]}}",
    ),
  )
  let spec = @configmirror.decode_spec(mirror).unwrap()
  assert_eq(spec.source_namespace(), "source")
  assert_eq(spec.source_name(), "settings")
  assert_eq(spec.targets().to_owned(), ["east", "west"])
  let duplicate = @object.DynamicObject::from_json(
    @json.parse(
      "{\"metadata\":{\"name\":\"demo\"},\"spec\":{\"source\":{\"namespace\":\"source\",\"name\":\"settings\"},\"targets\":[\"east\",\"east\"]}}",
    ),
  )
  assert_true(@configmirror.decode_spec(duplicate) is Err(_))
}

///|
test "content hash ignores object metadata and JSON map key order" {
  let first = @object.DynamicObject::from_json(
    @json.parse(
      "{\"metadata\":{\"name\":\"settings\",\"resourceVersion\":\"1\"},\"data\":{\"a\":\"one\",\"b\":\"two\"}}",
    ),
  )
  let second = @object.DynamicObject::from_json(
    @json.parse(
      "{\"metadata\":{\"name\":\"settings\",\"resourceVersion\":\"2\"},\"data\":{\"b\":\"two\",\"a\":\"one\"}}",
    ),
  )
  assert_eq(
    @configmirror.content_hash(first).unwrap(),
    @configmirror.content_hash(second).unwrap(),
  )
  assert_eq(@configmirror.content_hash(first).unwrap().length(), 64)
}

///|
test "desired ConfigMap carries owner UID and source content" {
  let mirror = @object.DynamicObject::from_json(
    @json.parse("{\"metadata\":{\"name\":\"mirror\",\"uid\":\"uid-1\"}}"),
  )
  let source = @object.DynamicObject::from_json(
    @json.parse(
      "{\"metadata\":{\"name\":\"settings\"},\"data\":{\"key\":\"value\"}}",
    ),
  )
  let desired = @configmirror.desired_configmap(mirror, source, "target").unwrap()
  guard desired is Object(root) &&
    root.get("metadata") is Some(Object(metadata)) &&
    metadata.get("annotations") is Some(Object(annotations)) else {
    fail("bad desired ConfigMap")
  }
  assert_eq(metadata.get("namespace"), Some(Json::string("target")))
  assert_eq(
    annotations.get(@configmirror.owner_annotation),
    Some(Json::string("uid-1")),
  )
  assert_eq(root.get("data"), Some(@json.parse("{\"key\":\"value\"}")))
}
