///|
test "read identity and resource version from unstructured metadata" {
  let input = "{\"apiVersion\":\"v1\",\"kind\":\"ConfigMap\",\"metadata\":{\"name\":\"settings\",\"namespace\":\"team-a\",\"uid\":\"u-17\",\"resourceVersion\":\"42\"},\"data\":{\"theme\":\"dark\"}}"
  let object = @object.DynamicObject::from_json(@json.parse(input))
  inspect(object.identity(), content="team-a/settings")
  inspect(object.uid(), content="u-17")
  inspect(object.resource_version(), content="42")
  inspect(object.raw() == @json.parse(input), content="true")
}

///|
test "reject object metadata without a name" {
  let input = "{\"apiVersion\":\"v1\",\"kind\":\"ConfigMap\",\"metadata\":{}}"
  let result = @object.DynamicObject::try_from_json(@json.parse(input))
  match result {
    Err(message) => inspect(message, content="Missing metadata.name")
    Ok(_) => fail("object without metadata.name must be rejected")
  }
}

///|
test "cluster scoped identity does not invent a namespace" {
  let input = "{\"apiVersion\":\"v1\",\"kind\":\"Namespace\",\"metadata\":{\"name\":\"team-a\"}}"
  let object = @object.DynamicObject::from_json(@json.parse(input))
  inspect(object.identity(), content="team-a")
  inspect(object.namespace_name().unwrap_or(""), content="")
  inspect(object.resource_version(), content="")
}
