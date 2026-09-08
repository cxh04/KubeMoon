///|
test "classify Kubernetes status reasons" {
  let missing = @apierror.ApiError::from_response(
    404, "{\"kind\":\"Status\",\"reason\":\"NotFound\",\"message\":\"configmaps \\\"settings\\\" not found\",\"code\":404}",
  )
  inspect(missing.reason(), content="NotFound")
  inspect(missing.message(), content="configmaps \"settings\" not found")
  inspect(missing.is_not_found(), content="true")
  inspect(missing.is_retryable(), content="false")

  let conflict = @apierror.ApiError::from_response(
    409, "{\"reason\":\"Conflict\",\"message\":\"resource version changed\"}",
  )
  inspect(conflict.is_conflict(), content="true")
}

///|
test "recognize expired watch versions and transient server failures" {
  let expired = @apierror.ApiError::from_response(
    410, "{\"reason\":\"Expired\",\"message\":\"too old resource version\"}",
  )
  inspect(expired.is_expired(), content="true")
  inspect(expired.is_retryable(), content="false")

  let overloaded = @apierror.ApiError::from_response(
    503, "temporarily unavailable",
  )
  inspect(overloaded.reason(), content="HTTP 503")
  inspect(overloaded.message(), content="temporarily unavailable")
  inspect(overloaded.is_retryable(), content="true")
}

///|
test "treat throttling as retryable" {
  let throttled = @apierror.ApiError::from_response(
    429, "{\"reason\":\"TooManyRequests\",\"message\":\"rate limit exceeded\"}",
  )
  inspect(throttled.status_code(), content="429")
  inspect(throttled.is_retryable(), content="true")
}
