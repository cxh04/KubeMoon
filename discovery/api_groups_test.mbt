///|
test "decode named API groups in server order" {
  let body =
    #|{"kind":"APIGroupList","apiVersion":"v1","groups":[{"name":"apps","versions":[{"groupVersion":"apps/v1","version":"v1"}],"preferredVersion":{"groupVersion":"apps/v1","version":"v1"}},{"name":"autoscaling","versions":[{"groupVersion":"autoscaling/v2","version":"v2"},{"groupVersion":"autoscaling/v1","version":"v1"}],"preferredVersion":{"groupVersion":"autoscaling/v2","version":"v2"}}]}
  let groups = @discovery.decode_api_group_list(body).unwrap()
  inspect(groups.groups().length(), content="2")
  inspect(groups.groups()[0].name(), content="apps")
  let autoscaling = groups.find("autoscaling").unwrap()
  inspect(autoscaling.versions()[0].version(), content="v2")
  inspect(autoscaling.versions()[1].version(), content="v1")
  inspect(
    autoscaling.preferred_version().unwrap().group_version(),
    content="autoscaling/v2",
  )
  inspect(
    autoscaling.find_version("v1").unwrap().group_version(),
    content="autoscaling/v1",
  )
  inspect(autoscaling.find_version("v3") is None, content="true")
  inspect(groups.find("batch") is None, content="true")
}

///|
test "accept optional preferred version and unknown fields" {
  let body =
    #|{"groups":[{"name":"batch","versions":[{"groupVersion":"batch/v1","version":"v1","future":true}],"serverAddressByClientCIDRs":[{"clientCIDR":"0.0.0.0/0"}]}],"futureTopLevel":true}
  let groups = @discovery.decode_api_group_list(body).unwrap()
  let batch = groups.find("batch").unwrap()
  inspect(batch.preferred_version() is None, content="true")
  inspect(batch.find_version("v1").unwrap().version(), content="v1")

  let empty = @discovery.decode_api_group_list("{\"groups\":[]}").unwrap()
  inspect(empty.groups().length(), content="0")
}

///|
test "reject malformed and inconsistent named API groups" {
  let cases = [
    ("not-json", "Invalid APIGroupList JSON"),
    ("[]", "APIGroupList must be a JSON object"),
    ("{}", "Missing groups"),
    ("{\"groups\":false}", "groups must be an array"),
    ("{\"groups\":[7]}", "groups[0]: group must be an object"),
    ("{\"groups\":[{\"versions\":[]}]}", "groups[0]: missing name"),
    (
      "{\"groups\":[{\"name\":\"apps\",\"versions\":false}]}", "groups[0]: versions must be an array",
    ),
    (
      "{\"groups\":[{\"name\":\"apps\",\"versions\":[{}]}]}", "groups[0].versions[0]: missing groupVersion",
    ),
    (
      "{\"groups\":[{\"name\":\"apps\",\"versions\":[{\"groupVersion\":\"apps/v1\"}]}]}",
      "groups[0].versions[0]: missing version",
    ),
    (
      "{\"groups\":[{\"name\":\"apps\",\"versions\":[{\"groupVersion\":\"batch/v1\",\"version\":\"v1\"}]}]}",
      "groups[0].versions[0]: groupVersion must match apps/v1",
    ),
    (
      "{\"groups\":[{\"name\":\"apps\",\"versions\":[{\"groupVersion\":\"apps/v1\",\"version\":\"v1\"}],\"preferredVersion\":{\"groupVersion\":\"apps/v2\",\"version\":\"v2\"}}]}",
      "groups[0].preferredVersion: preferred version must appear in versions",
    ),
    (
      "{\"groups\":[{\"name\":\"apps\",\"versions\":[],\"preferredVersion\":false}]}",
      "groups[0].preferredVersion: version must be an object",
    ),
  ]
  for input_expected in cases {
    let (input, expected) = input_expected
    match @discovery.decode_api_group_list(input) {
      Err(message) => inspect(message, content=expected)
      Ok(_) => fail("malformed API group list must be rejected")
    }
  }
}
