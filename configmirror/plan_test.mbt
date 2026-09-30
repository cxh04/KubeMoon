///|
fn sample_mirror() -> @object.DynamicObject raise {
  @object.DynamicObject::from_json(
    @json.parse("{\"metadata\":{\"name\":\"mirror\",\"uid\":\"uid-1\"}}"),
  )
}

///|
fn sample_source() -> @object.DynamicObject raise {
  @object.DynamicObject::from_json(
    @json.parse(
      "{\"metadata\":{\"name\":\"settings\"},\"data\":{\"key\":\"new\"}}",
    ),
  )
}

///|
test "missing target creates while unrelated target conflicts" {
  let mirror = sample_mirror()
  let source = sample_source()
  assert_true(
    @configmirror.plan_target(mirror, source, "west", None).unwrap()
    is Create(_),
  )
  let unrelated = @object.DynamicObject::from_json(
    @json.parse(
      "{\"metadata\":{\"name\":\"settings\",\"namespace\":\"west\",\"resourceVersion\":\"9\"}}",
    ),
  )
  assert_true(
    @configmirror.plan_target(mirror, source, "west", Some(unrelated)).unwrap()
    is Conflict,
  )
}

///|
test "owned target replacement preserves other annotations and clears removed data" {
  let mirror = sample_mirror()
  let source = sample_source()
  let current = @object.DynamicObject::from_json(
    @json.parse(
      "{\"metadata\":{\"name\":\"settings\",\"namespace\":\"west\",\"resourceVersion\":\"9\",\"annotations\":{\"cxh04.github.io/kubemoon-owner-uid\":\"uid-1\",\"other.example/keep\":\"yes\"}},\"data\":{\"old\":\"remove\"}}",
    ),
  )
  guard @configmirror.plan_target(mirror, source, "west", Some(current)).unwrap()
    is Replace(body) else {
    fail("expected replacement")
  }
  guard body is Object(root) &&
    root.get("metadata") is Some(Object(metadata)) &&
    metadata.get("annotations") is Some(Object(annotations)) else {
    fail("bad replacement body")
  }
  assert_eq(root.get("data"), Some(@json.parse("{\"key\":\"new\"}")))
  assert_eq(metadata.get("resourceVersion"), Some(Json::string("9")))
  assert_eq(annotations.get("other.example/keep"), Some(Json::string("yes")))
}
