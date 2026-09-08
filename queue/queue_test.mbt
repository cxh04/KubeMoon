///|
test "deduplicate pending reconcile keys" {
  let queue = @queue.WorkQueue::WorkQueue(base_delay_ms=100, max_delay_ms=800)
  queue.add("team-a/settings")
  queue.add("team-a/settings")
  inspect(queue.length(), content="1")
  inspect(queue.next().unwrap_or(""), content="team-a/settings")
  inspect(queue.next().unwrap_or(""), content="")
}

///|
test "requeue once when an event arrives during processing" {
  let queue = @queue.WorkQueue::WorkQueue(base_delay_ms=100, max_delay_ms=800)
  queue.add("team-a/settings")
  queue.next() |> ignore
  queue.add("team-a/settings")
  queue.add("team-a/settings")
  queue.done("team-a/settings")
  inspect(queue.length(), content="1")
  inspect(queue.next().unwrap_or(""), content="team-a/settings")
  queue.done("team-a/settings")
  inspect(queue.length(), content="0")
}

///|
test "apply capped exponential backoff and reset it after success" {
  let queue = @queue.WorkQueue::WorkQueue(base_delay_ms=100, max_delay_ms=250)
  queue.add("team-a/settings")
  queue.next() |> ignore
  inspect(queue.fail("team-a/settings"), content="100")
  queue.advance(99)
  inspect(queue.length(), content="0")
  queue.advance(1)
  queue.next() |> ignore
  inspect(queue.fail("team-a/settings"), content="200")
  queue.advance(200)
  queue.next() |> ignore
  inspect(queue.fail("team-a/settings"), content="250")
  queue.advance(250)
  queue.next() |> ignore
  queue.done("team-a/settings")
  queue.add("team-a/settings")
  queue.next() |> ignore
  inspect(queue.fail("team-a/settings"), content="100")
}
