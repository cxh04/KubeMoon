///|
test "decode core API versions in server order" {
  let body = "{\"kind\":\"APIVersions\",\"versions\":[\"v1\",\"v1beta1\"]}"
  let versions = @discovery.decode_api_versions(body).unwrap()
  inspect(versions.versions().join(","), content="v1,v1beta1")
  inspect(versions.supports("v1"), content="true")
  inspect(versions.supports("V1"), content="false")
}

///|
test "accept an empty core API version directory" {
  let body = "{\"versions\":[],\"futureField\":true}"
  let versions = @discovery.decode_api_versions(body).unwrap()
  inspect(versions.versions().length(), content="0")
  inspect(versions.supports("v1"), content="false")
}

///|
test "reject malformed core API version directories" {
  let cases = [
    ("not-json", "Invalid APIVersions JSON"),
    ("[]", "APIVersions must be a JSON object"),
    ("{}", "Missing versions"),
    ("{\"versions\":false}", "versions must be an array"),
    ("{\"versions\":[\"v1\",7]}", "versions[1] must be a string"),
  ]
  for input_expected in cases {
    let (input, expected) = input_expected
    match @discovery.decode_api_versions(input) {
      Err(message) => inspect(message, content=expected)
      Ok(_) => fail("malformed core API version directory must be rejected")
    }
  }
}
